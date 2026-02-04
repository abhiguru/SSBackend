-- =============================================
-- Masala Spice Shop - Delivery Tracking
-- Migration 37: Real-time delivery location tracking
-- =============================================

-- =============================================
-- Table: delivery_staff_locations
-- =============================================
-- Stores the current location of delivery staff.
-- Uses UPSERT pattern - one row per staff member, updated frequently.

CREATE TABLE IF NOT EXISTS delivery_staff_locations (
    delivery_staff_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    lat DECIMAL(10,8) NOT NULL,
    lng DECIMAL(11,8) NOT NULL,
    accuracy_meters NUMERIC(7,2),
    recorded_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast lookups by delivery staff
CREATE INDEX IF NOT EXISTS idx_delivery_staff_locations_updated
    ON delivery_staff_locations(updated_at);

-- Comment on table
COMMENT ON TABLE delivery_staff_locations IS 'Current location of delivery staff for real-time tracking';
COMMENT ON COLUMN delivery_staff_locations.recorded_at IS 'Client-provided timestamp when GPS was captured';
COMMENT ON COLUMN delivery_staff_locations.updated_at IS 'Server timestamp when record was saved';

-- =============================================
-- Enable RLS
-- =============================================

ALTER TABLE delivery_staff_locations ENABLE ROW LEVEL SECURITY;

-- =============================================
-- RLS Policies
-- =============================================

-- Delivery staff can manage (INSERT/UPDATE/DELETE) their own location
CREATE POLICY "staff_manage_own_location" ON delivery_staff_locations
    FOR ALL TO authenticated
    USING ((SELECT auth.is_delivery_staff()) AND delivery_staff_id = (SELECT auth.uid()))
    WITH CHECK ((SELECT auth.is_delivery_staff()) AND delivery_staff_id = (SELECT auth.uid()));

-- Admin can read all locations
CREATE POLICY "admin_read_locations" ON delivery_staff_locations
    FOR SELECT TO authenticated
    USING ((SELECT auth.is_admin()));

-- =============================================
-- Helper Function: get_delivery_tracking
-- =============================================
-- Returns delivery staff location for a customer's order.
-- Called via RPC from the delivery-tracking edge function.
-- SECURITY DEFINER allows bypassing RLS since we verify ownership in the function.

CREATE OR REPLACE FUNCTION get_delivery_tracking(p_order_id UUID, p_user_id UUID)
RETURNS TABLE (
    staff_lat DECIMAL(10,8),
    staff_lng DECIMAL(11,8),
    staff_name VARCHAR(100),
    staff_phone VARCHAR(15),
    last_updated TIMESTAMPTZ
) AS $$
    SELECT
        dsl.lat,
        dsl.lng,
        u.name,
        u.phone,
        dsl.updated_at
    FROM orders o
    JOIN users u ON u.id = o.delivery_staff_id
    LEFT JOIN delivery_staff_locations dsl ON dsl.delivery_staff_id = o.delivery_staff_id
    WHERE o.id = p_order_id
      AND o.user_id = p_user_id
      AND o.status = 'out_for_delivery'
      AND o.delivery_method = 'in_house';
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION get_delivery_tracking IS 'Get delivery staff location for customer order tracking';

-- =============================================
-- Grant Permissions
-- =============================================

GRANT SELECT, INSERT, UPDATE, DELETE ON delivery_staff_locations TO authenticated;
GRANT EXECUTE ON FUNCTION get_delivery_tracking TO authenticated;
