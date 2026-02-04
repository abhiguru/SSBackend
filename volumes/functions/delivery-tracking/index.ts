// Delivery Tracking Edge Function (Customer)
// GET /functions/v1/delivery-tracking?order_id={uuid}
// Returns delivery staff location for customer's order

import { getServiceClient, requireAuth } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

export async function handler(req: Request): Promise<Response> {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Only allow GET
    if (req.method !== 'GET') {
      return errorResponse('METHOD_NOT_ALLOWED', 'Only GET requests allowed', 405);
    }

    // Require authentication
    const auth = await requireAuth(req);
    const supabase = getServiceClient();

    // Parse order_id from query string
    const url = new URL(req.url);
    const orderId = url.searchParams.get('order_id');

    if (!orderId) {
      return errorResponse('INVALID_INPUT', 'order_id query parameter is required', 400);
    }

    // Validate UUID format
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(orderId)) {
      return errorResponse('INVALID_INPUT', 'order_id must be a valid UUID', 400);
    }

    // First check if order exists and belongs to user
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('id, status, delivery_method, delivery_staff_id')
      .eq('id', orderId)
      .eq('user_id', auth.userId)
      .single();

    if (orderError || !order) {
      return errorResponse('ORDER_NOT_FOUND', 'Order not found', 404);
    }

    // Check delivery method
    if (order.delivery_method !== 'in_house') {
      return errorResponse('SHIPROCKET_ORDER', 'Use Shiprocket tracking for this order', 400);
    }

    // Check order status
    if (order.status !== 'out_for_delivery') {
      return errorResponse('NOT_OUT_FOR_DELIVERY', `Order is ${order.status}, not out for delivery`, 400);
    }

    // Get tracking data via RPC function
    const { data: trackingData, error: trackingError } = await supabase
      .rpc('get_delivery_tracking', {
        p_order_id: orderId,
        p_user_id: auth.userId,
      });

    if (trackingError) {
      console.error('Failed to get tracking data:', trackingError);
      return errorResponse('SERVER_ERROR', 'Failed to get tracking data', 500);
    }

    // The RPC returns an array, get the first row
    const tracking = trackingData?.[0];

    if (!tracking) {
      return errorResponse('ORDER_NOT_FOUND', 'Order not found or not eligible for tracking', 404);
    }

    // Build response
    const response = {
      success: true,
      tracking: {
        staff_location: tracking.staff_lat && tracking.staff_lng
          ? {
              latitude: parseFloat(tracking.staff_lat),
              longitude: parseFloat(tracking.staff_lng),
            }
          : null,
        staff_name: tracking.staff_name,
        staff_phone: tracking.staff_phone,
        eta_minutes: null, // Not implemented in v1
        last_updated: tracking.last_updated,
      },
    };

    return jsonResponse(response);
  } catch (error) {
    return handleError(error, 'Delivery tracking');
  }
}

// For standalone execution
Deno.serve(handler);
