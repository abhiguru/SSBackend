-- =============================================
-- Migration: Order RPC Functions for Customers
-- =============================================

-- =============================================
-- get_orders(p_status, p_limit, p_offset) - List user's orders
-- =============================================
CREATE OR REPLACE FUNCTION get_orders(
    p_status TEXT DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_result JSON;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Validate and clamp limit
    IF p_limit IS NULL OR p_limit < 1 THEN
        p_limit := 20;
    ELSIF p_limit > 100 THEN
        p_limit := 100;
    END IF;

    -- Validate offset
    IF p_offset IS NULL OR p_offset < 0 THEN
        p_offset := 0;
    END IF;

    -- Validate status if provided
    IF p_status IS NOT NULL AND p_status NOT IN ('placed', 'confirmed', 'out_for_delivery', 'delivered', 'cancelled', 'delivery_failed') THEN
        RAISE EXCEPTION 'INVALID_STATUS: Status must be one of: placed, confirmed, out_for_delivery, delivered, cancelled, delivery_failed';
    END IF;

    SELECT COALESCE(json_agg(order_row ORDER BY order_row.created_at DESC), '[]'::json)
    INTO v_result
    FROM (
        SELECT
            o.id,
            o.order_number,
            o.status,
            o.total_paise,
            o.delivery_method,
            o.created_at,
            (SELECT COUNT(*)::INT FROM order_items oi WHERE oi.order_id = o.id) AS item_count
        FROM orders o
        WHERE o.user_id = v_user_id
          AND (p_status IS NULL OR o.status = p_status::order_status)
        ORDER BY o.created_at DESC
        LIMIT p_limit
        OFFSET p_offset
    ) order_row;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- get_order(p_order_id) - Get single order with items
-- =============================================
CREATE OR REPLACE FUNCTION get_order(p_order_id UUID)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_order JSON;
    v_items JSON;
    v_order_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Check order exists and belongs to user
    SELECT user_id INTO v_order_user_id
    FROM orders
    WHERE id = p_order_id;

    IF v_order_user_id IS NULL THEN
        RAISE EXCEPTION 'ORDER_NOT_FOUND: Order not found';
    END IF;

    IF v_order_user_id != v_user_id THEN
        RAISE EXCEPTION 'FORBIDDEN: Order does not belong to this user';
    END IF;

    -- Get order details
    SELECT json_build_object(
        'id', o.id,
        'order_number', o.order_number,
        'status', o.status,
        'shipping_name', o.shipping_name,
        'shipping_phone', o.shipping_phone,
        'shipping_address_line1', o.shipping_address_line1,
        'shipping_address_line2', o.shipping_address_line2,
        'shipping_city', o.shipping_city,
        'shipping_state', o.shipping_state,
        'shipping_pincode', o.shipping_pincode,
        'subtotal_paise', o.subtotal_paise,
        'shipping_paise', o.shipping_paise,
        'total_paise', o.total_paise,
        'delivery_method', o.delivery_method,
        'customer_notes', o.customer_notes,
        'cancellation_reason', o.cancellation_reason,
        'failure_reason', o.failure_reason,
        'created_at', o.created_at,
        'updated_at', o.updated_at
    )
    INTO v_order
    FROM orders o
    WHERE o.id = p_order_id;

    -- Get order items
    SELECT COALESCE(json_agg(
        json_build_object(
            'id', oi.id,
            'product_id', oi.product_id,
            'product_name', oi.product_name,
            'product_name_gu', oi.product_name_gu,
            'weight_label', oi.weight_label,
            'weight_grams', oi.weight_grams,
            'unit_price_paise', oi.unit_price_paise,
            'quantity', oi.quantity,
            'total_paise', oi.total_paise
        )
    ), '[]'::json)
    INTO v_items
    FROM order_items oi
    WHERE oi.order_id = p_order_id;

    -- Return combined result
    RETURN json_build_object(
        'id', v_order->>'id',
        'order_number', v_order->>'order_number',
        'status', v_order->>'status',
        'shipping_name', v_order->>'shipping_name',
        'shipping_phone', v_order->>'shipping_phone',
        'shipping_address_line1', v_order->>'shipping_address_line1',
        'shipping_address_line2', v_order->>'shipping_address_line2',
        'shipping_city', v_order->>'shipping_city',
        'shipping_state', v_order->>'shipping_state',
        'shipping_pincode', v_order->>'shipping_pincode',
        'subtotal_paise', (v_order->>'subtotal_paise')::INT,
        'shipping_paise', (v_order->>'shipping_paise')::INT,
        'total_paise', (v_order->>'total_paise')::INT,
        'delivery_method', v_order->>'delivery_method',
        'customer_notes', v_order->>'customer_notes',
        'cancellation_reason', v_order->>'cancellation_reason',
        'failure_reason', v_order->>'failure_reason',
        'created_at', v_order->>'created_at',
        'updated_at', v_order->>'updated_at',
        'items', v_items
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- cancel_order(p_order_id, p_reason) - Cancel own order
-- =============================================
CREATE OR REPLACE FUNCTION cancel_order(
    p_order_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_order RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Check order exists and belongs to user
    SELECT * INTO v_order
    FROM orders
    WHERE id = p_order_id;

    IF v_order IS NULL THEN
        RAISE EXCEPTION 'ORDER_NOT_FOUND: Order not found';
    END IF;

    IF v_order.user_id != v_user_id THEN
        RAISE EXCEPTION 'FORBIDDEN: Order does not belong to this user';
    END IF;

    -- Validate order status allows cancellation
    -- Can only cancel: placed, confirmed
    -- Cannot cancel: out_for_delivery, delivered, cancelled, delivery_failed
    IF v_order.status NOT IN ('placed', 'confirmed') THEN
        RAISE EXCEPTION 'CANCELLATION_NOT_ALLOWED: Cannot cancel order with status "%". Only orders in "placed" or "confirmed" status can be cancelled.', v_order.status;
    END IF;

    -- Update order status to cancelled
    UPDATE orders
    SET
        status = 'cancelled',
        cancellation_reason = COALESCE(p_reason, 'Cancelled by customer')
    WHERE id = p_order_id;

    -- Record status history
    INSERT INTO order_status_history (order_id, from_status, to_status, changed_by, notes)
    VALUES (p_order_id, v_order.status, 'cancelled', v_user_id, COALESCE(p_reason, 'Cancelled by customer'));

    -- Return updated order
    RETURN get_order(p_order_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- get_order_status_history(p_order_id) - Get order history
-- =============================================
CREATE OR REPLACE FUNCTION get_order_status_history(p_order_id UUID)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_order_user_id UUID;
    v_result JSON;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Check order exists and belongs to user
    SELECT user_id INTO v_order_user_id
    FROM orders
    WHERE id = p_order_id;

    IF v_order_user_id IS NULL THEN
        RAISE EXCEPTION 'ORDER_NOT_FOUND: Order not found';
    END IF;

    IF v_order_user_id != v_user_id THEN
        RAISE EXCEPTION 'FORBIDDEN: Order does not belong to this user';
    END IF;

    -- Get status history sorted by created_at ASC (chronological order)
    SELECT COALESCE(json_agg(
        json_build_object(
            'id', h.id,
            'from_status', h.from_status,
            'to_status', h.to_status,
            'notes', h.notes,
            'created_at', h.created_at
        ) ORDER BY h.created_at ASC
    ), '[]'::json)
    INTO v_result
    FROM order_status_history h
    WHERE h.order_id = p_order_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- GRANTS
-- =============================================

GRANT EXECUTE ON FUNCTION get_orders(TEXT, INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_order(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_order(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_order_status_history(UUID) TO authenticated;
