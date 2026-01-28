// Porter Cancel Edge Function (Admin only)
// POST /functions/v1/porter-cancel
// Body: { order_id, reason?, fallback_to_inhouse?: boolean }
// Cancels a Porter delivery and optionally falls back to in-house

import { getServiceClient, requireAdmin } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";
import { cancelOrder as cancelPorterOrder } from "../_shared/porter.ts";

interface CancelRequest {
  order_id: string;
  reason?: string;
  fallback_to_inhouse?: boolean;
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

    // Require admin authentication
    const auth = await requireAdmin(req);
    const supabase = getServiceClient();

    // Parse request body
    const body: CancelRequest = await req.json();

    if (!body.order_id) {
      return errorResponse('INVALID_INPUT', 'order_id is required', 400);
    }

    // Get order
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('*')
      .eq('id', body.order_id)
      .single();

    if (orderError || !order) {
      return errorResponse('ORDER_NOT_FOUND', 'Order not found', 404);
    }

    // Verify order is using Porter delivery
    if (order.delivery_type !== 'porter') {
      return errorResponse(
        'NOT_PORTER_DELIVERY',
        'This order is not using Porter delivery',
        400
      );
    }

    // Get porter_deliveries record
    const { data: porterDelivery, error: porterError } = await supabase
      .from('porter_deliveries')
      .select('*')
      .eq('order_id', body.order_id)
      .single();

    if (porterError || !porterDelivery) {
      return errorResponse('PORTER_NOT_FOUND', 'Porter delivery record not found', 404);
    }

    // Check if already cancelled or delivered
    if (porterDelivery.porter_status === 'cancelled') {
      return errorResponse('ALREADY_CANCELLED', 'Porter delivery already cancelled', 400);
    }

    if (porterDelivery.porter_status === 'ended' || order.status === 'delivered') {
      return errorResponse('ALREADY_DELIVERED', 'Order already delivered', 400);
    }

    // Cancel with Porter API
    const cancelResult = await cancelPorterOrder(
      porterDelivery.crn,
      body.reason || 'Cancelled by merchant'
    );

    if (!cancelResult.success) {
      console.error('Porter cancellation failed:', cancelResult.message);
      // Continue anyway to update local status - Porter may have already cancelled
    }

    // Update porter_deliveries status
    await supabase
      .from('porter_deliveries')
      .update({
        porter_status: 'cancelled',
      })
      .eq('id', porterDelivery.id);

    // Determine new order status based on fallback option
    let newStatus: string;
    let newDeliveryType: string;
    let historyNotes: string;

    if (body.fallback_to_inhouse) {
      // Reset to confirmed for re-dispatch with in-house delivery
      newStatus = 'confirmed';
      newDeliveryType = 'in_house';
      historyNotes = `Porter delivery cancelled: ${body.reason || 'No reason'}. Returned to dispatch queue for in-house assignment.`;
    } else {
      // Mark as delivery_failed
      newStatus = 'delivery_failed';
      newDeliveryType = order.delivery_type; // Keep as porter for records
      historyNotes = `Porter delivery cancelled: ${body.reason || 'No reason'}`;
    }

    // Update order
    const { error: updateError } = await supabase
      .from('orders')
      .update({
        status: newStatus,
        delivery_type: newDeliveryType,
        failure_reason: body.fallback_to_inhouse ? null : (body.reason || 'Porter delivery cancelled'),
      })
      .eq('id', body.order_id);

    if (updateError) {
      console.error('Failed to update order:', updateError);
      return errorResponse('DATABASE_ERROR', 'Failed to update order status', 500);
    }

    // Record status history
    await supabase
      .from('order_status_history')
      .insert({
        order_id: body.order_id,
        from_status: order.status,
        to_status: newStatus,
        changed_by: auth.userId,
        notes: historyNotes,
      });

    return jsonResponse({
      success: true,
      order_id: body.order_id,
      order_number: order.order_number,
      porter_cancelled: cancelResult.success,
      new_status: newStatus,
      fallback_to_inhouse: body.fallback_to_inhouse || false,
      message: body.fallback_to_inhouse
        ? 'Porter cancelled. Order returned to dispatch queue.'
        : 'Porter delivery cancelled.',
    });
  } catch (error) {
    return handleError(error, 'Porter cancel');
  }
}

// For standalone execution
Deno.serve(handler);
