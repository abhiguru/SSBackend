// Shiprocket Webhook Edge Function (Public, API key verified)
// POST /functions/v1/shiprocket-webhook
//
// Receives tracking updates from Shiprocket, logs payload,
// maps status codes to our order statuses, and updates accordingly.

import { getServiceClient } from "../_shared/auth.ts";
import { sendOrderPush } from "../_shared/push.ts";

import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse } from "../_shared/response.ts";
import { mapSRStatusToOrderStatus } from "../_shared/shiprocket.ts";

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Always return 200 to Shiprocket (even on errors) to prevent retries
  const ok = () => jsonResponse({ success: true });

  try {
    if (req.method !== "POST") {
      return ok();
    }

    // Verify webhook token
    const webhookToken = Deno.env.get("SHIPROCKET_WEBHOOK_TOKEN");
    if (!webhookToken) {
      console.error("SHIPROCKET_WEBHOOK_TOKEN not configured");
      return ok();
    }

    // Shiprocket sends token in X-API-Key or anx-api-key header
    const receivedToken =
      req.headers.get("anx-api-key") ||
      req.headers.get("x-api-key");

    if (receivedToken !== webhookToken) {
      console.error("Webhook token mismatch");
      return ok();
    }

    const payload = await req.json();
    const supabase = getServiceClient();

    // Extract key fields from webhook payload
    const awb = payload.awb || payload.awb_code || null;
    const srShipmentId = payload.shipment_id ? Number(payload.shipment_id) : null;
    const currentStatusCode = payload.current_status_id ? Number(payload.current_status_id) : null;
    const currentStatus = payload.current_status || null;

    // Log webhook payload
    const { error: logError } = await supabase
      .from("shiprocket_webhooks")
      .insert({
        payload,
        event_status: currentStatus,
        awb_code: awb,
        sr_shipment_id: srShipmentId,
      });

    if (logError) {
      console.error("Failed to log webhook:", logError);
    }

    if (!awb && !srShipmentId) {
      console.log("Webhook missing AWB and shipment_id, skipping");
      return ok();
    }

    if (currentStatusCode === null) {
      console.log("Webhook missing current_status_id, skipping");
      return ok();
    }

    // Look up shipment by AWB or sr_shipment_id
    let query = supabase.from("shiprocket_shipments").select("*, order:orders(*)");
    if (awb) {
      query = query.eq("awb_code", awb);
    } else {
      query = query.eq("sr_shipment_id", srShipmentId!);
    }

    const { data: shipment, error: shipmentError } = await query.single();

    if (shipmentError || !shipment) {
      console.log("Shipment not found for webhook:", { awb, srShipmentId });
      // Mark webhook as processed with error
      if (!logError) {
        await supabase
          .from("shiprocket_webhooks")
          .update({ processed: true, error: "Shipment not found", processed_at: new Date().toISOString() })
          .eq("awb_code", awb)
          .order("created_at", { ascending: false })
          .limit(1);
      }
      return ok();
    }

    // Update shipment SR status
    await supabase
      .from("shiprocket_shipments")
      .update({
        sr_status: currentStatus,
        sr_status_code: currentStatusCode,
      })
      .eq("id", shipment.id);

    // Map to our order status
    const newOrderStatus = mapSRStatusToOrderStatus(currentStatusCode);
    const order = shipment.order as Record<string, unknown>;

    if (!newOrderStatus || !order) {
      // No mapping or no order — just log
      await markWebhookProcessed(supabase, awb, srShipmentId);
      return ok();
    }

    const currentOrderStatus = order.status as string;

    // Skip if order is already in terminal state or same status
    if (
      currentOrderStatus === newOrderStatus ||
      currentOrderStatus === "delivered" ||
      currentOrderStatus === "cancelled"
    ) {
      await markWebhookProcessed(supabase, awb, srShipmentId);
      return ok();
    }

    // Build update data for status transition
    const updateData: Record<string, unknown> = {};
    if (newOrderStatus === "delivery_failed") {
      updateData.failure_reason = `Shiprocket: ${currentStatus} (code: ${currentStatusCode})`;
    }

    // Update order status atomically
    try {
      const { error: updateError } = await supabase.rpc("update_order_status_atomic", {
        p_order_id: order.id,
        p_from_status: currentOrderStatus,
        p_to_status: newOrderStatus,
        p_changed_by: null, // system/webhook
        p_notes: `Shiprocket webhook: ${currentStatus} (code: ${currentStatusCode})`,
        p_update_data: updateData,
      });

      if (updateError) {
        // Likely "status has changed" — idempotency, not a real error
        console.log("Order status update skipped:", updateError.message);
        await markWebhookProcessed(supabase, awb, srShipmentId, updateError.message);
        return ok();
      }

      // Send push notification to customer
      sendOrderPush(
        order.user_id as string,
        order.order_number as string,
        newOrderStatus,
        order.id as string,
      ).catch(console.error);
    } catch (err) {
      console.error("Error updating order from webhook:", err);
      await markWebhookProcessed(supabase, awb, srShipmentId, String(err));
      return ok();
    }

    await markWebhookProcessed(supabase, awb, srShipmentId);
    return ok();
  } catch (error) {
    console.error("Webhook handler error:", error);
    return ok();
  }
}

async function markWebhookProcessed(
  supabase: ReturnType<typeof getServiceClient>,
  awb: string | null,
  srShipmentId: number | null,
  error?: string,
): Promise<void> {
  try {
    let query = supabase
      .from("shiprocket_webhooks")
      .update({
        processed: true,
        processed_at: new Date().toISOString(),
        ...(error ? { error } : {}),
      });

    if (awb) {
      query = query.eq("awb_code", awb);
    } else if (srShipmentId) {
      query = query.eq("sr_shipment_id", srShipmentId);
    }

    // Update the most recent unprocessed webhook
    await query.eq("processed", false).order("created_at", { ascending: false }).limit(1);
  } catch (err) {
    console.error("Failed to mark webhook processed:", err);
  }
}

Deno.serve(handler);
