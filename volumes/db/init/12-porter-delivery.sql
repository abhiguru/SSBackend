-- =============================================
-- Masala Spice Shop - Porter Delivery Support
-- =============================================
-- Third-party delivery integration via Porter
-- Supports both in-house and Porter delivery methods

-- =============================================
-- DELIVERY TYPE ENUM
-- =============================================

CREATE TYPE delivery_type AS ENUM ('in_house', 'porter');

-- =============================================
-- ADD DELIVERY TYPE TO ORDERS
-- =============================================

ALTER TABLE orders ADD COLUMN delivery_type delivery_type NOT NULL DEFAULT 'in_house';

-- =============================================
-- PORTER DELIVERIES TABLE
-- =============================================
-- Stores Porter-specific delivery data separate from orders

CREATE TABLE porter_deliveries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,

    -- Porter identifiers
    porter_order_id VARCHAR(100),
    crn VARCHAR(100),                    -- Cancellation Reference Number
    tracking_url TEXT,

    -- Driver info (populated from webhook)
    driver_name VARCHAR(100),
    driver_phone VARCHAR(20),
    vehicle_number VARCHAR(20),

    -- Fare (in paise)
    quoted_fare_paise INT,
    final_fare_paise INT,

    -- Coordinates
    pickup_lat DECIMAL(10, 8),
    pickup_lng DECIMAL(11, 8),
    drop_lat DECIMAL(10, 8),
    drop_lng DECIMAL(11, 8),

    -- Porter status
    -- Values: pending, live, allocated, reached_for_pickup, picked_up,
    --         reached_for_drop, ended, cancelled
    porter_status VARCHAR(50),

    -- Timestamps
    estimated_pickup_time TIMESTAMPTZ,
    actual_pickup_time TIMESTAMPTZ,
    estimated_delivery_time TIMESTAMPTZ,
    actual_delivery_time TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================
-- PORTER WEBHOOKS AUDIT LOG
-- =============================================
-- Stores all incoming webhook events for debugging/auditing

CREATE TABLE porter_webhooks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES orders(id),
    porter_order_id VARCHAR(100),
    event_type VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL,
    processed_at TIMESTAMPTZ,
    error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================
-- INDEXES
-- =============================================

CREATE INDEX idx_porter_deliveries_order ON porter_deliveries(order_id);
CREATE INDEX idx_porter_deliveries_porter_order ON porter_deliveries(porter_order_id);
CREATE INDEX idx_porter_deliveries_status ON porter_deliveries(porter_status);
CREATE INDEX idx_porter_webhooks_order ON porter_webhooks(order_id);
CREATE INDEX idx_porter_webhooks_porter_order ON porter_webhooks(porter_order_id);
CREATE INDEX idx_porter_webhooks_created ON porter_webhooks(created_at DESC);
CREATE INDEX idx_orders_delivery_type ON orders(delivery_type);

-- =============================================
-- UPDATED_AT TRIGGER
-- =============================================

CREATE TRIGGER update_porter_deliveries_updated_at
    BEFORE UPDATE ON porter_deliveries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================
-- ROW LEVEL SECURITY
-- =============================================

ALTER TABLE porter_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE porter_webhooks ENABLE ROW LEVEL SECURITY;

-- Admin can do everything with porter_deliveries
CREATE POLICY "porter_deliveries_admin_all" ON porter_deliveries
    FOR ALL TO authenticated
    USING ((SELECT auth.is_admin()));

-- Customers can read their own order's porter delivery info
CREATE POLICY "porter_deliveries_customer_read" ON porter_deliveries
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = porter_deliveries.order_id
            AND orders.user_id = auth.uid()
        )
    );

-- Admin can read webhooks
CREATE POLICY "porter_webhooks_admin_read" ON porter_webhooks
    FOR SELECT TO authenticated
    USING ((SELECT auth.is_admin()));

-- Admin can insert webhooks (for manual debugging)
CREATE POLICY "porter_webhooks_admin_insert" ON porter_webhooks
    FOR INSERT TO authenticated
    WITH CHECK ((SELECT auth.is_admin()));

-- =============================================
-- TABLE GRANTS
-- =============================================

GRANT SELECT ON porter_deliveries TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON porter_deliveries TO authenticated;
GRANT SELECT, INSERT ON porter_webhooks TO authenticated;

-- =============================================
-- APP SETTINGS FOR STORE PICKUP LOCATION
-- =============================================

INSERT INTO app_settings (key, value, description) VALUES
    ('porter_pickup_lat', '"23.0339"', 'Store latitude for Porter pickup'),
    ('porter_pickup_lng', '"72.5614"', 'Store longitude for Porter pickup'),
    ('porter_pickup_address', '"2088, Usmanpura Gam, Nr. Kadava Patidar Vadi, Ashram Road, Ahmedabad 380013"', 'Store address for Porter'),
    ('porter_pickup_name', '"Masala Spice Shop"', 'Store name for Porter pickup'),
    ('porter_pickup_phone', '"+919876543210"', 'Store phone for Porter pickup (update this)')
ON CONFLICT (key) DO NOTHING;

-- =============================================
-- HELPER FUNCTION: Get Store Pickup Coordinates
-- =============================================

CREATE OR REPLACE FUNCTION get_store_pickup_coords()
RETURNS TABLE(lat DECIMAL, lng DECIMAL, address TEXT, name TEXT, phone TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT (value)::DECIMAL FROM app_settings WHERE key = 'porter_pickup_lat') AS lat,
        (SELECT (value)::DECIMAL FROM app_settings WHERE key = 'porter_pickup_lng') AS lng,
        (SELECT value::TEXT FROM app_settings WHERE key = 'porter_pickup_address') AS address,
        (SELECT value::TEXT FROM app_settings WHERE key = 'porter_pickup_name') AS name,
        (SELECT value::TEXT FROM app_settings WHERE key = 'porter_pickup_phone') AS phone;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_store_pickup_coords() TO authenticated;
