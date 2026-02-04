-- Fix create_order_atomic to remove weight_option_id reference
-- The order_items table no longer has this column after migration 30

BEGIN;

CREATE OR REPLACE FUNCTION create_order_atomic(
    p_user_id UUID,
    p_shipping JSONB,
    p_subtotal_paise INT,
    p_shipping_paise INT,
    p_total_paise INT,
    p_customer_notes TEXT,
    p_items JSONB
) RETURNS JSONB AS $$
DECLARE
    v_order_number TEXT;
    v_order_id UUID;
    v_order RECORD;
BEGIN
    SELECT generate_order_number() INTO v_order_number;

    INSERT INTO orders (
        order_number, user_id, status,
        shipping_name, shipping_phone, shipping_address_line1, shipping_address_line2,
        shipping_city, shipping_state, shipping_pincode,
        subtotal_paise, shipping_paise, total_paise, customer_notes
    ) VALUES (
        v_order_number, p_user_id, 'placed',
        p_shipping->>'name', p_shipping->>'phone', p_shipping->>'line1', p_shipping->>'line2',
        p_shipping->>'city', p_shipping->>'state', p_shipping->>'pincode',
        p_subtotal_paise, p_shipping_paise, p_total_paise, p_customer_notes
    ) RETURNING * INTO v_order;

    v_order_id := v_order.id;

    INSERT INTO order_items (
        order_id, product_id,
        product_name, product_name_gu, weight_label, weight_grams,
        unit_price_paise, quantity, total_paise
    )
    SELECT
        v_order_id,
        (item->>'product_id')::UUID,
        item->>'product_name',
        item->>'product_name_gu',
        item->>'weight_label',
        (item->>'weight_grams')::INT,
        (item->>'unit_price_paise')::INT,
        (item->>'quantity')::INT,
        (item->>'total_paise')::INT
    FROM jsonb_array_elements(p_items) AS item;

    INSERT INTO order_status_history (order_id, from_status, to_status, changed_by, notes)
    VALUES (v_order_id, NULL, 'placed', p_user_id, 'Order placed');

    RETURN jsonb_build_object(
        'id', v_order_id,
        'order_number', v_order_number,
        'status', 'placed',
        'subtotal_paise', p_subtotal_paise,
        'shipping_paise', p_shipping_paise,
        'total_paise', p_total_paise,
        'created_at', v_order.created_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
