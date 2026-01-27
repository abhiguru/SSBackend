-- =============================================
-- Masala Spice Shop - RLS Performance Optimizations
-- =============================================
-- Applies Supabase best practices:
-- 1A. Wrap auth functions in (select ...) for initPlan caching
-- 1B. SECURITY DEFINER helpers to eliminate cascading RLS
-- 1C. Explicit role targeting on policies
-- 1D. Expired data cleanup function
-- 1E. Missing app_settings updated_at trigger
--
-- Reference: https://supabase.com/docs/guides/troubleshooting/rls-performance-and-best-practices-Z5Jjwv

BEGIN;

-- =============================================
-- 1B. SECURITY DEFINER HELPER FUNCTIONS
-- =============================================
-- These bypass RLS on parent tables to eliminate cascading RLS evaluation.

CREATE OR REPLACE FUNCTION public.is_product_visible(p_product_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM products
        WHERE id = p_product_id
          AND is_available = true
          AND is_active = true
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.user_owns_order(p_order_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM orders
        WHERE id = p_order_id
          AND user_id = p_user_id
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.delivery_assigned_order(p_order_id UUID, p_staff_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM orders
        WHERE id = p_order_id
          AND delivery_staff_id = p_staff_id
          AND status = 'out_for_delivery'
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.is_product_visible(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.user_owns_order(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delivery_assigned_order(UUID, UUID) TO authenticated;

-- =============================================
-- 1D. CLEANUP EXPIRED DATA FUNCTION
-- =============================================

CREATE OR REPLACE FUNCTION public.cleanup_expired_data()
RETURNS JSONB AS $$
DECLARE
    v_otp_deleted INTEGER;
    v_tokens_deleted INTEGER;
    v_phone_rate_deleted INTEGER;
    v_ip_rate_deleted INTEGER;
BEGIN
    -- Delete OTP requests older than 24 hours
    DELETE FROM otp_requests
    WHERE created_at < NOW() - INTERVAL '24 hours';
    GET DIAGNOSTICS v_otp_deleted = ROW_COUNT;

    -- Delete revoked or expired refresh tokens older than 7 days
    DELETE FROM refresh_tokens
    WHERE (revoked = true OR expires_at < NOW())
      AND created_at < NOW() - INTERVAL '7 days';
    GET DIAGNOSTICS v_tokens_deleted = ROW_COUNT;

    -- Delete stale phone rate limit records older than 48 hours
    DELETE FROM otp_rate_limits
    WHERE updated_at < NOW() - INTERVAL '48 hours';
    GET DIAGNOSTICS v_phone_rate_deleted = ROW_COUNT;

    -- Delete stale IP rate limit records older than 48 hours
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

GRANT EXECUTE ON FUNCTION public.cleanup_expired_data() TO service_role;

-- =============================================
-- 1E. MISSING app_settings UPDATED_AT TRIGGER
-- =============================================

CREATE OR REPLACE TRIGGER update_app_settings_updated_at
    BEFORE UPDATE ON app_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================
-- 1A + 1C. REWRITE ALL RLS POLICIES
-- =============================================
-- Drop and recreate with (select ...) wrappers and role targeting.

-- =============================================
-- USERS
-- =============================================

DROP POLICY IF EXISTS "users_read_own" ON users;
CREATE POLICY "users_read_own" ON users
    FOR SELECT TO authenticated
    USING (id = (select auth.uid()));

DROP POLICY IF EXISTS "users_update_own" ON users;
CREATE POLICY "users_update_own" ON users
    FOR UPDATE TO authenticated
    USING (id = (select auth.uid()))
    WITH CHECK (id = (select auth.uid()));

DROP POLICY IF EXISTS "users_admin_read" ON users;
CREATE POLICY "users_admin_read" ON users
    FOR SELECT TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "users_admin_update" ON users;
CREATE POLICY "users_admin_update" ON users
    FOR UPDATE TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "users_superadmin_insert" ON users;
CREATE POLICY "users_superadmin_insert" ON users
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.is_super_admin()));

-- =============================================
-- PUSH_TOKENS
-- =============================================

DROP POLICY IF EXISTS "push_read_own" ON push_tokens;
CREATE POLICY "push_read_own" ON push_tokens
    FOR SELECT TO authenticated
    USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "push_insert_own" ON push_tokens;
CREATE POLICY "push_insert_own" ON push_tokens
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "push_update_own" ON push_tokens;
CREATE POLICY "push_update_own" ON push_tokens
    FOR UPDATE TO authenticated
    USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "push_delete_own" ON push_tokens;
CREATE POLICY "push_delete_own" ON push_tokens
    FOR DELETE TO authenticated
    USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "push_admin_read" ON push_tokens;
CREATE POLICY "push_admin_read" ON push_tokens
    FOR SELECT TO authenticated
    USING ((select auth.is_admin()));

-- =============================================
-- CATEGORIES
-- =============================================

DROP POLICY IF EXISTS "categories_public_read" ON categories;
CREATE POLICY "categories_public_read" ON categories
    FOR SELECT TO anon, authenticated
    USING (is_active = true);

DROP POLICY IF EXISTS "categories_admin_read" ON categories;
CREATE POLICY "categories_admin_read" ON categories
    FOR SELECT TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "categories_admin_insert" ON categories;
CREATE POLICY "categories_admin_insert" ON categories
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.is_admin()));

DROP POLICY IF EXISTS "categories_admin_update" ON categories;
CREATE POLICY "categories_admin_update" ON categories
    FOR UPDATE TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "categories_admin_delete" ON categories;
CREATE POLICY "categories_admin_delete" ON categories
    FOR DELETE TO authenticated
    USING ((select auth.is_admin()));

-- =============================================
-- PRODUCTS
-- =============================================

DROP POLICY IF EXISTS "products_public_read" ON products;
CREATE POLICY "products_public_read" ON products
    FOR SELECT TO anon, authenticated
    USING (is_available = true AND is_active = true);

DROP POLICY IF EXISTS "products_admin_read" ON products;
CREATE POLICY "products_admin_read" ON products
    FOR SELECT TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "products_admin_insert" ON products;
CREATE POLICY "products_admin_insert" ON products
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.is_admin()));

DROP POLICY IF EXISTS "products_admin_update" ON products;
CREATE POLICY "products_admin_update" ON products
    FOR UPDATE TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "products_admin_delete" ON products;
CREATE POLICY "products_admin_delete" ON products
    FOR DELETE TO authenticated
    USING ((select auth.is_admin()));

-- =============================================
-- WEIGHT_OPTIONS
-- =============================================

DROP POLICY IF EXISTS "weight_options_public_read" ON weight_options;
CREATE POLICY "weight_options_public_read" ON weight_options
    FOR SELECT TO anon, authenticated
    USING (
        is_available = true
        AND is_product_visible(product_id)
    );

DROP POLICY IF EXISTS "weight_options_admin_read" ON weight_options;
CREATE POLICY "weight_options_admin_read" ON weight_options
    FOR SELECT TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "weight_options_admin_insert" ON weight_options;
CREATE POLICY "weight_options_admin_insert" ON weight_options
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.is_admin()));

DROP POLICY IF EXISTS "weight_options_admin_update" ON weight_options;
CREATE POLICY "weight_options_admin_update" ON weight_options
    FOR UPDATE TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "weight_options_admin_delete" ON weight_options;
CREATE POLICY "weight_options_admin_delete" ON weight_options
    FOR DELETE TO authenticated
    USING ((select auth.is_admin()));

-- =============================================
-- USER_ADDRESSES
-- =============================================

DROP POLICY IF EXISTS "addresses_read_own" ON user_addresses;
CREATE POLICY "addresses_read_own" ON user_addresses
    FOR SELECT TO authenticated
    USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "addresses_insert_own" ON user_addresses;
CREATE POLICY "addresses_insert_own" ON user_addresses
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "addresses_update_own" ON user_addresses;
CREATE POLICY "addresses_update_own" ON user_addresses
    FOR UPDATE TO authenticated
    USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "addresses_delete_own" ON user_addresses;
CREATE POLICY "addresses_delete_own" ON user_addresses
    FOR DELETE TO authenticated
    USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "addresses_admin_read" ON user_addresses;
CREATE POLICY "addresses_admin_read" ON user_addresses
    FOR SELECT TO authenticated
    USING ((select auth.is_admin()));

-- =============================================
-- FAVORITES
-- =============================================

DROP POLICY IF EXISTS "favorites_read_own" ON favorites;
CREATE POLICY "favorites_read_own" ON favorites
    FOR SELECT TO authenticated
    USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "favorites_insert_own" ON favorites;
CREATE POLICY "favorites_insert_own" ON favorites
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "favorites_delete_own" ON favorites;
CREATE POLICY "favorites_delete_own" ON favorites
    FOR DELETE TO authenticated
    USING (user_id = (select auth.uid()));

-- =============================================
-- ORDERS
-- =============================================

DROP POLICY IF EXISTS "orders_read_own" ON orders;
CREATE POLICY "orders_read_own" ON orders
    FOR SELECT TO authenticated
    USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "orders_admin_read" ON orders;
CREATE POLICY "orders_admin_read" ON orders
    FOR SELECT TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "orders_admin_update" ON orders;
CREATE POLICY "orders_admin_update" ON orders
    FOR UPDATE TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "orders_delivery_read" ON orders;
CREATE POLICY "orders_delivery_read" ON orders
    FOR SELECT TO authenticated
    USING (
        (select auth.is_delivery_staff())
        AND delivery_staff_id = (select auth.uid())
        AND status = 'out_for_delivery'
    );

DROP POLICY IF EXISTS "orders_delivery_update" ON orders;
CREATE POLICY "orders_delivery_update" ON orders
    FOR UPDATE TO authenticated
    USING (
        (select auth.is_delivery_staff())
        AND delivery_staff_id = (select auth.uid())
        AND status = 'out_for_delivery'
    );

-- =============================================
-- ORDER_ITEMS
-- =============================================

DROP POLICY IF EXISTS "order_items_read_own" ON order_items;
CREATE POLICY "order_items_read_own" ON order_items
    FOR SELECT TO authenticated
    USING (user_owns_order(order_id, (select auth.uid())));

DROP POLICY IF EXISTS "order_items_admin_read" ON order_items;
CREATE POLICY "order_items_admin_read" ON order_items
    FOR SELECT TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "order_items_delivery_read" ON order_items;
CREATE POLICY "order_items_delivery_read" ON order_items
    FOR SELECT TO authenticated
    USING (delivery_assigned_order(order_id, (select auth.uid())));

-- =============================================
-- ORDER_STATUS_HISTORY
-- =============================================

DROP POLICY IF EXISTS "status_history_read_own" ON order_status_history;
CREATE POLICY "status_history_read_own" ON order_status_history
    FOR SELECT TO authenticated
    USING (user_owns_order(order_id, (select auth.uid())));

DROP POLICY IF EXISTS "status_history_admin_read" ON order_status_history;
CREATE POLICY "status_history_admin_read" ON order_status_history
    FOR SELECT TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "status_history_admin_insert" ON order_status_history;
CREATE POLICY "status_history_admin_insert" ON order_status_history
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.is_admin()));

-- =============================================
-- APP_SETTINGS
-- =============================================

DROP POLICY IF EXISTS "settings_public_read" ON app_settings;
CREATE POLICY "settings_public_read" ON app_settings
    FOR SELECT TO anon, authenticated
    USING (true);

DROP POLICY IF EXISTS "settings_admin_update" ON app_settings;
CREATE POLICY "settings_admin_update" ON app_settings
    FOR UPDATE TO authenticated
    USING ((select auth.is_admin()));

DROP POLICY IF EXISTS "settings_superadmin_insert" ON app_settings;
CREATE POLICY "settings_superadmin_insert" ON app_settings
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.is_super_admin()));

-- =============================================
-- SMS_CONFIG (from 05-auth-enhancements.sql)
-- =============================================

DROP POLICY IF EXISTS "Admin can manage sms_config" ON sms_config;
CREATE POLICY "Admin can manage sms_config" ON sms_config
    FOR ALL TO authenticated
    USING ((select auth.is_admin()))
    WITH CHECK ((select auth.is_admin()));

-- =============================================
-- TEST_OTP_RECORDS (from 05-auth-enhancements.sql)
-- =============================================

DROP POLICY IF EXISTS "Admin can manage test_otp_records" ON test_otp_records;
CREATE POLICY "Admin can manage test_otp_records" ON test_otp_records
    FOR ALL TO authenticated
    USING ((select auth.is_admin()))
    WITH CHECK ((select auth.is_admin()));

COMMIT;
