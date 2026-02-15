// Shiprocket Cancel Edge Function (Admin only)
// POST /functions/v1/shiprocket-cancel
// Body: { order_id, reason? }
//
// Cancels the Shiprocket order and transitions our order to cancelled.

import { getServiceClient, requireAdmin } from "../_shared/auth.ts";
import { sendOrderPush } from "../_shared/push.ts";

import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";
import { srFetchJSON } from "../_shared/shiprocket.ts";

interface CancelRequest {
  order_id: string;
  reason?: string;
}

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return errorResponse("METHOD_NOT_ALLOWED", "Only POST requests allowed", 405);
    }

    const auth = await requireAdmin(req);
    const supabase = getServiceClient();

    const body: CancelRequest = await req.json();

    if (!body.order_id) {
      return errorResponse("INVALID_INPUT", "order_id is required", 400);
    }

    // Get order
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("*, user:users!orders_user_id_fkey(phone)")
      .eq("id", body.order_id)
      .single();

    if (orderError || !order) {
      return errorResponse("ORDER_NOT_FOUND", "Order not found", 404);
    }

    if (order.status === "delivered" || order.status === "cancelled") {
      return errorResponse("INVALID_STATUS", `Cannot cancel order in ${order.status} status`, 400);
    }

    if (order.delivery_method !== "shiprocket") {
      return errorResponse("INVALID_METHOD", "Order is not using Shiprocket delivery. Use update-order-status instead.", 400);
    }

    // Get shipment
    const { data: shipment } = await supabase
      .from("shiprocket_shipments")
      .select("sr_order_id")
      .eq("order_id", body.order_id)
      .single();

    // Cancel on Shiprocket if we have an SR order
    if (shipment?.sr_order_id) {
      try {
        await srFetchJSON("/orders/cancel", {
          method: "POST",
          body: JSON.stringify({
            ids: [shipment.sr_order_id],
          }),
        });
      } catch (err) {
        console.error("Shiprocket cancel API failed (proceeding with local cancel):", err);
      }
    }

    // Cancel order locally
    const cancellationReason = body.reason || "Cancelled by admin (Shiprocket)";

    const { data: orderResult, error: updateError } = await supabase.rpc("update_order_status_atomic", {
      p_order_id: body.order_id,
      p_from_status: order.status,
      p_to_status: "cancelled",
      p_changed_by: auth.userId,
      p_notes: cancellationReason,
      p_update_data: { cancellation_reason: cancellationReason },
    });

    if (updateError) {
      console.error("Failed to cancel order:", updateError);
      if (updateError.message?.includes("status has changed")) {
        return errorResponse("STATUS_CHANGED", "Order status was modified by another request", 409);
      }
      return errorResponse("SERVER_ERROR", "Failed to cancel order", 500);
    }

    // Update shipment status
    await supabase
      .from("shiprocket_shipments")
      .update({ sr_status: "Cancelled" })
      .eq("order_id", body.order_id);

    // Send push notification to customer
    sendOrderPush(order.user_id, order.order_number, "cancelled", order.id).catch(console.error);

    return jsonResponse({
      success: true,
      order: {
        id: orderResult.id,
        order_number: orderResult.order_number,
        status: orderResult.status,
      },
      message: "Order cancelled",
    });
  } catch (error) {
    return handleError(error, "Shiprocket cancel");
  }
}

Deno.serve(handler);
