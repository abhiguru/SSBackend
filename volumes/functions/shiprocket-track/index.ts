// Shiprocket Track Edge Function (Auth required)
// GET /functions/v1/shiprocket-track?order_id=...
//
// On-demand tracking: fetches live status from Shiprocket API
// and updates local sr_status. Available to admin or order owner.

import { getServiceClient, requireAuth } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";
import { srFetchJSON } from "../_shared/shiprocket.ts";

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "GET") {
      return errorResponse("METHOD_NOT_ALLOWED", "Only GET requests allowed", 405);
    }

    const auth = await requireAuth(req);
    const supabase = getServiceClient();

    const url = new URL(req.url);
    const orderId = url.searchParams.get("order_id");

    if (!orderId) {
      return errorResponse("INVALID_INPUT", "order_id query parameter is required", 400);
    }

    // Get order
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("id, user_id, order_number, status, delivery_method")
      .eq("id", orderId)
      .single();

    if (orderError || !order) {
      return errorResponse("ORDER_NOT_FOUND", "Order not found", 404);
    }

    // Authorization: admin or order owner
    if (auth.role !== "admin" && order.user_id !== auth.userId) {
      return errorResponse("FORBIDDEN", "You can only track your own orders", 403);
    }

    if (order.delivery_method !== "shiprocket") {
      return errorResponse("INVALID_METHOD", "Order is not using Shiprocket delivery", 400);
    }

    // Get shipment
    const { data: shipment, error: shipmentError } = await supabase
      .from("shiprocket_shipments")
      .select("*")
      .eq("order_id", orderId)
      .single();

    if (shipmentError || !shipment) {
      return errorResponse("SHIPMENT_NOT_FOUND", "No shipment found for this order", 404);
    }

    // Fetch live tracking from Shiprocket
    let tracking: Record<string, unknown> | null = null;

    if (shipment.awb_code) {
      try {
        tracking = await srFetchJSON(`/courier/track/awb/${shipment.awb_code}`);
      } catch (err) {
        console.error("Live tracking fetch failed:", err);
      }
    } else if (shipment.sr_shipment_id) {
      try {
        tracking = await srFetchJSON(`/courier/track/shipment/${shipment.sr_shipment_id}`);
      } catch (err) {
        console.error("Live tracking fetch failed:", err);
      }
    }

    // Update local sr_status if tracking data available
    if (tracking) {
      const trackingData = (tracking as { tracking_data?: { shipment_track?: Array<{ current_status?: string }> } })
        ?.tracking_data;
      const currentStatus = trackingData?.shipment_track?.[0]?.current_status;
      if (currentStatus && currentStatus !== shipment.sr_status) {
        await supabase
          .from("shiprocket_shipments")
          .update({ sr_status: currentStatus })
          .eq("id", shipment.id);
      }
    }

    return jsonResponse({
      order_id: orderId,
      order_number: order.order_number,
      order_status: order.status,
      shipment: {
        awb_code: shipment.awb_code,
        courier_name: shipment.courier_name,
        sr_status: shipment.sr_status,
        label_url: shipment.label_url,
        tracking_url: shipment.tracking_url,
      },
      tracking: tracking || null,
    });
  } catch (error) {
    return handleError(error, "Shiprocket track");
  }
}

Deno.serve(handler);
