// Checkout Edge Function
// POST /functions/v1/checkout
// Body: { items: [{product_id, weight_grams, quantity}], address_id, notes? }

import { getServiceClient, requireAuth } from "../_shared/auth.ts";
import { sendNewOrderPushToAdmins } from "../_shared/push.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

interface CartItem {
  product_id: string;
  weight_grams: number;
  quantity: number;
}

interface CheckoutRequest {
  items: CartItem[];
  address_id: string;
  notes?: string;
}

function formatWeightLabel(grams: number): string {
  return grams >= 1000 ? `${grams / 1000}kg` : `${grams}g`;
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

    // Require authentication
    const auth = await requireAuth(req);
    const supabase = getServiceClient();

    // Parse request body
    const body: CheckoutRequest = await req.json();

    // Validate input
    if (!body.items || !Array.isArray(body.items) || body.items.length === 0) {
      return errorResponse('EMPTY_CART', 'Cart is empty', 400);
    }

    if (!body.address_id) {
      return errorResponse('MISSING_ADDRESS', 'Delivery address is required', 400);
    }

    // Get address
    const { data: address, error: addressError } = await supabase
      .from('user_addresses')
      .select('*')
      .eq('id', body.address_id)
      .eq('user_id', auth.userId)
      .single();

    if (addressError || !address) {
      return errorResponse('INVALID_ADDRESS', 'Invalid delivery address', 400);
    }

    // Check pincode serviceability
    const { data: pincodeSettings } = await supabase
      .from('app_settings')
      .select('value')
      .eq('key', 'serviceable_pincodes')
      .single();

    const serviceablePincodes: string[] = pincodeSettings?.value
      ? (typeof pincodeSettings.value === 'string' ? JSON.parse(pincodeSettings.value) : pincodeSettings.value)
      : [];

    if (serviceablePincodes.length > 0 && !serviceablePincodes.includes(address.pincode)) {
      return errorResponse(
        'PINCODE_NOT_SERVICEABLE',
        `Sorry, we don't deliver to pincode ${address.pincode} yet`,
        400,
      );
    }

    // Fetch products for all cart items
    const productIds = body.items.map(item => item.product_id);
    const { data: products, error: prodError } = await supabase
      .from('products')
      .select('id, name, name_gu, price_per_kg_paise, is_available, is_active')
      .in('id', productIds);

    if (prodError || !products) {
      return errorResponse('SERVER_ERROR', 'Failed to fetch product data', 500);
    }

    // Create lookup map
    const productMap = new Map(products.map(p => [p.id, p]));

    // Validate all items and calculate totals
    const orderItems: Array<{
      product_id: string;
      product_name: string;
      product_name_gu: string | null;
      weight_label: string;
      weight_grams: number;
      unit_price_paise: number;
      quantity: number;
      total_paise: number;
    }> = [];

    const unavailableItems: string[] = [];

    for (const item of body.items) {
      const product = productMap.get(item.product_id);

      if (!product) {
        return errorResponse('INVALID_ITEM', 'Product not found', 400);
      }

      // Check availability
      if (!product.is_available || !product.is_active) {
        unavailableItems.push(product.name);
        continue;
      }

      // Validate weight_grams
      if (!item.weight_grams || item.weight_grams <= 0) {
        return errorResponse('INVALID_WEIGHT', `Invalid weight for ${product.name}`, 400);
      }

      // Validate quantity
      if (item.quantity < 1 || item.quantity > 100) {
        return errorResponse('INVALID_QUANTITY', `Invalid quantity for ${product.name}`, 400);
      }

      // Compute price from per-kg rate
      const unitPricePaise = Math.round(product.price_per_kg_paise * item.weight_grams / 1000);

      orderItems.push({
        product_id: product.id,
        product_name: product.name,
        product_name_gu: product.name_gu,
        weight_label: formatWeightLabel(item.weight_grams),
        weight_grams: item.weight_grams,
        unit_price_paise: unitPricePaise,
        quantity: item.quantity,
        total_paise: unitPricePaise * item.quantity,
      });
    }

    if (unavailableItems.length > 0) {
      return errorResponse(
        'ITEMS_UNAVAILABLE',
        `Some items are no longer available: ${unavailableItems.join(', ')}`,
        400,
        { unavailable_items: unavailableItems },
      );
    }

    if (orderItems.length === 0) {
      return errorResponse('EMPTY_CART', 'No available items in cart', 400);
    }

    // Calculate subtotal
    const subtotalPaise = orderItems.reduce((sum, item) => sum + item.total_paise, 0);

    // Get shipping settings
    const { data: shippingSettings } = await supabase
      .from('app_settings')
      .select('key, value')
      .in('key', ['shipping_charge_paise', 'free_shipping_threshold_paise', 'min_order_paise']);

    const settings: Record<string, number> = {};
    shippingSettings?.forEach(s => {
      settings[s.key] = parseInt(s.value) || 0;
    });

    const shippingCharge = settings.shipping_charge_paise || 4000;
    const freeShippingThreshold = settings.free_shipping_threshold_paise || 50000;
    const minOrder = settings.min_order_paise || 10000;

    // Check minimum order
    if (subtotalPaise < minOrder) {
      return errorResponse(
        'MIN_ORDER_NOT_MET',
        `Minimum order amount is ₹${(minOrder / 100).toFixed(2)}`,
        400,
        { min_order_paise: minOrder, current_total_paise: subtotalPaise },
      );
    }

    // Calculate shipping
    const shippingPaise = subtotalPaise >= freeShippingThreshold ? 0 : shippingCharge;
    const totalPaise = subtotalPaise + shippingPaise;

    // Create order atomically (order + items + status history in one transaction)
    const { data: orderResult, error: orderError } = await supabase.rpc('create_order_atomic', {
      p_user_id: auth.userId,
      p_shipping: {
        name: address.full_name,
        phone: address.phone,
        line1: address.address_line1,
        line2: address.address_line2 || null,
        city: address.city,
        state: address.state,
        pincode: address.pincode,
      },
      p_subtotal_paise: subtotalPaise,
      p_shipping_paise: shippingPaise,
      p_total_paise: totalPaise,
      p_customer_notes: body.notes || null,
      p_items: orderItems,
    });

    if (orderError || !orderResult) {
      console.error('Failed to create order:', orderError);
      return errorResponse('SERVER_ERROR', 'Failed to create order', 500);
    }

    // Send push notification to admins
    const totalFormatted = `₹${(totalPaise / 100).toFixed(2)}`;
    sendNewOrderPushToAdmins(orderResult.order_number, totalFormatted).catch(console.error);

    return jsonResponse({
      success: true,
      order: {
        id: orderResult.id,
        order_number: orderResult.order_number,
        status: orderResult.status,
        subtotal_paise: orderResult.subtotal_paise,
        shipping_paise: orderResult.shipping_paise,
        total_paise: orderResult.total_paise,
        created_at: orderResult.created_at,
      },
      message: 'Order placed successfully',
    }, 201);
  } catch (error) {
    return handleError(error, 'Checkout');
  }
}

// For standalone execution
Deno.serve(handler);
