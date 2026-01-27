// Mark Delivery Failed Edge Function (Delivery Staff)
// POST /functions/v1/mark-delivery-failed
// Body: { order_id, reason }

import { getServiceClient, requireDeliveryStaff } from "../_shared/auth.ts";
import { sendOrderPush } from "../_shared/push.ts";
import { sendOrderStatusSMS } from "../_shared/sms.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

interface MarkFailedRequest {
  order_id: string;
  reason: string;
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
    const body: MarkFailedRequest = await req.json();

    if (!body.order_id || !body.reason) {
      return errorResponse('INVALID_INPUT', 'order_id and reason are required', 400);
    }

    // Validate reason
    if (body.reason.length < 5 || body.reason.length > 500) {
      return errorResponse('INVALID_REASON', 'Reason must be between 5 and 500 characters', 400);
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

    // Update order to delivery_failed
    const { data: updatedOrder, error: updateError } = await supabase
      .from('orders')
      .update({
        status: 'delivery_failed',
        failure_reason: body.reason,
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
        to_status: 'delivery_failed',
        changed_by: auth.userId,
        notes: body.reason,
      });

    // Send notifications to customer
    const customerPhone = (order.user as { phone: string })?.phone || order.shipping_phone;
    sendOrderStatusSMS(customerPhone, order.order_number, 'delivery_failed').catch(console.error);
    sendOrderPush(order.user_id, order.order_number, 'delivery_failed').catch(console.error);

    return jsonResponse({
      success: true,
      order: {
        id: updatedOrder.id,
        order_number: updatedOrder.order_number,
        status: updatedOrder.status,
        failure_reason: updatedOrder.failure_reason,
      },
      message: 'Delivery marked as failed',
    });
  } catch (error) {
    return handleError(error, 'Mark delivery failed');
  }
}

// For standalone execution
Deno.serve(handler);
