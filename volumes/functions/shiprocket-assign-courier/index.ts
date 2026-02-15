// Shiprocket Assign Courier Edge Function (Admin only)
// POST /functions/v1/shiprocket-assign-courier
// Body: { order_id, courier_id }
//
// Assigns AWB, generates pickup request, generates label,
// then transitions order to out_for_delivery.

import { getServiceClient, requireAdmin } from "../_shared/auth.ts";
import { sendOrderPush } from "../_shared/push.ts";

import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";
import { srFetchJSON } from "../_shared/shiprocket.ts";

interface AssignCourierRequest {
  order_id: string;
  courier_id: number;
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

    const body: AssignCourierRequest = await req.json();

    if (!body.order_id || !body.courier_id) {
      return errorResponse("INVALID_INPUT", "order_id and courier_id are required", 400);
    }

    // Get order + shipment
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("*, user:users!orders_user_id_fkey(phone)")
      .eq("id", body.order_id)
      .single();

    if (orderError || !order) {
      return errorResponse("ORDER_NOT_FOUND", "Order not found", 404);
    }

    if (order.delivery_method !== "shiprocket") {
      return errorResponse("INVALID_METHOD", "Order is not using Shiprocket delivery", 400);
    }

    if (order.status !== "confirmed") {
      return errorResponse("INVALID_STATUS", "Order must be in confirmed status", 400);
    }

    const { data: shipment, error: shipmentError } = await supabase
      .from("shiprocket_shipments")
      .select("*")
      .eq("order_id", body.order_id)
      .single();

    if (shipmentError || !shipment) {
      return errorResponse("SHIPMENT_NOT_FOUND", "No Shiprocket shipment found for this order. Create shipment first.", 404);
    }

    if (shipment.awb_code) {
      return errorResponse("ALREADY_ASSIGNED", "Courier already assigned with AWB: " + shipment.awb_code, 400);
    }

    // Step 1: Assign AWB
    const awbResult = await srFetchJSON<{
      response?: { data?: { awb_code: string; courier_name: string; courier_company_id: number } };
      awb_assign_status?: number;
    }>("/courier/assign/awb", {
      method: "POST",
      body: JSON.stringify({
        shipment_id: shipment.sr_shipment_id,
        courier_id: body.courier_id,
      }),
    });

    const awbData = awbResult?.response?.data;
    if (!awbData?.awb_code) {
      return errorResponse(
        "AWB_ASSIGN_FAILED",
        "Failed to assign AWB. Shiprocket response: " + JSON.stringify(awbResult),
        400,
      );
    }

    // Step 2: Generate pickup request
    let pickupScheduled = false;
    try {
      await srFetchJSON("/courier/generate/pickup", {
        method: "POST",
        body: JSON.stringify({
          shipment_id: [shipment.sr_shipment_id],
        }),
      });
      pickupScheduled = true;
    } catch (err) {
      console.error("Pickup generation failed (non-fatal):", err);
    }

    // Step 3: Generate manifest
    let manifestUrl: string | null = null;
    try {
      await srFetchJSON("/manifests/generate", {
        method: "POST",
        body: JSON.stringify({
          shipment_id: [shipment.sr_shipment_id],
        }),
      });
      // Print manifest to get PDF URL
      const manifestPrint = await srFetchJSON<{
        manifest_url?: string;
      }>("/manifests/print", {
        method: "POST",
        body: JSON.stringify({
          order_ids: [shipment.sr_order_id],
        }),
      });
      manifestUrl = manifestPrint?.manifest_url || null;
    } catch (err) {
      console.error("Manifest generation failed (non-fatal):", err);
    }

    // Step 4: Generate label
    let labelUrl: string | null = null;
    try {
      const labelResult = await srFetchJSON<{
        label_url?: string;
      }>("/courier/generate/label", {
        method: "POST",
        body: JSON.stringify({
          shipment_id: [shipment.sr_shipment_id],
        }),
      });
      labelUrl = labelResult?.label_url || null;
    } catch (err) {
      console.error("Label generation failed (non-fatal):", err);
    }

    // Step 5: Generate invoice
    let invoiceUrl: string | null = null;
    try {
      const invoiceResult = await srFetchJSON<{
        invoice_url?: string;
      }>("/orders/print/invoice", {
        method: "POST",
        body: JSON.stringify({
          ids: [shipment.sr_order_id],
        }),
      });
      invoiceUrl = invoiceResult?.invoice_url || null;
    } catch (err) {
      console.error("Invoice generation failed (non-fatal):", err);
    }

    // Build tracking URL
    const trackingUrl = `https://shiprocket.co/tracking/${awbData.awb_code}`;

    // Update shipment record
    await supabase
      .from("shiprocket_shipments")
      .update({
        awb_code: awbData.awb_code,
        courier_id: awbData.courier_company_id || body.courier_id,
        courier_name: awbData.courier_name || null,
        label_url: labelUrl,
        tracking_url: trackingUrl,
        sr_status: "AWB Assigned",
      })
      .eq("id", shipment.id);

    // Transition order to out_for_delivery via atomic RPC
    const { data: orderResult, error: updateError } = await supabase.rpc("update_order_status_atomic", {
      p_order_id: body.order_id,
      p_from_status: order.status,
      p_to_status: "out_for_delivery",
      p_changed_by: auth.userId,
      p_notes: `Shipped via ${awbData.courier_name || "Shiprocket"} (AWB: ${awbData.awb_code})`,
      p_update_data: {},
    });

    if (updateError) {
      console.error("Failed to update order status:", updateError);
      // AWB is already assigned, so this is a partial success
      return errorResponse("STATUS_UPDATE_FAILED", "AWB assigned but order status update failed", 500);
    }

    // Send push notification to customer
    sendOrderPush(order.user_id, order.order_number, "out_for_delivery", order.id).catch(console.error);

    return jsonResponse({
      success: true,
      awb_code: awbData.awb_code,
      courier_name: awbData.courier_name,
      label_url: labelUrl,
      manifest_url: manifestUrl,
      invoice_url: invoiceUrl,
      tracking_url: trackingUrl,
      pickup_scheduled: pickupScheduled,
      order: {
        id: orderResult.id,
        order_number: orderResult.order_number,
        status: orderResult.status,
      },
    });
  } catch (error) {
    return handleError(error, "Shiprocket assign courier");
  }
}

Deno.serve(handler);
