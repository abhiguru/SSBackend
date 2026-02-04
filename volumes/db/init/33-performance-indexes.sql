-- =============================================
-- 33-performance-indexes.sql
-- Performance Optimization: Database Indexes
-- =============================================
-- Implements items 1-6 from the performance audit:
-- 1. Index on order_items.product_id (FK index)
-- 2. Composite index for cart lookups
-- 3. Composite index for order status history
-- 4. Partial index for available products
-- 5. Composite index for products by category
-- 6. Index on order_status_history.changed_by
--
-- Also includes indexes on columns used in RLS policies (item 9)

BEGIN;

-- =============================================
-- ITEM 1: Missing Foreign Key Index on order_items.product_id
-- =============================================
-- Impact: HIGH - Eliminates sequential scans in order/product JOINs
-- The order_id index exists but product_id is missing

CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id);

-- =============================================
-- ITEM 2: Composite Index for Cart Lookups
-- =============================================
-- Impact: HIGH - Speeds up cart operations by 10-50x
-- Covers the UNIQUE constraint lookup pattern and user cart queries

CREATE INDEX IF NOT EXISTS idx_cart_items_user_product_weight
    ON cart_items(user_id, product_id, weight_option_id);

-- =============================================
-- ITEM 3: Composite Index for Order Status History
-- =============================================
-- Impact: MEDIUM - Improves order history timeline queries

CREATE INDEX IF NOT EXISTS idx_status_history_order_created
    ON order_status_history(order_id, created_at);

-- =============================================
-- ITEM 4: Partial Index for Available Products
-- =============================================
-- Impact: MEDIUM - Speeds up product catalog queries
-- Only indexes rows that match the common query filter

CREATE INDEX IF NOT EXISTS idx_products_available_active
    ON products(id)
    WHERE is_available = true AND is_active = true;

-- =============================================
-- ITEM 5: Composite Index for Products by Category
-- =============================================
-- Impact: MEDIUM - Optimizes "browse by category" queries

CREATE INDEX IF NOT EXISTS idx_products_category_available
    ON products(category_id, is_available, is_active);

-- =============================================
-- ITEM 6: Index on order_status_history.changed_by
-- =============================================
-- Impact: LOW - Improves admin audit queries

CREATE INDEX IF NOT EXISTS idx_status_history_changed_by
    ON order_status_history(changed_by)
    WHERE changed_by IS NOT NULL;

-- =============================================
-- ITEM 9: Indexes on Columns Used in RLS Policies
-- =============================================
-- Per Supabase docs, can improve RLS performance up to 100x
-- These cover user_id columns in RLS WHERE clauses

-- favorites.user_id (already has idx_favorites_user but verify)
CREATE INDEX IF NOT EXISTS idx_favorites_user_id ON favorites(user_id);

-- user_addresses.user_id (already has idx_addresses_user)
CREATE INDEX IF NOT EXISTS idx_addresses_user_id ON user_addresses(user_id);

-- push_tokens.user_id (already has idx_push_user)
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id ON push_tokens(user_id);

-- orders.delivery_staff_id for delivery staff queries
CREATE INDEX IF NOT EXISTS idx_orders_delivery_staff_status
    ON orders(delivery_staff_id, status)
    WHERE delivery_staff_id IS NOT NULL;

-- Weight options product lookup (for is_product_visible helper)
CREATE INDEX IF NOT EXISTS idx_weight_options_product_available
    ON weight_options(product_id, is_available);

-- =============================================
-- Additional Performance Indexes
-- =============================================

-- Orders by user and status (common query pattern)
CREATE INDEX IF NOT EXISTS idx_orders_user_status
    ON orders(user_id, status);

-- Orders by status for admin dashboard
CREATE INDEX IF NOT EXISTS idx_orders_status_created
    ON orders(status, created_at DESC);

-- Refresh tokens cleanup (for expired token queries)
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_revoked
    ON refresh_tokens(expires_at, revoked);

-- OTP requests cleanup and lookup
CREATE INDEX IF NOT EXISTS idx_otp_requests_phone_created
    ON otp_requests(phone, created_at DESC);

COMMIT;
