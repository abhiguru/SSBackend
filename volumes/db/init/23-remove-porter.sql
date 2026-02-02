-- =============================================
-- 23-remove-porter.sql
-- Remove all Porter delivery integration artifacts.
-- After this migration only in-house delivery exists.
-- =============================================

BEGIN;

-- 1. Drop Porter tables (policies, grants, indexes cascade)
DROP TABLE IF EXISTS porter_webhooks CASCADE;
DROP TABLE IF EXISTS porter_deliveries CASCADE;

-- 2. Drop Porter helper function
DROP FUNCTION IF EXISTS get_store_pickup_coords();

-- 3. Drop delivery_type column from orders (index drops with it)
ALTER TABLE orders DROP COLUMN IF EXISTS delivery_type;

-- 4. Drop the delivery_type enum
DROP TYPE IF EXISTS delivery_type;

-- 5. Remove Porter-related app_settings rows
DELETE FROM app_settings WHERE key LIKE 'porter_pickup_%';

-- 6. Recreate update_order_status_atomic without delivery_type
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
    -- Optimistic lock: verify status hasn't changed
    UPDATE orders
    SET status = p_to_status::order_status,
        delivery_staff_id = COALESCE((p_update_data->>'delivery_staff_id')::UUID, delivery_staff_id),
        delivery_otp_hash = COALESCE(p_update_data->>'delivery_otp_hash', delivery_otp_hash),
        delivery_otp_expires = COALESCE((p_update_data->>'delivery_otp_expires')::TIMESTAMPTZ, delivery_otp_expires),
        cancellation_reason = COALESCE(p_update_data->>'cancellation_reason', cancellation_reason)
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
        'status', v_order.status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_order_status_atomic TO service_role;

-- 7. Recreate cleanup_expired_data without porter_webhooks reference
CREATE OR REPLACE FUNCTION public.cleanup_expired_data()
RETURNS JSONB AS $$
DECLARE
    v_otp_deleted INTEGER;
    v_tokens_deleted INTEGER;
    v_phone_rate_deleted INTEGER;
    v_ip_rate_deleted INTEGER;
BEGIN
    DELETE FROM otp_requests
    WHERE created_at < NOW() - INTERVAL '24 hours';
    GET DIAGNOSTICS v_otp_deleted = ROW_COUNT;

    DELETE FROM refresh_tokens
    WHERE (revoked = true OR expires_at < NOW())
      AND created_at < NOW() - INTERVAL '7 days';
    GET DIAGNOSTICS v_tokens_deleted = ROW_COUNT;

    DELETE FROM otp_rate_limits
    WHERE updated_at < NOW() - INTERVAL '48 hours';
    GET DIAGNOSTICS v_phone_rate_deleted = ROW_COUNT;

    DELETE FROM ip_rate_limits
    WHERE updated_at < NOW() - INTERVAL '48 hours';
    GET DIAGNOSTICS v_ip_rate_deleted = ROW_COUNT;

    RETURN jsonb_build_object(
        'otp_requests_deleted', v_otp_deleted,
        'refresh_tokens_deleted', v_tokens_deleted,
        'phone_rate_limits_deleted', v_phone_rate_deleted,
        'ip_rate_limits_deleted', v_ip_rate_deleted,
        'cleaned_at', NOW()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. Clean up stale GRANTs from 17-best-practices.sql
-- (these will be no-ops if the tables were already dropped, but safe to run)

COMMIT;
