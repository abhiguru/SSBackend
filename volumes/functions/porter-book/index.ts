// Porter Book Edge Function (Admin only)
// POST /functions/v1/porter-book
// Body: { order_id }
// Creates a Porter delivery order and updates order status

import { getServiceClient, requireAdmin } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";
import { createOrder as createPorterOrder } from "../_shared/porter.ts";
import { geocodeAddress, buildAddressString } from "../_shared/geocoding.ts";
import { sendSMS } from "../_shared/sms.ts";

interface BookRequest {
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
    const auth = await requireAdmin(req);
    const supabase = getServiceClient();

    // Parse request body
    const body: BookRequest = await req.json();

    if (!body.order_id) {
      return errorResponse('INVALID_INPUT', 'order_id is required', 400);
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

    // Validate order status - can only book for confirmed orders
    if (order.status !== 'confirmed' && order.status !== 'delivery_failed') {
      return errorResponse(
        'INVALID_ORDER_STATUS',
        `Cannot book Porter for order with status: ${order.status}. Order must be confirmed.`,
        400
      );
    }

    // Check if order already has a Porter delivery
    const { data: existingPorter } = await supabase
      .from('porter_deliveries')
      .select('id, porter_status')
      .eq('order_id', body.order_id)
      .maybeSingle();

    if (existingPorter && existingPorter.porter_status !== 'cancelled') {
      return errorResponse(
        'PORTER_ALREADY_BOOKED',
        'This order already has an active Porter delivery',
        400
      );
    }

    // Get store pickup details from app_settings
    const settingsKeys = [
      'porter_pickup_lat',
      'porter_pickup_lng',
      'porter_pickup_address',
      'porter_pickup_name',
      'porter_pickup_phone',
    ];

    const { data: settings } = await supabase
      .from('app_settings')
      .select('key, value')
      .in('key', settingsKeys);

    const settingsMap: Record<string, string> = {};
    settings?.forEach(s => {
      // PostgREST returns JSONB as already-parsed values, so use directly
      settingsMap[s.key] = typeof s.value === 'string' ? s.value : String(s.value);
    });

    if (!settingsMap.porter_pickup_lat || !settingsMap.porter_pickup_lng) {
      return errorResponse(
        'CONFIG_ERROR',
        'Store pickup coordinates not configured',
        500
      );
    }

    // Build customer address
    const customerAddress = buildAddressString({
      shipping_address_line1: order.shipping_address_line1,
      shipping_address_line2: order.shipping_address_line2,
      shipping_city: order.shipping_city,
      shipping_state: order.shipping_state,
      shipping_pincode: order.shipping_pincode,
    });

    // Try cached coordinates from user_addresses first
    let dropCoords;
    if (order.address_id) {
      const { data: addr } = await supabase
        .from('user_addresses')
        .select('lat, lng, formatted_address')
        .eq('id', order.address_id)
        .single();

      if (addr?.lat && addr?.lng) {
        dropCoords = { lat: Number(addr.lat), lng: Number(addr.lng), formatted_address: addr.formatted_address };
      }
    }

    // Fall back to geocoding if no cached coordinates
    if (!dropCoords) {
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
    }

    // Create Porter order
    const porterResponse = await createPorterOrder({
      order_id: body.order_id,
      order_number: order.order_number,
      pickup: {
        lat: parseFloat(settingsMap.porter_pickup_lat),
        lng: parseFloat(settingsMap.porter_pickup_lng),
        address: settingsMap.porter_pickup_address || 'Masala Spice Shop, Ahmedabad',
        name: settingsMap.porter_pickup_name || 'Masala Spice Shop',
        phone: settingsMap.porter_pickup_phone || '+919876543210',
      },
      drop: {
        lat: dropCoords.lat,
        lng: dropCoords.lng,
        address: customerAddress,
        name: order.shipping_name,
        phone: order.shipping_phone,
      },
      customer: {
        name: order.shipping_name,
        phone: order.shipping_phone,
      },
      order_value_paise: order.total_paise,
    });

    // Prepare porter_deliveries data
    const porterData = {
      porter_order_id: porterResponse.porter_order_id,
      crn: porterResponse.crn,
      tracking_url: porterResponse.tracking_url,
      pickup_lat: parseFloat(settingsMap.porter_pickup_lat),
      pickup_lng: parseFloat(settingsMap.porter_pickup_lng),
      drop_lat: dropCoords.lat,
      drop_lng: dropCoords.lng,
      porter_status: 'live',
      estimated_pickup_time: porterResponse.estimated_pickup_time,
      estimated_delivery_time: porterResponse.estimated_delivery_time,
      // Clear previous delivery data
      driver_name: null,
      driver_phone: null,
      vehicle_number: null,
      actual_pickup_time: null,
      actual_delivery_time: null,
      quoted_fare_paise: null,
      final_fare_paise: null,
    };

    let porterRecord;
    let dbError;

    if (existingPorter) {
      // Update existing cancelled record
      console.log('Updating existing porter_deliveries:', existingPorter.id);
      const { data, error } = await supabase
        .from('porter_deliveries')
        .update(porterData)
        .eq('id', existingPorter.id)
        .select()
        .single();
      porterRecord = data;
      dbError = error;
    } else {
      // Insert new record
      console.log('Inserting new porter_deliveries for order:', body.order_id);
      const { data, error } = await supabase
        .from('porter_deliveries')
        .insert({ order_id: body.order_id, ...porterData })
        .select()
        .single();
      porterRecord = data;
      dbError = error;
    }

    if (dbError) {
      console.error('Failed to save porter_deliveries:', JSON.stringify(dbError));
      return errorResponse('DATABASE_ERROR', `Failed to record Porter delivery: ${dbError.message}`, 500);
    }
    console.log('Saved porter_deliveries:', JSON.stringify(porterRecord));

    // Update order status to out_for_delivery with delivery_type = porter
    const { error: updateError } = await supabase
      .from('orders')
      .update({
        status: 'out_for_delivery',
        delivery_type: 'porter',
        // Clear in-house delivery fields
        delivery_staff_id: null,
        delivery_otp_hash: null,
        delivery_otp_expires: null,
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
        to_status: 'out_for_delivery',
        changed_by: auth.userId,
        notes: `Porter delivery booked. Order ID: ${porterResponse.porter_order_id}`,
      });

    // Send SMS to customer with tracking link
    const customerPhone = (order.user as { phone: string })?.phone || order.shipping_phone;
    sendSMS({
      phone: customerPhone,
      message: `Your order ${order.order_number} is out for delivery via Porter. Track: ${porterResponse.tracking_url}`,
      variables: {
        order_number: order.order_number,
        tracking_url: porterResponse.tracking_url,
      },
    }).catch(console.error);

    return jsonResponse({
      success: true,
      order_id: body.order_id,
      order_number: order.order_number,
      porter: {
        porter_order_id: porterResponse.porter_order_id,
        crn: porterResponse.crn,
        tracking_url: porterResponse.tracking_url,
        estimated_pickup_time: porterResponse.estimated_pickup_time,
        estimated_delivery_time: porterResponse.estimated_delivery_time,
      },
      message: 'Porter delivery booked successfully',
    });
  } catch (error) {
    return handleError(error, 'Porter book');
  }
}

// For standalone execution
Deno.serve(handler);
