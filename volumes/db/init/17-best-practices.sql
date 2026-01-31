-- =============================================
-- 17-best-practices.sql
-- Database best practices: tighter GRANTs, RLS,
-- atomic RPCs, indexes, constraints, cleanup
-- =============================================

BEGIN;

-- =============================================
-- 1A. TIGHTEN GRANTs
-- =============================================

-- porter_deliveries: anon doesn't need SELECT
REVOKE SELECT ON porter_deliveries FROM anon;

-- porter_webhooks: webhooks come from Porter servers via service_role, not authenticated users
REVOKE INSERT ON porter_webhooks FROM authenticated;

-- =============================================
-- 1B. RESTRICT app_settings VISIBILITY
-- =============================================

DROP POLICY IF EXISTS "settings_public_read" ON app_settings;

-- Only expose customer-facing settings publicly
CREATE POLICY "settings_public_read" ON app_settings
    FOR SELECT TO anon, authenticated
    USING (key IN (
        'shipping_charge_paise', 'free_shipping_threshold_paise',
        'serviceable_pincodes', 'min_order_paise'
    ));

-- Admins see everything
DROP POLICY IF EXISTS "settings_admin_read_all" ON app_settings;
CREATE POLICY "settings_admin_read_all" ON app_settings
    FOR SELECT TO authenticated
    USING ((select auth.is_admin()));

-- =============================================
-- 1C. TRANSACTIONAL RPC: create_order_atomic
-- =============================================

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
        order_id, product_id, weight_option_id,
        product_name, product_name_gu, weight_label, weight_grams,
        unit_price_paise, quantity, total_paise
    )
    SELECT
        v_order_id,
        (item->>'product_id')::UUID,
        NULL,
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

GRANT EXECUTE ON FUNCTION create_order_atomic TO service_role;

-- =============================================
-- 1D. TRANSACTIONAL RPC: update_order_status_atomic
-- =============================================

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
        delivery_type = COALESCE((p_update_data->>'delivery_type')::delivery_type, delivery_type),
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

-- =============================================
-- 1E. TRANSACTIONAL RPC: process_account_deletion_atomic
-- =============================================

CREATE OR REPLACE FUNCTION process_account_deletion_atomic(
    p_request_id UUID,
    p_admin_id UUID,
    p_admin_notes TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    v_user RECORD;
    v_request RECORD;
    v_uuid_prefix TEXT;
BEGIN
    -- Fetch & lock the deletion request
    SELECT * INTO v_request FROM account_deletion_requests
    WHERE id = p_request_id AND status = 'pending' FOR UPDATE;

    IF v_request IS NULL THEN
        RAISE EXCEPTION 'Deletion request not found or already processed';
    END IF;

    -- Fetch the user
    SELECT * INTO v_user FROM users WHERE id = v_request.user_id;
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    -- Check active orders
    IF EXISTS (
        SELECT 1 FROM orders WHERE user_id = v_user.id
        AND status IN ('placed', 'confirmed', 'out_for_delivery', 'delivery_failed')
    ) THEN
        RAISE EXCEPTION 'ACTIVE_ORDERS_EXIST';
    END IF;

    -- Check active delivery assignments
    IF v_user.role = 'delivery_staff' AND EXISTS (
        SELECT 1 FROM orders WHERE delivery_staff_id = v_user.id
        AND status IN ('placed', 'confirmed', 'out_for_delivery', 'delivery_failed')
    ) THEN
        RAISE EXCEPTION 'ACTIVE_DELIVERY_ASSIGNMENTS';
    END IF;

    -- NULL out delivery_staff_id on terminal orders
    IF v_user.role = 'delivery_staff' THEN
        UPDATE orders SET delivery_staff_id = NULL
        WHERE delivery_staff_id = v_user.id AND status IN ('delivered', 'cancelled');
    END IF;

    -- Delete user data
    DELETE FROM user_addresses WHERE user_id = v_user.id;
    DELETE FROM favorites WHERE user_id = v_user.id;
    DELETE FROM push_tokens WHERE user_id = v_user.id;
    DELETE FROM refresh_tokens WHERE user_id = v_user.id;

    -- Clean phone-based records
    DELETE FROM otp_requests WHERE phone = v_user.phone;
    DELETE FROM otp_rate_limits WHERE phone_number = v_user.phone;
    DELETE FROM test_otp_records WHERE phone_number = v_user.phone;

    -- Anonymize user
    v_uuid_prefix := substring(gen_random_uuid()::TEXT from 1 for 8);
    UPDATE users SET
        phone = '+00deleted_' || v_uuid_prefix,
        name = 'Deleted User',
        is_active = false
    WHERE id = v_user.id;

    -- Mark request approved
    UPDATE account_deletion_requests SET
        status = 'approved',
        processed_by = p_admin_id,
        processed_at = NOW(),
        admin_notes = p_admin_notes
    WHERE id = p_request_id;

    RETURN jsonb_build_object('success', true, 'user_id', v_user.id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION process_account_deletion_atomic TO service_role;

-- =============================================
-- 1G. CHECK CONSTRAINTS
-- =============================================

ALTER TABLE users ADD CONSTRAINT chk_users_phone_format
    CHECK (phone ~ '^\+91[6-9]\d{9}$' OR phone ~ '^\+00deleted_');

ALTER TABLE order_items ADD CONSTRAINT chk_order_items_total
    CHECK (total_paise = unit_price_paise * quantity);

ALTER TABLE orders ADD CONSTRAINT chk_orders_total_gte_subtotal
    CHECK (total_paise >= subtotal_paise);

ALTER TABLE categories ADD CONSTRAINT chk_categories_slug_format
    CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$');

-- =============================================
-- 1H. SET MEANINGFUL DAILY OTP RATE LIMIT
-- =============================================

CREATE OR REPLACE FUNCTION check_otp_rate_limit(p_phone VARCHAR(15))
RETURNS JSONB AS $$
DECLARE
    v_record otp_rate_limits%ROWTYPE;
    v_hourly_limit INTEGER := 40;
    v_daily_limit INTEGER := 100;
    v_hourly_count INTEGER;
    v_daily_count INTEGER;
    v_now TIMESTAMPTZ := NOW();
    v_current_hour TIMESTAMPTZ;
    v_current_day TIMESTAMPTZ;
BEGIN
    v_current_hour := date_trunc('hour', v_now);
    v_current_day := date_trunc('day', v_now);

    SELECT * INTO v_record FROM otp_rate_limits WHERE phone_number = p_phone FOR UPDATE;

    IF v_record IS NULL THEN
        INSERT INTO otp_rate_limits (phone_number, hourly_count, daily_count, last_reset_hour, last_reset_day)
        VALUES (p_phone, 1, 1, v_current_hour, v_current_day)
        RETURNING * INTO v_record;

        RETURN jsonb_build_object(
            'allowed', true,
            'hourly_remaining', v_hourly_limit - 1,
            'daily_remaining', v_daily_limit - 1
        );
    END IF;

    IF v_record.last_reset_hour < v_current_hour THEN
        v_hourly_count := 0;
    ELSE
        v_hourly_count := v_record.hourly_count;
    END IF;

    IF v_record.last_reset_day < v_current_day THEN
        v_daily_count := 0;
    ELSE
        v_daily_count := v_record.daily_count;
    END IF;

    IF v_hourly_count >= v_hourly_limit THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'hourly_remaining', 0,
            'daily_remaining', v_daily_limit - v_daily_count,
            'error', 'HOURLY_LIMIT_EXCEEDED',
            'message', 'Too many OTP requests this hour. Please try again later.'
        );
    END IF;

    IF v_daily_count >= v_daily_limit THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'hourly_remaining', v_hourly_limit - v_hourly_count,
            'daily_remaining', 0,
            'error', 'DAILY_LIMIT_EXCEEDED',
            'message', 'Daily OTP limit reached. Please try again tomorrow.'
        );
    END IF;

    UPDATE otp_rate_limits
    SET hourly_count = CASE WHEN last_reset_hour < v_current_hour THEN 1 ELSE hourly_count + 1 END,
        daily_count = CASE WHEN last_reset_day < v_current_day THEN 1 ELSE daily_count + 1 END,
        last_reset_hour = CASE WHEN last_reset_hour < v_current_hour THEN v_current_hour ELSE last_reset_hour END,
        last_reset_day = CASE WHEN last_reset_day < v_current_day THEN v_current_day ELSE last_reset_day END
    WHERE phone_number = p_phone;

    RETURN jsonb_build_object(
        'allowed', true,
        'hourly_remaining', v_hourly_limit - v_hourly_count - 1,
        'daily_remaining', v_daily_limit - v_daily_count - 1
    );
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- 1I. ADD porter_webhooks CLEANUP
-- =============================================

CREATE OR REPLACE FUNCTION public.cleanup_expired_data()
RETURNS JSONB AS $$
DECLARE
    v_otp_deleted INTEGER;
    v_tokens_deleted INTEGER;
    v_phone_rate_deleted INTEGER;
    v_ip_rate_deleted INTEGER;
    v_webhooks_deleted INTEGER;
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

    DELETE FROM porter_webhooks
    WHERE created_at < NOW() - INTERVAL '90 days';
    GET DIAGNOSTICS v_webhooks_deleted = ROW_COUNT;

    RETURN jsonb_build_object(
        'otp_requests_deleted', v_otp_deleted,
        'refresh_tokens_deleted', v_tokens_deleted,
        'phone_rate_limits_deleted', v_phone_rate_deleted,
        'ip_rate_limits_deleted', v_ip_rate_deleted,
        'porter_webhooks_deleted', v_webhooks_deleted,
        'cleaned_at', NOW()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- 1J. ADDRESS LIMIT TRIGGER
-- =============================================

CREATE OR REPLACE FUNCTION check_address_limit()
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT COUNT(*) FROM user_addresses WHERE user_id = NEW.user_id) >= 10 THEN
        RAISE EXCEPTION 'Maximum 10 addresses per user';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_address_limit ON user_addresses;
CREATE TRIGGER enforce_address_limit
    BEFORE INSERT ON user_addresses
    FOR EACH ROW EXECUTE FUNCTION check_address_limit();

COMMIT;

-- =============================================
-- 1F. COMPOSITE INDEXES (outside transaction —
--     CREATE INDEX CONCURRENTLY cannot run in a tx)
-- =============================================

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_user_created ON orders(user_id, created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_user_status ON orders(user_id, status);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_role_active ON users(role, is_active) WHERE is_active = true;
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_refresh_tokens_active ON refresh_tokens(user_id) WHERE revoked = false;
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_favorites_product ON favorites(product_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_status_history_created ON order_status_history(created_at DESC);
