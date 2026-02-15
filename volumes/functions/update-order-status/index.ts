// Update Order Status Edge Function (Admin only)
// POST /functions/v1/update-order-status
// Body: { order_id, status, delivery_staff_id?, notes? }

import { getServiceClient, requireAdmin, generateDeliveryOTP, hashOTP } from "../_shared/auth.ts";
import { sendOrderPush, sendDeliveryAssignmentPush } from "../_shared/push.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";
import { srFetchJSON } from "../_shared/shiprocket.ts";

interface UpdateStatusRequest {
  order_id: string;
  status: 'confirmed' | 'out_for_delivery' | 'cancelled';
  delivery_staff_id?: string;
  notes?: string;
  cancellation_reason?: string;
  estimated_delivery_at?: string;  // ISO 8601 datetime
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
      return errorResponse('METHOD_NOT_ALLOWED', 'Only POST requests allowed', 405);
    }

    // Require admin authentication
    const auth = await requireAdmin(req);
    const supabase = getServiceClient();

    // Parse request body
    const body: UpdateStatusRequest = await req.json();

    if (!body.order_id || !body.status) {
      return errorResponse('INVALID_INPUT', 'order_id and status are required', 400);
    }

    // Get current order
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('*, user:users!orders_user_id_fkey(phone)')
      .eq('id', body.order_id)
      .single();

    if (orderError || !order) {
      return errorResponse('ORDER_NOT_FOUND', 'Order not found', 404);
    }

    // Validate status transition
    const currentStatus = order.status as string;
    const newStatus = body.status;

    const allowedTransitions = validTransitions[currentStatus] || [];
    if (!allowedTransitions.includes(newStatus)) {
      return errorResponse(
        'INVALID_TRANSITION',
        `Cannot change status from ${currentStatus} to ${newStatus}`,
        400,
        { allowed_transitions: allowedTransitions },
      );
    }

    // Guard: Shiprocket orders must use dedicated endpoints for shipping
    if (order.delivery_method === 'shiprocket' && newStatus === 'out_for_delivery') {
      return errorResponse(
        'USE_SHIPROCKET',
        'This order uses Shiprocket delivery. Use shiprocket-assign-courier to ship it.',
        400,
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
        return errorResponse('MISSING_DELIVERY_STAFF', 'Delivery staff must be assigned', 400);
      }

      // Verify delivery staff exists and has correct role
      const { data: deliveryStaff, error: staffError } = await supabase
        .from('users')
        .select('id, role, is_active, name')
        .eq('id', body.delivery_staff_id)
        .single();

      if (staffError || !deliveryStaff) {
        return errorResponse('INVALID_DELIVERY_STAFF', 'Delivery staff not found', 400);
      }

      if (deliveryStaff.role !== 'delivery_staff') {
        return errorResponse('INVALID_DELIVERY_STAFF', 'User is not a delivery staff member', 400);
      }

      if (!deliveryStaff.is_active) {
        return errorResponse('INVALID_DELIVERY_STAFF', 'Delivery staff account is deactivated', 400);
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

      // Notify delivery staff
      const address = `${order.shipping_address_line1}, ${order.shipping_city}`;
      sendDeliveryAssignmentPush(body.delivery_staff_id, order.order_number, address).catch(console.error);
    }

    if (newStatus === 'confirmed') {
      // Accept optional estimated delivery datetime
      if (body.estimated_delivery_at) {
        const parsed = new Date(body.estimated_delivery_at);
        if (isNaN(parsed.getTime())) {
          return errorResponse('INVALID_INPUT', 'estimated_delivery_at must be a valid ISO 8601 datetime', 400);
        }
        updateData.estimated_delivery_at = body.estimated_delivery_at;
      }
    }

    if (newStatus === 'cancelled') {
      updateData.cancellation_reason = body.cancellation_reason || body.notes || 'Cancelled by admin';

      // Also cancel on Shiprocket if applicable
      if (order.delivery_method === 'shiprocket') {
        const { data: shipment } = await supabase
          .from('shiprocket_shipments')
          .select('sr_order_id')
          .eq('order_id', body.order_id)
          .single();

        if (shipment?.sr_order_id) {
          srFetchJSON('/orders/cancel', {
            method: 'POST',
            body: JSON.stringify({ ids: [shipment.sr_order_id] }),
          }).catch((err: unknown) => console.error('Shiprocket cancel failed:', err));
        }
      }
    }

    // Build update data for RPC (only non-status fields)
    const rpcUpdateData: Record<string, unknown> = {};
    if (updateData.delivery_staff_id !== undefined) rpcUpdateData.delivery_staff_id = updateData.delivery_staff_id;
    if (updateData.delivery_otp_hash !== undefined) rpcUpdateData.delivery_otp_hash = updateData.delivery_otp_hash;
    if (updateData.delivery_otp_expires !== undefined) rpcUpdateData.delivery_otp_expires = updateData.delivery_otp_expires;
    if (updateData.cancellation_reason !== undefined) rpcUpdateData.cancellation_reason = updateData.cancellation_reason;
    if (updateData.estimated_delivery_at !== undefined) rpcUpdateData.estimated_delivery_at = updateData.estimated_delivery_at;

    // Update order + record status history atomically
    const { data: orderResult, error: updateError } = await supabase.rpc('update_order_status_atomic', {
      p_order_id: body.order_id,
      p_from_status: currentStatus,
      p_to_status: newStatus,
      p_changed_by: auth.userId,
      p_notes: body.notes || null,
      p_update_data: rpcUpdateData,
    });

    if (updateError) {
      console.error('Failed to update order:', updateError);
      if (updateError.message?.includes('status has changed')) {
        return errorResponse('STATUS_CHANGED', 'Order status was modified by another request', 409);
      }
      return errorResponse('SERVER_ERROR', 'Failed to update order', 500);
    }

    // Send push notification to customer
    sendOrderPush(order.user_id, order.order_number, newStatus, order.id).catch(console.error);

    return jsonResponse({
      success: true,
      order: {
        id: orderResult.id,
        order_number: orderResult.order_number,
        status: orderResult.status,
        previous_status: currentStatus,
      },
      message: `Order status updated to ${newStatus}`,
    });
  } catch (error) {
    return handleError(error, 'Update order status');
  }
}

// For standalone execution
Deno.serve(handler);
