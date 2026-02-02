// Shiprocket Create Shipment Edge Function (Admin only)
// POST /functions/v1/shiprocket-create-shipment
// Body: { order_id, length, breadth, height, weight }
//
// Creates a Shiprocket order from a confirmed order,
// checks courier serviceability, and returns available couriers.

import { getServiceClient, requireAdmin } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";
import { srFetchJSON } from "../_shared/shiprocket.ts";

interface CreateShipmentRequest {
  order_id: string;
  length: number;  // cm
  breadth: number; // cm
  height: number;  // cm
  weight: number;  // kg
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

    const body: CreateShipmentRequest = await req.json();

    if (!body.order_id) {
      return errorResponse("INVALID_INPUT", "order_id is required", 400);
    }
    if (!body.length || !body.breadth || !body.height || !body.weight) {
      return errorResponse("INVALID_INPUT", "Package dimensions (length, breadth, height, weight) are required", 400);
    }

    // Fetch order with items and user
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("*, order_items(*), user:users!orders_user_id_fkey(name, phone)")
      .eq("id", body.order_id)
      .single();

    if (orderError || !order) {
      return errorResponse("ORDER_NOT_FOUND", "Order not found", 404);
    }

    if (order.status !== "confirmed") {
      return errorResponse("INVALID_STATUS", "Order must be in confirmed status to create shipment", 400);
    }

    if (order.delivery_method === "shiprocket") {
      return errorResponse("ALREADY_CREATED", "Shiprocket shipment already exists for this order", 400);
    }

    // Get pickup postcode from app_settings
    const { data: pickupSetting } = await supabase
      .from("app_settings")
      .select("value")
      .eq("key", "shiprocket_pickup_postcode")
      .single();

    const pickupPostcode = pickupSetting?.value ? String(pickupSetting.value).replace(/"/g, "") : "000000";

    // Build line items for Shiprocket
    const orderItems = (order.order_items as Array<{
      product_name: string;
      quantity: number;
      unit_price_paise: number;
      weight_grams: number;
    }>).map((item) => ({
      name: item.product_name,
      sku: `MSS-${item.product_name.replace(/\s+/g, "-").substring(0, 20)}`,
      units: item.quantity,
      selling_price: String(item.unit_price_paise / 100),
      discount: "0",
      tax: "0",
      hsn: "",
    }));

    const user = order.user as { name: string; phone: string } | null;
    const customerName = order.shipping_name || user?.name || "Customer";
    const customerPhone = (user?.phone || order.shipping_phone || "").replace(/^\+91/, "");

    // Create adhoc Shiprocket order (no channel integration needed)
    const srOrder = await srFetchJSON<{
      order_id: number;
      shipment_id: number;
      status: string;
      status_code: number;
    }>("/orders/create/adhoc", {
      method: "POST",
      body: JSON.stringify({
        order_id: order.order_number,
        order_date: new Date(order.created_at).toISOString().split("T")[0],
        pickup_location: "warehouse",
        billing_customer_name: customerName.split(" ")[0],
        billing_last_name: customerName.split(" ").slice(1).join(" ") || "",
        billing_address: order.shipping_address_line1,
        billing_address_2: order.shipping_address_line2 || "",
        billing_city: order.shipping_city,
        billing_pincode: order.shipping_pincode,
        billing_state: order.shipping_state,
        billing_country: "India",
        billing_email: "",
        billing_phone: customerPhone,
        shipping_is_billing: true,
        order_items: orderItems,
        payment_method: "Prepaid",
        sub_total: order.total_paise / 100,
        length: body.length,
        breadth: body.breadth,
        height: body.height,
        weight: body.weight,
      }),
    });

    // Log full Shiprocket response for debugging
    console.log("Shiprocket create order response:", JSON.stringify(srOrder));

    // Insert shiprocket_shipments row
    const insertData = {
      order_id: body.order_id,
      sr_order_id: srOrder.order_id,
      sr_shipment_id: srOrder.shipment_id,
      length_cm: body.length,
      breadth_cm: body.breadth,
      height_cm: body.height,
      weight_kg: body.weight,
      sr_status: srOrder.status || "NEW",
      sr_status_code: srOrder.status_code || 1,
    };
    console.log("Inserting shipment:", JSON.stringify(insertData));

    const { error: insertError } = await supabase
      .from("shiprocket_shipments")
      .insert(insertData);

    if (insertError) {
      console.error("Failed to insert shiprocket_shipments:", JSON.stringify(insertError));
      return errorResponse("SERVER_ERROR", "Shipment created on Shiprocket but failed to save locally: " + insertError.message, 500);
    }

    // Set delivery_method on order (don't change status yet)
    await supabase
      .from("orders")
      .update({ delivery_method: "shiprocket" })
      .eq("id", body.order_id);

    // Check courier serviceability
    let couriers: Array<Record<string, unknown>> = [];
    try {
      const serviceability = await srFetchJSON<{
        data?: { available_courier_companies?: Array<Record<string, unknown>> };
      }>(
        `/courier/serviceability/?pickup_postcode=${pickupPostcode}&delivery_postcode=${order.shipping_pincode}&cod=0&weight=${body.weight}`,
      );
      couriers = serviceability?.data?.available_courier_companies || [];
    } catch (err) {
      console.error("Courier serviceability check failed:", err);
      // Non-fatal — admin can still assign manually
    }

    return jsonResponse({
      success: true,
      sr_order_id: srOrder.order_id,
      sr_shipment_id: srOrder.shipment_id,
      available_couriers: couriers.map((c) => ({
        courier_id: c.courier_company_id,
        courier_name: c.courier_name,
        rate: c.rate,
        etd: c.etd,
        estimated_delivery_days: c.estimated_delivery_days,
      })),
      message: "Shiprocket order created. Select a courier to assign AWB.",
    });
  } catch (error) {
    return handleError(error, "Shiprocket create shipment");
  }
}

Deno.serve(handler);
