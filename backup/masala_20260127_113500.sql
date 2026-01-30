--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8
-- Dumped by pg_dump version 15.8

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

DROP POLICY IF EXISTS weight_options_public_read ON public.weight_options;
DROP POLICY IF EXISTS weight_options_admin_update ON public.weight_options;
DROP POLICY IF EXISTS weight_options_admin_read ON public.weight_options;
DROP POLICY IF EXISTS weight_options_admin_insert ON public.weight_options;
DROP POLICY IF EXISTS weight_options_admin_delete ON public.weight_options;
DROP POLICY IF EXISTS users_update_own ON public.users;
DROP POLICY IF EXISTS users_superadmin_insert ON public.users;
DROP POLICY IF EXISTS users_read_own ON public.users;
DROP POLICY IF EXISTS users_admin_update ON public.users;
DROP POLICY IF EXISTS users_admin_read ON public.users;
DROP POLICY IF EXISTS status_history_read_own ON public.order_status_history;
DROP POLICY IF EXISTS status_history_admin_read ON public.order_status_history;
DROP POLICY IF EXISTS status_history_admin_insert ON public.order_status_history;
DROP POLICY IF EXISTS settings_superadmin_insert ON public.app_settings;
DROP POLICY IF EXISTS settings_public_read ON public.app_settings;
DROP POLICY IF EXISTS settings_admin_update ON public.app_settings;
DROP POLICY IF EXISTS push_update_own ON public.push_tokens;
DROP POLICY IF EXISTS push_read_own ON public.push_tokens;
DROP POLICY IF EXISTS push_insert_own ON public.push_tokens;
DROP POLICY IF EXISTS push_delete_own ON public.push_tokens;
DROP POLICY IF EXISTS push_admin_read ON public.push_tokens;
DROP POLICY IF EXISTS products_public_read ON public.products;
DROP POLICY IF EXISTS products_admin_update ON public.products;
DROP POLICY IF EXISTS products_admin_read ON public.products;
DROP POLICY IF EXISTS products_admin_insert ON public.products;
DROP POLICY IF EXISTS products_admin_delete ON public.products;
DROP POLICY IF EXISTS orders_read_own ON public.orders;
DROP POLICY IF EXISTS orders_delivery_update ON public.orders;
DROP POLICY IF EXISTS orders_delivery_read ON public.orders;
DROP POLICY IF EXISTS orders_admin_update ON public.orders;
DROP POLICY IF EXISTS orders_admin_read ON public.orders;
DROP POLICY IF EXISTS order_items_read_own ON public.order_items;
DROP POLICY IF EXISTS order_items_delivery_read ON public.order_items;
DROP POLICY IF EXISTS order_items_admin_read ON public.order_items;
DROP POLICY IF EXISTS favorites_read_own ON public.favorites;
DROP POLICY IF EXISTS favorites_insert_own ON public.favorites;
DROP POLICY IF EXISTS favorites_delete_own ON public.favorites;
DROP POLICY IF EXISTS categories_public_read ON public.categories;
DROP POLICY IF EXISTS categories_admin_update ON public.categories;
DROP POLICY IF EXISTS categories_admin_read ON public.categories;
DROP POLICY IF EXISTS categories_admin_insert ON public.categories;
DROP POLICY IF EXISTS categories_admin_delete ON public.categories;
DROP POLICY IF EXISTS addresses_update_own ON public.user_addresses;
DROP POLICY IF EXISTS addresses_read_own ON public.user_addresses;
DROP POLICY IF EXISTS addresses_insert_own ON public.user_addresses;
DROP POLICY IF EXISTS addresses_delete_own ON public.user_addresses;
DROP POLICY IF EXISTS addresses_admin_read ON public.user_addresses;
DROP POLICY IF EXISTS "Service role can manage test_otp_records" ON public.test_otp_records;
DROP POLICY IF EXISTS "Service role can manage sms_config" ON public.sms_config;
DROP POLICY IF EXISTS "Service role can manage otp_rate_limits" ON public.otp_rate_limits;
DROP POLICY IF EXISTS "Service role can manage ip_rate_limits" ON public.ip_rate_limits;
DROP POLICY IF EXISTS "Admin can manage test_otp_records" ON public.test_otp_records;
DROP POLICY IF EXISTS "Admin can manage sms_config" ON public.sms_config;
ALTER TABLE IF EXISTS ONLY storage.s3_multipart_uploads_parts DROP CONSTRAINT IF EXISTS s3_multipart_uploads_parts_upload_id_fkey;
ALTER TABLE IF EXISTS ONLY storage.s3_multipart_uploads_parts DROP CONSTRAINT IF EXISTS s3_multipart_uploads_parts_bucket_id_fkey;
ALTER TABLE IF EXISTS ONLY storage.s3_multipart_uploads DROP CONSTRAINT IF EXISTS s3_multipart_uploads_bucket_id_fkey;
ALTER TABLE IF EXISTS ONLY storage.objects DROP CONSTRAINT IF EXISTS "objects_bucketId_fkey";
ALTER TABLE IF EXISTS ONLY public.weight_options DROP CONSTRAINT IF EXISTS weight_options_product_id_fkey;
ALTER TABLE IF EXISTS ONLY public.user_addresses DROP CONSTRAINT IF EXISTS user_addresses_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.refresh_tokens DROP CONSTRAINT IF EXISTS refresh_tokens_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.push_tokens DROP CONSTRAINT IF EXISTS push_tokens_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.products DROP CONSTRAINT IF EXISTS products_category_id_fkey;
ALTER TABLE IF EXISTS ONLY public.orders DROP CONSTRAINT IF EXISTS orders_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.orders DROP CONSTRAINT IF EXISTS orders_delivery_staff_id_fkey;
ALTER TABLE IF EXISTS ONLY public.order_status_history DROP CONSTRAINT IF EXISTS order_status_history_order_id_fkey;
ALTER TABLE IF EXISTS ONLY public.order_status_history DROP CONSTRAINT IF EXISTS order_status_history_changed_by_fkey;
ALTER TABLE IF EXISTS ONLY public.order_items DROP CONSTRAINT IF EXISTS order_items_weight_option_id_fkey;
ALTER TABLE IF EXISTS ONLY public.order_items DROP CONSTRAINT IF EXISTS order_items_product_id_fkey;
ALTER TABLE IF EXISTS ONLY public.order_items DROP CONSTRAINT IF EXISTS order_items_order_id_fkey;
ALTER TABLE IF EXISTS ONLY public.favorites DROP CONSTRAINT IF EXISTS favorites_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.favorites DROP CONSTRAINT IF EXISTS favorites_product_id_fkey;
ALTER TABLE IF EXISTS ONLY _supavisor.users DROP CONSTRAINT IF EXISTS users_tenant_external_id_fkey;
ALTER TABLE IF EXISTS ONLY _supavisor.cluster_tenants DROP CONSTRAINT IF EXISTS cluster_tenants_tenant_external_id_fkey;
ALTER TABLE IF EXISTS ONLY _supavisor.cluster_tenants DROP CONSTRAINT IF EXISTS cluster_tenants_cluster_alias_fkey;
DROP TRIGGER IF EXISTS update_objects_updated_at ON storage.objects;
DROP TRIGGER IF EXISTS update_weight_options_updated_at ON public.weight_options;
DROP TRIGGER IF EXISTS update_users_updated_at ON public.users;
DROP TRIGGER IF EXISTS update_test_otp_records_updated_at ON public.test_otp_records;
DROP TRIGGER IF EXISTS update_sms_config_updated_at ON public.sms_config;
DROP TRIGGER IF EXISTS update_push_tokens_updated_at ON public.push_tokens;
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
DROP TRIGGER IF EXISTS update_products_search ON public.products;
DROP TRIGGER IF EXISTS update_otp_rate_limits_updated_at ON public.otp_rate_limits;
DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
DROP TRIGGER IF EXISTS update_ip_rate_limits_updated_at ON public.ip_rate_limits;
DROP TRIGGER IF EXISTS update_categories_updated_at ON public.categories;
DROP TRIGGER IF EXISTS update_app_settings_updated_at ON public.app_settings;
DROP TRIGGER IF EXISTS update_addresses_updated_at ON public.user_addresses;
DROP TRIGGER IF EXISTS ensure_default_address ON public.user_addresses;
DROP INDEX IF EXISTS storage.name_prefix_search;
DROP INDEX IF EXISTS storage.idx_objects_bucket_id_name;
DROP INDEX IF EXISTS storage.idx_multipart_uploads_list;
DROP INDEX IF EXISTS storage.bucketid_objname;
DROP INDEX IF EXISTS storage.bname;
DROP INDEX IF EXISTS public.idx_weight_product;
DROP INDEX IF EXISTS public.idx_users_role;
DROP INDEX IF EXISTS public.idx_users_phone;
DROP INDEX IF EXISTS public.idx_status_history_order;
DROP INDEX IF EXISTS public.idx_sms_config_singleton;
DROP INDEX IF EXISTS public.idx_refresh_user;
DROP INDEX IF EXISTS public.idx_refresh_token;
DROP INDEX IF EXISTS public.idx_push_user;
DROP INDEX IF EXISTS public.idx_products_search;
DROP INDEX IF EXISTS public.idx_products_category;
DROP INDEX IF EXISTS public.idx_products_available;
DROP INDEX IF EXISTS public.idx_otp_requests_ip;
DROP INDEX IF EXISTS public.idx_otp_phone;
DROP INDEX IF EXISTS public.idx_otp_expires;
DROP INDEX IF EXISTS public.idx_orders_user;
DROP INDEX IF EXISTS public.idx_orders_status;
DROP INDEX IF EXISTS public.idx_orders_number;
DROP INDEX IF EXISTS public.idx_orders_delivery;
DROP INDEX IF EXISTS public.idx_orders_created;
DROP INDEX IF EXISTS public.idx_order_items_order;
DROP INDEX IF EXISTS public.idx_favorites_user;
DROP INDEX IF EXISTS public.idx_categories_active;
DROP INDEX IF EXISTS public.idx_addresses_user;
DROP INDEX IF EXISTS _supavisor.users_db_user_alias_tenant_external_id_mode_type_index;
DROP INDEX IF EXISTS _supavisor.tenants_external_id_index;
DROP INDEX IF EXISTS _supavisor.clusters_alias_index;
DROP INDEX IF EXISTS _supavisor.cluster_tenants_tenant_external_id_index;
ALTER TABLE IF EXISTS ONLY storage.s3_multipart_uploads DROP CONSTRAINT IF EXISTS s3_multipart_uploads_pkey;
ALTER TABLE IF EXISTS ONLY storage.s3_multipart_uploads_parts DROP CONSTRAINT IF EXISTS s3_multipart_uploads_parts_pkey;
ALTER TABLE IF EXISTS ONLY storage.objects DROP CONSTRAINT IF EXISTS objects_pkey;
ALTER TABLE IF EXISTS ONLY storage.migrations DROP CONSTRAINT IF EXISTS migrations_pkey;
ALTER TABLE IF EXISTS ONLY storage.migrations DROP CONSTRAINT IF EXISTS migrations_name_key;
ALTER TABLE IF EXISTS ONLY storage.buckets DROP CONSTRAINT IF EXISTS buckets_pkey;
ALTER TABLE IF EXISTS ONLY public.weight_options DROP CONSTRAINT IF EXISTS weight_options_product_id_weight_grams_key;
ALTER TABLE IF EXISTS ONLY public.weight_options DROP CONSTRAINT IF EXISTS weight_options_pkey;
ALTER TABLE IF EXISTS ONLY public.users DROP CONSTRAINT IF EXISTS users_pkey;
ALTER TABLE IF EXISTS ONLY public.users DROP CONSTRAINT IF EXISTS users_phone_key;
ALTER TABLE IF EXISTS ONLY public.user_addresses DROP CONSTRAINT IF EXISTS user_addresses_pkey;
ALTER TABLE IF EXISTS ONLY public.test_otp_records DROP CONSTRAINT IF EXISTS test_otp_records_pkey;
ALTER TABLE IF EXISTS ONLY public.sms_config DROP CONSTRAINT IF EXISTS sms_config_pkey;
ALTER TABLE IF EXISTS ONLY public.refresh_tokens DROP CONSTRAINT IF EXISTS refresh_tokens_token_hash_key;
ALTER TABLE IF EXISTS ONLY public.refresh_tokens DROP CONSTRAINT IF EXISTS refresh_tokens_pkey;
ALTER TABLE IF EXISTS ONLY public.push_tokens DROP CONSTRAINT IF EXISTS push_tokens_user_id_token_key;
ALTER TABLE IF EXISTS ONLY public.push_tokens DROP CONSTRAINT IF EXISTS push_tokens_pkey;
ALTER TABLE IF EXISTS ONLY public.products DROP CONSTRAINT IF EXISTS products_pkey;
ALTER TABLE IF EXISTS ONLY public.otp_requests DROP CONSTRAINT IF EXISTS otp_requests_pkey;
ALTER TABLE IF EXISTS ONLY public.otp_rate_limits DROP CONSTRAINT IF EXISTS otp_rate_limits_pkey;
ALTER TABLE IF EXISTS ONLY public.orders DROP CONSTRAINT IF EXISTS orders_pkey;
ALTER TABLE IF EXISTS ONLY public.orders DROP CONSTRAINT IF EXISTS orders_order_number_key;
ALTER TABLE IF EXISTS ONLY public.order_status_history DROP CONSTRAINT IF EXISTS order_status_history_pkey;
ALTER TABLE IF EXISTS ONLY public.order_items DROP CONSTRAINT IF EXISTS order_items_pkey;
ALTER TABLE IF EXISTS ONLY public.ip_rate_limits DROP CONSTRAINT IF EXISTS ip_rate_limits_pkey;
ALTER TABLE IF EXISTS ONLY public.favorites DROP CONSTRAINT IF EXISTS favorites_user_id_product_id_key;
ALTER TABLE IF EXISTS ONLY public.favorites DROP CONSTRAINT IF EXISTS favorites_pkey;
ALTER TABLE IF EXISTS ONLY public.daily_order_counters DROP CONSTRAINT IF EXISTS daily_order_counters_pkey;
ALTER TABLE IF EXISTS ONLY public.categories DROP CONSTRAINT IF EXISTS categories_slug_key;
ALTER TABLE IF EXISTS ONLY public.categories DROP CONSTRAINT IF EXISTS categories_pkey;
ALTER TABLE IF EXISTS ONLY public.app_settings DROP CONSTRAINT IF EXISTS app_settings_pkey;
ALTER TABLE IF EXISTS ONLY _supavisor.users DROP CONSTRAINT IF EXISTS users_pkey;
ALTER TABLE IF EXISTS ONLY _supavisor.tenants DROP CONSTRAINT IF EXISTS tenants_pkey;
ALTER TABLE IF EXISTS ONLY _supavisor.schema_migrations DROP CONSTRAINT IF EXISTS schema_migrations_pkey;
ALTER TABLE IF EXISTS ONLY _supavisor.clusters DROP CONSTRAINT IF EXISTS clusters_pkey;
ALTER TABLE IF EXISTS ONLY _supavisor.cluster_tenants DROP CONSTRAINT IF EXISTS cluster_tenants_pkey;
ALTER TABLE IF EXISTS public.sms_config ALTER COLUMN id DROP DEFAULT;
DROP TABLE IF EXISTS storage.s3_multipart_uploads_parts;
DROP TABLE IF EXISTS storage.s3_multipart_uploads;
DROP TABLE IF EXISTS storage.objects;
DROP TABLE IF EXISTS storage.migrations;
DROP TABLE IF EXISTS storage.buckets;
DROP TABLE IF EXISTS public.weight_options;
DROP TABLE IF EXISTS public.users;
DROP TABLE IF EXISTS public.user_addresses;
DROP TABLE IF EXISTS public.test_otp_records;
DROP SEQUENCE IF EXISTS public.sms_config_id_seq;
DROP TABLE IF EXISTS public.sms_config;
DROP TABLE IF EXISTS public.refresh_tokens;
DROP TABLE IF EXISTS public.push_tokens;
DROP TABLE IF EXISTS public.products;
DROP TABLE IF EXISTS public.otp_requests;
DROP TABLE IF EXISTS public.otp_rate_limits;
DROP TABLE IF EXISTS public.orders;
DROP TABLE IF EXISTS public.order_status_history;
DROP TABLE IF EXISTS public.order_items;
DROP TABLE IF EXISTS public.ip_rate_limits;
DROP TABLE IF EXISTS public.favorites;
DROP TABLE IF EXISTS public.daily_order_counters;
DROP TABLE IF EXISTS public.categories;
DROP TABLE IF EXISTS public.app_settings;
DROP TABLE IF EXISTS _supavisor.users;
DROP TABLE IF EXISTS _supavisor.tenants;
DROP TABLE IF EXISTS _supavisor.schema_migrations;
DROP TABLE IF EXISTS _supavisor.clusters;
DROP TABLE IF EXISTS _supavisor.cluster_tenants;
DROP FUNCTION IF EXISTS storage.update_updated_at_column();
DROP FUNCTION IF EXISTS storage.search(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text);
DROP FUNCTION IF EXISTS storage.operation();
DROP FUNCTION IF EXISTS storage.list_objects_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer, start_after text, next_token text);
DROP FUNCTION IF EXISTS storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer, next_key_token text, next_upload_token text);
DROP FUNCTION IF EXISTS storage.get_size_by_bucket();
DROP FUNCTION IF EXISTS storage.foldername(name text);
DROP FUNCTION IF EXISTS storage.filename(name text);
DROP FUNCTION IF EXISTS storage.extension(name text);
DROP FUNCTION IF EXISTS storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb);
DROP FUNCTION IF EXISTS public.user_owns_order(p_order_id uuid, p_user_id uuid);
DROP FUNCTION IF EXISTS public.update_updated_at();
DROP FUNCTION IF EXISTS public.update_product_search();
DROP FUNCTION IF EXISTS public.is_product_visible(p_product_id uuid);
DROP FUNCTION IF EXISTS public.get_test_otp(p_phone character varying);
DROP FUNCTION IF EXISTS public.get_sms_config();
DROP FUNCTION IF EXISTS public.generate_order_number();
DROP FUNCTION IF EXISTS public.ensure_single_default_address();
DROP FUNCTION IF EXISTS public.delivery_assigned_order(p_order_id uuid, p_staff_id uuid);
DROP FUNCTION IF EXISTS public.cleanup_expired_data();
DROP FUNCTION IF EXISTS public.check_otp_rate_limit(p_phone character varying);
DROP FUNCTION IF EXISTS public.check_ip_rate_limit(p_ip inet);
DROP FUNCTION IF EXISTS auth.uid();
DROP FUNCTION IF EXISTS auth.role();
DROP FUNCTION IF EXISTS auth.is_super_admin();
DROP FUNCTION IF EXISTS auth.is_delivery_staff();
DROP FUNCTION IF EXISTS auth.is_admin();
DROP FUNCTION IF EXISTS auth.check_user_active();
DROP TYPE IF EXISTS public.user_role;
DROP TYPE IF EXISTS public.order_status;
DROP EXTENSION IF EXISTS "uuid-ossp";
DROP EXTENSION IF EXISTS pgcrypto;
DROP SCHEMA IF EXISTS storage;
DROP SCHEMA IF EXISTS extensions;
DROP SCHEMA IF EXISTS auth;
DROP SCHEMA IF EXISTS _supavisor;
--
-- Name: _supavisor; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA _supavisor;


--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA auth;


--
-- Name: extensions; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA extensions;


--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA storage;


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: order_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.order_status AS ENUM (
    'placed',
    'confirmed',
    'out_for_delivery',
    'delivered',
    'cancelled',
    'delivery_failed'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'customer',
    'admin',
    'delivery_staff',
    'super_admin'
);


--
-- Name: check_user_active(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.check_user_active() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
DECLARE
    user_active BOOLEAN;
BEGIN
    SELECT is_active INTO user_active
    FROM users
    WHERE id = auth.uid();

    RETURN COALESCE(user_active, false);
END;
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.is_admin() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
BEGIN
    RETURN auth.role() IN ('admin', 'super_admin');
END;
$$;


--
-- Name: is_delivery_staff(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.is_delivery_staff() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
BEGIN
    RETURN auth.role() = 'delivery_staff';
END;
$$;


--
-- Name: is_super_admin(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.is_super_admin() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
BEGIN
    RETURN auth.role() = 'super_admin';
END;
$$;


--
-- Name: role(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.role() RETURNS public.user_role
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
DECLARE
    jwt_claims JSON;
    user_role_claim TEXT;
    role_claim TEXT;
BEGIN
    jwt_claims := current_setting('request.jwt.claims', true)::json;
    user_role_claim := jwt_claims->>'user_role';
    role_claim := jwt_claims->>'role';

    -- Prefer user_role claim (new JWT format)
    IF user_role_claim IS NOT NULL AND user_role_claim IN ('customer', 'admin', 'delivery_staff', 'super_admin') THEN
        RETURN user_role_claim::user_role;
    END IF;

    -- Fall back to role claim (service_role tokens, legacy JWTs)
    IF role_claim IS NOT NULL THEN
        IF role_claim IN ('customer', 'admin', 'delivery_staff', 'super_admin') THEN
            RETURN role_claim::user_role;
        ELSIF role_claim = 'service_role' THEN
            RETURN 'super_admin'::user_role;
        END IF;
    END IF;

    RETURN NULL;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;


--
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
DECLARE
    jwt_claim TEXT;
BEGIN
    -- Get the 'sub' claim from the JWT (set by PostgREST)
    jwt_claim := current_setting('request.jwt.claims', true)::json->>'sub';

    IF jwt_claim IS NULL OR jwt_claim = '' THEN
        RETURN NULL;
    END IF;

    RETURN jwt_claim::UUID;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;


--
-- Name: check_ip_rate_limit(inet); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_ip_rate_limit(p_ip inet) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: check_otp_rate_limit(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_otp_rate_limit(p_phone character varying) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_record otp_rate_limits%ROWTYPE;
    v_hourly_limit INTEGER := 40;
    v_daily_limit INTEGER := 20;
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
$$;


--
-- Name: cleanup_expired_data(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_expired_data() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: delivery_assigned_order(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delivery_assigned_order(p_order_id uuid, p_staff_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM orders
        WHERE id = p_order_id
          AND delivery_staff_id = p_staff_id
          AND status = 'out_for_delivery'
    );
$$;


--
-- Name: ensure_single_default_address(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_single_default_address() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.is_default = true THEN
        UPDATE user_addresses
        SET is_default = false
        WHERE user_id = NEW.user_id AND id != NEW.id;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: generate_order_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_order_number() RETURNS character varying
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: get_sms_config(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_sms_config() RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
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
$$;


--
-- Name: get_test_otp(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_test_otp(p_phone character varying) RETURNS character varying
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_otp VARCHAR(6);
BEGIN
    SELECT fixed_otp INTO v_otp FROM test_otp_records WHERE phone_number = p_phone;
    RETURN v_otp;
END;
$$;


--
-- Name: is_product_visible(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_product_visible(p_product_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM products
        WHERE id = p_product_id
          AND is_available = true
          AND is_active = true
    );
$$;


--
-- Name: update_product_search(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_product_search() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', COALESCE(NEW.name, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.name_gu, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.description, '')), 'B');
    RETURN NEW;
END;
$$;


--
-- Name: update_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: user_owns_order(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.user_owns_order(p_order_id uuid, p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM orders
        WHERE id = p_order_id
          AND user_id = p_user_id
    );
$$;


--
-- Name: can_insert_object(text, text, uuid, jsonb); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


--
-- Name: extension(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.extension(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
_filename text;
BEGIN
	select string_to_array(name, '/') into _parts;
	select _parts[array_length(_parts,1)] into _filename;
	-- @todo return the last part instead of 2
	return reverse(split_part(reverse(_filename), '.', 1));
END
$$;


--
-- Name: filename(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.filename(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[1:array_length(_parts,1)-1];
END
$$;


--
-- Name: get_size_by_bucket(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_size_by_bucket() RETURNS TABLE(size bigint, bucket_id text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::int) as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


--
-- Name: list_multipart_uploads_with_delimiter(text, text, text, integer, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, next_key_token text DEFAULT ''::text, next_upload_token text DEFAULT ''::text) RETURNS TABLE(key text, id text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


--
-- Name: list_objects_with_delimiter(text, text, text, integer, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_objects_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, start_after text DEFAULT ''::text, next_token text DEFAULT ''::text) RETURNS TABLE(name text, id uuid, metadata jsonb, updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(name COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                        substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1)))
                    ELSE
                        name
                END AS name, id, metadata, updated_at
            FROM
                storage.objects
            WHERE
                bucket_id = $5 AND
                name ILIKE $1 || ''%'' AND
                CASE
                    WHEN $6 != '''' THEN
                    name COLLATE "C" > $6
                ELSE true END
                AND CASE
                    WHEN $4 != '''' THEN
                        CASE
                            WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                                substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                name COLLATE "C" > $4
                            END
                    ELSE
                        true
                END
            ORDER BY
                name COLLATE "C" ASC) as e order by name COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_token, bucket_id, start_after;
END;
$_$;


--
-- Name: operation(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.operation() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


--
-- Name: search(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
declare
  v_order_by text;
  v_sort_order text;
begin
  case
    when sortcolumn = 'name' then
      v_order_by = 'name';
    when sortcolumn = 'updated_at' then
      v_order_by = 'updated_at';
    when sortcolumn = 'created_at' then
      v_order_by = 'created_at';
    when sortcolumn = 'last_accessed_at' then
      v_order_by = 'last_accessed_at';
    else
      v_order_by = 'name';
  end case;

  case
    when sortorder = 'asc' then
      v_sort_order = 'asc';
    when sortorder = 'desc' then
      v_sort_order = 'desc';
    else
      v_sort_order = 'asc';
  end case;

  v_order_by = v_order_by || ' ' || v_sort_order;

  return query execute
    'with folders as (
       select path_tokens[$1] as folder
       from storage.objects
         where objects.name ilike $2 || $3 || ''%''
           and bucket_id = $4
           and array_length(objects.path_tokens, 1) <> $1
       group by folder
       order by folder ' || v_sort_order || '
     )
     (select folder as "name",
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[$1] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where objects.name ilike $2 || $3 || ''%''
       and bucket_id = $4
       and array_length(objects.path_tokens, 1) = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cluster_tenants; Type: TABLE; Schema: _supavisor; Owner: -
--

CREATE TABLE _supavisor.cluster_tenants (
    id uuid NOT NULL,
    type character varying(255) NOT NULL,
    active boolean DEFAULT false NOT NULL,
    cluster_alias character varying(255),
    tenant_external_id character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    CONSTRAINT type CHECK (((type)::text = ANY ((ARRAY['read'::character varying, 'write'::character varying])::text[])))
);


--
-- Name: clusters; Type: TABLE; Schema: _supavisor; Owner: -
--

CREATE TABLE _supavisor.clusters (
    id uuid NOT NULL,
    active boolean DEFAULT false NOT NULL,
    alias character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: _supavisor; Owner: -
--

CREATE TABLE _supavisor.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: tenants; Type: TABLE; Schema: _supavisor; Owner: -
--

CREATE TABLE _supavisor.tenants (
    id uuid NOT NULL,
    external_id character varying(255) NOT NULL,
    db_host character varying(255) NOT NULL,
    db_port integer NOT NULL,
    db_database character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    default_parameter_status jsonb NOT NULL,
    ip_version character varying(255) DEFAULT 'auto'::character varying NOT NULL,
    upstream_ssl boolean DEFAULT false NOT NULL,
    upstream_verify character varying(255),
    upstream_tls_ca bytea,
    enforce_ssl boolean DEFAULT false NOT NULL,
    require_user boolean DEFAULT true NOT NULL,
    auth_query character varying(255),
    default_pool_size integer DEFAULT 15 NOT NULL,
    sni_hostname character varying(255),
    default_max_clients integer DEFAULT 1000 NOT NULL,
    client_idle_timeout integer DEFAULT 0 NOT NULL,
    default_pool_strategy character varying(255) DEFAULT 'fifo'::character varying NOT NULL,
    client_heartbeat_interval integer DEFAULT 60 NOT NULL,
    allow_list character varying(255)[] DEFAULT ARRAY['0.0.0.0/0'::character varying, '::/0'::character varying] NOT NULL,
    CONSTRAINT auth_query_constraints CHECK (((require_user = true) OR ((require_user = false) AND (auth_query IS NOT NULL)))),
    CONSTRAINT default_pool_strategy_values CHECK (((default_pool_strategy)::text = ANY ((ARRAY['fifo'::character varying, 'lifo'::character varying])::text[]))),
    CONSTRAINT ip_version_values CHECK (((ip_version)::text = ANY ((ARRAY['auto'::character varying, 'v4'::character varying, 'v6'::character varying])::text[]))),
    CONSTRAINT upstream_constraints CHECK ((((upstream_ssl = false) AND (upstream_verify IS NULL)) OR ((upstream_ssl = true) AND (upstream_verify IS NOT NULL)))),
    CONSTRAINT upstream_verify_values CHECK (((upstream_verify)::text = ANY ((ARRAY['none'::character varying, 'peer'::character varying])::text[])))
);


--
-- Name: users; Type: TABLE; Schema: _supavisor; Owner: -
--

CREATE TABLE _supavisor.users (
    id uuid NOT NULL,
    db_user_alias character varying(255) NOT NULL,
    db_user character varying(255) NOT NULL,
    db_pass_encrypted bytea NOT NULL,
    pool_size integer NOT NULL,
    mode_type character varying(255) NOT NULL,
    is_manager boolean DEFAULT false NOT NULL,
    tenant_external_id character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    pool_checkout_timeout integer DEFAULT 60000 NOT NULL,
    max_clients integer
);


--
-- Name: app_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_settings (
    key character varying(100) NOT NULL,
    value jsonb NOT NULL,
    description text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(100) NOT NULL,
    name_gu character varying(100),
    slug character varying(100) NOT NULL,
    image_url text,
    display_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: daily_order_counters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_order_counters (
    date date NOT NULL,
    counter integer DEFAULT 0 NOT NULL
);


--
-- Name: favorites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.favorites (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    product_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ip_rate_limits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ip_rate_limits (
    ip_address inet NOT NULL,
    hourly_count integer DEFAULT 0 NOT NULL,
    last_reset_hour timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_items (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    order_id uuid NOT NULL,
    product_id uuid,
    weight_option_id uuid,
    product_name character varying(200) NOT NULL,
    product_name_gu character varying(200),
    weight_label character varying(50) NOT NULL,
    weight_grams integer NOT NULL,
    unit_price_paise integer NOT NULL,
    quantity integer NOT NULL,
    total_paise integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT order_items_quantity_check CHECK ((quantity > 0))
);


--
-- Name: order_status_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_status_history (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    order_id uuid NOT NULL,
    from_status public.order_status,
    to_status public.order_status NOT NULL,
    changed_by uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    order_number character varying(20) NOT NULL,
    user_id uuid NOT NULL,
    status public.order_status DEFAULT 'placed'::public.order_status NOT NULL,
    shipping_name character varying(100) NOT NULL,
    shipping_phone character varying(15) NOT NULL,
    shipping_address_line1 character varying(200) NOT NULL,
    shipping_address_line2 character varying(200),
    shipping_city character varying(100) NOT NULL,
    shipping_state character varying(100) NOT NULL,
    shipping_pincode character varying(10) NOT NULL,
    subtotal_paise integer NOT NULL,
    shipping_paise integer DEFAULT 0 NOT NULL,
    total_paise integer NOT NULL,
    delivery_staff_id uuid,
    delivery_otp_hash character varying(64),
    delivery_otp_expires timestamp with time zone,
    customer_notes text,
    admin_notes text,
    cancellation_reason text,
    failure_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT orders_shipping_paise_check CHECK ((shipping_paise >= 0)),
    CONSTRAINT orders_subtotal_paise_check CHECK ((subtotal_paise >= 0)),
    CONSTRAINT orders_total_paise_check CHECK ((total_paise >= 0))
);


--
-- Name: otp_rate_limits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.otp_rate_limits (
    phone_number character varying(15) NOT NULL,
    hourly_count integer DEFAULT 0 NOT NULL,
    daily_count integer DEFAULT 0 NOT NULL,
    last_reset_hour timestamp with time zone DEFAULT now() NOT NULL,
    last_reset_day timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: otp_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.otp_requests (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    phone character varying(15) NOT NULL,
    otp_hash character varying(64) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    ip_address inet,
    user_agent text,
    msg91_request_id character varying(255),
    delivery_status text DEFAULT 'pending'::text
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    category_id uuid NOT NULL,
    name character varying(200) NOT NULL,
    name_gu character varying(200),
    description text,
    description_gu text,
    image_url text,
    is_available boolean DEFAULT true NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    search_vector tsvector,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: push_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_tokens (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    token text NOT NULL,
    platform character varying(10) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT push_tokens_platform_check CHECK (((platform)::text = ANY ((ARRAY['ios'::character varying, 'android'::character varying])::text[])))
);


--
-- Name: refresh_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_tokens (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    token_hash character varying(64) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sms_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sms_config (
    id integer NOT NULL,
    production_mode boolean DEFAULT false NOT NULL,
    provider character varying(20) DEFAULT 'msg91'::character varying NOT NULL,
    msg91_auth_key text,
    msg91_template_id text,
    msg91_sender_id character varying(6) DEFAULT 'MSSHOP'::character varying,
    msg91_pe_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sms_config_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sms_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sms_config_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sms_config_id_seq OWNED BY public.sms_config.id;


--
-- Name: test_otp_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test_otp_records (
    phone_number character varying(15) NOT NULL,
    fixed_otp character varying(6) NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: user_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_addresses (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    label character varying(50) DEFAULT 'Home'::character varying NOT NULL,
    full_name character varying(100) NOT NULL,
    phone character varying(15) NOT NULL,
    address_line1 character varying(200) NOT NULL,
    address_line2 character varying(200),
    city character varying(100) NOT NULL,
    state character varying(100) DEFAULT 'Gujarat'::character varying NOT NULL,
    pincode character varying(10) NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    phone character varying(15) NOT NULL,
    name character varying(100),
    role public.user_role DEFAULT 'customer'::public.user_role NOT NULL,
    language character varying(5) DEFAULT 'en'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: weight_options; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weight_options (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    product_id uuid NOT NULL,
    weight_grams integer NOT NULL,
    weight_label character varying(50) NOT NULL,
    price_paise integer NOT NULL,
    is_available boolean DEFAULT true NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT weight_options_price_paise_check CHECK ((price_paise > 0))
);


--
-- Name: buckets; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    public boolean DEFAULT false,
    avif_autodetection boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    owner_id text
);


--
-- Name: COLUMN buckets.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.buckets.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: migrations; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.migrations (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    hash character varying(40) NOT NULL,
    executed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: objects; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    metadata jsonb,
    path_tokens text[] GENERATED ALWAYS AS (string_to_array(name, '/'::text)) STORED,
    version text,
    owner_id text,
    user_metadata jsonb
);


--
-- Name: COLUMN objects.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.objects.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: s3_multipart_uploads; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads (
    id text NOT NULL,
    in_progress_size bigint DEFAULT 0 NOT NULL,
    upload_signature text NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    version text NOT NULL,
    owner_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_metadata jsonb
);


--
-- Name: s3_multipart_uploads_parts; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads_parts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    upload_id text NOT NULL,
    size bigint DEFAULT 0 NOT NULL,
    part_number integer NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    etag text NOT NULL,
    owner_id text,
    version text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sms_config id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sms_config ALTER COLUMN id SET DEFAULT nextval('public.sms_config_id_seq'::regclass);


--
-- Data for Name: cluster_tenants; Type: TABLE DATA; Schema: _supavisor; Owner: -
--

COPY _supavisor.cluster_tenants (id, type, active, cluster_alias, tenant_external_id, inserted_at, updated_at) FROM stdin;
\.


--
-- Data for Name: clusters; Type: TABLE DATA; Schema: _supavisor; Owner: -
--

COPY _supavisor.clusters (id, active, alias, inserted_at, updated_at) FROM stdin;
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: _supavisor; Owner: -
--

COPY _supavisor.schema_migrations (version, inserted_at) FROM stdin;
20230125140723	2026-01-25 20:04:58
20230418151441	2026-01-25 20:04:58
20230502101623	2026-01-25 20:04:58
20230601125553	2026-01-25 20:04:58
20230619091028	2026-01-25 20:04:58
20230705154938	2026-01-25 20:04:58
20230711142028	2026-01-25 20:04:58
20230714153019	2026-01-25 20:04:58
20230718175315	2026-01-25 20:04:58
20230801090256	2026-01-25 20:04:58
20230801090942	2026-01-25 20:04:58
20230914102712	2026-01-25 20:04:58
20230919091334	2026-01-25 20:04:58
20230919100141	2026-01-25 20:04:58
20231004133121	2026-01-25 20:04:58
20231214120555	2026-01-25 20:04:58
20231229010413	2026-01-25 20:04:58
\.


--
-- Data for Name: tenants; Type: TABLE DATA; Schema: _supavisor; Owner: -
--

COPY _supavisor.tenants (id, external_id, db_host, db_port, db_database, inserted_at, updated_at, default_parameter_status, ip_version, upstream_ssl, upstream_verify, upstream_tls_ca, enforce_ssl, require_user, auth_query, default_pool_size, sni_hostname, default_max_clients, client_idle_timeout, default_pool_strategy, client_heartbeat_interval, allow_list) FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: _supavisor; Owner: -
--

COPY _supavisor.users (id, db_user_alias, db_user, db_pass_encrypted, pool_size, mode_type, is_manager, tenant_external_id, inserted_at, updated_at, pool_checkout_timeout, max_clients) FROM stdin;
\.


--
-- Data for Name: app_settings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_settings (key, value, description, updated_at) FROM stdin;
shipping_charge_paise	4000	Shipping charge in paise (Rs 40)	2026-01-26 13:35:17.666837+00
free_shipping_threshold_paise	50000	Free shipping above this amount (Rs 500)	2026-01-26 13:35:17.666837+00
min_order_paise	10000	Minimum order amount in paise (Rs 100)	2026-01-26 13:35:17.666837+00
otp_expiry_seconds	300	OTP validity in seconds (5 minutes)	2026-01-26 13:35:17.666837+00
max_otp_attempts	3	Maximum OTP verification attempts	2026-01-26 13:35:17.666837+00
delivery_otp_expiry_hours	24	Delivery OTP validity in hours	2026-01-26 13:35:17.666837+00
serviceable_pincodes	["360001", "360002", "360003", "360004", "360005", "380001"]	List of serviceable PIN codes	2026-01-26 13:35:17.666837+00
\.


--
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.categories (id, name, name_gu, slug, image_url, display_order, is_active, created_at, updated_at) FROM stdin;
c048a45d-7d1f-455f-9664-834e672b0303	Whole Spices	આખા મસાલા	whole-spices	\N	1	t	2026-01-26 13:35:45.336911+00	2026-01-26 13:35:45.336911+00
136ebd73-e401-4148-a364-f9f095005fe4	Ground Spices	પીસેલા મસાલા	ground-spices	\N	2	t	2026-01-26 13:35:45.336911+00	2026-01-26 13:35:45.336911+00
26b378aa-d6c8-45fd-b46b-f3a07b10eaf2	Blended Masalas	મિશ્ર મસાલા	blended-masalas	\N	3	t	2026-01-26 13:35:45.336911+00	2026-01-26 13:35:45.336911+00
326729c0-8690-441e-ad95-ffebce83f14d	Seeds	બીજ	seeds	\N	4	t	2026-01-26 13:35:45.336911+00	2026-01-26 13:35:45.336911+00
357a3bb8-63e5-4b7f-9fc5-90d2033c39dc	Dried Herbs	સૂકી વનસ્પતિ	dried-herbs	\N	5	t	2026-01-26 13:35:45.336911+00	2026-01-26 13:35:45.336911+00
\.


--
-- Data for Name: daily_order_counters; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.daily_order_counters (date, counter) FROM stdin;
2026-01-26	6
\.


--
-- Data for Name: favorites; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.favorites (id, user_id, product_id, created_at) FROM stdin;
\.


--
-- Data for Name: ip_rate_limits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ip_rate_limits (ip_address, hourly_count, last_reset_hour, created_at, updated_at) FROM stdin;
152.58.63.69	1	2026-01-26 15:00:00+00	2026-01-26 15:51:48.860652+00	2026-01-26 15:51:48.860652+00
2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	1	2026-01-26 16:00:00+00	2026-01-26 13:39:18.599272+00	2026-01-26 16:01:56.762694+00
172.21.0.1	2	2026-01-26 19:00:00+00	2026-01-26 13:36:52.216721+00	2026-01-26 19:59:44.904001+00
\.


--
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.order_items (id, order_id, product_id, weight_option_id, product_name, product_name_gu, weight_label, weight_grams, unit_price_paise, quantity, total_paise, created_at) FROM stdin;
c288953f-82fb-4a0e-8f8f-51aeb9fec5f7	c043f751-aeb8-4e25-aaa9-1050c74dddff	89471ee5-a847-45a6-a8cf-6067b199b858	35dd88fc-bd5f-4d30-ae92-fc029e20f444	Black Cardamom	મોટી એલચી	50g	50	4500	2	9000	2026-01-26 16:04:41.816041+00
87bb2b75-8088-4162-b01f-13088f3f1f52	c043f751-aeb8-4e25-aaa9-1050c74dddff	89471ee5-a847-45a6-a8cf-6067b199b858	35dd88fc-bd5f-4d30-ae92-fc029e20f444	Black Cardamom	મોટી એલચી	50g	50	4500	2	9000	2026-01-26 16:04:41.816041+00
295e5aa0-3742-4ced-8aa2-a705a7dc8963	c043f751-aeb8-4e25-aaa9-1050c74dddff	89471ee5-a847-45a6-a8cf-6067b199b858	35dd88fc-bd5f-4d30-ae92-fc029e20f444	Black Cardamom	મોટી એલચી	50g	50	4500	2	9000	2026-01-26 16:04:41.816041+00
2e092600-8a43-447a-8f08-a7ec5da4cf30	c043f751-aeb8-4e25-aaa9-1050c74dddff	89471ee5-a847-45a6-a8cf-6067b199b858	35dd88fc-bd5f-4d30-ae92-fc029e20f444	Black Cardamom	મોટી એલચી	50g	50	4500	2	9000	2026-01-26 16:04:41.816041+00
\.


--
-- Data for Name: order_status_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.order_status_history (id, order_id, from_status, to_status, changed_by, notes, created_at) FROM stdin;
315a2842-51f5-483c-b656-1e1007e79d8e	c043f751-aeb8-4e25-aaa9-1050c74dddff	\N	placed	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Order placed	2026-01-26 16:04:41.819909+00
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.orders (id, order_number, user_id, status, shipping_name, shipping_phone, shipping_address_line1, shipping_address_line2, shipping_city, shipping_state, shipping_pincode, subtotal_paise, shipping_paise, total_paise, delivery_staff_id, delivery_otp_hash, delivery_otp_expires, customer_notes, admin_notes, cancellation_reason, failure_reason, created_at, updated_at) FROM stdin;
c043f751-aeb8-4e25-aaa9-1050c74dddff	MSS-20260126-006	0f804627-964a-4d3c-8fa3-410d32a7e6c7	placed	Test User	+919876543210	123 Test Street	\N	Ahmedabad	Gujarat	380001	36000	4000	40000	\N	\N	\N	\N	\N	\N	\N	2026-01-26 16:04:41.812669+00	2026-01-26 16:04:41.812669+00
\.


--
-- Data for Name: otp_rate_limits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.otp_rate_limits (phone_number, hourly_count, daily_count, last_reset_hour, last_reset_day, created_at, updated_at) FROM stdin;
+919999900002	1	1	2026-01-26 14:00:00+00	2026-01-26 00:00:00+00	2026-01-26 14:04:00.733075+00	2026-01-26 14:04:00.733075+00
+919876543210	1	20	2026-01-26 19:00:00+00	2026-01-26 00:00:00+00	2026-01-26 13:36:52.22373+00	2026-01-26 19:59:10.745499+00
+919999900001	1	2	2026-01-26 19:00:00+00	2026-01-26 00:00:00+00	2026-01-26 14:04:00.658517+00	2026-01-26 19:59:44.907814+00
\.


--
-- Data for Name: otp_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.otp_requests (id, phone, otp_hash, expires_at, verified, attempts, created_at, ip_address, user_agent, msg91_request_id, delivery_status) FROM stdin;
101d0aef-ba84-40b7-966c-8d67a09b569e	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-26 20:04:10.758+00	t	0	2026-01-26 19:59:10.759914+00	172.21.0.1	curl/8.5.0	\N	test_phone
1f969dad-bfec-4908-84ab-a1c7c10aa9e3	+919999900001	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-26 20:04:44.917+00	t	0	2026-01-26 19:59:44.918578+00	172.21.0.1	curl/8.5.0	\N	test_phone
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.products (id, category_id, name, name_gu, description, description_gu, image_url, is_available, is_active, display_order, search_vector, created_at, updated_at) FROM stdin;
c2722195-c636-4e6b-ace8-f14008c4ed52	c048a45d-7d1f-455f-9664-834e672b0303	Cinnamon Sticks	તજ	Premium quality cinnamon sticks, aromatic and fresh	\N	\N	t	t	1	'aromat':8B 'cinnamon':1A,6B 'fresh':10B 'premium':4B 'qualiti':5B 'stick':2A,7B 'તજ':3A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
f2738b30-6b8b-404f-bd4a-e0e35fe3dc48	c048a45d-7d1f-455f-9664-834e672b0303	Cloves	લવિંગ	Hand-picked whole cloves with intense aroma	\N	\N	t	t	2	'aroma':10B 'clove':1A,7B 'hand':4B 'hand-pick':3B 'intens':9B 'pick':5B 'whole':6B 'લવિંગ':2A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
89471ee5-a847-45a6-a8cf-6067b199b858	c048a45d-7d1f-455f-9664-834e672b0303	Black Cardamom	મોટી એલચી	Large black cardamom pods, smoky flavor	\N	\N	t	t	3	'black':1A,6B 'cardamom':2A,7B 'flavor':10B 'larg':5B 'pod':8B 'smoki':9B 'એલચી':4A 'મોટી':3A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
4cc9c11e-697e-473a-be11-6b2505e4bcc8	c048a45d-7d1f-455f-9664-834e672b0303	Green Cardamom	લીલી એલચી	Fresh green cardamom, perfect for tea and desserts	\N	\N	t	t	4	'cardamom':2A,7B 'dessert':12B 'fresh':5B 'green':1A,6B 'perfect':8B 'tea':10B 'એલચી':4A 'લીલી':3A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
92f20362-4563-440a-89f0-ad6e87d9357a	c048a45d-7d1f-455f-9664-834e672b0303	Bay Leaves	તેજપત્તા	Aromatic bay leaves for curries and biryanis	\N	\N	t	t	5	'aromat':4B 'bay':1A,5B 'biryani':10B 'curri':8B 'leav':2A,6B 'તેજપત્તા':3A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
aa807fbc-9cb4-4ea9-9660-19543e2aadbf	136ebd73-e401-4148-a364-f9f095005fe4	Turmeric Powder	હળદર	Pure turmeric powder, vibrant color and flavor	\N	\N	t	t	1	'color':8B 'flavor':10B 'powder':2A,6B 'pure':4B 'turmer':1A,5B 'vibrant':7B 'હળદર':3A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
b5532989-fa34-45b6-8d7a-fff1598763a8	136ebd73-e401-4148-a364-f9f095005fe4	Red Chilli Powder	લાલ મરચું	Hot red chilli powder for authentic taste	\N	\N	t	t	2	'authent':11B 'chilli':2A,8B 'hot':6B 'powder':3A,9B 'red':1A,7B 'tast':12B 'મરચું':5A 'લાલ':4A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
ea08360e-b0b1-48fb-a349-9a9d5bd3d491	136ebd73-e401-4148-a364-f9f095005fe4	Coriander Powder	ધાણાજીરું	Freshly ground coriander, earthy and citrusy	\N	\N	t	t	3	'citrusi':9B 'coriand':1A,6B 'earthi':7B 'fresh':4B 'ground':5B 'powder':2A 'ધાણાજીરું':3A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
956dca68-7369-40dd-827e-b8a36c21933d	136ebd73-e401-4148-a364-f9f095005fe4	Cumin Powder	જીરું પાવડર	Aromatic cumin powder, essential for Indian cooking	\N	\N	t	t	4	'aromat':5B 'cook':11B 'cumin':1A,6B 'essenti':8B 'indian':10B 'powder':2A,7B 'જીરું':3A 'પાવડર':4A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
800b0290-e4af-4b52-99ca-eed94bbd8402	26b378aa-d6c8-45fd-b46b-f3a07b10eaf2	Garam Masala	ગરમ મસાલો	Traditional blend of aromatic spices	\N	\N	t	t	1	'aromat':8B 'blend':6B 'garam':1A 'masala':2A 'spice':9B 'tradit':5B 'ગરમ':3A 'મસાલો':4A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
0d098914-fb27-4e20-a450-d0b685355313	26b378aa-d6c8-45fd-b46b-f3a07b10eaf2	Chai Masala	ચા મસાલો	Perfect blend for authentic masala chai	\N	\N	t	t	2	'authent':8B 'blend':6B 'chai':1A,10B 'masala':2A,9B 'perfect':5B 'ચા':3A 'મસાલો':4A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
a197a453-a2b9-44ce-84d7-8c740d7a5610	26b378aa-d6c8-45fd-b46b-f3a07b10eaf2	Kitchen King Masala	કિચન કિંગ	All-purpose masala for vegetables and curries	\N	\N	t	t	3	'all-purpos':6B 'curri':13B 'king':2A 'kitchen':1A 'masala':3A,9B 'purpos':8B 'veget':11B 'કિંગ':5A 'કિચન':4A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
585fb618-a937-462d-b666-cc18e4abc6ec	26b378aa-d6c8-45fd-b46b-f3a07b10eaf2	Sambhar Masala	સાંભાર મસાલો	South Indian style sambhar spice mix	\N	\N	t	t	4	'indian':6B 'masala':2A 'mix':10B 'sambhar':1A,8B 'south':5B 'spice':9B 'style':7B 'મસાલો':4A 'સાંભાર':3A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
e6248417-4beb-4117-8a4d-bad9c88f43f8	326729c0-8690-441e-ad95-ffebce83f14d	Cumin Seeds	જીરું	Whole cumin seeds, essential tempering spice	\N	\N	t	t	1	'cumin':1A,5B 'essenti':7B 'seed':2A,6B 'spice':9B 'temper':8B 'whole':4B 'જીરું':3A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
48272bc4-e2cc-4eba-8a52-9012af9f56e0	326729c0-8690-441e-ad95-ffebce83f14d	Mustard Seeds	રાઈ	Black mustard seeds for South Indian cooking	\N	\N	t	t	2	'black':4B 'cook':10B 'indian':9B 'mustard':1A,5B 'seed':2A,6B 'south':8B 'રાઈ':3A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
861adf40-7b77-45ef-ab14-14555ba86037	326729c0-8690-441e-ad95-ffebce83f14d	Fenugreek Seeds	મેથી	Fenugreek seeds, slightly bitter, great for pickles	\N	\N	t	t	3	'bitter':7B 'fenugreek':1A,4B 'great':8B 'pickl':10B 'seed':2A,5B 'slight':6B 'મેથી':3A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
7746acce-4970-4922-9b50-43e2cf2cc3d4	326729c0-8690-441e-ad95-ffebce83f14d	Fennel Seeds	વરીયાળી	Sweet fennel seeds, perfect after-meal digestive	\N	\N	t	t	4	'after-m':8B 'digest':11B 'fennel':1A,5B 'meal':10B 'perfect':7B 'seed':2A,6B 'sweet':4B 'વરીયાળી':3A	2026-01-26 13:35:45.338693+00	2026-01-26 13:35:45.338693+00
\.


--
-- Data for Name: push_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.push_tokens (id, user_id, token, platform, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: refresh_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_tokens (id, user_id, token_hash, expires_at, revoked, created_at) FROM stdin;
eb947d5c-5771-4d4e-8f76-6adc049530d6	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	3c9c455655cc616e3e91e3c3f2819e9b3c33ed185acf526b37ef0766f539a8a6	2026-02-26 06:01:45.951+00	f	2026-01-27 06:01:45.952233+00
8398d286-a03c-4926-ab34-e8e91c0aff7d	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ae65ddf36f86a1dba4f63821c52c04c9c952ae69d4896df55fc03abe46e069dc	2026-02-25 19:59:15.848+00	f	2026-01-26 19:59:15.850949+00
dd0b0e7a-9b14-43d8-bad1-86aa964f4816	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	e68c611701af5e0a552880d8eb782747097a01e3ddeb1e3e25a32d34351dd4a6	2026-02-25 19:59:44.942+00	f	2026-01-26 19:59:44.943715+00
de12d209-b48e-4a9c-8247-1c507c489e06	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	6faa308d81a38512ef469101dd74c4369a67e26c68c057ce3acd73db194a7aec	2026-02-25 19:59:49.785+00	f	2026-01-26 19:59:49.786429+00
b7a45ef8-c46a-4b63-a468-33d42da4471d	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	26e5b03bc27b1881bae92c08f532ee8865aa701c59e226bfd59321bb9f9c166f	2026-02-26 05:59:39.392+00	f	2026-01-27 05:59:39.394971+00
a310fa14-7ac3-4e80-9279-a0adc95ac3c0	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	a827b8214c62ae94fd6303b0813953e20d0afda7dae5eb0ec94e2b578bbb8a35	2026-02-26 06:00:26.445+00	f	2026-01-27 06:00:26.446929+00
7c5d2c2e-b608-4951-b08e-acccf56fb0c3	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	57f5d38f333d2a1efa62747476a9ba9e88c9f153400626bcbb45117ebe0c1aad	2026-02-26 06:01:13.835+00	f	2026-01-27 06:01:13.836528+00
\.


--
-- Data for Name: sms_config; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sms_config (id, production_mode, provider, msg91_auth_key, msg91_template_id, msg91_sender_id, msg91_pe_id, created_at, updated_at) FROM stdin;
1	f	msg91	\N	\N	MSSHOP	\N	2026-01-26 13:34:26.359248+00	2026-01-26 13:34:26.359248+00
\.


--
-- Data for Name: test_otp_records; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.test_otp_records (phone_number, fixed_otp, description, created_at, updated_at) FROM stdin;
+919876543210	123456	Default test phone number	2026-01-26 13:34:26.359728+00	2026-01-26 13:34:26.359728+00
+919999900001	123456	Test admin	2026-01-26 14:03:35.847644+00	2026-01-26 14:03:35.847644+00
+919999900002	123456	Test delivery staff	2026-01-26 14:03:35.847644+00	2026-01-26 14:03:35.847644+00
\.


--
-- Data for Name: user_addresses; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_addresses (id, user_id, label, full_name, phone, address_line1, address_line2, city, state, pincode, is_default, created_at, updated_at) FROM stdin;
aba4794c-0375-457d-9089-5e198d5784c9	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Home	Test User	+919876543210	123 Test Street	\N	Ahmedabad	Gujarat	380001	t	2026-01-26 13:42:38.508504+00	2026-01-26 13:42:38.508504+00
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (id, phone, name, role, language, is_active, created_at, updated_at) FROM stdin;
0f804627-964a-4d3c-8fa3-410d32a7e6c7	+919876543210	\N	customer	en	t	2026-01-26 13:38:21.317661+00	2026-01-26 13:38:21.317661+00
31ec2b11-f6ed-4900-91ca-6a0436a2fc47	+919999900001	Test Admin	admin	en	t	2026-01-26 14:03:15.429006+00	2026-01-26 14:03:15.429006+00
fef515c7-74c2-44f8-875c-3a4ac0544af4	+919999900002	Test Delivery	delivery_staff	en	t	2026-01-26 14:03:15.429006+00	2026-01-26 14:03:15.429006+00
\.


--
-- Data for Name: weight_options; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.weight_options (id, product_id, weight_grams, weight_label, price_paise, is_available, display_order, created_at, updated_at) FROM stdin;
fe4262d1-505a-4276-a6f7-c10a03e5941b	c2722195-c636-4e6b-ace8-f14008c4ed52	50	50g	4500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
dc2c4ff9-9e68-4dbd-9871-df173285535e	f2738b30-6b8b-404f-bd4a-e0e35fe3dc48	50	50g	4500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
35dd88fc-bd5f-4d30-ae92-fc029e20f444	89471ee5-a847-45a6-a8cf-6067b199b858	50	50g	4500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
0c4d5d30-4ecf-4439-9357-5f1a372e2710	4cc9c11e-697e-473a-be11-6b2505e4bcc8	50	50g	4500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
6297d102-1e02-497b-904a-c359a73683cc	92f20362-4563-440a-89f0-ad6e87d9357a	50	50g	4500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
0aef6ecc-681a-464a-a687-0393ca64876c	aa807fbc-9cb4-4ea9-9660-19543e2aadbf	50	50g	3500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
63737610-d10a-44fa-9543-7178c6430b59	b5532989-fa34-45b6-8d7a-fff1598763a8	50	50g	3500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
505de83b-8b99-4b64-9301-e7399de5e3bc	ea08360e-b0b1-48fb-a349-9a9d5bd3d491	50	50g	3500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
7c7da18a-0cd0-4d00-b6a5-ec62e18af3b0	956dca68-7369-40dd-827e-b8a36c21933d	50	50g	3500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
acb03603-b9c3-4050-850e-e482146c4ea6	800b0290-e4af-4b52-99ca-eed94bbd8402	50	50g	5500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
cb118901-d61c-4d37-a43f-f68d0c5429a0	0d098914-fb27-4e20-a450-d0b685355313	50	50g	5500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
d999c6b9-8100-424a-8e98-3ca3000d83ab	a197a453-a2b9-44ce-84d7-8c740d7a5610	50	50g	5500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
6967bfb0-5436-4537-ab03-a6c6f6a0c015	585fb618-a937-462d-b666-cc18e4abc6ec	50	50g	5500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
3ac334bb-b4ad-4909-bce9-901335749d0a	e6248417-4beb-4117-8a4d-bad9c88f43f8	50	50g	2500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
663100cd-6323-4e39-be08-4a62426a4c61	48272bc4-e2cc-4eba-8a52-9012af9f56e0	50	50g	2500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
39aa97d8-0bd5-49f6-ad32-0415fa4df570	861adf40-7b77-45ef-ab14-14555ba86037	50	50g	2500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
79fc993e-82f5-4465-9866-a1cbf31e3a44	7746acce-4970-4922-9b50-43e2cf2cc3d4	50	50g	2500	t	1	2026-01-26 13:35:45.345379+00	2026-01-26 13:35:45.345379+00
6ef59fa6-a25b-4e31-84ca-3840510ffaae	c2722195-c636-4e6b-ace8-f14008c4ed52	100	100g	8500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
e4b0879a-4632-48b0-9c7b-723751f28560	f2738b30-6b8b-404f-bd4a-e0e35fe3dc48	100	100g	8500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
c633f83b-8222-4981-8aa8-8122ce1b66c7	89471ee5-a847-45a6-a8cf-6067b199b858	100	100g	8500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
1ddc982d-1255-4b9e-87b6-e5055f06b135	4cc9c11e-697e-473a-be11-6b2505e4bcc8	100	100g	8500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
754c909b-bafb-4c52-899c-a2370fa6cd27	92f20362-4563-440a-89f0-ad6e87d9357a	100	100g	8500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
61cd1ba6-db14-4d40-91a4-7ac7beae3a26	aa807fbc-9cb4-4ea9-9660-19543e2aadbf	100	100g	6500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
1d218411-64af-411a-8c5e-0fd415403430	b5532989-fa34-45b6-8d7a-fff1598763a8	100	100g	6500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
5aad6052-461c-46ce-9170-0a473a3ecba9	ea08360e-b0b1-48fb-a349-9a9d5bd3d491	100	100g	6500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
c5e298ef-3298-4ef5-ba1a-600eb86adb84	956dca68-7369-40dd-827e-b8a36c21933d	100	100g	6500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
11c77080-e4f2-4059-a729-2aeb36e8fb04	800b0290-e4af-4b52-99ca-eed94bbd8402	100	100g	10000	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
2ba37739-67c8-4164-8a4c-503952f387fa	0d098914-fb27-4e20-a450-d0b685355313	100	100g	10000	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
7391f47a-0141-42d3-9dae-bbc447a31a89	a197a453-a2b9-44ce-84d7-8c740d7a5610	100	100g	10000	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
7eac0cd3-8a27-4258-a671-098eb2bbe827	585fb618-a937-462d-b666-cc18e4abc6ec	100	100g	10000	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
600de081-d485-469b-aac4-af0b2afc63ec	e6248417-4beb-4117-8a4d-bad9c88f43f8	100	100g	4500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
4801647d-efa9-40c4-9f92-55eea7c70bfa	48272bc4-e2cc-4eba-8a52-9012af9f56e0	100	100g	4500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
08d543ae-5fe2-499d-9dbc-7a5bc3bf4332	861adf40-7b77-45ef-ab14-14555ba86037	100	100g	4500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
97e371b6-9bb5-4d0b-b5e7-89cf011c7fcf	7746acce-4970-4922-9b50-43e2cf2cc3d4	100	100g	4500	t	2	2026-01-26 13:35:45.346508+00	2026-01-26 13:35:45.346508+00
055f5925-9ade-4a12-9b19-a352e50a8aa1	c2722195-c636-4e6b-ace8-f14008c4ed52	250	250g	19900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
7a9df679-46c7-4dcf-a8b9-95c0ec987312	f2738b30-6b8b-404f-bd4a-e0e35fe3dc48	250	250g	19900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
f61a2900-7f2c-493d-bded-59e308c485ca	89471ee5-a847-45a6-a8cf-6067b199b858	250	250g	19900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
b3b7148d-e95a-49b8-baf0-713a700b921e	4cc9c11e-697e-473a-be11-6b2505e4bcc8	250	250g	19900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
fe8653f4-cf95-4ef6-ab27-38b2e6b15ae9	92f20362-4563-440a-89f0-ad6e87d9357a	250	250g	19900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
1a3bbb2f-30bb-444d-bbff-6a13dff7f5e8	aa807fbc-9cb4-4ea9-9660-19543e2aadbf	250	250g	14900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
46a93dca-11f0-4e3f-97df-3fda23f51967	b5532989-fa34-45b6-8d7a-fff1598763a8	250	250g	14900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
0a4e6efa-2507-410e-83a8-6fa3f3f07ade	ea08360e-b0b1-48fb-a349-9a9d5bd3d491	250	250g	14900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
9a8ee333-7da9-4bc5-b8c5-101538b268be	956dca68-7369-40dd-827e-b8a36c21933d	250	250g	14900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
721440f8-4f73-4390-9458-8c23d9849d01	800b0290-e4af-4b52-99ca-eed94bbd8402	250	250g	22900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
334372a5-2cc9-48d4-93f3-0123c5df47a8	0d098914-fb27-4e20-a450-d0b685355313	250	250g	22900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
d94fe314-f7ab-48b3-9a0b-da1b907e8273	a197a453-a2b9-44ce-84d7-8c740d7a5610	250	250g	22900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
12713836-8fd6-4880-b0fd-e10ba7062035	585fb618-a937-462d-b666-cc18e4abc6ec	250	250g	22900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
bba8ac64-d99a-4f34-acce-c632ac7719a6	e6248417-4beb-4117-8a4d-bad9c88f43f8	250	250g	9900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
c96cc14a-28fe-415a-bbe6-a29efa7e08fd	48272bc4-e2cc-4eba-8a52-9012af9f56e0	250	250g	9900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
3796dff4-449a-4be4-b8f9-e6e0d2693299	861adf40-7b77-45ef-ab14-14555ba86037	250	250g	9900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
c8bfe662-63d7-4d3f-9b5a-7c0c7dd77c60	7746acce-4970-4922-9b50-43e2cf2cc3d4	250	250g	9900	t	3	2026-01-26 13:35:45.34703+00	2026-01-26 13:35:45.34703+00
ed0d9bf2-e8e5-402f-bb81-2bda6c930803	c2722195-c636-4e6b-ace8-f14008c4ed52	500	500g	37900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
9d07f7fd-1362-4c1f-9be1-c676deca1537	f2738b30-6b8b-404f-bd4a-e0e35fe3dc48	500	500g	37900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
aff4600f-e3c2-46d4-a17c-1055e6ec984c	89471ee5-a847-45a6-a8cf-6067b199b858	500	500g	37900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
984d8f5f-d84c-4153-996c-1c5fb4a4fd69	4cc9c11e-697e-473a-be11-6b2505e4bcc8	500	500g	37900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
6343f355-f086-4a1f-8a7f-1dd9eac55bde	92f20362-4563-440a-89f0-ad6e87d9357a	500	500g	37900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
ef95c6c4-6847-434c-b16b-f232488afed4	aa807fbc-9cb4-4ea9-9660-19543e2aadbf	500	500g	27900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
495eff68-827c-4bd3-85e5-bf0ff23ae392	b5532989-fa34-45b6-8d7a-fff1598763a8	500	500g	27900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
ac4fe76f-25ca-4858-9c64-ffc3793b1558	ea08360e-b0b1-48fb-a349-9a9d5bd3d491	500	500g	27900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
575daf07-80b0-455b-b3f5-8ee24e303ed7	956dca68-7369-40dd-827e-b8a36c21933d	500	500g	27900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
ca95cfb4-167b-4057-a970-76cae7257682	800b0290-e4af-4b52-99ca-eed94bbd8402	500	500g	42900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
2fa9c944-69d6-4b3d-bb65-acae3aabeeca	0d098914-fb27-4e20-a450-d0b685355313	500	500g	42900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
ada6f5ba-ae72-4232-8392-c74368d60ca6	a197a453-a2b9-44ce-84d7-8c740d7a5610	500	500g	42900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
10199b8f-3198-469a-bbca-169ec46810c9	585fb618-a937-462d-b666-cc18e4abc6ec	500	500g	42900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
f0e3f876-6c2f-4d7d-8023-1424cc5e95ad	e6248417-4beb-4117-8a4d-bad9c88f43f8	500	500g	17900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
b028384f-b86f-4037-9c26-ab6c915385d2	48272bc4-e2cc-4eba-8a52-9012af9f56e0	500	500g	17900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
4449a7de-d468-489a-b29b-d7d3a71b1f5d	861adf40-7b77-45ef-ab14-14555ba86037	500	500g	17900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
bda1d186-8620-4269-96a9-39cef90f2653	7746acce-4970-4922-9b50-43e2cf2cc3d4	500	500g	17900	t	4	2026-01-26 13:35:45.347629+00	2026-01-26 13:35:45.347629+00
\.


--
-- Data for Name: buckets; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.buckets (id, name, owner, created_at, updated_at, public, avif_autodetection, file_size_limit, allowed_mime_types, owner_id) FROM stdin;
\.


--
-- Data for Name: migrations; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.migrations (id, name, hash, executed_at) FROM stdin;
0	create-migrations-table	e18db593bcde2aca2a408c4d1100f6abba2195df	2026-01-25 20:04:58.145188
1	initialmigration	6ab16121fbaa08bbd11b712d05f358f9b555d777	2026-01-25 20:04:58.152332
2	storage-schema	5c7968fd083fcea04050c1b7f6253c9771b99011	2026-01-25 20:04:58.153924
3	pathtoken-column	2cb1b0004b817b29d5b0a971af16bafeede4b70d	2026-01-25 20:04:58.163255
4	add-migrations-rls	427c5b63fe1c5937495d9c635c263ee7a5905058	2026-01-25 20:04:58.171421
5	add-size-functions	79e081a1455b63666c1294a440f8ad4b1e6a7f84	2026-01-25 20:04:58.172669
6	change-column-name-in-get-size	f93f62afdf6613ee5e7e815b30d02dc990201044	2026-01-25 20:04:58.174157
7	add-rls-to-buckets	e7e7f86adbc51049f341dfe8d30256c1abca17aa	2026-01-25 20:04:58.175264
8	add-public-to-buckets	fd670db39ed65f9d08b01db09d6202503ca2bab3	2026-01-25 20:04:58.17649
9	fix-search-function	3a0af29f42e35a4d101c259ed955b67e1bee6825	2026-01-25 20:04:58.178707
10	search-files-search-function	68dc14822daad0ffac3746a502234f486182ef6e	2026-01-25 20:04:58.180851
11	add-trigger-to-auto-update-updated_at-column	7425bdb14366d1739fa8a18c83100636d74dcaa2	2026-01-25 20:04:58.183396
12	add-automatic-avif-detection-flag	8e92e1266eb29518b6a4c5313ab8f29dd0d08df9	2026-01-25 20:04:58.186479
13	add-bucket-custom-limits	cce962054138135cd9a8c4bcd531598684b25e7d	2026-01-25 20:04:58.187728
14	use-bytes-for-max-size	941c41b346f9802b411f06f30e972ad4744dad27	2026-01-25 20:04:58.189776
15	add-can-insert-object-function	934146bc38ead475f4ef4b555c524ee5d66799e5	2026-01-25 20:04:58.19938
16	add-version	76debf38d3fd07dcfc747ca49096457d95b1221b	2026-01-25 20:04:58.200523
17	drop-owner-foreign-key	f1cbb288f1b7a4c1eb8c38504b80ae2a0153d101	2026-01-25 20:04:58.20169
18	add_owner_id_column_deprecate_owner	e7a511b379110b08e2f214be852c35414749fe66	2026-01-25 20:04:58.202997
19	alter-default-value-objects-id	02e5e22a78626187e00d173dc45f58fa66a4f043	2026-01-25 20:04:58.204573
20	list-objects-with-delimiter	cd694ae708e51ba82bf012bba00caf4f3b6393b7	2026-01-25 20:04:58.205845
21	s3-multipart-uploads	8c804d4a566c40cd1e4cc5b3725a664a9303657f	2026-01-25 20:04:58.208027
22	s3-multipart-uploads-big-ints	9737dc258d2397953c9953d9b86920b8be0cdb73	2026-01-25 20:04:58.21472
23	optimize-search-function	9d7e604cddc4b56a5422dc68c9313f4a1b6f132c	2026-01-25 20:04:58.220705
24	operation-function	8312e37c2bf9e76bbe841aa5fda889206d2bf8aa	2026-01-25 20:04:58.222067
25	custom-metadata	67eb93b7e8d401cafcdc97f9ac779e71a79bfe03	2026-01-25 20:04:58.22303
\.


--
-- Data for Name: objects; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.objects (id, bucket_id, name, owner, created_at, updated_at, last_accessed_at, metadata, version, owner_id, user_metadata) FROM stdin;
\.


--
-- Data for Name: s3_multipart_uploads; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.s3_multipart_uploads (id, in_progress_size, upload_signature, bucket_id, key, version, owner_id, created_at, user_metadata) FROM stdin;
\.


--
-- Data for Name: s3_multipart_uploads_parts; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.s3_multipart_uploads_parts (id, upload_id, size, part_number, bucket_id, key, etag, owner_id, version, created_at) FROM stdin;
\.


--
-- Name: sms_config_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sms_config_id_seq', 2, true);


--
-- Name: cluster_tenants cluster_tenants_pkey; Type: CONSTRAINT; Schema: _supavisor; Owner: -
--

ALTER TABLE ONLY _supavisor.cluster_tenants
    ADD CONSTRAINT cluster_tenants_pkey PRIMARY KEY (id);


--
-- Name: clusters clusters_pkey; Type: CONSTRAINT; Schema: _supavisor; Owner: -
--

ALTER TABLE ONLY _supavisor.clusters
    ADD CONSTRAINT clusters_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: _supavisor; Owner: -
--

ALTER TABLE ONLY _supavisor.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: _supavisor; Owner: -
--

ALTER TABLE ONLY _supavisor.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: _supavisor; Owner: -
--

ALTER TABLE ONLY _supavisor.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: app_settings app_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_settings
    ADD CONSTRAINT app_settings_pkey PRIMARY KEY (key);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: categories categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_key UNIQUE (slug);


--
-- Name: daily_order_counters daily_order_counters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_order_counters
    ADD CONSTRAINT daily_order_counters_pkey PRIMARY KEY (date);


--
-- Name: favorites favorites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_pkey PRIMARY KEY (id);


--
-- Name: favorites favorites_user_id_product_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_user_id_product_id_key UNIQUE (user_id, product_id);


--
-- Name: ip_rate_limits ip_rate_limits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ip_rate_limits
    ADD CONSTRAINT ip_rate_limits_pkey PRIMARY KEY (ip_address);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: order_status_history order_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_pkey PRIMARY KEY (id);


--
-- Name: orders orders_order_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_order_number_key UNIQUE (order_number);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: otp_rate_limits otp_rate_limits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.otp_rate_limits
    ADD CONSTRAINT otp_rate_limits_pkey PRIMARY KEY (phone_number);


--
-- Name: otp_requests otp_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.otp_requests
    ADD CONSTRAINT otp_requests_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: push_tokens push_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT push_tokens_pkey PRIMARY KEY (id);


--
-- Name: push_tokens push_tokens_user_id_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT push_tokens_user_id_token_key UNIQUE (user_id, token);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT refresh_tokens_token_hash_key UNIQUE (token_hash);


--
-- Name: sms_config sms_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sms_config
    ADD CONSTRAINT sms_config_pkey PRIMARY KEY (id);


--
-- Name: test_otp_records test_otp_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_otp_records
    ADD CONSTRAINT test_otp_records_pkey PRIMARY KEY (phone_number);


--
-- Name: user_addresses user_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_addresses
    ADD CONSTRAINT user_addresses_pkey PRIMARY KEY (id);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: weight_options weight_options_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weight_options
    ADD CONSTRAINT weight_options_pkey PRIMARY KEY (id);


--
-- Name: weight_options weight_options_product_id_weight_grams_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weight_options
    ADD CONSTRAINT weight_options_product_id_weight_grams_key UNIQUE (product_id, weight_grams);


--
-- Name: buckets buckets_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_name_key; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_name_key UNIQUE (name);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_pkey PRIMARY KEY (id);


--
-- Name: cluster_tenants_tenant_external_id_index; Type: INDEX; Schema: _supavisor; Owner: -
--

CREATE UNIQUE INDEX cluster_tenants_tenant_external_id_index ON _supavisor.cluster_tenants USING btree (tenant_external_id);


--
-- Name: clusters_alias_index; Type: INDEX; Schema: _supavisor; Owner: -
--

CREATE UNIQUE INDEX clusters_alias_index ON _supavisor.clusters USING btree (alias);


--
-- Name: tenants_external_id_index; Type: INDEX; Schema: _supavisor; Owner: -
--

CREATE UNIQUE INDEX tenants_external_id_index ON _supavisor.tenants USING btree (external_id);


--
-- Name: users_db_user_alias_tenant_external_id_mode_type_index; Type: INDEX; Schema: _supavisor; Owner: -
--

CREATE UNIQUE INDEX users_db_user_alias_tenant_external_id_mode_type_index ON _supavisor.users USING btree (db_user_alias, tenant_external_id, mode_type);


--
-- Name: idx_addresses_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_addresses_user ON public.user_addresses USING btree (user_id);


--
-- Name: idx_categories_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_categories_active ON public.categories USING btree (is_active, display_order);


--
-- Name: idx_favorites_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_favorites_user ON public.favorites USING btree (user_id);


--
-- Name: idx_order_items_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_items_order ON public.order_items USING btree (order_id);


--
-- Name: idx_orders_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_created ON public.orders USING btree (created_at DESC);


--
-- Name: idx_orders_delivery; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_delivery ON public.orders USING btree (delivery_staff_id) WHERE (delivery_staff_id IS NOT NULL);


--
-- Name: idx_orders_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_number ON public.orders USING btree (order_number);


--
-- Name: idx_orders_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_status ON public.orders USING btree (status);


--
-- Name: idx_orders_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_user ON public.orders USING btree (user_id);


--
-- Name: idx_otp_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_otp_expires ON public.otp_requests USING btree (expires_at);


--
-- Name: idx_otp_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_otp_phone ON public.otp_requests USING btree (phone);


--
-- Name: idx_otp_requests_ip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_otp_requests_ip ON public.otp_requests USING btree (ip_address);


--
-- Name: idx_products_available; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_available ON public.products USING btree (is_available, is_active);


--
-- Name: idx_products_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_category ON public.products USING btree (category_id);


--
-- Name: idx_products_search; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_search ON public.products USING gin (search_vector);


--
-- Name: idx_push_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_push_user ON public.push_tokens USING btree (user_id);


--
-- Name: idx_refresh_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_refresh_token ON public.refresh_tokens USING btree (token_hash);


--
-- Name: idx_refresh_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_refresh_user ON public.refresh_tokens USING btree (user_id);


--
-- Name: idx_sms_config_singleton; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_sms_config_singleton ON public.sms_config USING btree ((true));


--
-- Name: idx_status_history_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_status_history_order ON public.order_status_history USING btree (order_id);


--
-- Name: idx_users_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_phone ON public.users USING btree (phone);


--
-- Name: idx_users_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_role ON public.users USING btree (role);


--
-- Name: idx_weight_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_weight_product ON public.weight_options USING btree (product_id);


--
-- Name: bname; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX bname ON storage.buckets USING btree (name);


--
-- Name: bucketid_objname; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX bucketid_objname ON storage.objects USING btree (bucket_id, name);


--
-- Name: idx_multipart_uploads_list; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_multipart_uploads_list ON storage.s3_multipart_uploads USING btree (bucket_id, key, created_at);


--
-- Name: idx_objects_bucket_id_name; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_bucket_id_name ON storage.objects USING btree (bucket_id, name COLLATE "C");


--
-- Name: name_prefix_search; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX name_prefix_search ON storage.objects USING btree (name text_pattern_ops);


--
-- Name: user_addresses ensure_default_address; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ensure_default_address AFTER INSERT OR UPDATE OF is_default ON public.user_addresses FOR EACH ROW WHEN ((new.is_default = true)) EXECUTE FUNCTION public.ensure_single_default_address();


--
-- Name: user_addresses update_addresses_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_addresses_updated_at BEFORE UPDATE ON public.user_addresses FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: app_settings update_app_settings_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_app_settings_updated_at BEFORE UPDATE ON public.app_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: categories update_categories_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_categories_updated_at BEFORE UPDATE ON public.categories FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: ip_rate_limits update_ip_rate_limits_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ip_rate_limits_updated_at BEFORE UPDATE ON public.ip_rate_limits FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: orders update_orders_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: otp_rate_limits update_otp_rate_limits_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_otp_rate_limits_updated_at BEFORE UPDATE ON public.otp_rate_limits FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: products update_products_search; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_products_search BEFORE INSERT OR UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_product_search();


--
-- Name: products update_products_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: push_tokens update_push_tokens_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_push_tokens_updated_at BEFORE UPDATE ON public.push_tokens FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: sms_config update_sms_config_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_sms_config_updated_at BEFORE UPDATE ON public.sms_config FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: test_otp_records update_test_otp_records_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_test_otp_records_updated_at BEFORE UPDATE ON public.test_otp_records FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: users update_users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: weight_options update_weight_options_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_weight_options_updated_at BEFORE UPDATE ON public.weight_options FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: objects update_objects_updated_at; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();


--
-- Name: cluster_tenants cluster_tenants_cluster_alias_fkey; Type: FK CONSTRAINT; Schema: _supavisor; Owner: -
--

ALTER TABLE ONLY _supavisor.cluster_tenants
    ADD CONSTRAINT cluster_tenants_cluster_alias_fkey FOREIGN KEY (cluster_alias) REFERENCES _supavisor.clusters(alias) ON DELETE CASCADE;


--
-- Name: cluster_tenants cluster_tenants_tenant_external_id_fkey; Type: FK CONSTRAINT; Schema: _supavisor; Owner: -
--

ALTER TABLE ONLY _supavisor.cluster_tenants
    ADD CONSTRAINT cluster_tenants_tenant_external_id_fkey FOREIGN KEY (tenant_external_id) REFERENCES _supavisor.tenants(external_id);


--
-- Name: users users_tenant_external_id_fkey; Type: FK CONSTRAINT; Schema: _supavisor; Owner: -
--

ALTER TABLE ONLY _supavisor.users
    ADD CONSTRAINT users_tenant_external_id_fkey FOREIGN KEY (tenant_external_id) REFERENCES _supavisor.tenants(external_id) ON DELETE CASCADE;


--
-- Name: favorites favorites_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: favorites favorites_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;


--
-- Name: order_items order_items_weight_option_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_weight_option_id_fkey FOREIGN KEY (weight_option_id) REFERENCES public.weight_options(id) ON DELETE SET NULL;


--
-- Name: order_status_history order_status_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);


--
-- Name: order_status_history order_status_history_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_status_history
    ADD CONSTRAINT order_status_history_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: orders orders_delivery_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_delivery_staff_id_fkey FOREIGN KEY (delivery_staff_id) REFERENCES public.users(id);


--
-- Name: orders orders_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: products products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE RESTRICT;


--
-- Name: push_tokens push_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT push_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT refresh_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_addresses user_addresses_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_addresses
    ADD CONSTRAINT user_addresses_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: weight_options weight_options_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weight_options
    ADD CONSTRAINT weight_options_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: objects objects_bucketId_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_upload_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES storage.s3_multipart_uploads(id) ON DELETE CASCADE;


--
-- Name: sms_config Admin can manage sms_config; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin can manage sms_config" ON public.sms_config TO authenticated USING (( SELECT auth.is_admin() AS is_admin)) WITH CHECK (( SELECT auth.is_admin() AS is_admin));


--
-- Name: test_otp_records Admin can manage test_otp_records; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin can manage test_otp_records" ON public.test_otp_records TO authenticated USING (( SELECT auth.is_admin() AS is_admin)) WITH CHECK (( SELECT auth.is_admin() AS is_admin));


--
-- Name: ip_rate_limits Service role can manage ip_rate_limits; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Service role can manage ip_rate_limits" ON public.ip_rate_limits TO service_role USING (true) WITH CHECK (true);


--
-- Name: otp_rate_limits Service role can manage otp_rate_limits; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Service role can manage otp_rate_limits" ON public.otp_rate_limits TO service_role USING (true) WITH CHECK (true);


--
-- Name: sms_config Service role can manage sms_config; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Service role can manage sms_config" ON public.sms_config TO service_role USING (true) WITH CHECK (true);


--
-- Name: test_otp_records Service role can manage test_otp_records; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Service role can manage test_otp_records" ON public.test_otp_records TO service_role USING (true) WITH CHECK (true);


--
-- Name: user_addresses addresses_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addresses_admin_read ON public.user_addresses FOR SELECT TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: user_addresses addresses_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addresses_delete_own ON public.user_addresses FOR DELETE TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: user_addresses addresses_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addresses_insert_own ON public.user_addresses FOR INSERT TO authenticated WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: user_addresses addresses_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addresses_read_own ON public.user_addresses FOR SELECT TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: user_addresses addresses_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY addresses_update_own ON public.user_addresses FOR UPDATE TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: app_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: categories categories_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_admin_delete ON public.categories FOR DELETE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: categories categories_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_admin_insert ON public.categories FOR INSERT TO authenticated WITH CHECK (( SELECT auth.is_admin() AS is_admin));


--
-- Name: categories categories_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_admin_read ON public.categories FOR SELECT TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: categories categories_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_admin_update ON public.categories FOR UPDATE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: categories categories_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_public_read ON public.categories FOR SELECT TO anon, authenticated USING ((is_active = true));


--
-- Name: daily_order_counters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.daily_order_counters ENABLE ROW LEVEL SECURITY;

--
-- Name: favorites; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;

--
-- Name: favorites favorites_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY favorites_delete_own ON public.favorites FOR DELETE TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: favorites favorites_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY favorites_insert_own ON public.favorites FOR INSERT TO authenticated WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: favorites favorites_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY favorites_read_own ON public.favorites FOR SELECT TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: ip_rate_limits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ip_rate_limits ENABLE ROW LEVEL SECURITY;

--
-- Name: order_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

--
-- Name: order_items order_items_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_items_admin_read ON public.order_items FOR SELECT TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: order_items order_items_delivery_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_items_delivery_read ON public.order_items FOR SELECT TO authenticated USING (public.delivery_assigned_order(order_id, ( SELECT auth.uid() AS uid)));


--
-- Name: order_items order_items_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_items_read_own ON public.order_items FOR SELECT TO authenticated USING (public.user_owns_order(order_id, ( SELECT auth.uid() AS uid)));


--
-- Name: order_status_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY;

--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: orders orders_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_admin_read ON public.orders FOR SELECT TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: orders orders_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_admin_update ON public.orders FOR UPDATE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: orders orders_delivery_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_delivery_read ON public.orders FOR SELECT TO authenticated USING ((( SELECT auth.is_delivery_staff() AS is_delivery_staff) AND (delivery_staff_id = ( SELECT auth.uid() AS uid)) AND (status = 'out_for_delivery'::public.order_status)));


--
-- Name: orders orders_delivery_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_delivery_update ON public.orders FOR UPDATE TO authenticated USING ((( SELECT auth.is_delivery_staff() AS is_delivery_staff) AND (delivery_staff_id = ( SELECT auth.uid() AS uid)) AND (status = 'out_for_delivery'::public.order_status)));


--
-- Name: orders orders_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_read_own ON public.orders FOR SELECT TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: otp_rate_limits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.otp_rate_limits ENABLE ROW LEVEL SECURITY;

--
-- Name: otp_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.otp_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: products products_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_admin_delete ON public.products FOR DELETE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: products products_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_admin_insert ON public.products FOR INSERT TO authenticated WITH CHECK (( SELECT auth.is_admin() AS is_admin));


--
-- Name: products products_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_admin_read ON public.products FOR SELECT TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: products products_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_admin_update ON public.products FOR UPDATE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: products products_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_public_read ON public.products FOR SELECT TO anon, authenticated USING (((is_available = true) AND (is_active = true)));


--
-- Name: push_tokens push_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY push_admin_read ON public.push_tokens FOR SELECT TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: push_tokens push_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY push_delete_own ON public.push_tokens FOR DELETE TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: push_tokens push_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY push_insert_own ON public.push_tokens FOR INSERT TO authenticated WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: push_tokens push_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY push_read_own ON public.push_tokens FOR SELECT TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: push_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: push_tokens push_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY push_update_own ON public.push_tokens FOR UPDATE TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: refresh_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.refresh_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: app_settings settings_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY settings_admin_update ON public.app_settings FOR UPDATE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: app_settings settings_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY settings_public_read ON public.app_settings FOR SELECT TO anon, authenticated USING (true);


--
-- Name: app_settings settings_superadmin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY settings_superadmin_insert ON public.app_settings FOR INSERT TO authenticated WITH CHECK (( SELECT auth.is_super_admin() AS is_super_admin));


--
-- Name: sms_config; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sms_config ENABLE ROW LEVEL SECURITY;

--
-- Name: order_status_history status_history_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY status_history_admin_insert ON public.order_status_history FOR INSERT TO authenticated WITH CHECK (( SELECT auth.is_admin() AS is_admin));


--
-- Name: order_status_history status_history_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY status_history_admin_read ON public.order_status_history FOR SELECT TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: order_status_history status_history_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY status_history_read_own ON public.order_status_history FOR SELECT TO authenticated USING (public.user_owns_order(order_id, ( SELECT auth.uid() AS uid)));


--
-- Name: test_otp_records; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.test_otp_records ENABLE ROW LEVEL SECURITY;

--
-- Name: user_addresses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_addresses ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: users users_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_admin_read ON public.users FOR SELECT TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: users users_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_admin_update ON public.users FOR UPDATE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: users users_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_read_own ON public.users FOR SELECT TO authenticated USING ((id = ( SELECT auth.uid() AS uid)));


--
-- Name: users users_superadmin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_superadmin_insert ON public.users FOR INSERT TO authenticated WITH CHECK (( SELECT auth.is_super_admin() AS is_super_admin));


--
-- Name: users users_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_update_own ON public.users FOR UPDATE TO authenticated USING ((id = ( SELECT auth.uid() AS uid))) WITH CHECK ((id = ( SELECT auth.uid() AS uid)));


--
-- Name: weight_options; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.weight_options ENABLE ROW LEVEL SECURITY;

--
-- Name: weight_options weight_options_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY weight_options_admin_delete ON public.weight_options FOR DELETE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: weight_options weight_options_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY weight_options_admin_insert ON public.weight_options FOR INSERT TO authenticated WITH CHECK (( SELECT auth.is_admin() AS is_admin));


--
-- Name: weight_options weight_options_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY weight_options_admin_read ON public.weight_options FOR SELECT TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: weight_options weight_options_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY weight_options_admin_update ON public.weight_options FOR UPDATE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: weight_options weight_options_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY weight_options_public_read ON public.weight_options FOR SELECT TO anon, authenticated USING (((is_available = true) AND public.is_product_visible(product_id)));


--
-- Name: buckets; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

--
-- Name: migrations; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads_parts; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads_parts ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

