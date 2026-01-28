// Porter Mock Event Edge Function (Admin only)
// POST /functions/v1/porter-mock-event
// Simulates Porter webhook events for testing
// Only available when PORTER_ENV=mock

import { getServiceClient, requireAdmin } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

interface MockEventRequest {
  order_id: string;
  event: 'allocated' | 'picked_up' | 'in_transit' | 'delivered' | 'cancelled';
  driver_name?: string;
  driver_phone?: string;
  vehicle_number?: string;
}

// Map mock events to Porter event types
const EVENT_MAP: Record<string, string> = {
  'allocated': 'order_allocated',
  'picked_up': 'order_picked_up',
  'in_transit': 'order_reached_for_drop',
  'delivered': 'order_ended',
  'cancelled': 'order_cancelled',
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

    // Check if mock mode is enabled
    const porterEnv = Deno.env.get('PORTER_ENV') ?? 'mock';
    if (porterEnv !== 'mock') {
      return errorResponse(
        'NOT_MOCK_MODE',
        'Mock events are only available when PORTER_ENV=mock',
        403
      );
    }

    // Require admin authentication
    await requireAdmin(req);
    const supabase = getServiceClient();

    // Parse request body
    const body: MockEventRequest = await req.json();

    if (!body.order_id || !body.event) {
      return errorResponse('INVALID_INPUT', 'order_id and event are required', 400);
    }

    const validEvents = ['allocated', 'picked_up', 'in_transit', 'delivered', 'cancelled'];
    if (!validEvents.includes(body.event)) {
      return errorResponse(
        'INVALID_EVENT',
        `Invalid event. Must be one of: ${validEvents.join(', ')}`,
        400
      );
    }

    // Get porter_delivery record
    const { data: porterDelivery, error: findError } = await supabase
      .from('porter_deliveries')
      .select('*, orders!inner(id, order_number, status)')
      .eq('order_id', body.order_id)
      .single();

    if (findError || !porterDelivery) {
      return errorResponse('NOT_FOUND', 'Porter delivery not found for this order', 404);
    }

    // Build mock webhook payload
    const mockPayload = {
      order_id: porterDelivery.porter_order_id,
      request_id: body.order_id,
      event_type: EVENT_MAP[body.event],
      status: body.event === 'delivered' ? 'ended' : body.event,
      partner_info: body.event === 'allocated' || body.event === 'picked_up' ? {
        name: body.driver_name || 'Mock Driver',
        mobile: body.driver_phone || '+919876543210',
        vehicle_number: body.vehicle_number || 'GJ01AB1234',
      } : undefined,
      actual_pickup_time: body.event === 'picked_up' ? new Date().toISOString() : undefined,
      actual_drop_time: body.event === 'delivered' ? new Date().toISOString() : undefined,
      fare: body.event === 'delivered' ? 85 : undefined, // Mock fare in rupees
    };

    // Call the webhook handler internally
    // We'll make an internal request to the webhook endpoint
    const webhookUrl = `${Deno.env.get('SUPABASE_URL') ?? 'http://kong:8000'}/functions/v1/porter-webhook`;

    const webhookResponse = await fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      },
      body: JSON.stringify(mockPayload),
    });

    const webhookResult = await webhookResponse.json();

    // Get updated porter_delivery status
    const { data: updatedDelivery } = await supabase
      .from('porter_deliveries')
      .select('porter_status, driver_name, driver_phone, vehicle_number')
      .eq('order_id', body.order_id)
      .single();

    // Get updated order status
    const { data: updatedOrder } = await supabase
      .from('orders')
      .select('status')
      .eq('id', body.order_id)
      .single();

    return jsonResponse({
      success: true,
      event_sent: body.event,
      porter_event: EVENT_MAP[body.event],
      webhook_result: webhookResult,
      updated_status: {
        porter_status: updatedDelivery?.porter_status,
        order_status: updatedOrder?.status,
        driver_name: updatedDelivery?.driver_name,
        driver_phone: updatedDelivery?.driver_phone,
        vehicle_number: updatedDelivery?.vehicle_number,
      },
      message: `Mock ${body.event} event processed`,
    });
  } catch (error) {
    return handleError(error, 'Porter mock event');
  }
}

// For standalone execution
Deno.serve(handler);
