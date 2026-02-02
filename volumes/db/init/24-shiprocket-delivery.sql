-- =============================================
-- 24-shiprocket-delivery.sql
-- Add Shiprocket courier delivery alongside in-house delivery.
-- =============================================

BEGIN;

-- 1. delivery_method enum + column on orders
CREATE TYPE delivery_method AS ENUM ('in_house', 'shiprocket');

ALTER TABLE orders
  ADD COLUMN delivery_method delivery_method NOT NULL DEFAULT 'in_house';

CREATE INDEX idx_orders_delivery_method ON orders (delivery_method);

-- 2. shiprocket_shipments table
CREATE TABLE shiprocket_shipments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    sr_order_id BIGINT,
    sr_shipment_id BIGINT,
    awb_code VARCHAR(50),
    courier_id INTEGER,
    courier_name VARCHAR(100),
    label_url TEXT,
    tracking_url TEXT,
    length_cm NUMERIC(6,2),
    breadth_cm NUMERIC(6,2),
    height_cm NUMERIC(6,2),
    weight_kg NUMERIC(6,2),
    sr_status VARCHAR(50),
    sr_status_code INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_shiprocket_shipments_order ON shiprocket_shipments (order_id);
CREATE INDEX idx_shiprocket_shipments_awb ON shiprocket_shipments (awb_code) WHERE awb_code IS NOT NULL;
CREATE INDEX idx_shiprocket_shipments_sr_order ON shiprocket_shipments (sr_order_id) WHERE sr_order_id IS NOT NULL;
CREATE INDEX idx_shiprocket_shipments_sr_shipment ON shiprocket_shipments (sr_shipment_id) WHERE sr_shipment_id IS NOT NULL;

-- Auto-update updated_at
CREATE TRIGGER set_shiprocket_shipments_updated_at
    BEFORE UPDATE ON shiprocket_shipments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- 3. shiprocket_webhooks audit table
CREATE TABLE shiprocket_webhooks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payload JSONB NOT NULL,
    event_status VARCHAR(50),
    awb_code VARCHAR(50),
    sr_shipment_id BIGINT,
    processed BOOLEAN NOT NULL DEFAULT false,
    error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

CREATE INDEX idx_shiprocket_webhooks_created ON shiprocket_webhooks (created_at);
CREATE INDEX idx_shiprocket_webhooks_awb ON shiprocket_webhooks (awb_code) WHERE awb_code IS NOT NULL;

-- 4. RLS policies

ALTER TABLE shiprocket_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE shiprocket_webhooks ENABLE ROW LEVEL SECURITY;

-- Admin: full access to shipments
CREATE POLICY admin_all_shiprocket_shipments ON shiprocket_shipments
    FOR ALL TO authenticated
    USING (auth.role() = 'admin')
    WITH CHECK (auth.role() = 'admin');

-- Customer: read own shipment data
CREATE POLICY customer_read_own_shipment ON shiprocket_shipments
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = shiprocket_shipments.order_id
              AND orders.user_id = auth.uid()
        )
    );

-- service_role: full access (for edge functions / webhooks)
CREATE POLICY service_role_shiprocket_shipments ON shiprocket_shipments
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY service_role_shiprocket_webhooks ON shiprocket_webhooks
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- 5. GRANTs
GRANT SELECT, INSERT, UPDATE ON shiprocket_shipments TO authenticated;
GRANT ALL ON shiprocket_shipments TO service_role;
GRANT ALL ON shiprocket_webhooks TO service_role;

-- 6. Update update_order_status_atomic to handle delivery_method
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
        delivery_otp_hash = COALESCE(p_update_data->>'delivery_otp_hash', delivery_otp_hash),
        delivery_otp_expires = COALESCE((p_update_data->>'delivery_otp_expires')::TIMESTAMPTZ, delivery_otp_expires),
        cancellation_reason = COALESCE(p_update_data->>'cancellation_reason', cancellation_reason),
        failure_reason = COALESCE(p_update_data->>'failure_reason', failure_reason),
        delivery_method = COALESCE((p_update_data->>'delivery_method')::delivery_method, delivery_method)
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

GRANT EXECUTE ON FUNCTION update_order_status_atomic TO service_role;

-- 7. Insert shiprocket_pickup_postcode into app_settings
INSERT INTO app_settings (key, value, description)
VALUES ('shiprocket_pickup_postcode', '"000000"', 'Pickup location postcode for Shiprocket serviceability checks')
ON CONFLICT (key) DO NOTHING;

-- 8. Update cleanup_expired_data to prune webhook logs >90 days
CREATE OR REPLACE FUNCTION public.cleanup_expired_data()
RETURNS JSONB AS $$
DECLARE
    v_otp_deleted INTEGER;
    v_tokens_deleted INTEGER;
    v_phone_rate_deleted INTEGER;
    v_ip_rate_deleted INTEGER;
    v_sr_webhooks_deleted INTEGER;
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

    DELETE FROM shiprocket_webhooks
    WHERE created_at < NOW() - INTERVAL '90 days';
    GET DIAGNOSTICS v_sr_webhooks_deleted = ROW_COUNT;

    RETURN jsonb_build_object(
        'otp_requests_deleted', v_otp_deleted,
        'refresh_tokens_deleted', v_tokens_deleted,
        'phone_rate_limits_deleted', v_phone_rate_deleted,
        'ip_rate_limits_deleted', v_ip_rate_deleted,
        'shiprocket_webhooks_deleted', v_sr_webhooks_deleted,
        'cleaned_at', NOW()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
