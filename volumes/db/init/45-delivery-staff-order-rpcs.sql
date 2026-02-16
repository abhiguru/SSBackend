-- Migration: delivery staff order access + delivery OTP at confirmation
--
-- 1. Add delivery_otp plaintext column (customer sees it in-app, no SMS)
-- 2. Update update_order_status_atomic to handle delivery_otp
-- 3. get_orders: role-aware (delivery_staff sees assigned orders)
-- 4. get_order: role-aware access + includes delivery_otp for customer, customer object for all

-- ============================================================
-- Schema: add delivery_otp plaintext column
-- ============================================================
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_otp VARCHAR(4);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_confirmed_latitude DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_confirmed_longitude DOUBLE PRECISION;

-- ============================================================
-- update_order_status_atomic: handle delivery_otp field
-- ============================================================
CREATE OR REPLACE FUNCTION update_order_status_atomic(
    p_order_id UUID,
    p_from_status TEXT,
    p_to_status TEXT,
    p_changed_by UUID,
    p_notes TEXT DEFAULT NULL,
    p_update_data JSONB DEFAULT '{}'::JSONB
) RETURNS JSONB AS $$
DECLARE
    v_order RECORD;
BEGIN
    UPDATE orders
    SET status = p_to_status::order_status,
        delivery_staff_id = COALESCE((p_update_data->>'delivery_staff_id')::UUID, delivery_staff_id),
        delivery_otp = COALESCE(p_update_data->>'delivery_otp', delivery_otp),
        delivery_otp_hash = COALESCE(p_update_data->>'delivery_otp_hash', delivery_otp_hash),
        delivery_otp_expires = COALESCE((p_update_data->>'delivery_otp_expires')::TIMESTAMPTZ, delivery_otp_expires),
        cancellation_reason = COALESCE(p_update_data->>'cancellation_reason', cancellation_reason),
        failure_reason = COALESCE(p_update_data->>'failure_reason', failure_reason),
        delivery_method = COALESCE((p_update_data->>'delivery_method')::delivery_method, delivery_method),
        estimated_delivery_at = COALESCE((p_update_data->>'estimated_delivery_at')::TIMESTAMPTZ, estimated_delivery_at)
    WHERE id = p_order_id AND status = p_from_status::order_status
    RETURNING * INTO v_order;

    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found or status has changed (expected: %)', p_from_status;
    END IF;

    INSERT INTO order_status_history (order_id, from_status, to_status, changed_by, notes)
    VALUES (p_order_id, p_from_status::order_status, p_to_status::order_status, p_changed_by, p_notes);

    RETURN jsonb_build_object(
        'id', v_order.id,
        'order_number', v_order.order_number,
        'status', v_order.status,
        'delivery_method', v_order.delivery_method
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- get_orders: role-aware branching, includes delivery_otp for customers
-- ============================================================
CREATE OR REPLACE FUNCTION get_orders(
    p_status TEXT DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_role user_role;
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

    v_role := auth.role();

    IF v_role = 'delivery_staff' THEN
        -- Delivery staff see orders assigned to them (no OTP exposed)
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
            WHERE o.delivery_staff_id = v_user_id
              AND (p_status IS NULL OR o.status = p_status::order_status)
            ORDER BY o.created_at DESC
            LIMIT p_limit
            OFFSET p_offset
        ) order_row;
    ELSE
        -- Customers see their own orders with delivery_otp
        SELECT COALESCE(json_agg(order_row ORDER BY order_row.created_at DESC), '[]'::json)
        INTO v_result
        FROM (
            SELECT
                o.id,
                o.order_number,
                o.status,
                o.total_paise,
                o.delivery_method,
                o.delivery_otp,
                o.created_at,
                (SELECT COUNT(*)::INT FROM order_items oi WHERE oi.order_id = o.id) AS item_count
            FROM orders o
            WHERE o.user_id = v_user_id
              AND (p_status IS NULL OR o.status = p_status::order_status)
            ORDER BY o.created_at DESC
            LIMIT p_limit
            OFFSET p_offset
        ) order_row;
    END IF;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- get_order: role-aware access + delivery_otp for customer + customer object
-- ============================================================
CREATE OR REPLACE FUNCTION get_order(p_order_id UUID)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_role user_role;
    v_order JSON;
    v_items JSON;
    v_customer JSON;
    v_delivery_staff JSON;
    v_order_user_id UUID;
    v_delivery_staff_id UUID;
    v_delivery_otp VARCHAR(4);
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    v_role := auth.role();

    -- Check order exists and fetch ownership info
    SELECT user_id, delivery_staff_id, delivery_otp
    INTO v_order_user_id, v_delivery_staff_id, v_delivery_otp
    FROM orders
    WHERE id = p_order_id;

    IF v_order_user_id IS NULL THEN
        RAISE EXCEPTION 'ORDER_NOT_FOUND: Order not found';
    END IF;

    -- Allow access if: admin, customer owns it, or delivery staff is assigned
    IF v_role != 'admin' AND v_order_user_id != v_user_id THEN
        IF NOT (v_role = 'delivery_staff' AND v_delivery_staff_id IS NOT NULL AND v_delivery_staff_id = v_user_id) THEN
            RAISE EXCEPTION 'FORBIDDEN: Order does not belong to this user';
        END IF;
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

    -- Get customer info (order owner)
    SELECT json_build_object(
        'id', u.id,
        'name', u.name,
        'phone', u.phone
    )
    INTO v_customer
    FROM users u
    WHERE u.id = v_order_user_id;

    -- Get delivery staff info (if assigned)
    IF v_delivery_staff_id IS NOT NULL THEN
        SELECT json_build_object(
            'id', u.id,
            'name', u.name,
            'phone', u.phone
        )
        INTO v_delivery_staff
        FROM users u
        WHERE u.id = v_delivery_staff_id;
    END IF;

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
    -- delivery_otp only included for the order owner (customer), not delivery staff
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
        'delivery_otp', CASE WHEN v_order_user_id = v_user_id THEN v_delivery_otp ELSE NULL END,
        'items', v_items,
        'customer', v_customer,
        'delivery_staff', v_delivery_staff
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
