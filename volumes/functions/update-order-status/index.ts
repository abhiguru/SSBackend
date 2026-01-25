// Update Order Status Edge Function (Admin only)
// POST /functions/v1/update-order-status
// Body: { order_id, status, delivery_staff_id?, notes? }

import { getServiceClient, requireAdmin, generateDeliveryOTP, hashOTP } from "../_shared/auth.ts";
import { sendOrderPush, sendDeliveryAssignmentPush } from "../_shared/push.ts";
import { sendOrderStatusSMS, sendDeliveryOTP as sendDeliveryOTPSMS } from "../_shared/sms.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface UpdateStatusRequest {
  order_id: string;
  status: 'confirmed' | 'out_for_delivery' | 'cancelled';
  delivery_staff_id?: string;
  notes?: string;
  cancellation_reason?: string;
}

// Valid status transitions
const validTransitions: Record<string, string[]> = {
  'placed': ['confirmed', 'cancelled'],
  'confirmed': ['out_for_delivery', 'cancelled'],
  'out_for_delivery': ['delivered', 'cancelled', 'delivery_failed'],
  'delivered': [],
  'cancelled': [],
  'delivery_failed': ['out_for_delivery', 'cancelled'],
};

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

    // Require admin authentication
    const auth = await requireAdmin(req);
    const supabase = getServiceClient();

    // Parse request body
    const body: UpdateStatusRequest = await req.json();

    if (!body.order_id || !body.status) {
      return new Response(
        JSON.stringify({ error: 'INVALID_INPUT', message: 'order_id and status are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get current order
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

    // Validate status transition
    const currentStatus = order.status as string;
    const newStatus = body.status;

    const allowedTransitions = validTransitions[currentStatus] || [];
    if (!allowedTransitions.includes(newStatus)) {
      return new Response(
        JSON.stringify({
          error: 'INVALID_TRANSITION',
          message: `Cannot change status from ${currentStatus} to ${newStatus}`,
          allowed_transitions: allowedTransitions,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Prepare update data
    const updateData: Record<string, unknown> = {
      status: newStatus,
    };

    // Handle specific status requirements
    if (newStatus === 'out_for_delivery') {
      // Require delivery staff
      if (!body.delivery_staff_id) {
        return new Response(
          JSON.stringify({ error: 'MISSING_DELIVERY_STAFF', message: 'Delivery staff must be assigned' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // Verify delivery staff exists and has correct role
      const { data: deliveryStaff, error: staffError } = await supabase
        .from('users')
        .select('id, role, is_active, name')
        .eq('id', body.delivery_staff_id)
        .single();

      if (staffError || !deliveryStaff) {
        return new Response(
          JSON.stringify({ error: 'INVALID_DELIVERY_STAFF', message: 'Delivery staff not found' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      if (deliveryStaff.role !== 'delivery_staff') {
        return new Response(
          JSON.stringify({ error: 'INVALID_DELIVERY_STAFF', message: 'User is not a delivery staff member' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      if (!deliveryStaff.is_active) {
        return new Response(
          JSON.stringify({ error: 'INVALID_DELIVERY_STAFF', message: 'Delivery staff account is deactivated' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // Generate delivery OTP
      const deliveryOTP = generateDeliveryOTP();
      const otpHash = await hashOTP(deliveryOTP);

      // Get delivery OTP expiry from settings
      const { data: settings } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'delivery_otp_expiry_hours')
        .single();

      const expiryHours = settings?.value ? parseInt(settings.value) : 24;
      const otpExpiry = new Date(Date.now() + expiryHours * 60 * 60 * 1000).toISOString();

      updateData.delivery_staff_id = body.delivery_staff_id;
      updateData.delivery_otp_hash = otpHash;
      updateData.delivery_otp_expires = otpExpiry;

      // Send delivery OTP to customer
      const customerPhone = (order.user as { phone: string })?.phone || order.shipping_phone;
      sendDeliveryOTPSMS(customerPhone, order.order_number, deliveryOTP).catch(console.error);

      // Notify delivery staff
      const address = `${order.shipping_address_line1}, ${order.shipping_city}`;
      sendDeliveryAssignmentPush(body.delivery_staff_id, order.order_number, address).catch(console.error);
    }

    if (newStatus === 'cancelled') {
      updateData.cancellation_reason = body.cancellation_reason || body.notes || 'Cancelled by admin';
    }

    // Update order
    const { data: updatedOrder, error: updateError } = await supabase
      .from('orders')
      .update(updateData)
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
        from_status: currentStatus,
        to_status: newStatus,
        changed_by: auth.userId,
        notes: body.notes || null,
      });

    // Send notifications to customer
    const customerPhone = (order.user as { phone: string })?.phone || order.shipping_phone;
    sendOrderStatusSMS(customerPhone, order.order_number, newStatus).catch(console.error);
    sendOrderPush(order.user_id, order.order_number, newStatus).catch(console.error);

    return new Response(
      JSON.stringify({
        success: true,
        order: {
          id: updatedOrder.id,
          order_number: updatedOrder.order_number,
          status: updatedOrder.status,
          previous_status: currentStatus,
        },
        message: `Order status updated to ${newStatus}`,
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

    console.error('Update order status error:', error);
    return new Response(
      JSON.stringify({ error: 'SERVER_ERROR', message: 'An unexpected error occurred' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
}

// For standalone execution
Deno.serve(handler);
