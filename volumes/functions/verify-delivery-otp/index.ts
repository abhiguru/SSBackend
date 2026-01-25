// Verify Delivery OTP Edge Function (Delivery Staff)
// POST /functions/v1/verify-delivery-otp
// Body: { order_id, otp }

import { getServiceClient, requireDeliveryStaff, hashOTP } from "../_shared/auth.ts";
import { sendOrderPush } from "../_shared/push.ts";
import { sendOrderStatusSMS } from "../_shared/sms.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

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
      return new Response(
        JSON.stringify({ error: 'METHOD_NOT_ALLOWED', message: 'Only POST requests allowed' }),
        { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Require delivery staff authentication
    const auth = await requireDeliveryStaff(req);
    const supabase = getServiceClient();

    // Parse request body
    const body: VerifyDeliveryRequest = await req.json();

    if (!body.order_id || !body.otp) {
      return new Response(
        JSON.stringify({ error: 'INVALID_INPUT', message: 'order_id and otp are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate OTP format (4 digits)
    if (!/^\d{4}$/.test(body.otp)) {
      return new Response(
        JSON.stringify({ error: 'INVALID_OTP', message: 'OTP must be 4 digits' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get order
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('*, user:users(phone)')
      .eq('id', body.order_id)
      .single();

    if (orderError || !order) {
      return new Response(
        JSON.stringify({ error: 'ORDER_NOT_FOUND', message: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Verify this order is assigned to the requesting delivery staff
    if (order.delivery_staff_id !== auth.userId) {
      return new Response(
        JSON.stringify({ error: 'NOT_ASSIGNED', message: 'This order is not assigned to you' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Verify order is in correct status
    if (order.status !== 'out_for_delivery') {
      return new Response(
        JSON.stringify({ error: 'INVALID_STATUS', message: `Order is ${order.status}, not out for delivery` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check OTP expiry
    if (!order.delivery_otp_hash || !order.delivery_otp_expires) {
      return new Response(
        JSON.stringify({ error: 'NO_OTP', message: 'Delivery OTP not set for this order' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (new Date(order.delivery_otp_expires) < new Date()) {
      return new Response(
        JSON.stringify({ error: 'OTP_EXPIRED', message: 'Delivery OTP has expired. Please contact admin.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Verify OTP
    const otpHash = await hashOTP(body.otp);

    if (otpHash !== order.delivery_otp_hash) {
      return new Response(
        JSON.stringify({ error: 'INVALID_OTP', message: 'Invalid delivery OTP' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
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
      return new Response(
        JSON.stringify({ error: 'SERVER_ERROR', message: 'Failed to update order' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
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

    return new Response(
      JSON.stringify({
        success: true,
        order: {
          id: updatedOrder.id,
          order_number: updatedOrder.order_number,
          status: updatedOrder.status,
        },
        message: 'Delivery completed successfully',
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    if (error instanceof Error && error.name === 'AuthError') {
      return new Response(
        JSON.stringify({ error: 'UNAUTHORIZED', message: error.message }),
        { status: (error as { status?: number }).status || 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.error('Verify delivery OTP error:', error);
    return new Response(
      JSON.stringify({ error: 'SERVER_ERROR', message: 'An unexpected error occurred' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
}

// For standalone execution
Deno.serve(handler);
