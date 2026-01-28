-- =============================================
-- Masala Spice Shop - Database Schema
-- =============================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================
-- ENUMS
-- =============================================

CREATE TYPE user_role AS ENUM ('customer', 'admin', 'delivery_staff', 'super_admin');

CREATE TYPE order_status AS ENUM (
    'placed',
    'confirmed',
    'out_for_delivery',
    'delivered',
    'cancelled',
    'delivery_failed'
);

-- =============================================
-- TABLES
-- =============================================

-- Users table (all user types)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone VARCHAR(15) NOT NULL UNIQUE,
    name VARCHAR(100),
    role user_role NOT NULL DEFAULT 'customer',
    language VARCHAR(5) NOT NULL DEFAULT 'en',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_role ON users(role);

-- OTP requests (for authentication)
CREATE TABLE otp_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone VARCHAR(15) NOT NULL,
    otp_hash VARCHAR(64) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    verified BOOLEAN NOT NULL DEFAULT false,
    attempts INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_otp_phone ON otp_requests(phone);
CREATE INDEX idx_otp_expires ON otp_requests(expires_at);

-- Refresh tokens
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_token ON refresh_tokens(token_hash);

-- Push notification tokens
CREATE TABLE push_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform VARCHAR(10) NOT NULL CHECK (platform IN ('ios', 'android')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, token)
);

CREATE INDEX idx_push_user ON push_tokens(user_id);

-- Categories
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    name_gu VARCHAR(100),
    slug VARCHAR(100) NOT NULL UNIQUE,
    image_url TEXT,
    display_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_categories_active ON categories(is_active, display_order);

-- Products
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
    name VARCHAR(200) NOT NULL,
    name_gu VARCHAR(200),
    description TEXT,
    description_gu TEXT,
    image_url TEXT,
    is_available BOOLEAN NOT NULL DEFAULT true,
    is_active BOOLEAN NOT NULL DEFAULT true,
    price_per_kg_paise INT NOT NULL DEFAULT 0 CHECK (price_per_kg_paise >= 0),
    display_order INT NOT NULL DEFAULT 0,
    search_vector TSVECTOR,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_available ON products(is_available, is_active);
CREATE INDEX idx_products_search ON products USING GIN(search_vector);

-- Weight options (price variants for products)
CREATE TABLE weight_options (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    weight_grams INT NOT NULL,
    weight_label VARCHAR(50) NOT NULL,
    price_paise INT NOT NULL CHECK (price_paise > 0),
    is_available BOOLEAN NOT NULL DEFAULT true,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(product_id, weight_grams)
);

CREATE INDEX idx_weight_product ON weight_options(product_id);

-- User addresses
CREATE TABLE user_addresses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    label VARCHAR(50) NOT NULL DEFAULT 'Home',
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(15) NOT NULL,
    address_line1 VARCHAR(200) NOT NULL,
    address_line2 VARCHAR(200),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL DEFAULT 'Gujarat',
    pincode VARCHAR(10) NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_addresses_user ON user_addresses(user_id);

-- Favorites (wishlist)
CREATE TABLE favorites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, product_id)
);

CREATE INDEX idx_favorites_user ON favorites(user_id);

-- Daily order counters (for order number generation)
CREATE TABLE daily_order_counters (
    date DATE PRIMARY KEY,
    counter INT NOT NULL DEFAULT 0
);

-- Orders
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_number VARCHAR(20) NOT NULL UNIQUE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status order_status NOT NULL DEFAULT 'placed',

    -- Address snapshot
    shipping_name VARCHAR(100) NOT NULL,
    shipping_phone VARCHAR(15) NOT NULL,
    shipping_address_line1 VARCHAR(200) NOT NULL,
    shipping_address_line2 VARCHAR(200),
    shipping_city VARCHAR(100) NOT NULL,
    shipping_state VARCHAR(100) NOT NULL,
    shipping_pincode VARCHAR(10) NOT NULL,

    -- Pricing (all in paise)
    subtotal_paise INT NOT NULL CHECK (subtotal_paise >= 0),
    shipping_paise INT NOT NULL DEFAULT 0 CHECK (shipping_paise >= 0),
    total_paise INT NOT NULL CHECK (total_paise >= 0),

    -- Delivery
    delivery_staff_id UUID REFERENCES users(id),
    delivery_otp_hash VARCHAR(64),
    delivery_otp_expires TIMESTAMPTZ,

    -- Notes
    customer_notes TEXT,
    admin_notes TEXT,
    cancellation_reason TEXT,
    failure_reason TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_delivery ON orders(delivery_staff_id) WHERE delivery_staff_id IS NOT NULL;
CREATE INDEX idx_orders_number ON orders(order_number);
CREATE INDEX idx_orders_created ON orders(created_at DESC);

-- Order items (line items with product snapshot)
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    weight_option_id UUID REFERENCES weight_options(id) ON DELETE SET NULL,

    -- Snapshot at order time
    product_name VARCHAR(200) NOT NULL,
    product_name_gu VARCHAR(200),
    weight_label VARCHAR(50) NOT NULL,
    weight_grams INT NOT NULL,
    unit_price_paise INT NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    total_paise INT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_order_items_order ON order_items(order_id);

-- Order status history (audit trail)
CREATE TABLE order_status_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    from_status order_status,
    to_status order_status NOT NULL,
    changed_by UUID REFERENCES users(id),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_status_history_order ON order_status_history(order_id);

-- App settings (key-value store)
CREATE TABLE app_settings (
    key VARCHAR(100) PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================
-- FUNCTIONS
-- =============================================

-- Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Generate order number (MSS-YYYYMMDD-NNN)
CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS VARCHAR(20) AS $$
DECLARE
    today DATE := CURRENT_DATE;
    counter INT;
    order_num VARCHAR(20);
BEGIN
    -- Upsert daily counter
    INSERT INTO daily_order_counters (date, counter)
    VALUES (today, 1)
    ON CONFLICT (date)
    DO UPDATE SET counter = daily_order_counters.counter + 1
    RETURNING daily_order_counters.counter INTO counter;

    -- Format: MSS-YYYYMMDD-NNN
    order_num := 'MSS-' || TO_CHAR(today, 'YYYYMMDD') || '-' || LPAD(counter::TEXT, 3, '0');

    RETURN order_num;
END;
$$ LANGUAGE plpgsql;

-- Update product search vector
CREATE OR REPLACE FUNCTION update_product_search()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', COALESCE(NEW.name, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.name_gu, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.description, '')), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Set default address (ensure only one default per user)
CREATE OR REPLACE FUNCTION ensure_single_default_address()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_default = true THEN
        UPDATE user_addresses
        SET is_default = false
        WHERE user_id = NEW.user_id AND id != NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- TRIGGERS
-- =============================================

-- Updated_at triggers
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_categories_updated_at
    BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_weight_options_updated_at
    BEFORE UPDATE ON weight_options
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_addresses_updated_at
    BEFORE UPDATE ON user_addresses
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_push_tokens_updated_at
    BEFORE UPDATE ON push_tokens
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Product search vector trigger
CREATE TRIGGER update_products_search
    BEFORE INSERT OR UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_product_search();

-- Default address trigger
CREATE TRIGGER ensure_default_address
    AFTER INSERT OR UPDATE OF is_default ON user_addresses
    FOR EACH ROW
    WHEN (NEW.is_default = true)
    EXECUTE FUNCTION ensure_single_default_address();

-- =============================================
-- INITIAL APP SETTINGS
-- =============================================

INSERT INTO app_settings (key, value, description) VALUES
    ('shipping_charge_paise', '4000', 'Shipping charge in paise (Rs 40)'),
    ('free_shipping_threshold_paise', '50000', 'Free shipping above this amount (Rs 500)'),
    ('serviceable_pincodes', '["360001", "360002", "360003", "360004", "360005"]', 'List of serviceable PIN codes'),
    ('min_order_paise', '10000', 'Minimum order amount in paise (Rs 100)'),
    ('otp_expiry_seconds', '300', 'OTP validity in seconds (5 minutes)'),
    ('max_otp_attempts', '3', 'Maximum OTP verification attempts'),
    ('delivery_otp_expiry_hours', '24', 'Delivery OTP validity in hours')
ON CONFLICT (key) DO NOTHING;
