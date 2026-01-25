-- =============================================
-- Masala Spice Shop - Row Level Security Policies
-- =============================================

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE otp_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE weight_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_order_counters ENABLE ROW LEVEL SECURITY;

-- =============================================
-- USERS
-- =============================================

-- Users can read their own profile
CREATE POLICY "users_read_own" ON users
    FOR SELECT USING (id = auth.uid());

-- Users can update their own profile (name only)
CREATE POLICY "users_update_own" ON users
    FOR UPDATE USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- Admin can read all users
CREATE POLICY "users_admin_read" ON users
    FOR SELECT USING (auth.is_admin());

-- Admin can update users (role, is_active)
CREATE POLICY "users_admin_update" ON users
    FOR UPDATE USING (auth.is_admin());

-- Super admin can insert users
CREATE POLICY "users_superadmin_insert" ON users
    FOR INSERT WITH CHECK (auth.is_super_admin());

-- =============================================
-- OTP_REQUESTS (service role only via edge functions)
-- =============================================

-- No public access - handled by edge functions with service role

-- =============================================
-- REFRESH_TOKENS (service role only)
-- =============================================

-- No public access - handled by edge functions

-- =============================================
-- PUSH_TOKENS
-- =============================================

-- Users can manage their own push tokens
CREATE POLICY "push_read_own" ON push_tokens
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "push_insert_own" ON push_tokens
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "push_update_own" ON push_tokens
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "push_delete_own" ON push_tokens
    FOR DELETE USING (user_id = auth.uid());

-- Admin can read all push tokens (for notifications)
CREATE POLICY "push_admin_read" ON push_tokens
    FOR SELECT USING (auth.is_admin());

-- =============================================
-- CATEGORIES
-- =============================================

-- Public can read active categories
CREATE POLICY "categories_public_read" ON categories
    FOR SELECT USING (is_active = true);

-- Admin can read all categories
CREATE POLICY "categories_admin_read" ON categories
    FOR SELECT USING (auth.is_admin());

-- Admin can insert categories
CREATE POLICY "categories_admin_insert" ON categories
    FOR INSERT WITH CHECK (auth.is_admin());

-- Admin can update categories
CREATE POLICY "categories_admin_update" ON categories
    FOR UPDATE USING (auth.is_admin());

-- Admin can delete categories (soft delete preferred)
CREATE POLICY "categories_admin_delete" ON categories
    FOR DELETE USING (auth.is_admin());

-- =============================================
-- PRODUCTS
-- =============================================

-- Public can read available, active products
CREATE POLICY "products_public_read" ON products
    FOR SELECT USING (is_available = true AND is_active = true);

-- Admin can read all products
CREATE POLICY "products_admin_read" ON products
    FOR SELECT USING (auth.is_admin());

-- Admin can insert products
CREATE POLICY "products_admin_insert" ON products
    FOR INSERT WITH CHECK (auth.is_admin());

-- Admin can update products
CREATE POLICY "products_admin_update" ON products
    FOR UPDATE USING (auth.is_admin());

-- Admin can delete products
CREATE POLICY "products_admin_delete" ON products
    FOR DELETE USING (auth.is_admin());

-- =============================================
-- WEIGHT_OPTIONS
-- =============================================

-- Public can read available weight options for available products
CREATE POLICY "weight_options_public_read" ON weight_options
    FOR SELECT USING (
        is_available = true
        AND EXISTS (
            SELECT 1 FROM products
            WHERE products.id = weight_options.product_id
            AND products.is_available = true
            AND products.is_active = true
        )
    );

-- Admin can read all weight options
CREATE POLICY "weight_options_admin_read" ON weight_options
    FOR SELECT USING (auth.is_admin());

-- Admin can manage weight options
CREATE POLICY "weight_options_admin_insert" ON weight_options
    FOR INSERT WITH CHECK (auth.is_admin());

CREATE POLICY "weight_options_admin_update" ON weight_options
    FOR UPDATE USING (auth.is_admin());

CREATE POLICY "weight_options_admin_delete" ON weight_options
    FOR DELETE USING (auth.is_admin());

-- =============================================
-- USER_ADDRESSES
-- =============================================

-- Users can manage their own addresses
CREATE POLICY "addresses_read_own" ON user_addresses
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "addresses_insert_own" ON user_addresses
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "addresses_update_own" ON user_addresses
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "addresses_delete_own" ON user_addresses
    FOR DELETE USING (user_id = auth.uid());

-- Admin can read all addresses
CREATE POLICY "addresses_admin_read" ON user_addresses
    FOR SELECT USING (auth.is_admin());

-- =============================================
-- FAVORITES
-- =============================================

-- Users can manage their own favorites
CREATE POLICY "favorites_read_own" ON favorites
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "favorites_insert_own" ON favorites
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "favorites_delete_own" ON favorites
    FOR DELETE USING (user_id = auth.uid());

-- =============================================
-- ORDERS
-- =============================================

-- Users can read their own orders
CREATE POLICY "orders_read_own" ON orders
    FOR SELECT USING (user_id = auth.uid());

-- Admin can read all orders
CREATE POLICY "orders_admin_read" ON orders
    FOR SELECT USING (auth.is_admin());

-- Admin can update orders
CREATE POLICY "orders_admin_update" ON orders
    FOR UPDATE USING (auth.is_admin());

-- Delivery staff can read their assigned orders
CREATE POLICY "orders_delivery_read" ON orders
    FOR SELECT USING (
        auth.is_delivery_staff()
        AND delivery_staff_id = auth.uid()
        AND status = 'out_for_delivery'
    );

-- Delivery staff can update their assigned orders (limited fields via edge function)
CREATE POLICY "orders_delivery_update" ON orders
    FOR UPDATE USING (
        auth.is_delivery_staff()
        AND delivery_staff_id = auth.uid()
        AND status = 'out_for_delivery'
    );

-- =============================================
-- ORDER_ITEMS
-- =============================================

-- Users can read items of their own orders
CREATE POLICY "order_items_read_own" ON order_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_items.order_id
            AND orders.user_id = auth.uid()
        )
    );

-- Admin can read all order items
CREATE POLICY "order_items_admin_read" ON order_items
    FOR SELECT USING (auth.is_admin());

-- Delivery staff can read items of assigned orders
CREATE POLICY "order_items_delivery_read" ON order_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_items.order_id
            AND orders.delivery_staff_id = auth.uid()
            AND orders.status = 'out_for_delivery'
        )
    );

-- =============================================
-- ORDER_STATUS_HISTORY
-- =============================================

-- Users can read history of their own orders
CREATE POLICY "status_history_read_own" ON order_status_history
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_status_history.order_id
            AND orders.user_id = auth.uid()
        )
    );

-- Admin can read all history
CREATE POLICY "status_history_admin_read" ON order_status_history
    FOR SELECT USING (auth.is_admin());

-- Admin can insert history
CREATE POLICY "status_history_admin_insert" ON order_status_history
    FOR INSERT WITH CHECK (auth.is_admin());

-- =============================================
-- APP_SETTINGS
-- =============================================

-- Public can read app settings (shipping, pincodes, etc.)
CREATE POLICY "settings_public_read" ON app_settings
    FOR SELECT USING (true);

-- Admin can update settings
CREATE POLICY "settings_admin_update" ON app_settings
    FOR UPDATE USING (auth.is_admin());

-- Super admin can insert settings
CREATE POLICY "settings_superadmin_insert" ON app_settings
    FOR INSERT WITH CHECK (auth.is_super_admin());

-- =============================================
-- DAILY_ORDER_COUNTERS (service role only)
-- =============================================

-- No public access - used internally by generate_order_number()

-- =============================================
-- GRANT TABLE PERMISSIONS
-- =============================================

-- Grant usage on public schema
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Grant select on public read tables
GRANT SELECT ON categories TO anon, authenticated;
GRANT SELECT ON products TO anon, authenticated;
GRANT SELECT ON weight_options TO anon, authenticated;
GRANT SELECT ON app_settings TO anon, authenticated;

-- Grant full access on user-owned tables
GRANT SELECT, INSERT, UPDATE, DELETE ON user_addresses TO authenticated;
GRANT SELECT, INSERT, DELETE ON favorites TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON push_tokens TO authenticated;

-- Grant select on order tables
GRANT SELECT ON orders TO authenticated;
GRANT SELECT ON order_items TO authenticated;
GRANT SELECT ON order_status_history TO authenticated;

-- Grant select on users (filtered by RLS)
GRANT SELECT, UPDATE ON users TO authenticated;

-- Grant sequence usage
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;
