// Porter Webhook Edge Function
// POST /functions/v1/porter-webhook
// Receives webhook events from Porter and updates delivery/order status
// No JWT auth - uses webhook signature verification

import { getServiceClient } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { parseWebhookEvent, PORTER_STATUS_MAP } from "../_shared/porter.ts";
import { sendOrderPush } from "../_shared/push.ts";
import { sendSMS } from "../_shared/sms.ts";

// Porter webhook event types
const PORTER_EVENTS = {
  ORDER_ALLOCATED: 'order_allocated',
  ORDER_REACHED_FOR_PICKUP: 'order_reached_for_pickup',
  ORDER_PICKED_UP: 'order_picked_up',
  ORDER_REACHED_FOR_DROP: 'order_reached_for_drop',
  ORDER_ENDED: 'order_ended',
  ORDER_CANCELLED: 'order_cancelled',
};

export async function handler(req: Request): Promise<Response> {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabase = getServiceClient();

  try {
    // Only allow POST
    if (req.method !== 'POST') {
      return errorResponse('METHOD_NOT_ALLOWED', 'Only POST requests allowed', 405);
    }

    // Parse webhook payload
    const rawBody = await req.text();
    let payload: unknown;

    try {
      payload = JSON.parse(rawBody);
    } catch {
      return errorResponse('INVALID_JSON', 'Invalid JSON payload', 400);
    }

    // Parse the event
    const event = parseWebhookEvent(payload);

    if (!event.order_id) {
      return errorResponse('MISSING_ORDER_ID', 'order_id is required in webhook payload', 400);
    }

    // Find the porter_delivery record by porter_order_id
    const { data: porterDelivery, error: findError } = await supabase
      .from('porter_deliveries')
      .select('*, orders!inner(id, order_number, user_id, shipping_phone, status)')
      .eq('porter_order_id', event.order_id)
      .single();

    // Log webhook regardless of whether we found the order
    await supabase
      .from('porter_webhooks')
      .insert({
        order_id: porterDelivery?.order_id || null,
        porter_order_id: event.order_id,
        event_type: event.event_type,
        payload: payload as Record<string, unknown>,
        processed_at: porterDelivery ? new Date().toISOString() : null,
        error: findError ? 'Porter delivery not found' : null,
      });

    if (findError || !porterDelivery) {
      console.error('Porter delivery not found:', event.order_id);
      // Return 200 to acknowledge receipt (Porter may retry otherwise)
      return jsonResponse({
        success: false,
        message: 'Porter delivery not found',
        porter_order_id: event.order_id,
      });
    }

    const order = porterDelivery.orders as {
      id: string;
      order_number: string;
      user_id: string;
      shipping_phone: string;
      status: string;
    };

    // Build update data for porter_deliveries
    const updateData: Record<string, unknown> = {
      porter_status: event.status || event.event_type,
    };

    // Update driver info if provided
    if (event.partner_info) {
      if (event.partner_info.name) updateData.driver_name = event.partner_info.name;
      if (event.partner_info.mobile) updateData.driver_phone = event.partner_info.mobile;
      if (event.partner_info.vehicle_number) updateData.vehicle_number = event.partner_info.vehicle_number;
    }

    // Update timestamps based on event
    if (event.actual_pickup_time) {
      updateData.actual_pickup_time = event.actual_pickup_time;
    }
    if (event.actual_drop_time) {
      updateData.actual_delivery_time = event.actual_drop_time;
    }
    if (event.fare) {
      updateData.final_fare_paise = Math.round(event.fare * 100);
    }

    // Update porter_deliveries
    await supabase
      .from('porter_deliveries')
      .update(updateData)
      .eq('id', porterDelivery.id);

    // Handle order status updates based on event type
    let orderStatusUpdate: string | null = null;
    let customerMessage: string | null = null;

    switch (event.event_type.toLowerCase()) {
      case 'order_allocated':
      case 'allocated':
        // Driver assigned - notify customer
        customerMessage = `Driver ${event.partner_info?.name || 'assigned'} is on the way to pick up your order ${order.order_number}`;
        break;

      case 'order_picked_up':
      case 'picked_up':
        // Order picked up from store
        customerMessage = `Your order ${order.order_number} has been picked up and is on the way`;
        break;

      case 'order_reached_for_drop':
      case 'reached_for_drop':
        // Driver near customer
        customerMessage = `Your order ${order.order_number} is arriving. Please be ready to receive.`;
        break;

      case 'order_ended':
      case 'ended':
        // Delivery completed
        if (order.status !== 'delivered') {
          orderStatusUpdate = 'delivered';
          customerMessage = `Your order ${order.order_number} has been delivered. Thank you for shopping with Masala Spice Shop!`;
        }
        break;

      case 'order_cancelled':
      case 'cancelled':
        // Delivery cancelled by Porter
        if (order.status !== 'delivery_failed' && order.status !== 'cancelled') {
          orderStatusUpdate = 'delivery_failed';
          customerMessage = `Delivery attempt for order ${order.order_number} was unsuccessful. We'll contact you shortly.`;
        }
        break;
    }

    // Update order status if needed
    if (orderStatusUpdate) {
      await supabase
        .from('orders')
        .update({
          status: orderStatusUpdate,
          failure_reason: orderStatusUpdate === 'delivery_failed'
            ? 'Porter delivery cancelled'
            : null,
        })
        .eq('id', order.id);

      // Record status history
      await supabase
        .from('order_status_history')
        .insert({
          order_id: order.id,
          from_status: order.status,
          to_status: orderStatusUpdate,
          changed_by: null, // System-initiated
          notes: `Porter webhook: ${event.event_type}`,
        });
    }

    // Send notifications to customer
    if (customerMessage) {
      // Send SMS
      sendSMS({
        phone: order.shipping_phone,
        message: customerMessage,
        variables: {
          order_number: order.order_number,
        },
      }).catch(console.error);

      // Send push notification
      sendOrderPush(
        order.user_id,
        order.order_number,
        orderStatusUpdate || event.event_type
      ).catch(console.error);
    }

    // Update webhook record as processed
    await supabase
      .from('porter_webhooks')
      .update({
        processed_at: new Date().toISOString(),
      })
      .eq('porter_order_id', event.order_id)
      .eq('event_type', event.event_type)
      .is('processed_at', null);

    return jsonResponse({
      success: true,
      message: 'Webhook processed',
      order_id: order.id,
      event_type: event.event_type,
      order_status_updated: orderStatusUpdate !== null,
    });
  } catch (error) {
    console.error('Porter webhook error:', error);

    // Log the error but return 200 to prevent retries
    return jsonResponse({
      success: false,
      message: 'Webhook processing failed',
      error: String(error),
    });
  }
}

// For standalone execution
Deno.serve(handler);
