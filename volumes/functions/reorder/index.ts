// Reorder Edge Function
// POST /functions/v1/reorder
// Body: { order_id }
// Returns cart items from previous order, filtering unavailable products

import { getServiceClient, requireAuth } from "../_shared/auth.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface ReorderRequest {
  order_id: string;
}

interface CartItem {
  product_id: string;
  weight_option_id: string;
  quantity: number;
  product_name: string;
  product_name_gu: string | null;
  weight_label: string;
  price_paise: number;
  is_available: boolean;
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
    const body: ReorderRequest = await req.json();

    if (!body.order_id) {
      return new Response(
        JSON.stringify({ error: 'INVALID_INPUT', message: 'order_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get the original order
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('id, user_id, order_number')
      .eq('id', body.order_id)
      .single();

    if (orderError || !order) {
      return new Response(
        JSON.stringify({ error: 'ORDER_NOT_FOUND', message: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Verify order belongs to the user
    if (order.user_id !== auth.userId) {
      return new Response(
        JSON.stringify({ error: 'UNAUTHORIZED', message: 'This order does not belong to you' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get order items
    const { data: orderItems, error: itemsError } = await supabase
      .from('order_items')
      .select('product_id, weight_option_id, quantity, product_name, product_name_gu, weight_label')
      .eq('order_id', body.order_id);

    if (itemsError || !orderItems || orderItems.length === 0) {
      return new Response(
        JSON.stringify({ error: 'NO_ITEMS', message: 'No items found in this order' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get current product and weight option availability
    const productIds = orderItems.map(item => item.product_id).filter(Boolean);
    const weightOptionIds = orderItems.map(item => item.weight_option_id).filter(Boolean);

    // Fetch current products
    const { data: products } = await supabase
      .from('products')
      .select('id, name, name_gu, is_available, is_active')
      .in('id', productIds);

    // Fetch current weight options
    const { data: weightOptions } = await supabase
      .from('weight_options')
      .select('id, price_paise, is_available')
      .in('id', weightOptionIds);

    // Create lookup maps
    const productMap = new Map(products?.map(p => [p.id, p]) || []);
    const woMap = new Map(weightOptions?.map(wo => [wo.id, wo]) || []);

    // Build cart items with current availability
    const cartItems: CartItem[] = [];
    const unavailableItems: string[] = [];

    for (const item of orderItems) {
      const product = item.product_id ? productMap.get(item.product_id) : null;
      const weightOption = item.weight_option_id ? woMap.get(item.weight_option_id) : null;

      // Determine availability
      const isProductAvailable = product?.is_available && product?.is_active;
      const isWeightAvailable = weightOption?.is_available;
      const isAvailable = isProductAvailable && isWeightAvailable;

      if (!isAvailable) {
        unavailableItems.push(item.product_name);
      }

      // Include item even if unavailable (let frontend decide what to show)
      if (item.product_id && item.weight_option_id) {
        cartItems.push({
          product_id: item.product_id,
          weight_option_id: item.weight_option_id,
          quantity: item.quantity,
          product_name: product?.name || item.product_name,
          product_name_gu: product?.name_gu || item.product_name_gu,
          weight_label: item.weight_label,
          price_paise: weightOption?.price_paise || 0,
          is_available: isAvailable || false,
        });
      }
    }

    // Calculate total for available items only
    const availableItems = cartItems.filter(item => item.is_available);
    const subtotalPaise = availableItems.reduce(
      (sum, item) => sum + item.price_paise * item.quantity,
      0
    );

    return new Response(
      JSON.stringify({
        success: true,
        original_order_number: order.order_number,
        cart_items: cartItems,
        available_items: availableItems,
        unavailable_items: unavailableItems,
        subtotal_paise: subtotalPaise,
        message: unavailableItems.length > 0
          ? `${unavailableItems.length} item(s) are no longer available`
          : 'All items are available',
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    if (error instanceof Error && error.name === 'AuthError') {
      return new Response(
        JSON.stringify({ error: 'UNAUTHORIZED', message: error.message }),
        { status: (error as { status?: number }).status || 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.error('Reorder error:', error);
    return new Response(
      JSON.stringify({ error: 'SERVER_ERROR', message: 'An unexpected error occurred' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
}

// For standalone execution
Deno.serve(handler);
