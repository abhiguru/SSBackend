// Porter Quote Edge Function (Admin only)
// POST /functions/v1/porter-quote
// Body: { order_id }
// Returns fare estimate, ETA, and distance for Porter delivery

import { getServiceClient, requireAdmin } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";
import { getQuote } from "../_shared/porter.ts";
import { geocodeAddress, buildAddressString } from "../_shared/geocoding.ts";

interface QuoteRequest {
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

    // Require admin authentication
    await requireAdmin(req);
    const supabase = getServiceClient();

    // Parse request body
    const body: QuoteRequest = await req.json();

    if (!body.order_id) {
      return errorResponse('INVALID_INPUT', 'order_id is required', 400);
    }

    // Get order with shipping address
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('*')
      .eq('id', body.order_id)
      .single();

    if (orderError || !order) {
      return errorResponse('ORDER_NOT_FOUND', 'Order not found', 404);
    }

    // Validate order status - can only quote for confirmed orders
    if (order.status !== 'confirmed' && order.status !== 'delivery_failed') {
      return errorResponse(
        'INVALID_ORDER_STATUS',
        `Cannot get quote for order with status: ${order.status}. Order must be confirmed.`,
        400
      );
    }

    // Get store pickup coordinates from app_settings
    const { data: pickupLat } = await supabase
      .from('app_settings')
      .select('value')
      .eq('key', 'porter_pickup_lat')
      .single();

    const { data: pickupLng } = await supabase
      .from('app_settings')
      .select('value')
      .eq('key', 'porter_pickup_lng')
      .single();

    if (!pickupLat?.value || !pickupLng?.value) {
      return errorResponse(
        'CONFIG_ERROR',
        'Store pickup coordinates not configured',
        500
      );
    }

    // Build customer address string
    const customerAddress = buildAddressString({
      shipping_address_line1: order.shipping_address_line1,
      shipping_address_line2: order.shipping_address_line2,
      shipping_city: order.shipping_city,
      shipping_state: order.shipping_state,
      shipping_pincode: order.shipping_pincode,
    });

    // Geocode customer address
    let dropCoords;
    try {
      dropCoords = await geocodeAddress(customerAddress);
    } catch (geoError) {
      console.error('Geocoding failed:', geoError);
      return errorResponse(
        'GEOCODING_FAILED',
        'Could not determine delivery location coordinates',
        400
      );
    }

    // Get quote from Porter
    const pickupCoords = {
      lat: parseFloat(String(pickupLat.value)),
      lng: parseFloat(String(pickupLng.value)),
    };

    const quote = await getQuote({
      pickup: pickupCoords,
      drop: { lat: dropCoords.lat, lng: dropCoords.lng },
    });

    return jsonResponse({
      success: true,
      order_id: body.order_id,
      order_number: order.order_number,
      quote: {
        fare_paise: quote.fare_paise,
        fare_display: `₹${(quote.fare_paise / 100).toFixed(2)}`,
        estimated_minutes: quote.estimated_minutes,
        estimated_time_display: formatDuration(quote.estimated_minutes),
        distance_km: quote.distance_km,
        vehicle_type: quote.vehicle_type || 'bike',
      },
      addresses: {
        pickup: {
          lat: pickupCoords.lat,
          lng: pickupCoords.lng,
        },
        drop: {
          lat: dropCoords.lat,
          lng: dropCoords.lng,
          address: customerAddress,
          formatted_address: dropCoords.formatted_address,
        },
      },
    });
  } catch (error) {
    return handleError(error, 'Porter quote');
  }
}

function formatDuration(minutes: number): string {
  if (minutes < 60) {
    return `${minutes} min`;
  }
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`;
}

// For standalone execution
Deno.serve(handler);
