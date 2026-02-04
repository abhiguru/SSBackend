// Notify Arrival Edge Function (Delivery Staff)
// POST /functions/v1/notify-arrival
// Sends push notification to customer that delivery person has arrived

import { getServiceClient, requireDeliveryStaff } from "../_shared/auth.ts";
import { sendPush } from "../_shared/push.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

interface NotifyArrivalRequest {
  order_id: string;
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
    const body: NotifyArrivalRequest = await req.json();

    if (!body.order_id) {
      return errorResponse('INVALID_INPUT', 'order_id is required', 400);
    }

    // Validate UUID format
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(body.order_id)) {
      return errorResponse('INVALID_INPUT', 'order_id must be a valid UUID', 400);
    }

    // Get order details
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('id, order_number, status, delivery_staff_id, user_id')
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

    // Send push notification to customer
    const pushSent = await sendPush(order.user_id, {
      title: 'Delivery Arriving',
      body: `Your delivery person for order ${order.order_number} has arrived!`,
      data: {
        type: 'delivery_arrival',
        order_id: order.id,
        order_number: order.order_number,
      },
      channelId: 'orders',
    });

    return jsonResponse({
      success: true,
      message: 'Customer notified',
      notification_sent: pushSent,
    });
  } catch (error) {
    return handleError(error, 'Notify arrival');
  }
}

// For standalone execution
Deno.serve(handler);
