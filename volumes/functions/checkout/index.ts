// Checkout Edge Function
// POST /functions/v1/checkout
// Body: { items: [{product_id, weight_option_id, quantity}], address_id, notes? }

import { getServiceClient, requireAuth } from "../_shared/auth.ts";
import { sendNewOrderPushToAdmins } from "../_shared/push.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface CartItem {
  product_id: string;
  weight_option_id: string;
  quantity: number;
}

interface CheckoutRequest {
  items: CartItem[];
  address_id: string;
  notes?: string;
}

export async function handler(req: Request): Promise<Response> {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Only allow POST
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ error: 'METHOD_NOT_ALLOWED', message: 'Only POST requests allowed' }),
        { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Require authentication
    const auth = await requireAuth(req);
    const supabase = getServiceClient();

    // Parse request body
    const body: CheckoutRequest = await req.json();

    // Validate input
    if (!body.items || !Array.isArray(body.items) || body.items.length === 0) {
      return new Response(
        JSON.stringify({ error: 'EMPTY_CART', message: 'Cart is empty' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!body.address_id) {
      return new Response(
        JSON.stringify({ error: 'MISSING_ADDRESS', message: 'Delivery address is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get address
    const { data: address, error: addressError } = await supabase
      .from('user_addresses')
      .select('*')
      .eq('id', body.address_id)
      .eq('user_id', auth.userId)
      .single();

    if (addressError || !address) {
      return new Response(
        JSON.stringify({ error: 'INVALID_ADDRESS', message: 'Invalid delivery address' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
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
      return new Response(
        JSON.stringify({
          error: 'PINCODE_NOT_SERVICEABLE',
          message: `Sorry, we don't deliver to pincode ${address.pincode} yet`,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate and fetch cart items with product data
    const weightOptionIds = body.items.map(item => item.weight_option_id);
    const { data: weightOptions, error: woError } = await supabase
      .from('weight_options')
      .select(`
        id,
        weight_grams,
        weight_label,
        price_paise,
        is_available,
        product:products (
          id,
          name,
          name_gu,
          is_available,
          is_active
        )
      `)
      .in('id', weightOptionIds);

    if (woError || !weightOptions) {
      return new Response(
        JSON.stringify({ error: 'SERVER_ERROR', message: 'Failed to fetch product data' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create lookup map
    const woMap = new Map(weightOptions.map(wo => [wo.id, wo]));

    // Validate all items and calculate totals
    const orderItems: Array<{
      product_id: string;
      weight_option_id: string;
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
      const wo = woMap.get(item.weight_option_id);

      if (!wo) {
        return new Response(
          JSON.stringify({ error: 'INVALID_ITEM', message: `Product variant not found` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      const product = wo.product as { id: string; name: string; name_gu: string | null; is_available: boolean; is_active: boolean };

      // Check availability
      if (!wo.is_available || !product.is_available || !product.is_active) {
        unavailableItems.push(product.name);
        continue;
      }

      // Validate quantity
      if (item.quantity < 1 || item.quantity > 100) {
        return new Response(
          JSON.stringify({ error: 'INVALID_QUANTITY', message: `Invalid quantity for ${product.name}` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      orderItems.push({
        product_id: product.id,
        weight_option_id: wo.id,
        product_name: product.name,
        product_name_gu: product.name_gu,
        weight_label: wo.weight_label,
        weight_grams: wo.weight_grams,
        unit_price_paise: wo.price_paise,
        quantity: item.quantity,
        total_paise: wo.price_paise * item.quantity,
      });
    }

    if (unavailableItems.length > 0) {
      return new Response(
        JSON.stringify({
          error: 'ITEMS_UNAVAILABLE',
          message: `Some items are no longer available: ${unavailableItems.join(', ')}`,
          unavailable_items: unavailableItems,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (orderItems.length === 0) {
      return new Response(
        JSON.stringify({ error: 'EMPTY_CART', message: 'No available items in cart' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
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
      return new Response(
        JSON.stringify({
          error: 'MIN_ORDER_NOT_MET',
          message: `Minimum order amount is ₹${(minOrder / 100).toFixed(2)}`,
          min_order_paise: minOrder,
          current_total_paise: subtotalPaise,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Calculate shipping
    const shippingPaise = subtotalPaise >= freeShippingThreshold ? 0 : shippingCharge;
    const totalPaise = subtotalPaise + shippingPaise;

    // Generate order number
    const { data: orderNumber, error: onError } = await supabase
      .rpc('generate_order_number');

    if (onError || !orderNumber) {
      console.error('Failed to generate order number:', onError);
      return new Response(
        JSON.stringify({ error: 'SERVER_ERROR', message: 'Failed to create order' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create order
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .insert({
        order_number: orderNumber,
        user_id: auth.userId,
        status: 'placed',
        shipping_name: address.full_name,
        shipping_phone: address.phone,
        shipping_address_line1: address.address_line1,
        shipping_address_line2: address.address_line2,
        shipping_city: address.city,
        shipping_state: address.state,
        shipping_pincode: address.pincode,
        subtotal_paise: subtotalPaise,
        shipping_paise: shippingPaise,
        total_paise: totalPaise,
        customer_notes: body.notes || null,
      })
      .select()
      .single();

    if (orderError || !order) {
      console.error('Failed to create order:', orderError);
      return new Response(
        JSON.stringify({ error: 'SERVER_ERROR', message: 'Failed to create order' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create order items
    const { error: itemsError } = await supabase
      .from('order_items')
      .insert(
        orderItems.map(item => ({
          order_id: order.id,
          product_id: item.product_id,
          weight_option_id: item.weight_option_id,
          product_name: item.product_name,
          product_name_gu: item.product_name_gu,
          weight_label: item.weight_label,
          weight_grams: item.weight_grams,
          unit_price_paise: item.unit_price_paise,
          quantity: item.quantity,
          total_paise: item.total_paise,
        }))
      );

    if (itemsError) {
      console.error('Failed to create order items:', itemsError);
    }

    // Create initial status history
    await supabase
      .from('order_status_history')
      .insert({
        order_id: order.id,
        from_status: null,
        to_status: 'placed',
        changed_by: auth.userId,
        notes: 'Order placed',
      });

    // Send push notification to admins
    const totalFormatted = `₹${(totalPaise / 100).toFixed(2)}`;
    sendNewOrderPushToAdmins(orderNumber, totalFormatted).catch(console.error);

    return new Response(
      JSON.stringify({
        success: true,
        order: {
          id: order.id,
          order_number: order.order_number,
          status: order.status,
          subtotal_paise: subtotalPaise,
          shipping_paise: shippingPaise,
          total_paise: totalPaise,
          created_at: order.created_at,
        },
        message: 'Order placed successfully',
      }),
      { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    if (error instanceof Error && error.name === 'AuthError') {
      return new Response(
        JSON.stringify({ error: 'UNAUTHORIZED', message: error.message }),
        { status: (error as { status?: number }).status || 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.error('Checkout error:', error);
    return new Response(
      JSON.stringify({ error: 'SERVER_ERROR', message: 'An unexpected error occurred' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
}

// For standalone execution
Deno.serve(handler);
