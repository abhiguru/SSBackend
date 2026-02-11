-- =============================================
-- 35-function-optimization.sql
-- Performance Optimization: SQL Function Fixes
-- =============================================
-- Implements items 11-13 from the performance audit:
-- 11. Fix N+1 query in get_orders() function
-- 12. Optimize address default trigger
-- 13. Batch rate limit checks (helper function)

BEGIN;

-- =============================================
-- ITEM 11: Fix N+1 Query in get_orders() Function
-- =============================================
-- BEFORE: Subquery for item_count runs once per order (N+1)
-- AFTER: Single aggregated query with LEFT JOIN

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

    -- OPTIMIZED: Use LEFT JOIN with aggregation instead of correlated subquery
    -- This reduces N+1 queries to a single query
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
            COALESCE(item_counts.item_count, 0)::INT AS item_count
        FROM orders o
        LEFT JOIN (
            SELECT order_id, COUNT(*)::INT AS item_count
            FROM order_items
            GROUP BY order_id
        ) item_counts ON item_counts.order_id = o.id
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
-- ITEM 12: Optimize Address Default Trigger
-- =============================================
-- Add WHERE clause to limit scanned rows

CREATE OR REPLACE FUNCTION ensure_single_default_address()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_default = true THEN
        -- OPTIMIZED: Only update rows where is_default = true
        -- This avoids scanning non-default addresses
        UPDATE user_addresses
        SET is_default = false
        WHERE user_id = NEW.user_id
          AND id != NEW.id
          AND is_default = true;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- ITEM 13: Batch Rate Limit Checks
-- =============================================
-- Combined function to check both phone and IP rate limits in single call
-- Reduces network round-trips in send-otp edge function

CREATE OR REPLACE FUNCTION check_rate_limits_combined(
    p_phone TEXT,
    p_ip INET
)
RETURNS TABLE(
    phone_ok BOOLEAN,
    phone_count INT,
    ip_ok BOOLEAN,
    ip_count INT
) AS $$
DECLARE
    v_phone_limit INT := 5;  -- Max OTPs per phone per hour
    v_ip_limit INT := 20;    -- Max OTPs per IP per hour
    v_phone_count INT;
    v_ip_count INT;
BEGIN
    -- Get phone rate limit count
    SELECT COALESCE(count, 0)
    INTO v_phone_count
    FROM otp_rate_limits
    WHERE phone = p_phone
      AND updated_at > NOW() - INTERVAL '1 hour';

    IF v_phone_count IS NULL THEN
        v_phone_count := 0;
    END IF;

    -- Get IP rate limit count
    SELECT COALESCE(count, 0)
    INTO v_ip_count
    FROM ip_rate_limits
    WHERE ip_address = p_ip
      AND updated_at > NOW() - INTERVAL '1 hour';

    IF v_ip_count IS NULL THEN
        v_ip_count := 0;
    END IF;

    -- Return combined results
    RETURN QUERY SELECT
        v_phone_count < v_phone_limit,
        v_phone_count,
        v_ip_count < v_ip_limit,
        v_ip_count;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION check_rate_limits_combined(TEXT, INET) TO service_role;

-- =============================================
-- Additional Function Optimizations
-- =============================================

-- Optimize get_cart_summary with explicit column selection
CREATE OR REPLACE FUNCTION get_cart_summary()
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_item_count INTEGER;
    v_subtotal_paise BIGINT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- OPTIMIZED: Uses custom_weight_grams with price_per_kg_paise
    SELECT
        COALESCE(SUM(ci.quantity), 0),
        COALESCE(SUM((p.price_per_kg_paise * ci.custom_weight_grams / 1000) * ci.quantity), 0)
    INTO v_item_count, v_subtotal_paise
    FROM cart_items ci
    INNER JOIN products p ON p.id = ci.product_id
    WHERE ci.user_id = v_user_id;

    RETURN json_build_object(
        'item_count', v_item_count,
        'subtotal_paise', v_subtotal_paise
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMIT;
