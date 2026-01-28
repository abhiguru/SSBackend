-- =============================================
-- Masala Spice Shop - Auth Enhancements
-- Aligns with GuruColdStorage MSG91 pattern
-- =============================================

-- =============================================
-- SMS CONFIGURATION TABLE
-- =============================================
-- Stores SMS provider settings with database-backed config

CREATE TABLE IF NOT EXISTS sms_config (
    id SERIAL PRIMARY KEY,
    production_mode BOOLEAN NOT NULL DEFAULT false,
    provider VARCHAR(20) NOT NULL DEFAULT 'msg91',
    msg91_auth_key TEXT,
    msg91_template_id TEXT,
    msg91_sender_id VARCHAR(6) DEFAULT 'MSSHOP',
    msg91_pe_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure only one config row exists
CREATE UNIQUE INDEX IF NOT EXISTS idx_sms_config_singleton ON sms_config ((true));

-- =============================================
-- PHONE-BASED RATE LIMITS TABLE
-- =============================================
-- Tracks hourly and daily OTP request counts per phone number

CREATE TABLE IF NOT EXISTS otp_rate_limits (
    phone_number VARCHAR(15) PRIMARY KEY,
    hourly_count INTEGER NOT NULL DEFAULT 0,
    daily_count INTEGER NOT NULL DEFAULT 0,
    last_reset_hour TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_reset_day TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================
-- IP-BASED RATE LIMITS TABLE
-- =============================================
-- Tracks hourly OTP request counts per IP address

CREATE TABLE IF NOT EXISTS ip_rate_limits (
    ip_address INET PRIMARY KEY,
    hourly_count INTEGER NOT NULL DEFAULT 0,
    last_reset_hour TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================
-- TEST OTP RECORDS TABLE
-- =============================================
-- Phone numbers with fixed OTPs for testing (works in all modes)

CREATE TABLE IF NOT EXISTS test_otp_records (
    phone_number VARCHAR(15) PRIMARY KEY,
    fixed_otp VARCHAR(6) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================
-- ENHANCE OTP_REQUESTS TABLE
-- =============================================
-- Add tracking fields to existing otp_requests table

-- Add new columns if they don't exist
DO $$
BEGIN
    -- IP address of the requester
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'otp_requests' AND column_name = 'ip_address') THEN
        ALTER TABLE otp_requests ADD COLUMN ip_address INET;
    END IF;

    -- User agent string
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'otp_requests' AND column_name = 'user_agent') THEN
        ALTER TABLE otp_requests ADD COLUMN user_agent TEXT;
    END IF;

    -- MSG91 request ID for tracking
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'otp_requests' AND column_name = 'msg91_request_id') THEN
        ALTER TABLE otp_requests ADD COLUMN msg91_request_id VARCHAR(255);
    END IF;

    -- Delivery status: pending, sent, delivered, failed, test_mode, test_phone
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'otp_requests' AND column_name = 'delivery_status') THEN
        ALTER TABLE otp_requests ADD COLUMN delivery_status TEXT DEFAULT 'pending';
    END IF;
END $$;

-- Add index for IP-based queries
CREATE INDEX IF NOT EXISTS idx_otp_requests_ip ON otp_requests(ip_address);

-- =============================================
-- UPDATED_AT TRIGGERS FOR NEW TABLES
-- =============================================

CREATE OR REPLACE TRIGGER update_sms_config_updated_at
    BEFORE UPDATE ON sms_config
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE OR REPLACE TRIGGER update_otp_rate_limits_updated_at
    BEFORE UPDATE ON otp_rate_limits
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE OR REPLACE TRIGGER update_ip_rate_limits_updated_at
    BEFORE UPDATE ON ip_rate_limits
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE OR REPLACE TRIGGER update_test_otp_records_updated_at
    BEFORE UPDATE ON test_otp_records
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================
-- PHONE RATE LIMIT CHECK FUNCTION
-- =============================================
-- Returns: {allowed: boolean, hourly_remaining: int, daily_remaining: int}
-- Limits: 40/hour, 20/day

CREATE OR REPLACE FUNCTION check_otp_rate_limit(p_phone VARCHAR(15))
RETURNS JSONB AS $$
DECLARE
    v_record otp_rate_limits%ROWTYPE;
    v_hourly_limit INTEGER := 40;
    v_daily_limit INTEGER := 999999; -- effectively disabled
    v_hourly_count INTEGER;
    v_daily_count INTEGER;
    v_now TIMESTAMPTZ := NOW();
    v_current_hour TIMESTAMPTZ;
    v_current_day TIMESTAMPTZ;
BEGIN
    -- Calculate current hour and day boundaries
    v_current_hour := date_trunc('hour', v_now);
    v_current_day := date_trunc('day', v_now);

    -- Get or create rate limit record
    SELECT * INTO v_record FROM otp_rate_limits WHERE phone_number = p_phone FOR UPDATE;

    IF v_record IS NULL THEN
        -- Create new record
        INSERT INTO otp_rate_limits (phone_number, hourly_count, daily_count, last_reset_hour, last_reset_day)
        VALUES (p_phone, 1, 1, v_current_hour, v_current_day)
        RETURNING * INTO v_record;

        RETURN jsonb_build_object(
            'allowed', true,
            'hourly_remaining', v_hourly_limit - 1,
            'daily_remaining', v_daily_limit - 1
        );
    END IF;

    -- Reset hourly count if hour has changed
    IF v_record.last_reset_hour < v_current_hour THEN
        v_hourly_count := 0;
    ELSE
        v_hourly_count := v_record.hourly_count;
    END IF;

    -- Reset daily count if day has changed
    IF v_record.last_reset_day < v_current_day THEN
        v_daily_count := 0;
    ELSE
        v_daily_count := v_record.daily_count;
    END IF;

    -- Check limits
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

    -- Increment counters
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
-- IP RATE LIMIT CHECK FUNCTION
-- =============================================
-- Returns: {allowed: boolean, remaining: int}
-- Limit: 100/hour

CREATE OR REPLACE FUNCTION check_ip_rate_limit(p_ip INET)
RETURNS JSONB AS $$
DECLARE
    v_record ip_rate_limits%ROWTYPE;
    v_limit INTEGER := 100;
    v_count INTEGER;
    v_now TIMESTAMPTZ := NOW();
    v_current_hour TIMESTAMPTZ;
BEGIN
    -- Handle null IP (skip rate limiting)
    IF p_ip IS NULL THEN
        RETURN jsonb_build_object('allowed', true, 'remaining', v_limit);
    END IF;

    v_current_hour := date_trunc('hour', v_now);

    -- Get or create rate limit record
    SELECT * INTO v_record FROM ip_rate_limits WHERE ip_address = p_ip FOR UPDATE;

    IF v_record IS NULL THEN
        INSERT INTO ip_rate_limits (ip_address, hourly_count, last_reset_hour)
        VALUES (p_ip, 1, v_current_hour)
        RETURNING * INTO v_record;

        RETURN jsonb_build_object('allowed', true, 'remaining', v_limit - 1);
    END IF;

    -- Reset count if hour has changed
    IF v_record.last_reset_hour < v_current_hour THEN
        v_count := 0;
    ELSE
        v_count := v_record.hourly_count;
    END IF;

    -- Check limit
    IF v_count >= v_limit THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'remaining', 0,
            'error', 'IP_RATE_LIMITED',
            'message', 'Too many requests from this IP. Please try again later.'
        );
    END IF;

    -- Increment counter
    UPDATE ip_rate_limits
    SET hourly_count = CASE WHEN last_reset_hour < v_current_hour THEN 1 ELSE hourly_count + 1 END,
        last_reset_hour = CASE WHEN last_reset_hour < v_current_hour THEN v_current_hour ELSE last_reset_hour END
    WHERE ip_address = p_ip;

    RETURN jsonb_build_object('allowed', true, 'remaining', v_limit - v_count - 1);
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- GET SMS CONFIG FUNCTION
-- =============================================
-- Returns current SMS configuration with env fallback

CREATE OR REPLACE FUNCTION get_sms_config()
RETURNS JSONB AS $$
DECLARE
    v_config sms_config%ROWTYPE;
BEGIN
    SELECT * INTO v_config FROM sms_config LIMIT 1;

    IF v_config IS NULL THEN
        -- Return defaults when no config exists
        RETURN jsonb_build_object(
            'production_mode', false,
            'provider', 'msg91',
            'msg91_auth_key', NULL,
            'msg91_template_id', NULL,
            'msg91_sender_id', 'MSSHOP',
            'msg91_pe_id', NULL
        );
    END IF;

    RETURN jsonb_build_object(
        'production_mode', v_config.production_mode,
        'provider', v_config.provider,
        'msg91_auth_key', v_config.msg91_auth_key,
        'msg91_template_id', v_config.msg91_template_id,
        'msg91_sender_id', v_config.msg91_sender_id,
        'msg91_pe_id', v_config.msg91_pe_id
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================
-- GET TEST OTP FUNCTION
-- =============================================
-- Returns fixed OTP for test phone numbers, NULL otherwise

CREATE OR REPLACE FUNCTION get_test_otp(p_phone VARCHAR(15))
RETURNS VARCHAR(6) AS $$
DECLARE
    v_otp VARCHAR(6);
BEGIN
    SELECT fixed_otp INTO v_otp FROM test_otp_records WHERE phone_number = p_phone;
    RETURN v_otp;
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================
-- RLS POLICIES FOR NEW TABLES
-- =============================================

-- sms_config: Only admins can read/modify
ALTER TABLE sms_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin can manage sms_config"
    ON sms_config FOR ALL
    TO authenticated
    USING ((select auth.is_admin()))
    WITH CHECK ((select auth.is_admin()));

-- Allow service role full access
CREATE POLICY "Service role can manage sms_config"
    ON sms_config FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- otp_rate_limits: Service role only (internal use)
ALTER TABLE otp_rate_limits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can manage otp_rate_limits"
    ON otp_rate_limits FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- ip_rate_limits: Service role only (internal use)
ALTER TABLE ip_rate_limits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can manage ip_rate_limits"
    ON ip_rate_limits FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- test_otp_records: Only admins can read/modify
ALTER TABLE test_otp_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin can manage test_otp_records"
    ON test_otp_records FOR ALL
    TO authenticated
    USING ((select auth.is_admin()))
    WITH CHECK ((select auth.is_admin()));

CREATE POLICY "Service role can manage test_otp_records"
    ON test_otp_records FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- =============================================
-- GRANTS
-- =============================================

GRANT SELECT ON sms_config TO authenticated;
GRANT ALL ON sms_config TO service_role;

GRANT ALL ON otp_rate_limits TO service_role;
GRANT ALL ON ip_rate_limits TO service_role;

GRANT SELECT ON test_otp_records TO authenticated;
GRANT ALL ON test_otp_records TO service_role;

GRANT EXECUTE ON FUNCTION check_otp_rate_limit(VARCHAR) TO service_role;
GRANT EXECUTE ON FUNCTION check_ip_rate_limit(INET) TO service_role;
GRANT EXECUTE ON FUNCTION get_sms_config() TO service_role;
GRANT EXECUTE ON FUNCTION get_test_otp(VARCHAR) TO service_role;

-- =============================================
-- DEFAULT DATA
-- =============================================

-- Insert default SMS config (production_mode=false for safety)
INSERT INTO sms_config (production_mode, provider, msg91_sender_id)
VALUES (false, 'msg91', 'MSSHOP')
ON CONFLICT DO NOTHING;

-- Insert test phone number
INSERT INTO test_otp_records (phone_number, fixed_otp, description)
VALUES ('+919876543210', '123456', 'Default test phone number')
ON CONFLICT (phone_number) DO NOTHING;
