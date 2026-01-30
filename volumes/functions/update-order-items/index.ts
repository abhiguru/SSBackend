import { requireAdmin, getServiceClient } from "../_shared/auth.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

function formatWeightLabel(grams: number): string {
  return grams >= 1000 ? `${grams / 1000}kg` : `${grams}g`;
}

export async function handler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return errorResponse('METHOD_NOT_ALLOWED', 'Only POST is allowed', 405);
  }

  try {
    await requireAdmin(req);
    const supabase = getServiceClient();

    const { order_id, items } = await req.json();

    if (!order_id) {
      return errorResponse('INVALID_REQUEST', 'order_id is required', 400);
    }
    if (!Array.isArray(items) || items.length === 0) {
      return errorResponse('INVALID_REQUEST', 'items array is required and must not be empty', 400);
    }

    // Fetch order
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('*')
      .eq('id', order_id)
      .single();

    if (orderError || !order) {
      return errorResponse('NOT_FOUND', 'Order not found', 404);
    }

    if (order.status !== 'placed' && order.status !== 'confirmed') {
      return errorResponse('INVALID_STATUS', `Cannot modify items for order with status '${order.status}'`, 400);
    }

    // Fetch all referenced products
    const productIds = [...new Set(items.map((i: { product_id: string }) => i.product_id))];
    const { data: products, error: productsError } = await supabase
      .from('products')
      .select('id, name, name_gu, price_per_kg_paise, is_available')
      .in('id', productIds);

    if (productsError) {
      return errorResponse('SERVER_ERROR', 'Failed to fetch products', 500);
    }

    const productMap = new Map(products?.map((p: { id: string }) => [p.id, p]) || []);

    // Validate all products exist and are active
    for (const item of items) {
      const product = productMap.get(item.product_id);
      if (!product) {
        return errorResponse('INVALID_PRODUCT', `Product ${item.product_id} not found`, 400);
      }
      if (!(product as { is_available: boolean }).is_available) {
        return errorResponse('PRODUCT_UNAVAILABLE', `Product '${(product as { name: string }).name}' is not available`, 400);
      }
    }

    // Calculate pricing per item
    const orderItems = items.map((item: { product_id: string; weight_grams: number; quantity: number }) => {
      const product = productMap.get(item.product_id) as {
        id: string; name: string; name_gu: string; price_per_kg_paise: number;
      };
      const unitPricePaise = Math.round(product.price_per_kg_paise * item.weight_grams / 1000);
      const totalPaise = unitPricePaise * item.quantity;
      return {
        order_id,
        product_id: item.product_id,
        weight_option_id: null,
        product_name: product.name,
        product_name_gu: product.name_gu,
        weight_label: formatWeightLabel(item.weight_grams),
        weight_grams: item.weight_grams,
        unit_price_paise: unitPricePaise,
        quantity: item.quantity,
        total_paise: totalPaise,
      };
    });

    // Delete existing order items
    const { error: deleteError } = await supabase
      .from('order_items')
      .delete()
      .eq('order_id', order_id);

    if (deleteError) {
      return errorResponse('SERVER_ERROR', 'Failed to delete existing order items', 500);
    }

    // Insert new order items
    const { error: insertError } = await supabase
      .from('order_items')
      .insert(orderItems);

    if (insertError) {
      return errorResponse('SERVER_ERROR', 'Failed to insert new order items', 500);
    }

    // Recalculate totals
    const subtotalPaise = orderItems.reduce((sum: number, item: { total_paise: number }) => sum + item.total_paise, 0);

    const { data: shippingSettings } = await supabase
      .from('app_settings')
      .select('key, value')
      .in('key', ['shipping_charge_paise', 'free_shipping_threshold_paise']);

    const settings: Record<string, number> = {};
    shippingSettings?.forEach((s: { key: string; value: string }) => {
      settings[s.key] = parseInt(s.value) || 0;
    });

    const shippingCharge = settings.shipping_charge_paise || 4000;
    const freeShippingThreshold = settings.free_shipping_threshold_paise || 50000;
    const shippingPaise = subtotalPaise >= freeShippingThreshold ? 0 : shippingCharge;
    const totalPaise = subtotalPaise + shippingPaise;

    // Update order totals
    const { error: updateError } = await supabase
      .from('orders')
      .update({
        subtotal_paise: subtotalPaise,
        shipping_paise: shippingPaise,
        total_paise: totalPaise,
      })
      .eq('id', order_id);

    if (updateError) {
      return errorResponse('SERVER_ERROR', 'Failed to update order totals', 500);
    }

    // Re-fetch order with items
    const { data: updatedOrder, error: fetchError } = await supabase
      .from('orders')
      .select('*, order_items(*)')
      .eq('id', order_id)
      .single();

    if (fetchError) {
      return errorResponse('SERVER_ERROR', 'Failed to fetch updated order', 500);
    }

    return jsonResponse(updatedOrder);
  } catch (error) {
    return handleError(error, 'update-order-items');
  }
}
