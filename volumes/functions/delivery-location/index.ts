// Delivery Location Edge Function (Delivery Staff)
// POST /functions/v1/delivery-location
// Updates the delivery staff's current GPS location

import { getServiceClient, requireDeliveryStaff } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

interface LocationUpdateRequest {
  latitude: number;
  longitude: number;
  accuracy?: number;
  timestamp?: string;
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
    const body: LocationUpdateRequest = await req.json();

    // Validate required fields
    if (body.latitude === undefined || body.longitude === undefined) {
      return errorResponse('INVALID_INPUT', 'latitude and longitude are required', 400);
    }

    // Validate latitude range (-90 to 90)
    if (typeof body.latitude !== 'number' || body.latitude < -90 || body.latitude > 90) {
      return errorResponse('INVALID_INPUT', 'latitude must be between -90 and 90', 400);
    }

    // Validate longitude range (-180 to 180)
    if (typeof body.longitude !== 'number' || body.longitude < -180 || body.longitude > 180) {
      return errorResponse('INVALID_INPUT', 'longitude must be between -180 and 180', 400);
    }

    // Validate accuracy if provided (must be positive)
    if (body.accuracy !== undefined && (typeof body.accuracy !== 'number' || body.accuracy < 0)) {
      return errorResponse('INVALID_INPUT', 'accuracy must be a positive number', 400);
    }

    // Parse timestamp or use current time
    let recordedAt: Date;
    if (body.timestamp) {
      recordedAt = new Date(body.timestamp);
      if (isNaN(recordedAt.getTime())) {
        return errorResponse('INVALID_INPUT', 'timestamp must be a valid ISO 8601 date', 400);
      }
    } else {
      recordedAt = new Date();
    }

    // UPSERT location (insert or update if exists)
    const { error: upsertError } = await supabase
      .from('delivery_staff_locations')
      .upsert({
        delivery_staff_id: auth.userId,
        lat: body.latitude,
        lng: body.longitude,
        accuracy_meters: body.accuracy ?? null,
        recorded_at: recordedAt.toISOString(),
        updated_at: new Date().toISOString(),
      }, {
        onConflict: 'delivery_staff_id',
      });

    if (upsertError) {
      console.error('Failed to update location:', upsertError);
      return errorResponse('SERVER_ERROR', 'Failed to update location', 500);
    }

    return jsonResponse({
      success: true,
      message: 'Location updated',
    });
  } catch (error) {
    return handleError(error, 'Delivery location update');
  }
}

// For standalone execution
Deno.serve(handler);
