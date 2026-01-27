// Verify Delivery OTP Edge Function (Delivery Staff)
// POST /functions/v1/verify-delivery-otp
// Body: { order_id, otp }

import { getServiceClient, requireDeliveryStaff, hashOTP } from "../_shared/auth.ts";
import { sendOrderPush } from "../_shared/push.ts";
import { sendOrderStatusSMS } from "../_shared/sms.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

interface VerifyDeliveryRequest {
  order_id: string;
  otp: string;
}

export async function handler(req: Request): Promise<Response> {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Only allow POST
    if (req.method !== 'POST') {
      return errorResponse('METHOD_NOT_ALLOWED', 'Only POST requests allowed', 405);
    }

    // Require delivery staff authentication
    const auth = await requireDeliveryStaff(req);
    const supabase = getServiceClient();

    // Parse request body
    const body: VerifyDeliveryRequest = await req.json();

    if (!body.order_id || !body.otp) {
      return errorResponse('INVALID_INPUT', 'order_id and otp are required', 400);
    }

    // Validate OTP format (4 digits)
    if (!/^\d{4}$/.test(body.otp)) {
      return errorResponse('INVALID_OTP', 'OTP must be 4 digits', 400);
    }

    // Get order
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('*, user:users!orders_user_id_fkey(phone)')
      .eq('id', body.order_id)
      .single();

    if (orderError || !order) {
      return errorResponse('ORDER_NOT_FOUND', 'Order not found', 404);
    }

    // Verify this order is assigned to the requesting delivery staff
    if (order.delivery_staff_id !== auth.userId) {
      return errorResponse('NOT_ASSIGNED', 'This order is not assigned to you', 403);
    }

    // Verify order is in correct status
    if (order.status !== 'out_for_delivery') {
      return errorResponse('INVALID_STATUS', `Order is ${order.status}, not out for delivery`, 400);
    }

    // Check OTP expiry
    if (!order.delivery_otp_hash || !order.delivery_otp_expires) {
      return errorResponse('NO_OTP', 'Delivery OTP not set for this order', 400);
    }

    if (new Date(order.delivery_otp_expires) < new Date()) {
      return errorResponse('OTP_EXPIRED', 'Delivery OTP has expired. Please contact admin.', 400);
    }

    // Verify OTP
    const otpHash = await hashOTP(body.otp);

    if (otpHash !== order.delivery_otp_hash) {
      return errorResponse('INVALID_OTP', 'Invalid delivery OTP', 400);
    }

    // Update order to delivered
    const { data: updatedOrder, error: updateError } = await supabase
      .from('orders')
      .update({
        status: 'delivered',
        delivery_otp_hash: null,
        delivery_otp_expires: null,
      })
      .eq('id', body.order_id)
      .select()
      .single();

    if (updateError) {
      console.error('Failed to update order:', updateError);
      return errorResponse('SERVER_ERROR', 'Failed to update order', 500);
    }

    // Record status history
    await supabase
      .from('order_status_history')
      .insert({
        order_id: body.order_id,
        from_status: 'out_for_delivery',
        to_status: 'delivered',
        changed_by: auth.userId,
        notes: 'Delivery completed with OTP verification',
      });

    // Send notifications to customer
    const customerPhone = (order.user as { phone: string })?.phone || order.shipping_phone;
    sendOrderStatusSMS(customerPhone, order.order_number, 'delivered').catch(console.error);
    sendOrderPush(order.user_id, order.order_number, 'delivered').catch(console.error);

    return jsonResponse({
      success: true,
      order: {
        id: updatedOrder.id,
        order_number: updatedOrder.order_number,
        status: updatedOrder.status,
      },
      message: 'Delivery completed successfully',
    });
  } catch (error) {
    return handleError(error, 'Verify delivery OTP');
  }
}

// For standalone execution
Deno.serve(handler);
