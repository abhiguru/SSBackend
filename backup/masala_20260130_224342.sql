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
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


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
-- Name: delivery_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.delivery_type AS ENUM (
    'in_house',
    'porter'
);


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
    RETURN auth.role() = 'admin';
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
    IF user_role_claim IS NOT NULL THEN
        IF user_role_claim IN ('customer', 'admin', 'delivery_staff') THEN
            RETURN user_role_claim::user_role;
        ELSIF user_role_claim = 'super_admin' THEN
            RETURN 'admin'::user_role;
        END IF;
    END IF;

    -- Fall back to role claim (service_role tokens, legacy JWTs)
    IF role_claim IS NOT NULL THEN
        IF role_claim IN ('customer', 'admin', 'delivery_staff') THEN
            RETURN role_claim::user_role;
        ELSIF role_claim IN ('super_admin', 'service_role') THEN
            RETURN 'admin'::user_role;
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
    v_daily_limit INTEGER := 999999;
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
-- Name: cleanup_orphaned_product_images(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_orphaned_product_images(p_max_age_hours integer DEFAULT 1) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_deleted_count INT;
    v_storage_paths TEXT[];
BEGIN
    -- Collect storage paths of orphaned images before deleting
    SELECT ARRAY_AGG(storage_path)
    INTO v_storage_paths
    FROM product_images
    WHERE status = 'pending'
      AND created_at < NOW() - (p_max_age_hours || ' hours')::INTERVAL;

    -- Delete orphaned pending records
    DELETE FROM product_images
    WHERE status = 'pending'
      AND created_at < NOW() - (p_max_age_hours || ' hours')::INTERVAL;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    RETURN jsonb_build_object(
        'success', true,
        'deleted_count', v_deleted_count,
        'storage_paths', COALESCE(to_jsonb(v_storage_paths), '[]'::JSONB)
    );
END;
$$;


--
-- Name: confirm_product_image_upload(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirm_product_image_upload(p_image_id uuid, p_upload_token uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_image RECORD;
BEGIN
    -- Validate token matches a pending record
    SELECT id, product_id, storage_path, status
    INTO v_image
    FROM product_images
    WHERE id = p_image_id
      AND upload_token = p_upload_token
      AND status = 'pending';

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_TOKEN',
            'message', 'Image not found or already confirmed'
        );
    END IF;

    -- Confirm the image
    UPDATE product_images
    SET status = 'confirmed',
        upload_token = NULL
    WHERE id = v_image.id;

    -- Update products.image_url with the first confirmed image (display_order = 0)
    UPDATE products
    SET image_url = (
        SELECT storage_path
        FROM product_images
        WHERE product_id = v_image.product_id
          AND status = 'confirmed'
        ORDER BY display_order ASC, created_at ASC
        LIMIT 1
    )
    WHERE id = v_image.product_id;

    RETURN jsonb_build_object(
        'success', true,
        'image_id', v_image.id,
        'storage_path', v_image.storage_path,
        'product_id', v_image.product_id,
        'status', 'confirmed'
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
-- Name: get_store_pickup_coords(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_store_pickup_coords() RETURNS TABLE(lat numeric, lng numeric, address text, name text, phone text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT (value)::DECIMAL FROM app_settings WHERE key = 'porter_pickup_lat') AS lat,
        (SELECT (value)::DECIMAL FROM app_settings WHERE key = 'porter_pickup_lng') AS lng,
        (SELECT value::TEXT FROM app_settings WHERE key = 'porter_pickup_address') AS address,
        (SELECT value::TEXT FROM app_settings WHERE key = 'porter_pickup_name') AS name,
        (SELECT value::TEXT FROM app_settings WHERE key = 'porter_pickup_phone') AS phone;
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
-- Name: register_and_confirm_product_image(uuid, text, character varying, integer, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.register_and_confirm_product_image(p_product_id uuid, p_storage_path text, p_original_filename character varying, p_file_size integer, p_mime_type character varying) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_image RECORD;
    v_next_order INT;
BEGIN
    -- Determine next display_order
    SELECT COALESCE(MAX(display_order), -1) + 1 INTO v_next_order
    FROM product_images WHERE product_id = p_product_id AND status = 'confirmed';

    -- Insert as confirmed directly (skip pending state)
    INSERT INTO product_images (
        product_id, storage_path, original_filename,
        file_size, mime_type, display_order, uploaded_by, status
    ) VALUES (
        p_product_id, p_storage_path, p_original_filename,
        p_file_size, p_mime_type, v_next_order, auth.uid(), 'confirmed'
    ) RETURNING id, product_id, storage_path INTO v_image;

    -- Update products.image_url with first confirmed image
    UPDATE products SET image_url = (
        SELECT storage_path FROM product_images
        WHERE product_id = v_image.product_id AND status = 'confirmed'
        ORDER BY display_order ASC, created_at ASC LIMIT 1
    ) WHERE id = v_image.product_id;

    RETURN jsonb_build_object(
        'success', true,
        'image_id', v_image.id,
        'storage_path', v_image.storage_path,
        'product_id', v_image.product_id,
        'status', 'confirmed'
    );
END;
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
    delivery_type public.delivery_type DEFAULT 'in_house'::public.delivery_type NOT NULL,
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
-- Name: porter_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.porter_deliveries (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    order_id uuid NOT NULL,
    porter_order_id character varying(100),
    crn character varying(100),
    tracking_url text,
    driver_name character varying(100),
    driver_phone character varying(20),
    vehicle_number character varying(20),
    quoted_fare_paise integer,
    final_fare_paise integer,
    pickup_lat numeric(10,8),
    pickup_lng numeric(11,8),
    drop_lat numeric(10,8),
    drop_lng numeric(11,8),
    porter_status character varying(50),
    estimated_pickup_time timestamp with time zone,
    actual_pickup_time timestamp with time zone,
    estimated_delivery_time timestamp with time zone,
    actual_delivery_time timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: porter_webhooks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.porter_webhooks (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    order_id uuid,
    porter_order_id character varying(100),
    event_type character varying(50) NOT NULL,
    payload jsonb NOT NULL,
    processed_at timestamp with time zone,
    error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: product_images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_images (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    product_id uuid NOT NULL,
    storage_path text NOT NULL,
    original_filename character varying(255) NOT NULL,
    file_size integer NOT NULL,
    mime_type character varying(50) NOT NULL,
    display_order integer DEFAULT 0,
    uploaded_by uuid,
    status character varying(20) DEFAULT 'pending'::character varying,
    upload_token uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT product_images_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'confirmed'::character varying])::text[]))),
    CONSTRAINT product_images_valid_file_size CHECK (((file_size > 0) AND (file_size <= 5242880))),
    CONSTRAINT product_images_valid_mime_type CHECK (((mime_type)::text = ANY ((ARRAY['image/jpeg'::character varying, 'image/png'::character varying, 'image/webp'::character varying])::text[])))
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
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    price_per_kg_paise integer DEFAULT 0 NOT NULL,
    CONSTRAINT products_price_per_kg_paise_check CHECK ((price_per_kg_paise >= 0))
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
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    lat numeric(10,8),
    lng numeric(11,8),
    formatted_address text
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
porter_pickup_lat	"23.0339"	Store latitude for Porter pickup	2026-01-28 13:05:46.561437+00
porter_pickup_lng	"72.5614"	Store longitude for Porter pickup	2026-01-28 13:05:46.561437+00
porter_pickup_address	"2088, Usmanpura Gam, Nr. Kadava Patidar Vadi, Ashram Road, Ahmedabad 380013"	Store address for Porter	2026-01-28 13:05:46.561437+00
porter_pickup_name	"Masala Spice Shop"	Store name for Porter pickup	2026-01-28 13:05:46.561437+00
porter_pickup_phone	"+919876543210"	Store phone for Porter pickup (update this)	2026-01-28 13:05:46.561437+00
\.


--
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.categories (id, name, name_gu, slug, image_url, display_order, is_active, created_at, updated_at) FROM stdin;
a1000000-0000-0000-0000-000000000001	Spices	મસાલા	spices	\N	1	t	2026-01-27 08:16:56.480255+00	2026-01-27 08:16:56.480255+00
a1000000-0000-0000-0000-000000000002	Dried Goods	સુકવણી	dried-goods	\N	2	t	2026-01-27 08:16:56.480255+00	2026-01-27 08:16:56.480255+00
a1000000-0000-0000-0000-000000000003	Powders	પાવડર	powders	\N	3	t	2026-01-27 08:16:56.480255+00	2026-01-27 08:16:56.480255+00
a1000000-0000-0000-0000-000000000004	Spice Mixes	મિશ્ર મસાલા	spice-mixes	\N	4	t	2026-01-27 08:16:56.480255+00	2026-01-27 08:16:56.480255+00
\.


--
-- Data for Name: daily_order_counters; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.daily_order_counters (date, counter) FROM stdin;
2026-01-26	6
2026-01-30	1
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
103.85.8.96	1	2026-01-30 07:00:00+00	2026-01-30 05:08:52.811106+00	2026-01-30 07:34:35.375533+00
172.21.0.1	1	2026-01-30 14:00:00+00	2026-01-26 13:36:52.216721+00	2026-01-30 14:50:53.924572+00
152.58.63.69	1	2026-01-30 16:00:00+00	2026-01-26 15:51:48.860652+00	2026-01-30 16:42:50.464234+00
2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	3	2026-01-27 17:00:00+00	2026-01-26 13:39:18.599272+00	2026-01-27 17:59:32.36901+00
2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	2	2026-01-28 08:00:00+00	2026-01-27 19:06:46.640447+00	2026-01-28 08:50:46.659992+00
\.


--
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.order_items (id, order_id, product_id, weight_option_id, product_name, product_name_gu, weight_label, weight_grams, unit_price_paise, quantity, total_paise, created_at) FROM stdin;
c288953f-82fb-4a0e-8f8f-51aeb9fec5f7	c043f751-aeb8-4e25-aaa9-1050c74dddff	\N	\N	Black Cardamom	મોટી એલચી	50g	50	4500	2	9000	2026-01-26 16:04:41.816041+00
87bb2b75-8088-4162-b01f-13088f3f1f52	c043f751-aeb8-4e25-aaa9-1050c74dddff	\N	\N	Black Cardamom	મોટી એલચી	50g	50	4500	2	9000	2026-01-26 16:04:41.816041+00
295e5aa0-3742-4ced-8aa2-a705a7dc8963	c043f751-aeb8-4e25-aaa9-1050c74dddff	\N	\N	Black Cardamom	મોટી એલચી	50g	50	4500	2	9000	2026-01-26 16:04:41.816041+00
2e092600-8a43-447a-8f08-a7ec5da4cf30	c043f751-aeb8-4e25-aaa9-1050c74dddff	\N	\N	Black Cardamom	મોટી એલચી	50g	50	4500	2	9000	2026-01-26 16:04:41.816041+00
ff0efb1d-1cec-4e8c-9495-47f972f19597	3d6c4aa4-fc1c-4f6a-99e9-59552948b550	5e2837e0-13ae-4d27-9cc5-94c9327c03c8	\N	Whole Turmeric	Haldar Akhi	1kg	1000	22000	2	44000	2026-01-30 14:59:53.289342+00
e8793569-53f3-4559-90ab-9f1e70e26d22	3d6c4aa4-fc1c-4f6a-99e9-59552948b550	32245343-af0c-4856-9c16-9045fa6989fe	\N	Cinnamon	Taj	1kg	1000	60000	1	60000	2026-01-30 14:59:53.289342+00
\.


--
-- Data for Name: order_status_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.order_status_history (id, order_id, from_status, to_status, changed_by, notes, created_at) FROM stdin;
315a2842-51f5-483c-b656-1e1007e79d8e	c043f751-aeb8-4e25-aaa9-1050c74dddff	\N	placed	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Order placed	2026-01-26 16:04:41.819909+00
94a220b1-6da8-4df0-8f85-ced9831fbe2f	c043f751-aeb8-4e25-aaa9-1050c74dddff	placed	confirmed	0f804627-964a-4d3c-8fa3-410d32a7e6c7	\N	2026-01-28 12:17:32.715852+00
3530ff1b-4a02-4d94-a399-70f91f45bc36	c043f751-aeb8-4e25-aaa9-1050c74dddff	confirmed	out_for_delivery	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Porter delivery booked. Order ID: MOCK-1769606426358-peoeac	2026-01-28 13:20:26.367455+00
1a844353-3411-4cb9-995d-f2b213fddc39	c043f751-aeb8-4e25-aaa9-1050c74dddff	confirmed	out_for_delivery	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Porter delivery booked. Order ID: MOCK-1769606447769-e00wg	2026-01-28 13:20:47.776397+00
56772167-0afd-4ef0-92e0-2db5a41cee29	c043f751-aeb8-4e25-aaa9-1050c74dddff	out_for_delivery	delivered	\N	Porter webhook: order_ended	2026-01-28 13:23:16.129217+00
89427c1f-029f-40d1-a282-6758c3cb2755	c043f751-aeb8-4e25-aaa9-1050c74dddff	confirmed	out_for_delivery	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Porter delivery booked. Order ID: MOCK-1769606654610-hds1c2	2026-01-28 13:24:14.619376+00
bef60ad8-18c5-4f21-80af-a99c19566483	c043f751-aeb8-4e25-aaa9-1050c74dddff	out_for_delivery	delivery_failed	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Porter delivery cancelled: Customer requested cancellation	2026-01-28 13:24:30.985324+00
c2dd79ed-9f3a-400c-a699-8619dc5136fc	c043f751-aeb8-4e25-aaa9-1050c74dddff	confirmed	out_for_delivery	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Porter delivery booked. Order ID: MOCK-1769606742560-67pv3	2026-01-28 13:25:42.570121+00
9c6cc780-e990-4442-9192-870ec7b144a2	c043f751-aeb8-4e25-aaa9-1050c74dddff	out_for_delivery	confirmed	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Porter delivery cancelled: Porter unavailable. Returned to dispatch queue for in-house assignment.	2026-01-28 13:26:53.807971+00
8c2caf0c-81b8-4325-9431-ba952423b93d	c043f751-aeb8-4e25-aaa9-1050c74dddff	confirmed	out_for_delivery	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Porter delivery booked. Order ID: MOCK-1769612389468-4hixes	2026-01-28 14:59:49.476688+00
1110d833-bb0b-4949-ba26-631fa58d8086	c043f751-aeb8-4e25-aaa9-1050c74dddff	out_for_delivery	confirmed	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Porter delivery cancelled: Reassigning to in-house. Returned to dispatch queue for in-house assignment.	2026-01-29 03:53:49.17808+00
ef94616a-3065-4d15-8977-15cab75cf6bf	c043f751-aeb8-4e25-aaa9-1050c74dddff	confirmed	out_for_delivery	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Porter delivery booked. Order ID: MOCK-1769658849180-08zzh	2026-01-29 03:54:09.187101+00
604a07c8-85fc-48bb-b1ed-d3d3a3265e1c	c043f751-aeb8-4e25-aaa9-1050c74dddff	out_for_delivery	delivery_failed	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Porter delivery cancelled: Cancelled by admin	2026-01-30 12:15:10.993152+00
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.orders (id, order_number, user_id, status, shipping_name, shipping_phone, shipping_address_line1, shipping_address_line2, shipping_city, shipping_state, shipping_pincode, subtotal_paise, shipping_paise, total_paise, delivery_staff_id, delivery_otp_hash, delivery_otp_expires, customer_notes, admin_notes, cancellation_reason, failure_reason, created_at, updated_at, delivery_type) FROM stdin;
c043f751-aeb8-4e25-aaa9-1050c74dddff	MSS-20260126-006	0f804627-964a-4d3c-8fa3-410d32a7e6c7	delivery_failed	Test User	+919876543210	123 Test Street	\N	Ahmedabad	Gujarat	380001	36000	4000	40000	\N	\N	\N	\N	\N	\N	Cancelled by admin	2026-01-26 16:04:41.812669+00	2026-01-30 12:15:10.990379+00	porter
3d6c4aa4-fc1c-4f6a-99e9-59552948b550	MSS-20260130-001	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	placed	Test Customer	+919999900001	123 Test Street	\N	Ahmedabad	Gujarat	380001	104000	0	104000	\N	\N	\N	\N	\N	\N	\N	2026-01-30 14:46:17.293314+00	2026-01-30 14:59:53.294831+00	in_house
\.


--
-- Data for Name: otp_rate_limits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.otp_rate_limits (phone_number, hourly_count, daily_count, last_reset_hour, last_reset_day, created_at, updated_at) FROM stdin;
+919876543210	1	4	2026-01-30 14:00:00+00	2026-01-30 00:00:00+00	2026-01-26 13:36:52.22373+00	2026-01-30 14:50:53.941034+00
+919999900001	1	1	2026-01-30 16:00:00+00	2026-01-30 00:00:00+00	2026-01-26 14:04:00.658517+00	2026-01-30 16:42:50.47689+00
+919999900002	1	1	2026-01-26 14:00:00+00	2026-01-26 00:00:00+00	2026-01-26 14:04:00.733075+00	2026-01-26 14:04:00.733075+00
\.


--
-- Data for Name: otp_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.otp_requests (id, phone, otp_hash, expires_at, verified, attempts, created_at, ip_address, user_agent, msg91_request_id, delivery_status) FROM stdin;
d2adcb48-77da-433d-8dec-fd482a65c3e9	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 13:38:21.677+00	t	0	2026-01-27 13:33:21.67856+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
04bbad2e-6811-4d13-9c70-f54a83691e1a	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 14:07:53.025+00	t	0	2026-01-27 14:02:53.026193+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
7f1e3745-5e6d-4b7c-b866-e40c68a948b9	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 14:24:08.642+00	t	0	2026-01-27 14:19:08.644398+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
ae1de2b5-74b7-4853-8df1-9c2d0cf2ffd4	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 14:39:50.175+00	t	0	2026-01-27 14:34:50.177151+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
21082baf-82ae-4e82-ad84-3e09d2c67354	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 14:45:02.188+00	t	0	2026-01-27 14:40:02.189811+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
2928f1fc-0b3f-44c0-9955-fdd139d92f22	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 15:04:27.444+00	t	0	2026-01-27 14:59:27.445078+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
64df70a2-6996-4d64-93a9-9d365350fe46	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 17:22:03.849+00	t	0	2026-01-27 17:17:03.850321+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
d36b88e2-ce6c-4c19-9c6c-55dfba064005	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 17:58:03.674+00	t	0	2026-01-27 17:53:03.674975+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
23ac4f71-48c5-4da9-85c0-f39d09d8b60a	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 18:04:32.391+00	t	0	2026-01-27 17:59:32.392511+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
8b8fc14a-0625-43ef-b78e-33852e7fdb57	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 19:11:46.662+00	t	0	2026-01-27 19:06:46.662982+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
9edcf6fe-987d-4bb0-8ea0-551cf34d5849	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 19:16:40.492+00	t	0	2026-01-27 19:11:40.492871+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
101d0aef-ba84-40b7-966c-8d67a09b569e	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-26 20:04:10.758+00	t	0	2026-01-26 19:59:10.759914+00	172.21.0.1	curl/8.5.0	\N	test_phone
1f969dad-bfec-4908-84ab-a1c7c10aa9e3	+919999900001	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-26 20:04:44.917+00	t	0	2026-01-26 19:59:44.918578+00	172.21.0.1	curl/8.5.0	\N	test_phone
71456d76-3ae7-4a53-a102-655517c14b34	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 11:37:17.471+00	t	0	2026-01-27 11:32:17.473259+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
ddb3e98c-c793-4e01-aa14-4a14abf53164	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 11:39:34.323+00	t	0	2026-01-27 11:34:34.324268+00	152.58.63.69	okhttp/4.12.0	\N	test_phone
4e308221-e52b-4588-8909-ee00e8ea20c8	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 13:20:03.75+00	t	0	2026-01-27 13:15:03.751362+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
ff2b2614-2972-42f2-923a-0d56c0a28197	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 13:32:58.791+00	t	0	2026-01-27 13:27:58.792766+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
1867284d-15bd-4a30-8951-b7bcf93dea41	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 13:36:09.788+00	t	0	2026-01-27 13:31:09.789038+00	2409:40c1:5003:fc10:bb24:ec5f:ea6c:b3a0	okhttp/4.12.0	\N	test_phone
d8692d91-e445-498a-b5c5-40a7e574b78c	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 19:31:42.585+00	t	0	2026-01-27 19:26:42.585926+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
2ad2590e-27e0-4085-aa5d-17b796d2af72	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 19:46:25.585+00	t	0	2026-01-27 19:41:25.58615+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
22048039-b475-4bdf-a042-d845d1d2f021	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 20:09:17.461+00	t	0	2026-01-27 20:04:17.462407+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
f4a86345-8d8b-4ab9-924d-a047339ffbfe	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 20:19:34.844+00	t	0	2026-01-27 20:14:34.844657+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
7adf91a0-764d-4c1f-809a-70e9ebe99d9a	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 20:40:01.522+00	t	0	2026-01-27 20:35:01.523584+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
52a0c8f2-5bb9-4c12-a400-2e315e3b4082	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-27 20:43:34.886+00	t	0	2026-01-27 20:38:34.887394+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
7473ed84-4c44-4e7c-8dd0-5b82fd3913f1	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-28 05:42:02.122+00	t	0	2026-01-28 05:37:02.123574+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
eb11f850-1b9f-431a-a7d5-413a8c947e5b	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-28 06:59:03.906+00	t	0	2026-01-28 06:54:03.907265+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
794f644b-634c-4a60-8da5-3b630d957013	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-28 07:53:36.773+00	t	0	2026-01-28 07:48:36.775266+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
993f11db-e0b4-4e99-a3b0-2d503ac6852e	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-28 08:50:09.239+00	t	0	2026-01-28 08:45:09.240375+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
5613627b-e736-4261-802c-acc13e1b7651	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-28 08:55:46.689+00	t	0	2026-01-28 08:50:46.689812+00	2409:40c1:5003:fc10:cc73:3b0e:a68c:1705	okhttp/4.12.0	\N	test_phone
15e1ac4c-93d3-4f91-bcbf-74f7f8dbff32	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-28 14:51:19.527+00	t	0	2026-01-28 14:46:19.529272+00	172.21.0.1	curl/8.5.0	\N	test_phone
a3e9b806-e116-475c-a34d-d55f5086aadf	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-28 15:04:35.605+00	t	0	2026-01-28 14:59:35.606867+00	172.21.0.1	curl/8.5.0	\N	test_phone
e5a51191-4a34-48a6-8974-f1ef6591940f	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-29 05:03:34.776+00	t	0	2026-01-29 04:58:34.777961+00	172.21.0.1	curl/8.5.0	\N	test_phone
17e77be4-bd0a-4ea5-a1d7-88080ea0d72d	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-29 07:04:44.294+00	t	0	2026-01-29 06:59:44.2966+00	172.21.0.1	curl/8.5.0	\N	test_phone
945a5d33-cf70-48f6-9ee2-f725f23bcab3	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-30 05:13:52.838+00	t	0	2026-01-30 05:08:52.839172+00	103.85.8.96	okhttp/4.12.0	\N	test_phone
4b72d166-17da-40e6-9b97-2f37343d7da9	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-30 07:39:35.432+00	t	0	2026-01-30 07:34:35.436+00	103.85.8.96	okhttp/4.12.0	\N	test_phone
f6ca5ab8-bd0c-48d2-bd62-c096d65bb946	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-30 07:46:14.656+00	t	0	2026-01-30 07:41:14.661797+00	172.21.0.1	curl/8.5.0	\N	test_phone
e9b6ceb1-1354-45ce-9f29-f43e127d435f	+919876543210	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-30 14:55:53.956+00	t	0	2026-01-30 14:50:53.958284+00	172.21.0.1	curl/8.5.0	\N	test_phone
d26e2f2f-e474-470f-9866-b33048b74a55	+919999900001	67716c1d25b98652df3e9529591e5f1a575ff9ba02101232f297559b84bd3694	2026-01-30 16:47:50.489+00	t	0	2026-01-30 16:42:50.490082+00	152.58.63.69	okhttp/4.12.0	\N	test_phone
\.


--
-- Data for Name: porter_deliveries; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.porter_deliveries (id, order_id, porter_order_id, crn, tracking_url, driver_name, driver_phone, vehicle_number, quoted_fare_paise, final_fare_paise, pickup_lat, pickup_lng, drop_lat, drop_lng, porter_status, estimated_pickup_time, actual_pickup_time, estimated_delivery_time, actual_delivery_time, created_at, updated_at) FROM stdin;
315b4751-ca1c-4c70-a911-bce64060a3f5	c043f751-aeb8-4e25-aaa9-1050c74dddff	MOCK-1769658849180-08zzh	CRN-MOCK-1769658849180-08zzh	https://porter.in/track/MOCK-1769658849180-08zzh	\N	\N	\N	\N	\N	23.03390000	72.56140000	23.02250000	72.57140000	cancelled	2026-01-29 04:24:09.18+00	\N	2026-01-29 04:54:09.18+00	\N	2026-01-28 13:25:42.562271+00	2026-01-30 12:15:10.986446+00
\.


--
-- Data for Name: porter_webhooks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.porter_webhooks (id, order_id, porter_order_id, event_type, payload, processed_at, error, created_at) FROM stdin;
\.


--
-- Data for Name: product_images; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.product_images (id, product_id, storage_path, original_filename, file_size, mime_type, display_order, uploaded_by, status, upload_token, created_at, updated_at) FROM stdin;
8190bcd5-fa03-44b5-b64e-239f64c88f8c	5e2837e0-13ae-4d27-9cc5-94c9327c03c8	5e2837e0-13ae-4d27-9cc5-94c9327c03c8/1769594755304.png	8d113284-0733-4a90-bd02-01f19d54aedb.png	944161	image/png	0	\N	confirmed	\N	2026-01-28 10:05:56.98397+00	2026-01-28 10:05:57.516059+00
3dd2edb6-2de6-4df2-a578-c7769c9fa5bf	89f27e16-064e-4981-901b-ed91a04f7062	89f27e16-064e-4981-901b-ed91a04f7062/1769785317033.jpg	b722b7fb-a431-43b0-8bb1-bc85208bddad-1_all_35243.jpg	49671	image/jpeg	0	0f804627-964a-4d3c-8fa3-410d32a7e6c7	confirmed	\N	2026-01-30 15:01:57.983762+00	2026-01-30 15:01:57.983762+00
74f48537-d195-48b2-ba0c-3dad1450a701	89f27e16-064e-4981-901b-ed91a04f7062	89f27e16-064e-4981-901b-ed91a04f7062/1769785351372.jpg	b722b7fb-a431-43b0-8bb1-bc85208bddad-1_all_35240.jpg	67259	image/jpeg	1	0f804627-964a-4d3c-8fa3-410d32a7e6c7	confirmed	\N	2026-01-30 15:02:33.293329+00	2026-01-30 15:02:33.293329+00
7008da12-dfb4-48bd-b0d9-84ecf333e1bb	fecbd54a-f72c-4115-a725-5beb2931fa64	fecbd54a-f72c-4115-a725-5beb2931fa64/1769590675855.png	409b2061-28dd-460c-8cd5-db4a10515c9e.png	944161	image/png	0	\N	confirmed	\N	2026-01-28 08:57:58.650342+00	2026-01-30 16:58:32.461401+00
c15f4ba4-4607-43d6-b8ee-830ffc5f8619	fecbd54a-f72c-4115-a725-5beb2931fa64	fecbd54a-f72c-4115-a725-5beb2931fa64/1769590700769.png	a317df83-7b03-4ad7-9af3-7f99900c9841.png	1477546	image/png	1	\N	confirmed	\N	2026-01-28 09:01:48.334013+00	2026-01-30 16:58:32.461401+00
776c769d-f6b6-4148-beea-1aba87033196	fecbd54a-f72c-4115-a725-5beb2931fa64	fecbd54a-f72c-4115-a725-5beb2931fa64/1769591134337.jpeg	02e99189-c5d7-4e58-a2e7-b02059f0a554.jpeg	56923	image/jpeg	2	\N	confirmed	\N	2026-01-28 09:05:34.528326+00	2026-01-30 16:58:32.461401+00
c82a293c-5859-4f91-b475-f395d2745c23	1983e5a5-8b23-4266-8d8c-9f3aa81a578d	1983e5a5-8b23-4266-8d8c-9f3aa81a578d/1769593974360.png	5fb98b35-7786-4dc1-a125-a789dc7fd1df.png	944161	image/png	0	\N	confirmed	\N	2026-01-28 09:53:06.754969+00	2026-01-30 17:00:26.798073+00
c39fce4f-fd89-4fa6-a611-8982f6cc8317	1983e5a5-8b23-4266-8d8c-9f3aa81a578d	1983e5a5-8b23-4266-8d8c-9f3aa81a578d/1769593999373.png	210dac6e-d9c0-431c-8819-9cb04971cef6.png	1477546	image/png	1	\N	confirmed	\N	2026-01-28 09:53:28.826016+00	2026-01-30 17:00:26.798073+00
88659e3e-f584-47c6-94ac-f58f8bd5d4d1	1983e5a5-8b23-4266-8d8c-9f3aa81a578d	1983e5a5-8b23-4266-8d8c-9f3aa81a578d/1769594228519.jpeg	c6627c45-4baa-42bf-a0a8-43b84956e560.jpeg	1910341	image/jpeg	2	\N	confirmed	\N	2026-01-28 09:57:14.122775+00	2026-01-30 17:00:26.798073+00
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.products (id, category_id, name, name_gu, description, description_gu, image_url, is_available, is_active, display_order, search_vector, created_at, updated_at, price_per_kg_paise) FROM stdin;
5e2837e0-13ae-4d27-9cc5-94c9327c03c8	a1000000-0000-0000-0000-000000000001	Whole Turmeric	Haldar Akhi	Dried haldi fingers with a deep golden hue, earthy aroma, and warm, slightly bitter flavor. Grind fresh for the purest turmeric powder. Used in pickling and traditional remedies.	\N	5e2837e0-13ae-4d27-9cc5-94c9327c03c8/1769594755304.png	t	t	4	'akhi':4A 'aroma':14B 'bitter':18B 'deep':10B 'dri':5B 'earthi':13B 'finger':7B 'flavor':19B 'fresh':21B 'golden':11B 'grind':20B 'haldar':3A 'haldi':6B 'hue':12B 'pickl':29B 'powder':26B 'purest':24B 'remedi':32B 'slight':17B 'tradit':31B 'turmer':2A,25B 'use':27B 'warm':16B 'whole':1A	2026-01-27 08:16:56.480255+00	2026-01-29 04:06:52.936067+00	22000
32245343-af0c-4856-9c16-9045fa6989fe	a1000000-0000-0000-0000-000000000001	Cinnamon	Taj	Warm, sweet bark with a comforting woody aroma. A staple in garam masala, biryanis, chai, and curries. Adds gentle sweetness to both savory dishes and desserts.	\N	\N	t	t	39	'add':20B 'aroma':10B 'bark':5B 'biryani':16B 'chai':17B 'cinnamon':1A 'comfort':8B 'curri':19B 'dessert':28B 'dish':26B 'garam':14B 'gentl':21B 'masala':15B 'savori':25B 'stapl':12B 'sweet':4B,22B 'taj':2A 'warm':3B 'woodi':9B	2026-01-27 08:16:56.480255+00	2026-01-28 07:28:14.859766+00	60000
d91f87a4-fd91-49c9-8f76-45c970b9c1ad	a1000000-0000-0000-0000-000000000003	Black Salt Powder	Sanchal Powder	Distinctive smoky-sulphurous mineral salt with an earthy, tangy flavor. A signature ingredient in chaat masala, raitas, chutneys, and refreshing jaljeera drinks.	\N	\N	t	t	6	'black':1A 'chaat':21B 'chutney':24B 'distinct':6B 'drink':28B 'earthi':14B 'flavor':16B 'ingredi':19B 'jaljeera':27B 'masala':22B 'miner':10B 'powder':3A,5A 'raita':23B 'refresh':26B 'salt':2A,11B 'sanchal':4A 'signatur':18B 'smoki':8B 'smoky-sulphur':7B 'sulphur':9B 'tangi':15B	2026-01-27 08:16:56.480255+00	2026-01-30 15:01:32.281231+00	10000
1983e5a5-8b23-4266-8d8c-9f3aa81a578d	a1000000-0000-0000-0000-000000000001	Crushed Chilli (Medium)	Marchu Khandelu (Reshampatti)	Balanced chilli flakes offering moderate heat with good flavor depth. Ideal for those who enjoy warmth without overwhelming spice. Great in curries, stir-fries, and marinades.	\N	1983e5a5-8b23-4266-8d8c-9f3aa81a578d/1769593974360.png	t	t	2	'balanc':7B 'chilli':2A,8B 'crush':1A 'curri':28B 'depth':16B 'enjoy':21B 'flake':9B 'flavor':15B 'fri':31B 'good':14B 'great':26B 'heat':12B 'ideal':17B 'khandelu':5A 'marchu':4A 'marinad':33B 'medium':3A 'moder':11B 'offer':10B 'overwhelm':24B 'reshampatti':6A 'spice':25B 'stir':30B 'stir-fri':29B 'warmth':22B 'without':23B	2026-01-27 08:16:56.480255+00	2026-01-28 09:57:15.521847+00	38000
fecbd54a-f72c-4115-a725-5beb2931fa64	a1000000-0000-0000-0000-000000000001	Crushed Chilli (Local)	Marchu Khandelu (Deshi)	Classic Indian dried red chilli flakes with straightforward heat and rustic flavor. A versatile everyday spice for tadkas, chutneys, pickles, and general seasoning.	\N	fecbd54a-f72c-4115-a725-5beb2931fa64/1769590675855.png	t	t	1	'chilli':2A,11B 'chutney':25B 'classic':7B 'crush':1A 'deshi':6A 'dri':9B 'everyday':21B 'flake':12B 'flavor':18B 'general':28B 'heat':15B 'indian':8B 'khandelu':5A 'local':3A 'marchu':4A 'pickl':26B 'red':10B 'rustic':17B 'season':29B 'spice':22B 'straightforward':14B 'tadka':24B 'versatil':20B	2026-01-27 08:16:56.480255+00	2026-01-29 04:07:27.20117+00	30000
bfb1d26b-6584-41b0-940d-d1f0253614f2	a1000000-0000-0000-0000-000000000001	Crushed Chilli (Kashmiri)	Marchu Khandelu (Kashmiri)	Vibrant deep-red flakes prized for brilliant color and gentle, fruity heat. Perfect for curries, tandoori marinades, and gravies where rich color matters more than spice.	\N	\N	t	t	3	'brilliant':14B 'chilli':2A 'color':15B,29B 'crush':1A 'curri':22B 'deep':9B 'deep-r':8B 'flake':11B 'fruiti':18B 'gentl':17B 'gravi':26B 'heat':19B 'kashmiri':3A,6A 'khandelu':5A 'marchu':4A 'marinad':24B 'matter':30B 'perfect':20B 'prize':12B 'red':10B 'rich':28B 'spice':33B 'tandoori':23B 'vibrant':7B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	50000
9aefe2c6-eaaa-4b2b-87c7-b4cb3371b6c2	a1000000-0000-0000-0000-000000000001	Whole Coriander Seeds	Dhani Akhi	Fragrant sabut dhania with a warm, citrusy, slightly floral aroma. A foundational spice for homemade curry powders, dhana-jeera, and pickling blends. Roast and grind fresh.	\N	\N	t	t	6	'akhi':5A 'aroma':15B 'blend':28B 'citrusi':12B 'coriand':2A 'curri':21B 'dhana':24B 'dhana-jeera':23B 'dhani':4A 'dhania':8B 'floral':14B 'foundat':17B 'fragrant':6B 'fresh':32B 'grind':31B 'homemad':20B 'jeera':25B 'pickl':27B 'powder':22B 'roast':29B 'sabut':7B 'seed':3A 'slight':13B 'spice':18B 'warm':11B 'whole':1A	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	15000
887c27a8-4338-41a5-985d-43239e93a4b1	a1000000-0000-0000-0000-000000000001	Crushed Coriander-Cumin	Dhanajiru Khandelu	A classic Gujarati blend of crushed coriander and cumin in perfect proportion. The essential base seasoning for dals, sabzis, and everyday Indian cooking.	\N	\N	t	t	7	'base':21B 'blend':10B 'classic':8B 'cook':29B 'coriand':3A,13B 'coriander-cumin':2A 'crush':1A,12B 'cumin':4A,15B 'dal':24B 'dhanajiru':5A 'essenti':20B 'everyday':27B 'gujarati':9B 'indian':28B 'khandelu':6A 'perfect':17B 'proport':18B 'sabzi':25B 'season':22B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	28000
ab98651e-c6b2-439b-b181-aa403f680b28	a1000000-0000-0000-0000-000000000004	Buttermilk Masala	Chhash no Masalo	A zesty Gujarati blend of roasted cumin, black salt, and dried herbs. Adds a refreshing tangy kick to chilled buttermilk. Ideal for making traditional masala chaas.	\N	\N	t	t	2	'add':18B 'black':13B 'blend':9B 'buttermilk':1A,25B 'chaa':31B 'chhash':3A 'chill':24B 'cumin':12B 'dri':16B 'gujarati':8B 'herb':17B 'ideal':26B 'kick':22B 'make':28B 'masala':2A,30B 'masalo':5A 'refresh':20B 'roast':11B 'salt':14B 'tangi':21B 'tradit':29B 'zesti':7B	2026-01-27 08:16:56.480255+00	2026-01-30 15:37:46.051322+00	60000
a268dbfc-9fa9-4264-bb61-3d511af92088	a1000000-0000-0000-0000-000000000001	Spiced Coriander-Cumin Mix	Masala Dhanajiru	An elevated dhana-jeera blend enriched with additional warming spices for a more complex, aromatic profile. Stir into dals, curries, raita, and buttermilk for instant depth.	\N	\N	t	t	8	'addit':16B 'aromat':23B 'blend':13B 'buttermilk':31B 'complex':22B 'coriand':3A 'coriander-cumin':2A 'cumin':4A 'curri':28B 'dal':27B 'depth':34B 'dhana':11B 'dhana-jeera':10B 'dhanajiru':7A 'elev':9B 'enrich':14B 'instant':33B 'jeera':12B 'masala':6A 'mix':5A 'profil':24B 'raita':29B 'spice':1A,18B 'stir':25B 'warm':17B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	30000
a9e44a53-7102-4c05-a852-2b326685083e	a1000000-0000-0000-0000-000000000001	Split Mustard Seeds (Yellow)	Rai Khamni	Mild yellow split mustard with gentler, tangy heat perfect for pickles and achaar masalas. Their softer bite and bright color make them ideal for lighter chutneys and preserves.	\N	\N	t	t	12	'achaar':19B 'bite':23B 'bright':25B 'chutney':32B 'color':26B 'gentler':12B 'heat':14B 'ideal':29B 'khamni':6A 'lighter':31B 'make':27B 'masala':20B 'mild':7B 'mustard':2A,10B 'perfect':15B 'pickl':17B 'preserv':34B 'rai':5A 'seed':3A 'softer':22B 'split':1A,9B 'tangi':13B 'yellow':4A,8B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	11000
025ed25d-f7d8-4130-ab29-59e57e1452c9	a1000000-0000-0000-0000-000000000001	Carom Seeds (Ajwain)	Ajmo	Tiny, ridged seeds with a sharp thyme-like flavor and peppery bite. A digestive aid used in parathas, pakoras, and dal tadkas. A little goes a long way.	\N	\N	t	t	14	'aid':20B 'ajmo':4A 'ajwain':3A 'bite':17B 'carom':1A 'dal':26B 'digest':19B 'flavor':14B 'goe':30B 'like':13B 'littl':29B 'long':32B 'pakora':24B 'paratha':23B 'pepperi':16B 'ridg':6B 'seed':2A,7B 'sharp':10B 'tadka':27B 'thyme':12B 'thyme-lik':11B 'tini':5B 'use':21B 'way':33B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	22000
0ea8a5ae-bbb8-432d-9e68-ff3053bcdadb	a1000000-0000-0000-0000-000000000001	Turmeric Powder	Haldar Daleli	Vibrant golden turmeric with warm, earthy flavor and mild peppery note. The cornerstone of Indian cooking, essential for curries, dals, rice, and wellness remedies.	\N	\N	t	t	5	'cook':20B 'cornerston':17B 'curri':23B 'dal':24B 'dale':4A 'earthi':10B 'essenti':21B 'flavor':11B 'golden':6B 'haldar':3A 'indian':19B 'mild':13B 'note':15B 'pepperi':14B 'powder':2A 'remedi':28B 'rice':25B 'turmer':1A,7B 'vibrant':5B 'warm':9B 'well':27B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	30000
bea99d7f-ce6c-4911-94ad-b4fbfe2ac315	a1000000-0000-0000-0000-000000000001	Cumin Seeds	Jiru	Earthy, warm seeds with a distinctive nutty aroma. The backbone of Indian cooking, essential for tadkas, jeera rice, raitas, and spice blends. Dry-roast for best flavor.	\N	\N	t	t	9	'aroma':11B 'backbon':13B 'best':30B 'blend':25B 'cook':16B 'cumin':1A 'distinct':9B 'dri':27B 'dry-roast':26B 'earthi':4B 'essenti':17B 'flavor':31B 'indian':15B 'jeera':20B 'jiru':3A 'nutti':10B 'raita':22B 'rice':21B 'roast':28B 'seed':2A,6B 'spice':24B 'tadka':19B 'warm':5B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	35000
9f20c595-f3c6-43a9-aa61-29a67cf91256	a1000000-0000-0000-0000-000000000001	Cumin Powder	Jiru Powder	Earthy, warm, and slightly smoky ground cumin with a deep aroma. Indispensable in Indian cuisine for seasoning curries, raitas, chaats, and lentil dishes.	\N	\N	t	t	10	'aroma':15B 'chaat':24B 'cuisin':19B 'cumin':1A,11B 'curri':22B 'deep':14B 'dish':27B 'earthi':5B 'ground':10B 'indian':18B 'indispens':16B 'jiru':3A 'lentil':26B 'powder':2A,4A 'raita':23B 'season':21B 'slight':8B 'smoki':9B 'warm':6B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	40000
17fdecc9-b0a3-40d1-980b-3ff5ffcbdc79	a1000000-0000-0000-0000-000000000001	Mustard Seeds	Rai	Bold black-brown seeds with a sharp, pungent bite that mellows into nutty warmth when tempered in hot oil. Essential for tadka, South Indian curries, and pickles.	\N	\N	t	t	11	'bite':13B 'black':6B 'black-brown':5B 'bold':4B 'brown':7B 'curri':29B 'essenti':24B 'hot':22B 'indian':28B 'mellow':15B 'mustard':1A 'nutti':17B 'oil':23B 'pickl':31B 'pungent':12B 'rai':3A 'seed':2A,8B 'sharp':11B 'south':27B 'tadka':26B 'temper':20B 'warmth':18B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	8000
de5abcd4-ab10-4a81-8965-5d84ce0f9acb	a1000000-0000-0000-0000-000000000001	Fenugreek Seeds	Methi	Small, golden-amber seeds with a pleasantly bitter, maple-like flavor. Essential in pickles, tadkas, and spice blends. A staple in South and West Indian cooking.	\N	\N	t	t	13	'amber':7B 'bitter':12B 'blend':23B 'cook':31B 'essenti':17B 'fenugreek':1A 'flavor':16B 'golden':6B 'golden-amb':5B 'indian':30B 'like':15B 'mapl':14B 'maple-lik':13B 'methi':3A 'pickl':19B 'pleasant':11B 'seed':2A,8B 'small':4B 'south':27B 'spice':22B 'stapl':25B 'tadka':20B 'west':29B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	12000
8a26ac11-52c5-43d6-8286-701589510e46	a1000000-0000-0000-0000-000000000001	Sweet Mango Pickle Mix	Golkeri no Masalo	Ready-to-use achaar masala blend for sweet-style aam ka achaar. Combines warming spices with a hint of sweetness. Mix with raw mango and oil for tangy-sweet homemade pickle.	\N	\N	t	t	32	'aam':19B 'achaar':12B,21B 'blend':14B 'combin':22B 'golkeri':5A 'hint':27B 'homemad':40B 'ka':20B 'mango':2A,33B 'masala':13B 'masalo':7A 'mix':4A,30B 'oil':35B 'pickl':3A,41B 'raw':32B 'readi':9B 'ready-to-us':8B 'spice':24B 'style':18B 'sweet':1A,17B,29B,39B 'sweet-styl':16B 'tangi':38B 'tangy-sweet':37B 'use':11B 'warm':23B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	22000
a3019233-53ed-44a4-8ab3-1777bdd3c6b3	a1000000-0000-0000-0000-000000000001	Split Mustard Seeds	Rai na Kuriya	Coarsely split brown rai with sharper, more immediate pungency than whole seeds. A key ingredient in Gujarati and Rajasthani pickles, chutneys, and spice pastes.	\N	\N	t	t	33	'brown':9B 'chutney':27B 'coars':7B 'gujarati':23B 'immedi':14B 'ingredi':21B 'key':20B 'kuriya':6A 'mustard':2A 'na':5A 'past':30B 'pickl':26B 'pungenc':15B 'rai':4A,10B 'rajasthani':25B 'seed':3A,18B 'sharper':12B 'spice':29B 'split':1A,8B 'whole':17B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	10000
9810f9c6-1c25-4dd1-ae5d-0b47cd8d584e	a1000000-0000-0000-0000-000000000001	Split Fenugreek Seeds	Methi na Kuriya	Split methi seeds with a distinctive bitter, maple-like aroma. Used in Gujarati pickles, special masala blends, and traditional remedies. Adds unique depth to achaar mixes.	\N	\N	t	t	34	'achaar':32B 'add':28B 'aroma':17B 'bitter':13B 'blend':24B 'depth':30B 'distinct':12B 'fenugreek':2A 'gujarati':20B 'kuriya':6A 'like':16B 'mapl':15B 'maple-lik':14B 'masala':23B 'methi':4A,8B 'mix':33B 'na':5A 'pickl':21B 'remedi':27B 'seed':3A,9B 'special':22B 'split':1A,7B 'tradit':26B 'uniqu':29B 'use':18B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	14000
d9b6164a-b836-4d15-b60a-ec8ae34e34c6	a1000000-0000-0000-0000-000000000001	Split Coriander Seeds	Dhanakuriya	Dhana dal split from whole coriander, with a mild, citrusy, slightly sweet taste. A popular mukhwas ingredient and light snack. Also used in dry chutneys and spice blends.	\N	\N	t	t	35	'also':25B 'blend':32B 'chutney':29B 'citrusi':14B 'coriand':2A,10B 'dal':6B 'dhana':5B 'dhanakuriya':4A 'dri':28B 'ingredi':21B 'light':23B 'mild':13B 'mukhwa':20B 'popular':19B 'seed':3A 'slight':15B 'snack':24B 'spice':31B 'split':1A,7B 'sweet':16B 'tast':17B 'use':26B 'whole':9B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	16000
e83e7e59-d517-41b5-82c6-c09475ff3302	a1000000-0000-0000-0000-000000000001	Poppy Seeds	Khashkhash	Fine, cream-colored khus khus seeds with a mild, nutty flavor. Used as a thickener in rich Mughlai gravies and kormas, and as a topping for naan and baked goods.	\N	\N	t	t	36	'bake':33B 'color':7B 'cream':6B 'cream-color':5B 'fine':4B 'flavor':15B 'good':34B 'gravi':23B 'khashkhash':3A 'khus':8B,9B 'korma':25B 'mild':13B 'mughlai':22B 'naan':31B 'nutti':14B 'poppi':1A 'rich':21B 'seed':2A,10B 'thicken':19B 'top':29B 'use':16B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	55000
78034add-1f38-4b45-a5fc-c3f5cd55dc86	a1000000-0000-0000-0000-000000000001	Black Pepper	Kala Mari	The king of spices. Sharp, pungent whole peppercorns with a woody aroma. Essential in seasoning blends, marinades, soups, and rasam. Crush fresh for maximum flavor.	\N	\N	t	t	37	'aroma':16B 'black':1A 'blend':20B 'crush':25B 'essenti':17B 'flavor':29B 'fresh':26B 'kala':3A 'king':6B 'mari':4A 'marinad':21B 'maximum':28B 'pepper':2A 'peppercorn':12B 'pungent':10B 'rasam':24B 'season':19B 'sharp':9B 'soup':22B 'spice':8B 'whole':11B 'woodi':15B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	65000
8c447f95-ab26-45f5-af43-1399976b03c7	a1000000-0000-0000-0000-000000000001	Dried Round Chillies	Vaghariya Marcha	Compact, round dried chillies with sharp, concentrated heat. Popular in Gujarati and Rajasthani cuisine for tempering dals and chutneys. Adds rustic flavor and a fiery punch.	\N	\N	t	t	41	'add':25B 'chilli':3A,9B 'chutney':24B 'compact':6B 'concentr':12B 'cuisin':19B 'dal':22B 'dri':1A,8B 'fieri':30B 'flavor':27B 'gujarati':16B 'heat':13B 'marcha':5A 'popular':14B 'punch':31B 'rajasthani':18B 'round':2A,7B 'rustic':26B 'sharp':11B 'temper':21B 'vaghariya':4A	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	35000
f2668d2b-a641-46dc-88e6-6954b5d5923a	a1000000-0000-0000-0000-000000000001	Nutmeg	Jayfal	Whole jaiphal with a warm, sweet, and slightly woody aroma. Grate fresh into biryanis, chai, sweets, and garam masala. A little goes a long way in adding aromatic warmth.	\N	\N	t	t	43	'ad':29B 'aroma':12B 'aromat':30B 'biryani':16B 'chai':17B 'fresh':14B 'garam':20B 'goe':24B 'grate':13B 'jaiphal':4B 'jayfal':2A 'littl':23B 'long':26B 'masala':21B 'nutmeg':1A 'slight':10B 'sweet':8B,18B 'warm':7B 'warmth':31B 'way':27B 'whole':3B 'woodi':11B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	200000
e288e693-92f2-4296-b126-df9737170282	a1000000-0000-0000-0000-000000000001	Star Anise	Badiyan	Beautiful star-shaped pods with a sweet, warm, licorice-like aroma. Adds fragrant depth to biryanis, slow-cooked curries, and chai. Grind into garam masala for aromatic finish.	\N	\N	t	t	45	'add':17B 'anis':2A 'aroma':16B 'aromat':33B 'badiyan':3A 'beauti':4B 'biryani':21B 'chai':27B 'cook':24B 'curri':25B 'depth':19B 'finish':34B 'fragrant':18B 'garam':30B 'grind':28B 'licoric':14B 'licorice-lik':13B 'like':15B 'masala':31B 'pod':8B 'shape':7B 'slow':23B 'slow-cook':22B 'star':1A,6B 'star-shap':5B 'sweet':11B 'warm':12B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	80000
ce01ab70-28dc-481b-99d8-ea77ba9ebdd1	a1000000-0000-0000-0000-000000000001	Dried Fenugreek Leaves	Kasuri Methi	Fragrant, slightly bitter leaves with a unique maple-like aroma. Crush and sprinkle into butter chicken, paneer dishes, and naan dough for an authentic finishing touch.	\N	\N	t	t	46	'aroma':16B 'authent':30B 'bitter':8B 'butter':21B 'chicken':22B 'crush':17B 'dish':24B 'dough':27B 'dri':1A 'fenugreek':2A 'finish':31B 'fragrant':6B 'kasuri':4A 'leav':3A,9B 'like':15B 'mapl':14B 'maple-lik':13B 'methi':5A 'naan':26B 'paneer':23B 'slight':7B 'sprinkl':19B 'touch':32B 'uniqu':12B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	40000
02178503-95bd-44fc-b06a-35f867a64e3f	a1000000-0000-0000-0000-000000000001	Mace	Javantri	Javitri, the delicate lacy covering of nutmeg, with a warm, subtly sweet aroma. Adds elegant depth to Mughlai curries, kormas, biryanis, and desserts.	\N	\N	t	t	47	'add':16B 'aroma':15B 'biryani':23B 'cover':7B 'curri':21B 'delic':5B 'depth':18B 'dessert':25B 'eleg':17B 'javantri':2A 'javitri':3B 'korma':22B 'laci':6B 'mace':1A 'mughlai':20B 'nutmeg':9B 'subt':13B 'sweet':14B 'warm':12B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	250000
56c0b274-d0b7-49da-a7d9-2472ba8f98ae	a1000000-0000-0000-0000-000000000001	Cinnamon (Export)	Taj Export	Superior Ceylon-style cinnamon with delicate, layered bark and a refined, mildly sweet flavor. Ideal for premium spice blends, rich pulaos, and desserts.	\N	\N	t	t	48	'bark':13B 'blend':24B 'ceylon':7B 'ceylon-styl':6B 'cinnamon':1A,9B 'delic':11B 'dessert':28B 'export':2A,4A 'flavor':19B 'ideal':20B 'layer':12B 'mild':17B 'premium':22B 'pulao':26B 'refin':16B 'rich':25B 'spice':23B 'style':8B 'superior':5B 'sweet':18B 'taj':3A	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	90000
9f504bc8-4df3-4214-89ac-f8ea522ea3d2	a1000000-0000-0000-0000-000000000002	Rice Papads	Sarevda	Large traditional papads made from premium rice flour. Roast or deep-fry for a light, crispy accompaniment to any Indian meal. A perfect side dish for dal-rice or thali spreads.	\N	\N	t	t	1	'accompani':21B 'crispi':20B 'dal':32B 'dal-ric':31B 'deep':15B 'deep-fri':14B 'dish':29B 'flour':11B 'fri':16B 'indian':24B 'larg':4B 'light':19B 'made':7B 'meal':25B 'papad':2A,6B 'perfect':27B 'premium':9B 'rice':1A,10B,33B 'roast':12B 'sarevda':3A 'side':28B 'spread':36B 'thali':35B 'tradit':5B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	16000
08c7a2fc-46d0-449b-a563-a9eaa36de9c3	a1000000-0000-0000-0000-000000000002	Small Rice Papads	Disco Sarevda	Bite-sized mini rice papads, perfect for quick frying or roasting. These petite, crispy rounds make a delightful accompaniment to meals or a light snack on their own.	\N	\N	t	t	2	'accompani':25B 'bite':7B 'bite-s':6B 'crispi':20B 'delight':24B 'disco':4A 'fri':15B 'light':30B 'make':22B 'meal':27B 'mini':9B 'papad':3A,11B 'perfect':12B 'petit':19B 'quick':14B 'rice':2A,10B 'roast':17B 'round':21B 'sarevda':5A 'size':8B 'small':1A 'snack':31B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	17000
536a502e-7ada-44dd-8e66-e122f5c1bab7	a1000000-0000-0000-0000-000000000002	Wheat Vermicelli	Ghaun ni Sev	Fine, traditional wheat noodles for both sweet and savory dishes. Make creamy sheer khurma, comforting kheer, or a quick vegetable upma. A versatile pantry staple.	\N	\N	t	t	3	'comfort':20B 'creami':17B 'dish':15B 'fine':6B 'ghaun':3A 'kheer':21B 'khurma':19B 'make':16B 'ni':4A 'noodl':9B 'pantri':29B 'quick':24B 'savori':14B 'sev':5A 'sheer':18B 'stapl':30B 'sweet':12B 'tradit':7B 'upma':26B 'veget':25B 'vermicelli':2A 'versatil':28B 'wheat':1A,8B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	12000
63c3c551-219a-40fb-a6ba-65af1e9f4829	a1000000-0000-0000-0000-000000000002	Dried Potato Chips	Bataka Katri	Sun-dried potato slices ready to deep-fry into crispy golden chips. These traditional snacks puff up beautifully when fried. Perfect for tea-time munching or festive gatherings.	\N	\N	t	t	4	'bataka':4A 'beauti':25B 'chip':3A,19B 'crispi':17B 'deep':14B 'deep-fri':13B 'dri':1A,8B 'festiv':35B 'fri':15B,27B 'gather':36B 'golden':18B 'katri':5A 'munch':33B 'perfect':28B 'potato':2A,9B 'puff':23B 'readi':11B 'slice':10B 'snack':22B 'sun':7B 'sun-dri':6B 'tea':31B 'tea-tim':30B 'time':32B 'tradit':21B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	18000
c65eac30-2a67-4010-b0a4-4e4ee44fa30b	a1000000-0000-0000-0000-000000000002	Potato Wafers (Netted)	Bataka Jalivali	Net-patterned sun-dried potato wafers that fry into delicate, lacy crisps. Their unique lattice design gives extra-light crunch. A stunning snack for parties and tea-time.	\N	\N	t	t	5	'bataka':4A 'crisp':19B 'crunch':28B 'delic':17B 'design':23B 'dri':11B 'extra':26B 'extra-light':25B 'fri':15B 'give':24B 'jalivali':5A 'laci':18B 'lattic':22B 'light':27B 'net':3A,7B 'net-pattern':6B 'parti':33B 'pattern':8B 'potato':1A,12B 'snack':31B 'stun':30B 'sun':10B 'sun-dri':9B 'tea':36B 'tea-tim':35B 'time':37B 'uniqu':21B 'wafer':2A,13B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	22000
166857aa-9391-4cd2-89e1-b3d7c2053a87	a1000000-0000-0000-0000-000000000002	Potato Sticks	Bataka Salivali	Thin-cut sun-dried potato sticks that fry into crunchy, golden sev in minutes. A beloved traditional snack with a satisfying crunch. Ideal for tea-time or as a chaat topping.	\N	\N	t	t	6	'bataka':3A 'belov':22B 'chaat':37B 'crunch':28B 'crunchi':16B 'cut':7B 'dri':10B 'fri':14B 'golden':17B 'ideal':29B 'minut':20B 'potato':1A,11B 'salivali':4A 'satisfi':27B 'sev':18B 'snack':24B 'stick':2A,12B 'sun':9B 'sun-dri':8B 'tea':32B 'tea-tim':31B 'thin':6B 'thin-cut':5B 'time':33B 'top':38B 'tradit':23B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	20000
50fea0a5-67e0-4b3c-b5da-b132012e6c35	a1000000-0000-0000-0000-000000000003	Dry Ginger Powder	Sunth Powder	Finely ground dried ginger with a sharp, warming, and slightly sweet flavor. Widely used in chai, kadha, sweets, and Ayurvedic remedies for digestion and immunity.	\N	\N	t	t	1	'ayurved':25B 'chai':21B 'digest':28B 'dri':1A,8B 'fine':6B 'flavor':17B 'ginger':2A,9B 'ground':7B 'immun':30B 'kadha':22B 'powder':3A,5A 'remedi':26B 'sharp':12B 'slight':15B 'sunth':4A 'sweet':16B,23B 'use':19B 'warm':13B 'wide':18B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	35000
97d1d9c7-27c5-46f9-9b2b-de1b170ede99	a1000000-0000-0000-0000-000000000003	Pipramul Root Powder	Ganthoda Powder	Long pepper root powder with a warm, earthy, mildly peppery taste. A revered Ayurvedic spice used in traditional remedies, herbal formulations, and warming spice blends.	\N	\N	t	t	2	'ayurved':19B 'blend':30B 'earthi':13B 'formul':26B 'ganthoda':4A 'herbal':25B 'long':6B 'mild':14B 'pepper':7B 'pepperi':15B 'pipramul':1A 'powder':3A,5A,9B 'remedi':24B 'rever':18B 'root':2A,8B 'spice':20B,29B 'tast':16B 'tradit':23B 'use':21B 'warm':12B,28B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	60000
726ba094-776a-48ba-a075-4ee07923a1d6	a1000000-0000-0000-0000-000000000003	Baking Soda	Khavana Soda	Pure sodium bicarbonate, a versatile leavening agent. Adds lightness to baked goods, batters, and dhokla. Also used as a tenderizer in marinades and for quick-rising doughs.	\N	\N	t	t	3	'add':12B 'agent':11B 'also':20B 'bake':1A,15B 'batter':17B 'bicarbon':7B 'dhokla':19B 'dough':32B 'good':16B 'khavana':3A 'leaven':10B 'light':13B 'marinad':26B 'pure':5B 'quick':30B 'quick-ris':29B 'rise':31B 'soda':2A,4A 'sodium':6B 'tender':24B 'use':21B 'versatil':9B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	8000
9d15551a-c0aa-481e-9bca-ecfb3b5c8132	a1000000-0000-0000-0000-000000000003	Citric Acid	Limbu na Phool	Food-grade crystalline citric acid with a clean, sharp sourness. Used to add tangy brightness to chutneys, preserves, sherbets, and homemade spice blends.	\N	\N	t	t	4	'acid':2A,11B 'add':19B 'blend':29B 'bright':21B 'chutney':23B 'citric':1A,10B 'clean':14B 'crystallin':9B 'food':7B 'food-grad':6B 'grade':8B 'homemad':27B 'limbu':3A 'na':4A 'phool':5A 'preserv':24B 'sharp':15B 'sherbet':25B 'sour':16B 'spice':28B 'tangi':20B 'use':17B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	15000
5296aa05-9ac2-4542-a029-76747316c44f	a1000000-0000-0000-0000-000000000003	Rock Salt Powder	Sindhav Powder	Finely ground mineral-rich rock salt with a mild, clean flavor. Preferred during fasting rituals, and ideal for chaats, raitas, fruit seasoning, and everyday cooking.	\N	\N	t	t	5	'chaat':25B 'clean':16B 'cook':31B 'everyday':30B 'fast':20B 'fine':6B 'flavor':17B 'fruit':27B 'ground':7B 'ideal':23B 'mild':15B 'miner':9B 'mineral-rich':8B 'powder':3A,5A 'prefer':18B 'raita':26B 'rich':10B 'ritual':21B 'rock':1A,11B 'salt':2A,12B 'season':28B 'sindhav':4A	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	8000
acae9d48-c2b7-4b43-bcbc-71142438fc9d	a1000000-0000-0000-0000-000000000003	Fenugreek Powder	Methi Powder	Slightly bitter, maple-scented ground fenugreek with earthy depth. Adds complexity to curries, pickles, and spice blends. Valued in traditional wellness practices.	\N	\N	t	t	7	'add':15B 'bitter':6B 'blend':22B 'complex':16B 'curri':18B 'depth':14B 'earthi':13B 'fenugreek':1A,11B 'ground':10B 'mapl':8B 'maple-sc':7B 'methi':3A 'pickl':19B 'powder':2A,4A 'practic':27B 'scent':9B 'slight':5B 'spice':21B 'tradit':25B 'valu':23B 'well':26B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	18000
0a8e3bd8-deec-40c7-9d98-60ab3ad51c9d	a1000000-0000-0000-0000-000000000003	Cinnamon Powder	Taj Powder	Warm, sweet, and subtly woody ground cinnamon with a fragrant aroma. Ideal for biryanis, desserts, chai masala, curries, and baked goods. A versatile pantry staple.	\N	\N	t	t	9	'aroma':15B 'bake':24B 'biryani':18B 'chai':20B 'cinnamon':1A,11B 'curri':22B 'dessert':19B 'fragrant':14B 'good':25B 'ground':10B 'ideal':16B 'masala':21B 'pantri':28B 'powder':2A,4A 'stapl':29B 'subt':8B 'sweet':6B 'taj':3A 'versatil':27B 'warm':5B 'woodi':9B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	65000
7ec08b5e-91a9-450e-b0a2-5f28a36b2fdb	a1000000-0000-0000-0000-000000000003	Tomato Powder	Tomato Powder	Dehydrated tomato powder with concentrated, sweet-tangy umami flavor. Adds rich tomato depth to gravies, soups, sauces, dry rubs, and instant spice mixes.	\N	\N	t	t	10	'add':15B 'concentr':9B 'dehydr':5B 'depth':18B 'dri':23B 'flavor':14B 'gravi':20B 'instant':26B 'mix':28B 'powder':2A,4A,7B 'rich':16B 'rub':24B 'sauc':22B 'soup':21B 'spice':27B 'sweet':11B 'sweet-tangi':10B 'tangi':12B 'tomato':1A,3A,6B,17B 'umami':13B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	35000
7844b6a7-0603-400b-a264-7d2c6d75d85e	a1000000-0000-0000-0000-000000000003	Tamarind Powder	Aambali Powder	Tangy, sweet-sour ground tamarind with rich, fruity depth. A convenient alternative to tamarind pulp for chutneys, sambar, rasam, and South Indian dishes.	\N	\N	t	t	11	'aambali':3A 'altern':17B 'chutney':22B 'conveni':16B 'depth':14B 'dish':28B 'fruiti':13B 'ground':9B 'indian':27B 'powder':2A,4A 'pulp':20B 'rasam':24B 'rich':12B 'sambar':23B 'sour':8B 'south':26B 'sweet':7B 'sweet-sour':6B 'tamarind':1A,10B,19B 'tangi':5B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	20000
03688177-85d2-4074-8fd5-8143c4cfced3	a1000000-0000-0000-0000-000000000003	Lemon Powder	Limbu Powder	Dehydrated lemon powder with bright, zesty tartness. A convenient seasoning for chaats, salads, rice dishes, beverages, and dry rubs where fresh lemon is impractical.	\N	\N	t	t	12	'beverag':20B 'bright':9B 'chaat':16B 'conveni':13B 'dehydr':5B 'dish':19B 'dri':22B 'fresh':25B 'impract':28B 'lemon':1A,6B,26B 'limbu':3A 'powder':2A,4A,7B 'rice':18B 'rub':23B 'salad':17B 'season':14B 'tart':11B 'zesti':10B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	25000
7498d892-4cd9-4b3c-aff9-73c3b709d31f	a1000000-0000-0000-0000-000000000003	Psyllium Husk	Isabgul	Natural dietary fiber with a neutral taste and smooth texture. Supports digestive health and regularity. Also used as a binding agent in gluten-free baking and dough preparation.	\N	\N	t	t	13	'agent':24B 'also':19B 'bake':29B 'bind':23B 'dietari':5B 'digest':15B 'dough':31B 'fiber':6B 'free':28B 'gluten':27B 'gluten-fre':26B 'health':16B 'husk':2A 'isabgul':3A 'natur':4B 'neutral':9B 'prepar':32B 'psyllium':1A 'regular':18B 'smooth':12B 'support':14B 'tast':10B 'textur':13B 'use':20B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	25000
7cd82429-0803-4c45-93d9-7325c4a1324b	a1000000-0000-0000-0000-000000000003	Chilli Flakes	Chilli Flakes	Crushed red pepper flakes with bright, lingering heat and rustic texture. Perfect for sprinkling on pizzas, pastas, stir-fries, and adding a fiery kick to marinades and dressings.	\N	\N	t	t	14	'ad':26B 'bright':10B 'chilli':1A,3A 'crush':5B 'dress':33B 'fieri':28B 'flake':2A,4A,8B 'fri':24B 'heat':12B 'kick':29B 'linger':11B 'marinad':31B 'pasta':21B 'pepper':7B 'perfect':16B 'pizza':20B 'red':6B 'rustic':14B 'sprinkl':18B 'stir':23B 'stir-fri':22B 'textur':15B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	40000
fa47dbc9-c2cb-4e5f-a257-481c4925245c	a1000000-0000-0000-0000-000000000003	Oregano	Oregano	Dried Mediterranean oregano with a robust, slightly peppery herbaceous flavor. A must-have for pizzas, pastas, garlic bread, salads, and Italian-inspired seasonings.	\N	\N	t	t	15	'bread':21B 'dri':3B 'flavor':12B 'garlic':20B 'herbac':11B 'inspir':26B 'italian':25B 'italian-inspir':24B 'mediterranean':4B 'must':15B 'must-hav':14B 'oregano':1A,2A,5B 'pasta':19B 'pepperi':10B 'pizza':18B 'robust':8B 'salad':22B 'season':27B 'slight':9B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	50000
89f27e16-064e-4981-901b-ed91a04f7062	a1000000-0000-0000-0000-000000000003	Black Pepper Powder	Mari Powder	Freshly ground black pepper with bold, pungent heat and sharp aroma. The king of spices, essential for seasoning curries, soups, marinades, and everyday cooking.	\N	89f27e16-064e-4981-901b-ed91a04f7062/1769785317033.jpg	t	t	8	'aroma':16B 'black':1A,8B 'bold':11B 'cook':29B 'curri':24B 'essenti':21B 'everyday':28B 'fresh':6B 'ground':7B 'heat':13B 'king':18B 'mari':4A 'marinad':26B 'pepper':2A,9B 'powder':3A,5A 'pungent':12B 'season':23B 'sharp':15B 'soup':25B 'spice':20B	2026-01-27 08:16:56.480255+00	2026-01-30 15:37:14.002093+00	70000
edf4adb0-39e8-4a07-ae6e-f4c62f5e6475	a1000000-0000-0000-0000-000000000003	Onion Powder	Dungli Powder	Finely ground dehydrated onion with concentrated sweetness and savory depth. Blends seamlessly into spice rubs, marinades, gravies, dips, and seasoning mixes.	\N	\N	t	t	16	'blend':15B 'concentr':10B 'dehydr':7B 'depth':14B 'dip':22B 'dung':3A 'fine':5B 'gravi':21B 'ground':6B 'marinad':20B 'mix':25B 'onion':1A,8B 'powder':2A,4A 'rub':19B 'savori':13B 'seamless':16B 'season':24B 'spice':18B 'sweet':11B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	22000
33d972a2-8d86-4689-9c6d-5714e8072184	a1000000-0000-0000-0000-000000000003	Garlic Powder	Lasan Powder	Finely ground dehydrated garlic with smooth, concentrated flavor and pungent aroma. A pantry essential for rubs, marinades, sauces, bread seasoning, and everyday cooking.	\N	\N	t	t	17	'aroma':15B 'bread':23B 'concentr':11B 'cook':27B 'dehydr':7B 'essenti':18B 'everyday':26B 'fine':5B 'flavor':12B 'garlic':1A,8B 'ground':6B 'lasan':3A 'marinad':21B 'pantri':17B 'powder':2A,4A 'pungent':14B 'rub':20B 'sauc':22B 'season':24B 'smooth':10B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	32000
ae6a3e0c-535f-4e07-a47e-3a30fbc858ae	a1000000-0000-0000-0000-000000000003	Onion Flakes	Dungli Flakes	Dehydrated onion pieces with sweet, savory flavor that intensifies when cooked. Add to soups, gravies, stuffings, and dry mixes for rich onion taste with long shelf life.	\N	\N	t	t	18	'add':16B 'cook':15B 'dehydr':5B 'dri':22B 'dung':3A 'flake':2A,4A 'flavor':11B 'gravi':19B 'intensifi':13B 'life':31B 'long':29B 'mix':23B 'onion':1A,6B,26B 'piec':7B 'rich':25B 'savori':10B 'shelf':30B 'soup':18B 'stuf':20B 'sweet':9B 'tast':27B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	28000
7564bc0e-ad9b-479a-90e7-4926f2585f9a	a1000000-0000-0000-0000-000000000003	Garlic Flakes	Lasan Flakes	Dehydrated garlic slices with concentrated, savory-sweet flavor. Rehydrate in cooking or crush into dishes for a convenient garlic punch in soups, stir-fries, and seasonings.	\N	\N	t	t	19	'concentr':9B 'conveni':23B 'cook':16B 'crush':18B 'dehydr':5B 'dish':20B 'flake':2A,4A 'flavor':13B 'fri':30B 'garlic':1A,6B,24B 'lasan':3A 'punch':25B 'rehydr':14B 'savori':11B 'savory-sweet':10B 'season':32B 'slice':7B 'soup':27B 'stir':29B 'stir-fri':28B 'sweet':12B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	30000
48fd2075-e141-4b8a-9a3d-5f07f5bb3dfd	a1000000-0000-0000-0000-000000000001	Tea Masala	Cha no Masalo	A warm, aromatic blend of ginger, cardamom, cinnamon, and clove crafted for Indian masala chai. Add a pinch to your brewing tea for a fragrant, soul-warming cup every time.	\N	\N	t	t	19	'add':21B 'aromat':8B 'blend':9B 'brew':26B 'cardamom':12B 'cha':3A 'chai':20B 'cinnamon':13B 'clove':15B 'craft':16B 'cup':34B 'everi':35B 'fragrant':30B 'ginger':11B 'indian':18B 'masala':2A,19B 'masalo':5A 'pinch':23B 'soul':32B 'soul-warm':31B 'tea':1A,27B 'time':36B 'warm':7B,33B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	120000
37b0caec-bd41-45ca-84e7-a1db4f21840f	a1000000-0000-0000-0000-000000000001	Salted Kokum	Lunavala Kokam	Sun-dried Garcinia indica preserved in salt with a deep tangy-sour flavor. A signature souring agent in Gujarati kadhi, sol kadi, and Konkani fish curries.	\N	\N	t	t	15	'agent':23B 'curri':32B 'deep':15B 'dri':7B 'fish':31B 'flavor':19B 'garcinia':8B 'gujarati':25B 'indica':9B 'kadhi':26B 'kadi':28B 'kokam':4A 'kokum':2A 'konkani':30B 'lunavala':3A 'preserv':10B 'salt':1A,12B 'signatur':21B 'sol':27B 'sour':18B,22B 'sun':6B 'sun-dri':5B 'tangi':17B 'tangy-sour':16B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	25000
220c8803-5d7a-4f41-82d8-53bc57af4ff4	a1000000-0000-0000-0000-000000000001	Tamarind	Aambali	Dense, dried imli block with an intense sour-sweet tang. The essential base for tamarind chutney, sambar, rasam, and pani puri water. Soak and strain for rich pulp.	\N	\N	t	t	16	'aambali':2A 'base':16B 'block':6B 'chutney':19B 'dens':3B 'dri':4B 'essenti':15B 'im':5B 'intens':9B 'pani':23B 'pulp':31B 'puri':24B 'rasam':21B 'rich':30B 'sambar':20B 'soak':26B 'sour':11B 'sour-sweet':10B 'strain':28B 'sweet':12B 'tamarind':1A,18B 'tang':13B 'water':25B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	15000
c5e218e3-7338-4846-b047-e0d6b81532fd	a1000000-0000-0000-0000-000000000001	Crushed Asafoetida	Hing Khandeli	Pungent resin with a strong onion-garlic aroma that mellows into savory umami when cooked. Essential in dal tadkas, sambar, and Jain cuisine. A pinch transforms any dish.	\N	\N	t	t	17	'aroma':13B 'asafoetida':2A 'cook':20B 'crush':1A 'cuisin':28B 'dal':23B 'dish':33B 'essenti':21B 'garlic':12B 'hing':3A 'jain':27B 'khand':4A 'mellow':15B 'onion':11B 'onion-garl':10B 'pinch':30B 'pungent':5B 'resin':6B 'sambar':25B 'savori':17B 'strong':9B 'tadka':24B 'transform':31B 'umami':18B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	150000
843cbd54-fac4-4d9c-8b06-6937f40482b7	a1000000-0000-0000-0000-000000000001	Lentil & Veg Spice Mix	Dal-Shak no Masalo	A versatile dal-sabji masala with a balanced blend of warming spices. Earthy, mildly pungent, and aromatic. Stir into everyday dals, mixed vegetable curries, and sabzis.	\N	\N	t	t	18	'aromat':27B 'balanc':18B 'blend':19B 'curri':34B 'dal':6A,13B,31B 'dal-sabji':12B 'dal-shak':5A 'earthi':23B 'everyday':30B 'lentil':1A 'masala':15B 'masalo':9A 'mild':24B 'mix':4A,32B 'pungent':25B 'sabji':14B 'sabzi':36B 'shak':7A 'spice':3A,22B 'stir':28B 'veg':2A 'veget':33B 'versatil':11B 'warm':21B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	35000
0a224b3c-5a9c-494a-b9c4-c16b90f00260	a1000000-0000-0000-0000-000000000001	Fennel Seeds (Lucknow)	Variyali (Lucknow)	Premium small-grain fennel from Lucknow, prized for exceptional sweetness and delicate aroma. The preferred choice for mukhwas, fine spice blends, and desserts.	\N	\N	t	t	21	'aroma':19B 'blend':27B 'choic':22B 'delic':18B 'dessert':29B 'except':15B 'fennel':1A,10B 'fine':25B 'grain':9B 'lucknow':3A,5A,12B 'mukhwa':24B 'prefer':21B 'premium':6B 'prize':13B 'seed':2A 'small':8B 'small-grain':7B 'spice':26B 'sweet':16B 'variyali':4A	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	30000
e255cdbc-b34a-4766-b55c-8a8d4ad1607e	a1000000-0000-0000-0000-000000000001	Roasted Split Coriander	Dhanadal (Bhagat)	Crunchy roasted dhana dal with a warm, citrusy, toasted flavor. A beloved Gujarati snack on its own or in mukhwas. Also pairs well as a garnish over chaats and salads.	\N	\N	t	t	22	'also':26B 'belov':17B 'bhagat':5A 'chaat':33B 'citrusi':13B 'coriand':3A 'crunchi':6B 'dal':9B 'dhana':8B 'dhanad':4A 'flavor':15B 'garnish':31B 'gujarati':18B 'mukhwa':25B 'pair':27B 'roast':1A,7B 'salad':35B 'snack':19B 'split':2A 'toast':14B 'warm':12B 'well':28B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	18000
6aa93b11-d5dd-4026-bb1e-8b4be3fdec1d	a1000000-0000-0000-0000-000000000001	Sesame Seeds	Tal	Clean, white hulled til seeds with a delicate nutty flavor that intensifies when toasted. Essential for til chikki, ladoo, and dry chutneys. Adds subtle crunch to breads.	\N	\N	t	t	23	'add':26B 'bread':30B 'chikki':21B 'chutney':25B 'clean':4B 'crunch':28B 'delic':11B 'dri':24B 'essenti':18B 'flavor':13B 'hull':6B 'intensifi':15B 'ladoo':22B 'nutti':12B 'seed':2A,8B 'sesam':1A 'subtl':27B 'tal':3A 'til':7B,20B 'toast':17B 'white':5B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	20000
ae81b2ff-2cfb-4a8b-80ac-b5c9cf3f042f	a1000000-0000-0000-0000-000000000001	Black Sesame Seeds	Kala Tal	Nutty, earthy seeds with a richer flavor than white sesame. Used in chutneys, ladoos, and til sweets. Excellent as a garnish for naan, salads, and stir-fries.	\N	\N	t	t	24	'black':1A 'chutney':18B 'earthi':7B 'excel':23B 'flavor':12B 'fri':33B 'garnish':26B 'kala':4A 'ladoo':19B 'naan':28B 'nutti':6B 'richer':11B 'salad':29B 'seed':3A,8B 'sesam':2A,15B 'stir':32B 'stir-fri':31B 'sweet':22B 'tal':5A 'til':21B 'use':16B 'white':14B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	25000
7b8d38f6-d03d-4aef-b5b0-4eb18da69bf2	a1000000-0000-0000-0000-000000000001	Flaxseed Masala	Alsi Masala	Traditional Gujarati condiment of roasted flaxseeds blended with chilli, salt, and spices. Nutty, savory, and mildly spicy. Enjoy with rotla, khichdi, or sprinkle over dal.	\N	\N	t	t	25	'alsi':3A 'blend':11B 'chilli':13B 'condiment':7B 'dal':29B 'enjoy':22B 'flaxse':1A,10B 'gujarati':6B 'khichdi':25B 'masala':2A,4A 'mild':20B 'nutti':17B 'roast':9B 'rotla':24B 'salt':14B 'savori':18B 'spice':16B 'spici':21B 'sprinkl':27B 'tradit':5B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	28000
e0294cee-7bbe-4c4e-ad34-353ba9b2bb0f	a1000000-0000-0000-0000-000000000001	Garlic	Lasan	Premium dehydrated whole garlic with robust, pungent aroma and bold flavor. Rehydrates quickly in cooking. Ideal for curries, tadkas, marinades, and chutneys.	\N	\N	t	t	27	'aroma':10B 'bold':12B 'chutney':24B 'cook':17B 'curri':20B 'dehydr':4B 'flavor':13B 'garlic':1A,6B 'ideal':18B 'lasan':2A 'marinad':22B 'premium':3B 'pungent':9B 'quick':15B 'rehydr':14B 'robust':8B 'tadka':21B 'whole':5B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	15000
bfb0def3-d4be-41ef-a0fe-1b03e927dc84	a1000000-0000-0000-0000-000000000001	Dried Mango Slices	Aamboliya	Sun-dried raw mango slices with intense tangy sourness. The traditional base for authentic Gujarati and Rajasthani aam ka achaar. Ready to use in homemade pickle preparations.	\N	\N	t	t	28	'aam':23B 'aamboliya':4A 'achaar':25B 'authent':19B 'base':17B 'dri':1A,7B 'gujarati':20B 'homemad':30B 'intens':12B 'ka':24B 'mango':2A,9B 'pickl':31B 'prepar':32B 'rajasthani':22B 'raw':8B 'readi':26B 'slice':3A,10B 'sour':14B 'sun':6B 'sun-dri':5B 'tangi':13B 'tradit':16B 'use':28B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	30000
31bda0f9-d514-4fa1-9a1c-2ebf5f8c8b4f	a1000000-0000-0000-0000-000000000001	Dry Mango Powder (Amchur)	Aamboliya Powder	Tangy, fruity powder from sun-dried unripe mangoes. Adds bright sourness to chaats, chutneys, marinades, and vegetable dishes. A citrus-free way to add acidity to any recipe.	\N	\N	t	t	29	'aamboliya':5A 'acid':33B 'add':16B,32B 'amchur':4A 'bright':17B 'chaat':20B 'chutney':21B 'citrus':28B 'citrus-fre':27B 'dish':25B 'dri':1A,13B 'free':29B 'fruiti':8B 'mango':2A,15B 'marinad':22B 'powder':3A,6A,9B 'recip':36B 'sour':18B 'sun':12B 'sun-dri':11B 'tangi':7B 'unrip':14B 'veget':24B 'way':30B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	25000
4770c27a-e36a-453f-a7fa-68ea36ed624c	a1000000-0000-0000-0000-000000000001	Tapioca Pearls	Sabudana	Clean, white sabudana pearls that turn translucent and chewy when soaked. A fasting-day favorite for khichdi, vada, and kheer. High in energy and easy to digest.	\N	\N	t	t	30	'chewi':12B 'clean':4B 'day':18B 'digest':31B 'easi':29B 'energi':27B 'fast':17B 'fasting-day':16B 'favorit':19B 'high':25B 'kheer':24B 'khichdi':21B 'pearl':2A,7B 'sabudana':3A,6B 'soak':14B 'tapioca':1A 'transluc':10B 'turn':9B 'vada':22B 'white':5B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	12000
9dec7b4c-8fa3-4c18-b101-7644af2d1ddd	a1000000-0000-0000-0000-000000000001	Fennel Seeds	Variyali	Sweet, aromatic seeds with a mild licorice flavor. Used in panch phoron, meat curries, and pickles. Equally loved as an after-meal digestive with a refreshing, cooling note.	\N	\N	t	t	20	'after-m':24B 'aromat':5B 'cool':31B 'curri':17B 'digest':27B 'equal':20B 'fennel':1A 'flavor':11B 'licoric':10B 'love':21B 'meal':26B 'meat':16B 'mild':9B 'note':32B 'panch':14B 'phoron':15B 'pickl':19B 'refresh':30B 'seed':2A,6B 'sweet':4B 'use':12B 'variyali':3A	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	20000
6cee05e1-3027-4e41-a385-5a3a8bbffa81	a1000000-0000-0000-0000-000000000001	Coriander Powder	Dhana Powder	Mildly sweet, citrusy ground coriander with a warm, nutty undertone. A foundational spice in Indian cooking, essential for curries, dals, chutneys, and spice blends.	\N	\N	t	t	26	'blend':28B 'chutney':25B 'citrusi':7B 'cook':20B 'coriand':1A,9B 'curri':23B 'dal':24B 'dhana':3A 'essenti':21B 'foundat':16B 'ground':8B 'indian':19B 'mild':5B 'nutti':13B 'powder':2A,4A 'spice':17B,27B 'sweet':6B 'underton':14B 'warm':12B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	25000
c4e3206c-88b6-400a-bc09-df9e37935d56	a1000000-0000-0000-0000-000000000001	Cloves	Laving	Intensely aromatic flower buds with a warm, sweet, and slightly sharp flavor. A pillar of garam masala, biryanis, and chai. Used in marinades and rice dishes.	\N	\N	t	t	38	'aromat':4B 'biryani':20B 'bud':6B 'chai':22B 'clove':1A 'dish':28B 'flavor':14B 'flower':5B 'garam':18B 'intens':3B 'lave':2A 'marinad':25B 'masala':19B 'pillar':16B 'rice':27B 'sharp':13B 'slight':12B 'sweet':10B 'use':23B 'warm':9B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	90000
470b80ec-ce76-4f5c-ac7b-e43fcf956636	a1000000-0000-0000-0000-000000000001	Bay Leaves	Tamalpatra	Aromatic dried leaves with a warm, herbal fragrance. Essential for tempering dals, biryanis, pulaos, and slow-cooked curries. Adds subtle depth to rice dishes and meat preparations.	\N	\N	t	t	40	'add':23B 'aromat':4B 'bay':1A 'biryani':16B 'cook':21B 'curri':22B 'dal':15B 'depth':25B 'dish':28B 'dri':5B 'essenti':12B 'fragranc':11B 'herbal':10B 'leav':2A,6B 'meat':30B 'prepar':31B 'pulao':17B 'rice':27B 'slow':20B 'slow-cook':19B 'subtl':24B 'tamalpatra':3A 'temper':14B 'warm':9B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	12000
8ab78523-41d4-4a43-a7e1-62d5185b0e4f	a1000000-0000-0000-0000-000000000001	Green Cardamom	Ilaychi	Aromatic pods with a warm, sweet, and floral flavor. Prized in biryanis, chai, kheer, and mithai. Adds fragrant depth to both savory dishes and desserts.	\N	\N	t	t	42	'add':20B 'aromat':4B 'biryani':15B 'cardamom':2A 'chai':16B 'depth':22B 'dessert':28B 'dish':26B 'flavor':12B 'floral':11B 'fragrant':21B 'green':1A 'ilaychi':3A 'kheer':17B 'mithai':19B 'pod':5B 'prize':13B 'savori':25B 'sweet':9B 'warm':8B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	280000
e4bef568-330a-4a07-9c49-d26d33b03170	a1000000-0000-0000-0000-000000000001	Black Cardamom	Elcha	Bold, smoky pods with an intense camphor-like aroma. Prized in rich gravies, biryanis, and garam masala blends. Adds deep, earthy warmth to meat curries and festive rice dishes.	\N	\N	t	t	44	'add':23B 'aroma':13B 'biryani':18B 'black':1A 'blend':22B 'bold':4B 'camphor':11B 'camphor-lik':10B 'cardamom':2A 'curri':29B 'deep':24B 'dish':33B 'earthi':25B 'elcha':3A 'festiv':31B 'garam':20B 'gravi':17B 'intens':9B 'like':12B 'masala':21B 'meat':28B 'pod':6B 'prize':14B 'rice':32B 'rich':16B 'smoki':5B 'warmth':26B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	180000
309a7a50-a330-4d83-a163-624846f9ce6f	a1000000-0000-0000-0000-000000000001	Fenugreek Pickle Mix	Methi no Masalo	A ready-to-use spiced blend built around fenugreek seeds for traditional methi achaar. Aromatic, tangy, and perfectly balanced. Mix with oil and lemon for instant pickle.	\N	\N	t	t	31	'achaar':21B 'aromat':22B 'around':15B 'balanc':26B 'blend':13B 'built':14B 'fenugreek':1A,16B 'instant':33B 'lemon':31B 'masalo':6A 'methi':4A,20B 'mix':3A,27B 'oil':29B 'perfect':25B 'pickl':2A,34B 'readi':9B 'ready-to-us':8B 'seed':17B 'spice':12B 'tangi':23B 'tradit':19B 'use':11B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	22000
520a52f4-b585-4e7b-960e-3af0311b97d2	a1000000-0000-0000-0000-000000000004	Sambar Masala	Sambhar Masalo	A traditional South Indian blend of roasted lentils, red chilli, fenugreek, and curry leaves. Imparts authentic tangy-spiced depth to sambar, rasam, and lentil-vegetable stews.	\N	\N	t	t	7	'authent':20B 'blend':9B 'chilli':14B 'curri':17B 'depth':24B 'fenugreek':15B 'impart':19B 'indian':8B 'leav':18B 'lentil':12B,30B 'lentil-veget':29B 'masala':2A 'masalo':4A 'rasam':27B 'red':13B 'roast':11B 'sambar':1A,26B 'sambhar':3A 'south':7B 'spice':23B 'stew':32B 'tangi':22B 'tangy-sp':21B 'tradit':6B 'veget':31B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	50000
d19208f6-ea36-466a-b99c-a353c0d5f67c	a1000000-0000-0000-0000-000000000004	Kitchen King	Kitchen King Masalo	A versatile all-purpose masala combining coriander, fenugreek, turmeric, and aromatic spices. Enhances any vegetable, paneer, or dal dish with balanced, savory depth of flavor.	\N	\N	t	t	8	'all-purpos':8B 'aromat':17B 'balanc':27B 'combin':12B 'coriand':13B 'dal':24B 'depth':29B 'dish':25B 'enhanc':19B 'fenugreek':14B 'flavor':31B 'king':2A,4A 'kitchen':1A,3A 'masala':11B 'masalo':5A 'paneer':22B 'purpos':10B 'savori':28B 'spice':18B 'turmer':15B 'veget':21B 'versatil':7B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	70000
056a9315-9f73-4a0c-a80a-4e3c83305ee3	a1000000-0000-0000-0000-000000000003	Degi Chilli Powder	Degi Marchu (Extra Hot)	Kashmiri-style chilli powder prized for its brilliant red color and gentle warmth. Adds vibrant hue to tandoori dishes, curries, and gravies without overpowering heat.	\N	\N	t	t	20	'add':22B 'brilliant':16B 'chilli':2A,11B 'color':18B 'curri':28B 'degi':1A,4A 'dish':27B 'extra':6A 'gentl':20B 'gravi':30B 'heat':33B 'hot':7A 'hue':24B 'kashmiri':9B 'kashmiri-styl':8B 'marchu':5A 'overpow':32B 'powder':3A,12B 'prize':13B 'red':17B 'style':10B 'tandoori':26B 'vibrant':23B 'warmth':21B 'without':31B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	45000
d759a92d-ce90-4957-b79b-02c16d4a566d	a1000000-0000-0000-0000-000000000004	Dabeli Masala	Dabeli no Masalo	A signature Kutchi-Gujarati blend balancing sweet, spicy, and tangy notes with dried coconut and chilli powders. The essential seasoning for crafting authentic dabeli.	\N	\N	t	t	1	'authent':29B 'balanc':12B 'blend':11B 'chilli':22B 'coconut':20B 'craft':28B 'dabe':1A,3A,30B 'dri':19B 'essenti':25B 'gujarati':10B 'kutchi':9B 'kutchi-gujarati':8B 'masala':2A 'masalo':5A 'note':17B 'powder':23B 'season':26B 'signatur':7B 'spici':14B 'sweet':13B 'tangi':16B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	55000
6681bc7a-7d97-4108-aff3-283af7f76c81	a1000000-0000-0000-0000-000000000004	Chole Masala	Chole Chana no Masalo	A robust, earthy blend of coriander, pomegranate seed powder, and warming spices. Delivers the deep, dark flavor of Punjabi-style chickpea curry. Pairs perfectly with bhatura.	\N	\N	t	t	3	'bhatura':33B 'blend':10B 'chana':4A 'chickpea':28B 'chole':1A,3A 'coriand':12B 'curri':29B 'dark':22B 'deep':21B 'deliv':19B 'earthi':9B 'flavor':23B 'masala':2A 'masalo':6A 'pair':30B 'perfect':31B 'pomegran':13B 'powder':15B 'punjabi':26B 'punjabi-styl':25B 'robust':8B 'seed':14B 'spice':18B 'style':27B 'warm':17B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	65000
fbfdb0cf-0ca5-413c-83f4-1f9162bf413c	a1000000-0000-0000-0000-000000000004	Pav Bhaji Masala	Bhaji Pav no Masalo	A vibrant, tangy-spicy blend featuring Kashmiri chilli, coriander, and amchur. Recreate the iconic Mumbai street-food flavor in your mixed-vegetable bhaji. Best with buttered pav.	\N	\N	t	t	4	'amchur':19B 'best':34B 'bhaji':2A,4A,33B 'blend':13B 'butter':36B 'chilli':16B 'coriand':17B 'featur':14B 'flavor':27B 'food':26B 'icon':22B 'kashmiri':15B 'masala':3A 'masalo':7A 'mix':31B 'mixed-veget':30B 'mumbai':23B 'pav':1A,5A,37B 'recreat':20B 'spici':12B 'street':25B 'street-food':24B 'tangi':11B 'tangy-spici':10B 'veget':32B 'vibrant':9B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	65000
8ff71008-5e27-4ae5-a7f6-3c546b51f4ed	a1000000-0000-0000-0000-000000000004	Biryani Masala	Biryani no Masalo	A fragrant blend of whole and ground spices including bay leaf, mace, and cardamom. Delivers the rich, layered aroma essential to authentic dum biryani preparations.	\N	\N	t	t	5	'aroma':24B 'authent':27B 'bay':15B 'biryani':1A,3A,29B 'blend':8B 'cardamom':19B 'deliv':20B 'dum':28B 'essenti':25B 'fragrant':7B 'ground':12B 'includ':14B 'layer':23B 'leaf':16B 'mace':17B 'masala':2A 'masalo':5A 'prepar':30B 'rich':22B 'spice':13B 'whole':10B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	80000
97ed8a9b-e09a-42a3-affa-a0dd670424c2	a1000000-0000-0000-0000-000000000004	Chaat Masala	Chaat Masalo	A lively mix of amchur, black salt, and cumin with a bold tangy-spicy punch. Sprinkle over fruit, salads, or street-food favorites like pani puri and bhel.	\N	\N	t	t	6	'amchur':9B 'bhel':34B 'black':10B 'bold':16B 'chaat':1A,3A 'cumin':13B 'favorit':29B 'food':28B 'fruit':23B 'like':30B 'live':6B 'masala':2A 'masalo':4A 'mix':7B 'pani':31B 'punch':20B 'puri':32B 'salad':24B 'salt':11B 'spici':19B 'sprinkl':21B 'street':27B 'street-food':26B 'tangi':18B 'tangy-spici':17B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	55000
bf6ebc4b-6afa-4048-81df-6beae1a59c30	a1000000-0000-0000-0000-000000000004	Peri Peri	Peri Peri Masalo	A fiery blend inspired by African-Portuguese cuisine with bird's eye chilli, paprika, garlic, and citrus notes. Adds bold heat and smoky tang to fries, grilled veggies, and snacks.	\N	\N	t	t	9	'add':25B 'african':12B 'african-portugues':11B 'bird':16B 'blend':8B 'bold':26B 'chilli':19B 'citrus':23B 'cuisin':14B 'eye':18B 'fieri':7B 'fri':32B 'garlic':21B 'grill':33B 'heat':27B 'inspir':9B 'masalo':5A 'note':24B 'paprika':20B 'peri':1A,2A,3A,4A 'portugues':13B 'smoki':29B 'snack':36B 'tang':30B 'veggi':34B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	80000
9f3f7980-cbc0-452d-8d60-0233d98a7a5d	a1000000-0000-0000-0000-000000000004	Khichdi Masala	Khichdi no Masalo	A comforting blend of turmeric, cumin, and mild whole spices for the classic rice-and-lentil dish. Adds gentle warmth and aroma to everyday khichdi and light dal preparations.	\N	\N	t	t	10	'add':24B 'aroma':28B 'blend':8B 'classic':18B 'comfort':7B 'cumin':11B 'dal':34B 'dish':23B 'everyday':30B 'gentl':25B 'khichdi':1A,3A,31B 'lentil':22B 'light':33B 'masala':2A 'masalo':5A 'mild':13B 'prepar':35B 'rice':20B 'rice-and-lentil':19B 'spice':15B 'turmer':10B 'warmth':26B 'whole':14B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	50000
2803ec2a-e367-4174-99a7-d2a987d39d91	a1000000-0000-0000-0000-000000000004	Jiralu Powder	Jiralu (Spe. Khakhra)	A traditional Gujarati digestive powder of roasted cumin, black pepper, and hing. Offers warm, earthy flavor that aids digestion. Enjoy after meals or sprinkle over dal and rice.	\N	\N	t	t	11	'aid':23B 'black':14B 'cumin':13B 'dal':31B 'digest':9B,24B 'earthi':20B 'enjoy':25B 'flavor':21B 'gujarati':8B 'hing':17B 'jiralu':1A,3A 'khakhra':5A 'meal':27B 'offer':18B 'pepper':15B 'powder':2A,10B 'rice':33B 'roast':12B 'spe':4A 'sprinkl':29B 'tradit':7B 'warm':19B	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	45000
7b3223ac-a49d-4a5c-a585-71c8cb3293b9	a1000000-0000-0000-0000-000000000004	Vadapav Masala	Vadapav no Masalo	A punchy, garlicky dry spice blend with red chilli, mustard, and hing. Captures the bold flavor of Mumbai's beloved street snack. Dust over vada or mix into dry chutney.	\N	\N	t	t	12	'belov':25B 'blend':11B 'bold':20B 'captur':18B 'chilli':14B 'chutney':35B 'dri':9B,34B 'dust':28B 'flavor':21B 'garlicki':8B 'hing':17B 'masala':2A 'masalo':5A 'mix':32B 'mumbai':23B 'mustard':15B 'punchi':7B 'red':13B 'snack':27B 'spice':10B 'street':26B 'vada':30B 'vadapav':1A,3A	2026-01-27 08:16:56.480255+00	2026-01-27 17:39:51.805776+00	55000
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
a3801538-1198-4f74-8c44-e88afc311990	0f804627-964a-4d3c-8fa3-410d32a7e6c7	c6b7c1499f5bc76276f5bb740df6cbab8393ccbedea6421bbcfab0b8131375ae	2026-02-26 11:32:23.142+00	t	2026-01-27 11:32:23.143409+00
a321cb1c-f390-4e47-b7e4-755932407c55	0f804627-964a-4d3c-8fa3-410d32a7e6c7	a9225006fd153876c76a6c6f029ba1f8942aa8e45d10306607b6f13c9da9a3ef	2026-02-26 11:34:32.575+00	f	2026-01-27 11:34:32.576907+00
93c7e973-8f70-4a76-b645-b1a7b3af664c	0f804627-964a-4d3c-8fa3-410d32a7e6c7	9450947ea6e49a69f4305b68fb875d600989b8c9110f4d163d8a5f48f6ae66e0	2026-02-26 11:34:37.692+00	t	2026-01-27 11:34:37.693014+00
f6ec7d87-2a1e-4464-9013-4043e8989550	0f804627-964a-4d3c-8fa3-410d32a7e6c7	a4623ad6d038b8bff25fc278535de4065a1370abfb1bac9cf57bc4f49abf890c	2026-02-26 13:14:52.901+00	f	2026-01-27 13:14:52.902446+00
345d2bed-9c8a-4671-ba6f-2d1fec7ab072	0f804627-964a-4d3c-8fa3-410d32a7e6c7	7a50f893b6e58ca6487441a4d6412632589ec53a342b7e3188b9f13d77abd7be	2026-02-26 13:15:07.786+00	t	2026-01-27 13:15:07.788584+00
48396088-bf61-4083-a789-20db06cca5f0	0f804627-964a-4d3c-8fa3-410d32a7e6c7	8fb145d2595d58e1b7654a0627e8cd0d962151668b7364cda97c3f9c26852ed2	2026-02-26 13:27:44.407+00	f	2026-01-27 13:27:44.408356+00
d29c883b-6dc7-469d-94b9-e62a57956014	0f804627-964a-4d3c-8fa3-410d32a7e6c7	3318f9ec5505c68b1063019d0972ff2516c535a740bec0490e69915439c86b52	2026-02-26 13:28:07.721+00	t	2026-01-27 13:28:07.722768+00
000f317a-5da7-4fe7-859c-19597d29d8a5	0f804627-964a-4d3c-8fa3-410d32a7e6c7	de60a6a1c0544491bc06f7d5028fc2b875aa56d746d4daf60f461b779acb8d5e	2026-02-26 13:31:05.377+00	f	2026-01-27 13:31:05.379173+00
0ba5ce26-8f7c-4652-9fbe-ab5c38fe8564	0f804627-964a-4d3c-8fa3-410d32a7e6c7	61bbb8355ebb1050cdc1341dcc77f44bbd036c6fd3e9bd2dc60c69a8b49c22f0	2026-02-26 13:31:16.336+00	t	2026-01-27 13:31:16.336774+00
06192927-8b6e-4c09-bddd-93e398af4722	0f804627-964a-4d3c-8fa3-410d32a7e6c7	252816393988e5b445460b8bdb39bcb240f6b13dc5549220c9711c780511f70d	2026-02-26 13:33:16.282+00	f	2026-01-27 13:33:16.284235+00
3340525d-d3ae-491b-b084-657f7310b427	0f804627-964a-4d3c-8fa3-410d32a7e6c7	37f0e9f1dc39c54ab5e6d3bf8b21d43745cca58b041a66cff65cae90507ac45a	2026-02-26 13:33:27.266+00	t	2026-01-27 13:33:27.267501+00
8398d286-a03c-4926-ab34-e8e91c0aff7d	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ae65ddf36f86a1dba4f63821c52c04c9c952ae69d4896df55fc03abe46e069dc	2026-02-25 19:59:15.848+00	f	2026-01-26 19:59:15.850949+00
dd0b0e7a-9b14-43d8-bad1-86aa964f4816	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	e68c611701af5e0a552880d8eb782747097a01e3ddeb1e3e25a32d34351dd4a6	2026-02-25 19:59:44.942+00	f	2026-01-26 19:59:44.943715+00
de12d209-b48e-4a9c-8247-1c507c489e06	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	6faa308d81a38512ef469101dd74c4369a67e26c68c057ce3acd73db194a7aec	2026-02-25 19:59:49.785+00	f	2026-01-26 19:59:49.786429+00
b7a45ef8-c46a-4b63-a468-33d42da4471d	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	26e5b03bc27b1881bae92c08f532ee8865aa701c59e226bfd59321bb9f9c166f	2026-02-26 05:59:39.392+00	f	2026-01-27 05:59:39.394971+00
a310fa14-7ac3-4e80-9279-a0adc95ac3c0	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	a827b8214c62ae94fd6303b0813953e20d0afda7dae5eb0ec94e2b578bbb8a35	2026-02-26 06:00:26.445+00	f	2026-01-27 06:00:26.446929+00
7c5d2c2e-b608-4951-b08e-acccf56fb0c3	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	57f5d38f333d2a1efa62747476a9ba9e88c9f153400626bcbb45117ebe0c1aad	2026-02-26 06:01:13.835+00	f	2026-01-27 06:01:13.836528+00
86598680-b61c-472c-a8ee-1d1d4adf0300	0f804627-964a-4d3c-8fa3-410d32a7e6c7	48e7a99c5d650bb2ec89b6d2d542cb73c3bd496ba85d73a779e2e961be646e5d	2026-02-26 13:35:16.717+00	t	2026-01-27 13:35:16.718267+00
ca82f17e-eeae-4550-b4fb-d6ff5cb665e1	0f804627-964a-4d3c-8fa3-410d32a7e6c7	86607d21783728d9f9f72480e5b243e463f9dc204ad0bd63fda05e46857bd35b	2026-02-26 13:35:43.664+00	t	2026-01-27 13:35:43.664803+00
b0e2e8de-365a-4d62-9348-044231036a35	0f804627-964a-4d3c-8fa3-410d32a7e6c7	32e2bb261ace1a1648398e17ab5afbdc6b12e0e82ded31249c694fa6f3645902	2026-02-26 13:35:48.905+00	t	2026-01-27 13:35:48.905993+00
86862c15-1459-4d06-9a55-aa2a70ce6a1f	0f804627-964a-4d3c-8fa3-410d32a7e6c7	3308c9b189fa1321097b4c249e8424a4312fe3f987e50ca160a0161c39540da6	2026-02-26 14:02:47.771+00	f	2026-01-27 14:02:47.772819+00
45a7d980-3a5f-4fae-a48a-5cf2790b3ad5	0f804627-964a-4d3c-8fa3-410d32a7e6c7	5ed5844f0fe94f0be168a7b92658c8b2dda6c2806a61c7973dec5be568799dcb	2026-02-26 14:03:01.282+00	t	2026-01-27 14:03:01.284529+00
22374b26-5948-447e-a897-3d465fec8c2e	0f804627-964a-4d3c-8fa3-410d32a7e6c7	82a03f697afb3730559b70432b23e02a18c20d09044036cd03f8ba362695c378	2026-02-26 14:19:04.783+00	f	2026-01-27 14:19:04.784013+00
538df8ff-760f-49e7-a179-e868b2270f80	0f804627-964a-4d3c-8fa3-410d32a7e6c7	8998a68a25df8da15cabfb0cabdaad38fda50d5864539ffc83c5f72380cf6cb3	2026-02-26 14:19:12.302+00	t	2026-01-27 14:19:12.304045+00
2fedc053-d603-47d9-a80c-75089cbde08c	0f804627-964a-4d3c-8fa3-410d32a7e6c7	224dd60f22bb2f8a5dd66b610f077fb9089a7dafe8e8bfd7064793fb9a96fdbd	2026-02-26 14:34:27.759+00	f	2026-01-27 14:34:27.760695+00
99a500b3-7eac-4ef1-aa61-27ca19a24fac	0f804627-964a-4d3c-8fa3-410d32a7e6c7	4eeb74d3903749d72747a73a15be780de2c5c9801058e9712ebd18ef5434a70a	2026-02-26 14:34:56.439+00	t	2026-01-27 14:34:56.440571+00
b84c9123-4a6d-4b43-89f7-087bba47c3c5	0f804627-964a-4d3c-8fa3-410d32a7e6c7	4e316e608a803a89aecec416347ee2929cf936702e899fd22ac53518085e9638	2026-02-26 14:39:58.143+00	f	2026-01-27 14:39:58.144811+00
d7a7d79d-951b-46f3-9170-df5f474321bf	0f804627-964a-4d3c-8fa3-410d32a7e6c7	853433b616f738a4f6b04dcb40ea07fa3baafa9cf62b8ecc99a4f558761b1727	2026-02-26 14:40:08.401+00	t	2026-01-27 14:40:08.403195+00
66732a6b-55a4-44ff-a198-007b4c2da894	0f804627-964a-4d3c-8fa3-410d32a7e6c7	d834d7db0f893db38ba360bfe79ce4d7c1fa1d9e9c1ee47e8078f251e5a22422	2026-02-26 14:46:58.051+00	f	2026-01-27 14:46:58.052769+00
972bbb29-ae1a-4058-b961-64e8d2093a91	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ce2c83e82c41254398f4105e66caf9c2e6b49188ca97951dc5189e1e4a103a2e	2026-02-26 15:00:01.15+00	t	2026-01-27 15:00:01.151695+00
a43669c7-3d18-4c42-9d39-e3421c63e978	0f804627-964a-4d3c-8fa3-410d32a7e6c7	4c4233553b43c6c780ead91c1966bb5484e073877240a7eed4df61ca89ba7add	2026-02-26 17:09:50.493+00	t	2026-01-27 17:09:50.49397+00
b250f9c9-e3ab-485f-8a97-09227db3972c	0f804627-964a-4d3c-8fa3-410d32a7e6c7	cf3d8c6c079082b9c22faa430d74234221d05d19a9f36e01cd106593c2371764	2026-02-26 17:09:51.32+00	t	2026-01-27 17:09:51.324281+00
bdb5abef-c894-464a-88e7-c264923979c4	0f804627-964a-4d3c-8fa3-410d32a7e6c7	7e1e50230bb7b791a6b0ff386abb67ec813f62ef36421e6f817d41b551cbcae4	2026-02-26 17:10:55.033+00	t	2026-01-27 17:10:55.034258+00
ac107157-817e-477b-9936-e181fb5d021e	0f804627-964a-4d3c-8fa3-410d32a7e6c7	210eefbb3b38b17387daa4d80db2ff1cd09152399b50992915f8ada7e91cbf56	2026-02-26 17:13:35.58+00	t	2026-01-27 17:13:35.582818+00
b245bb07-f110-4c44-ab9f-1ea3f05358c3	0f804627-964a-4d3c-8fa3-410d32a7e6c7	cabfd98f6fe841c3a07b0f2b702affa0863cc50879fb5204d17922cc805d1489	2026-02-26 17:16:41.677+00	f	2026-01-27 17:16:41.680332+00
2f8d2863-8352-4254-b13f-f6b71f79ec5c	0f804627-964a-4d3c-8fa3-410d32a7e6c7	f6074957cb9591b23e94c23e43723089b9ade6d2c68fdf8951665952c40ab6df	2026-02-26 17:17:09.698+00	t	2026-01-27 17:17:09.698751+00
07ad0f60-fbda-4b96-825a-082e36d4b478	0f804627-964a-4d3c-8fa3-410d32a7e6c7	4475288f1773a0a1b59b58eaede9f924079c5dab9ffac4e5dfcbe1215a3d6fd3	2026-02-26 17:52:56.509+00	f	2026-01-27 17:52:56.51028+00
0eb819ac-02ed-49b9-a9d7-ed3e2cd513e8	0f804627-964a-4d3c-8fa3-410d32a7e6c7	fe7c95b553be0525a469811e8f4cf5764b0316b7e7c9dbb5b80b0d5e6d86d62d	2026-02-26 17:53:07.754+00	t	2026-01-27 17:53:07.755571+00
e2ba225b-65d8-4515-b6b9-9e003521a11b	0f804627-964a-4d3c-8fa3-410d32a7e6c7	05e9e3806d2ededf952a32f96fd7ad4f7d977328b6946cb36a1871492e66b7c5	2026-02-26 17:59:07.599+00	f	2026-01-27 17:59:07.600042+00
c1337e03-c0e7-44b0-a2a0-5263cb04aa4b	0f804627-964a-4d3c-8fa3-410d32a7e6c7	b5fd34793ac2d97f309c382e4f379c75cb5822b2d68adcfc5019e56265512753	2026-02-26 17:59:39.766+00	t	2026-01-27 17:59:39.76766+00
dc021b39-0693-429a-9f4e-6b07074d905e	0f804627-964a-4d3c-8fa3-410d32a7e6c7	9832eb80bec96b131aaac1183ba48f236256a11cc827d59efa9a8f848560e992	2026-02-26 19:06:42.177+00	f	2026-01-27 19:06:42.180274+00
b4a44c02-968d-4fa0-bead-1d033e3e2bc7	0f804627-964a-4d3c-8fa3-410d32a7e6c7	40eb01b83183d7c970e637c4f41093aa082da7104834fc82afcaf04cfa535fc9	2026-02-26 19:06:56.3+00	t	2026-01-27 19:06:56.30107+00
cdbf2ad9-38af-4e94-92b5-b3f71ef866e5	0f804627-964a-4d3c-8fa3-410d32a7e6c7	92d5d8bdcb3b714ec71b95d43945a858c1ef0dfeca01edb13f350c96f2a782e1	2026-02-26 19:10:42.677+00	f	2026-01-27 19:10:42.678219+00
546aa1b9-50cf-4d8f-b638-26f3b4ec6fe2	0f804627-964a-4d3c-8fa3-410d32a7e6c7	7b4fa74fcafccb44b95d5df785e05249cfdfa6ddd9ed37c494a4023c82be49c1	2026-02-26 19:11:54.207+00	t	2026-01-27 19:11:54.207748+00
225b134d-283d-4142-b71f-bdbb3022015a	0f804627-964a-4d3c-8fa3-410d32a7e6c7	e322cf7f82241530d7159c68ecfe28d5ac796f107b7675bf896f1325a2340caf	2026-02-26 19:25:45.937+00	f	2026-01-27 19:25:45.938718+00
4991bfc8-4ee8-4854-8bd1-878c7364369a	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2c15ccd1838e5dc4a48944bff1a4ba8f3174f5890aab48a00a6247b79d3b0ac1	2026-02-26 19:26:46.704+00	t	2026-01-27 19:26:46.705049+00
16b20efc-9693-4bc3-94f3-678fcb01e0d7	0f804627-964a-4d3c-8fa3-410d32a7e6c7	884f2d0a5eca7fd7110018c9df536af6bcafe661ee6ca06c970dc662f7b9076b	2026-02-26 19:40:46.2+00	f	2026-01-27 19:40:46.201337+00
172f34ae-a495-43cb-a5af-b1262149dba0	0f804627-964a-4d3c-8fa3-410d32a7e6c7	9ad5238b7c1e412853d8cc495be9013435799e7bb926e179727949d23b629738	2026-02-26 19:41:30.574+00	t	2026-01-27 19:41:30.57533+00
4bb9a113-ff80-4778-9b12-79df9dba9b7b	0f804627-964a-4d3c-8fa3-410d32a7e6c7	65c3d541b39f9c77e35c6a76b4a9278a6b6dd0cadb2fc6d20b4c3971cbca2432	2026-02-26 20:04:14.395+00	f	2026-01-27 20:04:14.395971+00
e3e6110d-ee3e-437f-ad9a-f25c8a58af86	0f804627-964a-4d3c-8fa3-410d32a7e6c7	c158dfd4da4a06af42d54dcb630313ed950faa6dbace4c89d39649e5cdfbd1d5	2026-02-26 20:04:23.517+00	t	2026-01-27 20:04:23.518827+00
5f9a529c-9423-4c55-a7bb-84670ebaccce	0f804627-964a-4d3c-8fa3-410d32a7e6c7	51d077a244c5dc68120b3f4fe51da682ff1c840ab5ad2a51f781b0211a50c37b	2026-02-26 20:14:31.333+00	f	2026-01-27 20:14:31.334526+00
b1abfc41-05a8-493a-b073-6e7e76bd5934	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2ec65f0dea6bd47d6e88c1a9e8dc4d25fd8c92eb4ccd046a4ba9807e1b9bbbef	2026-02-26 20:14:38.748+00	t	2026-01-27 20:14:38.749054+00
f11d8754-14ec-4c82-a4dc-b81ad6980d6f	0f804627-964a-4d3c-8fa3-410d32a7e6c7	27cba643986dcf86c4059d6f4116cc4ea4007ff565464a15d3ebfc4ef9620d45	2026-02-26 20:17:59.855+00	t	2026-01-27 20:17:59.856155+00
4fe12293-0987-46b2-8bd0-2e18590c27e0	0f804627-964a-4d3c-8fa3-410d32a7e6c7	55786a4a6b367b0a3ddfce07ce7c631e56177427f24e2da03e5e522351abc7e5	2026-02-26 20:18:11.552+00	t	2026-01-27 20:18:11.553487+00
a18a7b91-5877-4b8d-8560-22603e13ec1b	0f804627-964a-4d3c-8fa3-410d32a7e6c7	bc0f5c49f5f3ad13d705178dd3dee196bb104a87f8ad55b04bda3ad0282f1ba4	2026-02-26 20:19:19.731+00	f	2026-01-27 20:19:19.732516+00
152f18d9-119b-4ed2-8cd1-25c64dda72ba	0f804627-964a-4d3c-8fa3-410d32a7e6c7	8c4dafc9e6d3ccf3097e2fe9f78ff815a58b48a76bb14d92843ad1c07b0d9ccc	2026-02-26 20:35:06.117+00	t	2026-01-27 20:35:06.11831+00
f1838083-6a34-4969-b515-fa51c3003729	0f804627-964a-4d3c-8fa3-410d32a7e6c7	90c693c53526460ea6da24aa07c9433e04e7cb3169bbddedb5603dd58738fc15	2026-02-26 20:36:13.088+00	f	2026-01-27 20:36:13.089235+00
a1f94ec5-fbf9-43ac-ae83-bdbfe281ee9a	0f804627-964a-4d3c-8fa3-410d32a7e6c7	653e86cc995ce3e5f90d131d913be29038984bca8a00f270e9da5fd67781411d	2026-02-26 20:38:39.231+00	t	2026-01-27 20:38:39.232418+00
4661e735-7327-438c-af5d-c10dbc867321	0f804627-964a-4d3c-8fa3-410d32a7e6c7	6edd25ffc485061a5a763a78603a69f369800ef5db06573a15ddc723e6f4c56e	2026-02-26 20:40:28.4+00	t	2026-01-27 20:40:28.401445+00
6e9871fb-a537-4bf9-bc7f-fcf5b2dd0be9	0f804627-964a-4d3c-8fa3-410d32a7e6c7	4207ad6b2d8c4b47f41ae31700eb1be0d4938f68ba4336fde34c21ec5a98ece1	2026-02-26 20:40:40.983+00	t	2026-01-27 20:40:40.986629+00
d4ae2788-5ac4-478f-bf89-7871ac1d4a41	0f804627-964a-4d3c-8fa3-410d32a7e6c7	7ea1668217f2c585fb68028008465890614fa4c3844cf14719021a35e27475ff	2026-02-26 21:07:25.323+00	t	2026-01-27 21:07:25.324159+00
5daeda91-0a00-47e1-955c-312c38350333	0f804627-964a-4d3c-8fa3-410d32a7e6c7	1ef4ceaceb84420635be6d9f8be0acfb45192c08631291c27a83d90286386336	2026-02-26 21:24:23.073+00	t	2026-01-27 21:24:23.074469+00
d226b7c2-44fe-42b3-bdb2-3f91fd347f64	0f804627-964a-4d3c-8fa3-410d32a7e6c7	259acc5365c173518c65b5ed2d6b0622ca33670234986b456fbf8fb04cac34fc	2026-02-26 21:29:40.457+00	t	2026-01-27 21:29:40.45839+00
c6921ecb-9a22-45cf-9c86-373b3b3de597	0f804627-964a-4d3c-8fa3-410d32a7e6c7	1e528612c4c18df7e8561f92a1a9bcd6831d3d94dd423cf03c9d3a6f21e00cce	2026-02-26 21:30:25.408+00	t	2026-01-27 21:30:25.409178+00
a38ee93c-bd01-46bf-9190-0a0f3a80ccb2	0f804627-964a-4d3c-8fa3-410d32a7e6c7	1e8c2ff9889897ec5d3806c5c99f8d9adc1b119d4c7f144b82945a62faaa930f	2026-02-26 21:30:41.428+00	t	2026-01-27 21:30:41.429362+00
87f30475-2060-41d1-a9be-157215fb14fa	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2c1228787cd478df6116d3bcacecfdc0968ca0272f942dc11c388734ee143496	2026-02-26 21:31:04.827+00	t	2026-01-27 21:31:04.827852+00
d5edbb2c-3c9c-4432-88ea-56e3b1ba0546	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ef22f2b651b27893ab25aa4ecc13c338f7a1af0e3b115053bceac584dae947ca	2026-02-26 21:31:11.51+00	t	2026-01-27 21:31:11.511617+00
0d338a41-875e-4e78-bda2-36df0cf08067	0f804627-964a-4d3c-8fa3-410d32a7e6c7	f9010f4432c96ed762a5f078221cfe67da80487b9cb66e68bff7f986ebc27ae4	2026-02-26 21:40:06.987+00	t	2026-01-27 21:40:06.988683+00
006d0d06-337e-4d40-b7e6-c0c37e7fa519	0f804627-964a-4d3c-8fa3-410d32a7e6c7	4b71719252768d2b3751b760a3e35b5eb46cad9dcd54197117cbed9eb244be49	2026-02-26 21:50:05.638+00	t	2026-01-27 21:50:05.6397+00
63c33c6b-2ab5-4771-81ad-3b022587e101	0f804627-964a-4d3c-8fa3-410d32a7e6c7	986528251234e808d0af84077cf80ee81d9e898c9c035abb3d76e977626da380	2026-02-26 21:53:21.607+00	t	2026-01-27 21:53:21.608145+00
7dc546c0-c42c-4f94-8fe9-27a3be29d2ee	0f804627-964a-4d3c-8fa3-410d32a7e6c7	37d1049d927d93190ecddb3cfbef81df5d9f0ad37fcaa40914835fc4811dc976	2026-02-27 04:47:31.226+00	t	2026-01-28 04:47:31.227979+00
10ac63f3-c2ec-4bbc-95f1-1663e308b1dc	0f804627-964a-4d3c-8fa3-410d32a7e6c7	6ee803c140b5f4692694aef8507ae77263b15ab8d2fdf29e30f69621aeec2230	2026-02-27 05:17:48.56+00	f	2026-01-28 05:17:48.561546+00
4038e214-41b8-4da8-8891-3960dfea27fd	0f804627-964a-4d3c-8fa3-410d32a7e6c7	829fb89285986832ae0870ff8b3e7936a8829c963cc7d0e9d7b12dbd22260fa5	2026-02-27 05:37:10.103+00	t	2026-01-28 05:37:10.1048+00
faf21ba7-52ea-45f7-944f-c06863ec0e50	0f804627-964a-4d3c-8fa3-410d32a7e6c7	29d152ccd4aa341878673f32ccf205c332cf4d98fe62fc4b0c0b6b4cdadbeb0d	2026-02-27 06:39:13.322+00	f	2026-01-28 06:39:13.323695+00
628509c9-51b5-41b3-9c8a-04fdca94f62c	0f804627-964a-4d3c-8fa3-410d32a7e6c7	07f11d715d500a7814a15bea473283eddf0d8da6f9f41a71bfae539dc9479611	2026-02-27 06:36:56.816+00	t	2026-01-28 06:36:56.817645+00
a7e9c989-b875-4f0c-9ffe-372eed4884e9	0f804627-964a-4d3c-8fa3-410d32a7e6c7	367868e7cfdd2df04d8380dec772503af8fe10db578ca0fbb1b17218a5d1c059	2026-02-27 06:42:16.581+00	t	2026-01-28 06:42:16.582365+00
9408edb3-472d-4359-8772-81e8dad16cd6	0f804627-964a-4d3c-8fa3-410d32a7e6c7	38f536ce8fcfb7d9377644d14d88aa8bbe644b2fc62e378c4d4360ddd15e1364	2026-02-27 06:47:49.15+00	t	2026-01-28 06:47:49.151241+00
07567c82-957d-4d39-a190-afdbc8710eda	0f804627-964a-4d3c-8fa3-410d32a7e6c7	9d9f5f80bc1c85d895a734d577a394f58bce6657e4251224dd6e5f028fc5051c	2026-02-27 06:49:39.557+00	t	2026-01-28 06:49:39.558725+00
0bb01fe5-8027-46d1-996a-c3c265aa607e	0f804627-964a-4d3c-8fa3-410d32a7e6c7	0deaee7d32a8c4918dfc21d8ebdd1b9680783b1205bf180d471174fba3b706dd	2026-02-27 06:54:01.693+00	f	2026-01-28 06:54:01.694761+00
fd676d08-00e2-404d-befc-1bd8860c8e64	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ce974f68071ea3b1c7e5706c21e6d4a40e9a66c3a7aa76612d42c41c17a6b2f0	2026-02-27 06:54:08.345+00	t	2026-01-28 06:54:08.34665+00
a80e421c-20e4-497e-bc9f-ab310a04a0eb	0f804627-964a-4d3c-8fa3-410d32a7e6c7	bf6e7a9736500d7751a9c6e39fdc433077b8cc9c8a0007097d3c371f900e9f5e	2026-02-27 07:46:32.343+00	t	2026-01-28 07:46:32.343884+00
5283308b-0414-4daa-a110-0413edd63888	0f804627-964a-4d3c-8fa3-410d32a7e6c7	8354667ec411b1724274ce81f1847674deceb500c16bb2e4c6317317dbc90981	2026-02-27 07:48:34.897+00	f	2026-01-28 07:48:34.898439+00
afde1493-07a0-4ea1-8094-7d835cdbf6ee	0f804627-964a-4d3c-8fa3-410d32a7e6c7	4b9e866754dd4fc4e4810e8b4de7bef585b4367dda6a6527f1ef6ef58fad0dfc	2026-02-27 07:48:41.815+00	t	2026-01-28 07:48:41.816379+00
b7a1186f-c0e7-4351-82a9-a6dc5ce97c8d	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ec80a981ba5bd9561e4c54ca0452e5c92e6926963b6e444afaa17faa60a35073	2026-02-27 07:56:09.844+00	t	2026-01-28 07:56:09.844965+00
976ff7f5-e8b3-409d-b0e1-50e7df5e449a	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ff11b99bfdd3745d0fc0c99aab3b347c358499461b0094b1e90addfaaf4569f1	2026-02-27 08:41:55.052+00	t	2026-01-28 08:41:55.053454+00
2e201350-6716-4a30-93c2-738a9e214a66	0f804627-964a-4d3c-8fa3-410d32a7e6c7	21be7b83998dd3e188cb3c272c0004756cea3b2df76218fe870360dccd3d1f78	2026-02-27 08:45:02.583+00	f	2026-01-28 08:45:02.585064+00
4780ad26-517c-4a61-b775-0fc82ba7f056	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2b0f30a5b26ef06e5e310c4edbde85640d43407215019c9a57a26b2d2fa5b55e	2026-02-27 08:45:14.606+00	t	2026-01-28 08:45:14.606938+00
56d14337-e123-4230-acd3-bd3c541e608d	0f804627-964a-4d3c-8fa3-410d32a7e6c7	e2059d9455b8d7c0c9ba019d1f16305e56aa72e10ad2ccab94693a600722a90b	2026-02-27 08:49:30.693+00	t	2026-01-28 08:49:30.694844+00
46a43a76-2628-44f6-97d1-886c40a5dda8	0f804627-964a-4d3c-8fa3-410d32a7e6c7	66955a7205449b9f958e73225a752b5e8a6a1de1ddc7ab69f6f1b6f679640c9a	2026-02-27 08:50:24.861+00	t	2026-01-28 08:50:24.862479+00
738820ca-4c1a-4238-bc78-d55305e9a3e5	0f804627-964a-4d3c-8fa3-410d32a7e6c7	a137e5ac4bf656f9a63bf8aecdcd17aea7bb7edd5d288a98a887f4f872244c83	2026-02-27 08:50:33.474+00	f	2026-01-28 08:50:33.475091+00
8d280136-a3b9-4143-8aba-eaf13651854b	0f804627-964a-4d3c-8fa3-410d32a7e6c7	c0b418ecfa9192fa983d628eed7a546816f0d36692540419a6181de6025a6495	2026-02-27 08:50:52.293+00	t	2026-01-28 08:50:52.295147+00
a098a3f4-06e0-4811-83c9-fc87d4143acc	0f804627-964a-4d3c-8fa3-410d32a7e6c7	8ff424629c1ece2a9a1fe6d7bcc60d77f4eef4e58b3600a6795bc78c80a53d8d	2026-02-27 09:51:22.781+00	t	2026-01-28 09:51:22.781728+00
87a90778-7b44-4e3d-9c70-6fa6635e428a	0f804627-964a-4d3c-8fa3-410d32a7e6c7	810d84ed84b92df6da0889c1cc8bbfe8d0d5a1a6744d67603306a2689768eb2e	2026-02-27 09:52:38.188+00	t	2026-01-28 09:52:38.19014+00
d576c6ce-99ac-413a-958d-f81f99d5ff84	0f804627-964a-4d3c-8fa3-410d32a7e6c7	d5a1b8e47c7fa40f9a1ea51bdc4898a37cea81a2e17b45fad7e114165a480261	2026-02-27 10:05:15.209+00	t	2026-01-28 10:05:15.210686+00
f42ee7a9-ce81-4a78-acce-cffdca426950	0f804627-964a-4d3c-8fa3-410d32a7e6c7	258757b95b966aebd1af9ff9204f82084c13003a1cc25456af822b9e0df76d52	2026-02-27 10:16:27.751+00	t	2026-01-28 10:16:27.752514+00
1136534b-03b9-47e7-9201-5462551e143d	0f804627-964a-4d3c-8fa3-410d32a7e6c7	39a5a0fa4e33c96c860fadbcf9e19d6f4f56decb9a972ba41da9d244d5b8905a	2026-02-27 10:18:39.24+00	t	2026-01-28 10:18:39.241887+00
07444596-3472-4eb3-bff3-b1a04f339ad1	0f804627-964a-4d3c-8fa3-410d32a7e6c7	73fee7b5f15d522154e276edce6ba1e1b19317e793b0146aa92d42a046bdd3b7	2026-02-27 10:23:18.597+00	t	2026-01-28 10:23:18.598051+00
a6afb5a8-6587-4c1c-9787-54414265a63a	0f804627-964a-4d3c-8fa3-410d32a7e6c7	1256487a2915c5db475000012c064b4cb4ae26416b0ceda7b8199d9f926834cc	2026-02-27 12:16:37.811+00	t	2026-01-28 12:16:37.812236+00
911a7da5-9007-44b3-8829-4fcf0db0d560	0f804627-964a-4d3c-8fa3-410d32a7e6c7	a3453588621c2eb47422bc1b21ebf6c0a05cf287268124eed3c154c5eb021131	2026-02-27 12:18:50.114+00	t	2026-01-28 12:18:50.115963+00
c5cf215a-786f-4d64-8d1d-77b2eb9b3539	0f804627-964a-4d3c-8fa3-410d32a7e6c7	08d090517f23dfc2e4a158b29e2dce01da0f5f8fe4e8fb7e7d510641814f6837	2026-02-27 12:21:15.492+00	t	2026-01-28 12:21:15.493885+00
84c21ba2-3f24-41b9-87e3-d34ec6cd3374	0f804627-964a-4d3c-8fa3-410d32a7e6c7	0dd414707b0454b084a981229b4edf7d2e3c098363a9fa4efc943ed6be954266	2026-02-27 12:21:25.507+00	t	2026-01-28 12:21:25.508344+00
126aca8b-bc4e-4f3d-85d8-aeee347329a6	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ac6b062b3a569ee86fd6ea08d1a097eefa05bfa9d32ba76b80ad1e34a4bd6844	2026-02-27 14:46:30.216+00	f	2026-01-28 14:46:30.217242+00
f130c73c-273d-4654-a4bc-69e4adcf6d6e	0f804627-964a-4d3c-8fa3-410d32a7e6c7	66aa884ca72dad6cca0cb4eff806740a4e934643d378bbc349390700ceb4fac8	2026-02-27 12:22:09.601+00	t	2026-01-28 12:22:09.602958+00
afc3a784-332e-4bae-9101-01f033fcc610	0f804627-964a-4d3c-8fa3-410d32a7e6c7	e0eb1ce656feb8c912581a887dc8c0bd44acfb6cb7c7cb607dd49d8f2af4cfcf	2026-02-27 14:56:57.977+00	t	2026-01-28 14:56:57.9781+00
f9944114-99ce-49cd-8e3b-0d79bc232397	0f804627-964a-4d3c-8fa3-410d32a7e6c7	31a827d72a77112b2dec0327c44c01a5cadce479bdc7a8026d87237dc9048f7e	2026-02-27 14:59:39.897+00	f	2026-01-28 14:59:39.898659+00
5ed7e57c-d7fe-42cb-9525-e4abd46b367c	0f804627-964a-4d3c-8fa3-410d32a7e6c7	676855e63c35bdca6d8d0c3104e369c5255f67d14aa469f0c8c8bc1cf01286ed	2026-02-27 14:57:55.41+00	t	2026-01-28 14:57:55.411192+00
61780505-9977-4866-9a8e-b7817030fdce	0f804627-964a-4d3c-8fa3-410d32a7e6c7	a0cfe68637d54df4983e55c9b69f93805c0d85b929d8ff9d9e61f7f89f82ac65	2026-02-28 03:53:49.045+00	t	2026-01-29 03:53:49.046115+00
2e93188d-d261-480a-80d1-f225c001be05	0f804627-964a-4d3c-8fa3-410d32a7e6c7	48b7980d7bd3efe0b5c6b03a64dcb32c15da2553212f0201430f87aafaf97066	2026-02-28 04:00:38.613+00	t	2026-01-29 04:00:38.614454+00
92e22572-32e7-4237-b715-4f3c33deb193	0f804627-964a-4d3c-8fa3-410d32a7e6c7	12bb76884be26051da6b7082ce2bd0491c9dcd1f99cf4487b045a9b3a197f7ac	2026-02-28 04:02:12.588+00	t	2026-01-29 04:02:12.590506+00
cee97a2b-9e3f-40b3-8633-3864c03be1d8	0f804627-964a-4d3c-8fa3-410d32a7e6c7	bbb134cdd26b1e8df0d29719d18319c7ea337dbf86a2ac15c4cc778137afe526	2026-02-28 04:58:37.465+00	f	2026-01-29 04:58:37.466453+00
bc679271-1377-4164-a369-cad8c07897ae	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ea85f300539e267590c134371f3318596b1cf0bc36404125c1ac0d3ecbe91764	2026-02-28 04:02:17.252+00	t	2026-01-29 04:02:17.253655+00
e4def41a-7aa8-4f5f-a9ca-31226372b1b6	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ff172bc12448ec51597378d7f3725dd4c8793ac0e9369f5b5124de4ff4f5f4b2	2026-02-28 05:46:31.675+00	t	2026-01-29 05:46:31.676905+00
6e830e2e-00b7-4e45-862c-5e3d2647ace0	0f804627-964a-4d3c-8fa3-410d32a7e6c7	40da4e93c25164dae6f7885dfb6bffbf6d84767c95948b71c5452781f26e8e1a	2026-02-28 06:10:55.725+00	t	2026-01-29 06:10:55.727101+00
d2986648-3c19-493a-8bed-bf52d469e24b	0f804627-964a-4d3c-8fa3-410d32a7e6c7	07a3b9ba3fb47f58bd0fb9b8b774986a796e4fcabb2628e854b4ae4640f2cef0	2026-02-28 06:17:59.081+00	t	2026-01-29 06:17:59.082539+00
ec56b624-9150-4dcc-b47d-7789324ae281	0f804627-964a-4d3c-8fa3-410d32a7e6c7	48eb2b04c8c76a19567f01533f4968ab8db35b798d59b82c68bb57f19ebe1471	2026-02-28 06:50:17.248+00	t	2026-01-29 06:50:17.249481+00
24aa4d1e-b184-4ae4-8483-bc15e4e424db	0f804627-964a-4d3c-8fa3-410d32a7e6c7	0ca9825c1e189de9efb713b4a28d9811ae3a0f9b2843068c45824d064e6684af	2026-02-28 06:59:48.908+00	f	2026-01-29 06:59:48.910179+00
e5a65f5a-74c7-4be7-9de6-48ead3b64cf9	0f804627-964a-4d3c-8fa3-410d32a7e6c7	8478b934313a463a49f0b6b62ab5dda47c7db426d4132a1f58d6cb95b339ca8a	2026-02-28 06:55:55.523+00	t	2026-01-29 06:55:55.524503+00
13e920df-1549-46d3-a3fd-e9f25f503139	0f804627-964a-4d3c-8fa3-410d32a7e6c7	af7a38027cceb570417ca238088fe3c3c8ea8f704dc33b06d6f5fd57e6af9b92	2026-02-28 07:03:34.305+00	t	2026-01-29 07:03:34.306003+00
d2e5a24c-9928-48e7-a061-fa4bcb06035f	0f804627-964a-4d3c-8fa3-410d32a7e6c7	c5aeb985f0e39fe30e7de18f19198738072f0cedea00a9cd1385a1241898f63a	2026-02-28 07:42:29.592+00	t	2026-01-29 07:42:29.593487+00
8f89b6e7-33bd-41e9-963f-4c0cd10cdfd8	0f804627-964a-4d3c-8fa3-410d32a7e6c7	21025004efe75a9867bc7fcd53e3e1643642664476f8c649d81a20f4cfad3cc9	2026-02-28 07:45:02.299+00	t	2026-01-29 07:45:02.300969+00
3ac2c942-ecfd-4112-a380-d8d614f372e5	0f804627-964a-4d3c-8fa3-410d32a7e6c7	a31418cf29954704305f766ac376e611964698043cff564d62654a87ef175e2b	2026-02-28 07:45:03.29+00	t	2026-01-29 07:45:03.291536+00
da3d0abe-78c9-4835-8634-61db7445379d	0f804627-964a-4d3c-8fa3-410d32a7e6c7	28d4254109c21333bbb0fd82bc9b28877ce8d247b1b597e6d2ab63d9f9962d17	2026-02-28 07:46:50.073+00	t	2026-01-29 07:46:50.074868+00
9c86d7a3-6d3d-4496-a1a4-038d090d1b1c	0f804627-964a-4d3c-8fa3-410d32a7e6c7	14a443dd3fad59ae42befdb65abd586ad8046630fe38c536f11ab63fd14543d3	2026-02-28 08:22:34.763+00	t	2026-01-29 08:22:34.763969+00
9be15583-6948-4383-a199-4b3b65a93c6e	0f804627-964a-4d3c-8fa3-410d32a7e6c7	bcadcb42b579bbe8dbe8a8e6011da9c5c72dbd26bce1ccf24070ea54795f99d8	2026-02-28 08:23:15.668+00	t	2026-01-29 08:23:15.669236+00
d1d07e09-e431-482b-843d-11e917273d84	0f804627-964a-4d3c-8fa3-410d32a7e6c7	42cfa145782772360947191681cf4d5180a8b5af9a4465ee686ed8d12e91063b	2026-02-28 08:23:16.717+00	t	2026-01-29 08:23:16.717836+00
435e5621-c327-4553-b566-69cfc19ee04b	0f804627-964a-4d3c-8fa3-410d32a7e6c7	6d99d237ba8e93e2797a592ce46bdb4581e5047f12c2ffa2d8c76430650592a9	2026-02-28 08:46:09.322+00	t	2026-01-29 08:46:09.323296+00
c28e8da9-e6f4-4c00-a53c-267ff1ac921f	0f804627-964a-4d3c-8fa3-410d32a7e6c7	7f0d05bc835d79c487ee2f761bdb690fdd5cec7b3deed122e388260f9b7f8000	2026-02-28 10:58:29.389+00	t	2026-01-29 10:58:29.390723+00
3ec10309-61cf-4794-b086-e4d9936433fd	0f804627-964a-4d3c-8fa3-410d32a7e6c7	b06f7157003283210090d9c5d76b8b5b76ebb4bc78b467605570f9ab539a5587	2026-02-28 11:54:24.579+00	t	2026-01-29 11:54:24.579959+00
f04a633b-6794-489b-b1c8-f9c3c1133e3c	0f804627-964a-4d3c-8fa3-410d32a7e6c7	7d4c5ed587bc8952e28b5fde25afdc65fc2fd2da3633c70415c317baae080e1b	2026-02-28 14:30:04.624+00	t	2026-01-29 14:30:04.625863+00
d01f909e-1956-4849-9868-c33048a1982f	0f804627-964a-4d3c-8fa3-410d32a7e6c7	87c7a04370a05155652d597d97283b9085c29cc5b10c96aa980f4a16792c4754	2026-02-28 14:48:24.177+00	t	2026-01-29 14:48:24.178777+00
343797a1-a694-4dad-afa9-78401e1971af	0f804627-964a-4d3c-8fa3-410d32a7e6c7	d5f22a4b24e179c7f43c96c9f2cebb24830e53602cdf095d2cb2bc44345f1678	2026-02-28 15:10:17.613+00	t	2026-01-29 15:10:17.614387+00
a69205df-b066-4411-a668-67ba58a10e3a	0f804627-964a-4d3c-8fa3-410d32a7e6c7	f857972d6abbbc824b9d0a6fad1ccf7547cb6f80f28952518c1d4838f80190fd	2026-02-28 15:20:38.216+00	t	2026-01-29 15:20:38.216845+00
3a80cf7b-42cc-4370-b650-341cd78a618b	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ab644513756e378d4837beef31436bfc5455719a609d1282214531b14761d789	2026-02-28 15:25:32.643+00	t	2026-01-29 15:25:32.643947+00
aaba3899-0a71-4342-8315-29077c671538	0f804627-964a-4d3c-8fa3-410d32a7e6c7	e577b5747f12e988869f78d166418bfe62419e4d11058577890f055d4e26b74f	2026-02-28 15:34:16.658+00	t	2026-01-29 15:34:16.659241+00
4c0ed97a-ea79-4a5f-b3ba-c6ac23d1cd98	0f804627-964a-4d3c-8fa3-410d32a7e6c7	adb489e129caa33c85d3c0edc1a216476d41cbcbe13036fae7f6ccd7a8e97570	2026-02-28 15:34:28.076+00	t	2026-01-29 15:34:28.077921+00
c165204f-f3bf-4230-9e9e-b2e50dc6b0c0	0f804627-964a-4d3c-8fa3-410d32a7e6c7	df83d87e66540a450a72c360eadec72f8425731c0f5c9769cb9ed650dd3f6f32	2026-02-28 15:34:38.819+00	t	2026-01-29 15:34:38.819981+00
ed551830-0572-414e-996f-2f397b2fc251	0f804627-964a-4d3c-8fa3-410d32a7e6c7	f01d9e2b7c71336739b79e0625a5ca1ae6dfca52b3c87bd4275a5ecb06f0a576	2026-02-28 15:34:59.926+00	f	2026-01-29 15:34:59.927274+00
bd761989-8b0c-46ac-9211-07de482f4b34	0f804627-964a-4d3c-8fa3-410d32a7e6c7	b38cc066e7982b3a0ff7d90aaf77733bfdb94de5f658b63391e15e38ca156e21	2026-03-01 05:09:01.223+00	t	2026-01-30 05:09:01.225466+00
ac1b6348-ebeb-4479-8351-dd7295fc917c	0f804627-964a-4d3c-8fa3-410d32a7e6c7	d3f9bce9621debb08fff6ad610f8c030743d447ea95a752b665f4273b8c1e862	2026-03-01 07:26:13.629+00	t	2026-01-30 07:26:13.630123+00
c26289a2-1172-46f7-833c-be0308ec598a	0f804627-964a-4d3c-8fa3-410d32a7e6c7	767f8f57bc017bed0df79c25b0db6fbf55ff249b549749e1d6ab87deb42e8368	2026-03-01 07:27:57.95+00	t	2026-01-30 07:27:57.951004+00
e37b3429-fd27-482b-8c81-f2f4f0d40273	0f804627-964a-4d3c-8fa3-410d32a7e6c7	fa4b7796162737fb9112c9dfb8043bf3f5275786d870c54c6c5218ec4ed4b1a2	2026-03-01 07:34:07.27+00	f	2026-01-30 07:34:07.271779+00
cb1bf22b-470a-4c95-ba9a-faa5fa9509b5	0f804627-964a-4d3c-8fa3-410d32a7e6c7	63ee6f6673b0abe10d3960ddf73d224aec726968f2660728e7b84998d786e358	2026-03-01 07:41:14.689+00	f	2026-01-30 07:41:14.690928+00
220a398a-c654-4450-8508-78ce7703f3c9	0f804627-964a-4d3c-8fa3-410d32a7e6c7	223440204fda5e902075b7f7193610a40dc7da5ceba27fc8ce16cfc0e03b957d	2026-03-01 07:34:41.769+00	t	2026-01-30 07:34:41.770588+00
e3e343c5-d1ee-4042-81cc-616da193ea61	0f804627-964a-4d3c-8fa3-410d32a7e6c7	ca5c16f83a387a7c6f744da5867026d0e5cdf8afba18e373574b690e16441c9a	2026-03-01 08:54:55.079+00	t	2026-01-30 08:54:55.080645+00
79408aae-7507-43c0-bca0-c09e463d42b1	0f804627-964a-4d3c-8fa3-410d32a7e6c7	7299d9691063e85b9697de3b4d3e88232415798b9f932247255d4abe12fcf2c6	2026-03-01 12:15:09.776+00	t	2026-01-30 12:15:09.777736+00
dbb71e41-29ff-49d9-9e0d-66d68e6f791d	0f804627-964a-4d3c-8fa3-410d32a7e6c7	d4253e1a2f701ce1ba5fa1f6ee96b12492c94c141bd5546c91b1c0720a91dafb	2026-03-01 13:38:43.962+00	t	2026-01-30 13:38:43.963452+00
df072186-084c-4e44-ba48-fa6578dbed22	0f804627-964a-4d3c-8fa3-410d32a7e6c7	af7ca55bb50d64428d72942b69c9c7151a05b5374246d420b790dcc8ba6f0abb	2026-03-01 13:55:41.704+00	t	2026-01-30 13:55:41.708447+00
88c0b854-767d-4b40-b396-983c0d24f6c7	0f804627-964a-4d3c-8fa3-410d32a7e6c7	c21f0f0956c052429e426ab805d64e2fee09c3a2c0751021bcb5999107765478	2026-03-01 13:59:55.337+00	t	2026-01-30 13:59:55.338497+00
5aa1eb50-4d83-4f53-96a1-358cb5bced92	0f804627-964a-4d3c-8fa3-410d32a7e6c7	02f2263462c8287f4f5d94a8b9d65d488aa36cc763563ec13864a961c06134cd	2026-03-01 14:03:43.403+00	t	2026-01-30 14:03:43.404659+00
d970590c-edc0-4495-90d0-e2ef9b7dceb9	0f804627-964a-4d3c-8fa3-410d32a7e6c7	8950b1272d9385a4cd365187572141b21b7f806510f82ab6b6e398a9011552c4	2026-03-01 14:13:36.415+00	t	2026-01-30 14:13:36.416351+00
592a0948-86bf-4d5f-a9a4-0042c807b34e	0f804627-964a-4d3c-8fa3-410d32a7e6c7	404f995a671ed6d637025f31e815622f0beee412310469806ad9b106e7872a6d	2026-03-01 14:44:13.207+00	t	2026-01-30 14:44:13.208559+00
cd748a33-438f-4b70-86da-48d2b44775c7	0f804627-964a-4d3c-8fa3-410d32a7e6c7	70f7b641f2fef07e4c0fb033907762f340375e764d245ab3b7b80421636b515b	2026-03-01 14:51:07.024+00	f	2026-01-30 14:51:07.025177+00
db40c8b3-a634-4b36-86cb-cb6059696293	0f804627-964a-4d3c-8fa3-410d32a7e6c7	85d0bbdfee71ad55cecbc0db37f9bf0442cab55d1ea146db5880463141076223	2026-03-01 14:47:43.904+00	t	2026-01-30 14:47:43.90559+00
778444ec-33d7-434d-afc5-b23a577b1978	0f804627-964a-4d3c-8fa3-410d32a7e6c7	9fb1528b77cbeab2522ac2515dc45683a10fe13f20b0d51e4213a60aceab357c	2026-03-01 15:08:07.19+00	t	2026-01-30 15:08:07.191113+00
0f1fdc72-0695-42f0-b87a-ac44270c87dc	0f804627-964a-4d3c-8fa3-410d32a7e6c7	41d646a626105c2c6fc58c45b18de2456383d1265a782e0ebe9d9772d0f1cc7a	2026-03-01 15:11:42.621+00	t	2026-01-30 15:11:42.622777+00
3eb739cd-ce86-4f29-94dd-39fad4d2fa7d	0f804627-964a-4d3c-8fa3-410d32a7e6c7	4aad87845dfc82253a01010d4b4ab4c48e362876342562308b8233e0b4ceaf9a	2026-03-01 15:33:01.999+00	t	2026-01-30 15:33:02.000546+00
8f89fc91-7fc5-4b90-b6c2-8f60f794e929	0f804627-964a-4d3c-8fa3-410d32a7e6c7	e31ab2d79111afbabcc041a75fe5bd2b57f7f31136115cd2e413ba198fcee02c	2026-03-01 16:09:46.824+00	t	2026-01-30 16:09:46.825192+00
997e4f8e-0c35-40a5-878e-1b21fb59c0cb	0f804627-964a-4d3c-8fa3-410d32a7e6c7	843ef7937f2830055f1e2818a7415401a055fb6725519c438f33dc920b77a9c2	2026-03-01 16:16:00.386+00	f	2026-01-30 16:16:00.387601+00
6a3ba15a-86e2-4dc3-aff3-2747940638c7	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	40931655b3749d6ad54f6aac770338d60bd224ed35cc29b6db1b4c6832672fb3	2026-03-01 16:42:54.955+00	t	2026-01-30 16:42:54.957363+00
92ea5557-9797-4dcd-aa41-0b29f13d8291	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	1e80f24cf8b737b0ff559d7f48bfd6eb6a2f1bfeffd980d4041aeb0b7acb2323	2026-03-01 16:50:00.762+00	f	2026-01-30 16:50:00.763785+00
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
+919999900002	123456	Test delivery staff	2026-01-26 14:03:35.847644+00	2026-01-26 14:03:35.847644+00
+919999900001	123456	Demo user	2026-01-26 14:03:35.847644+00	2026-01-30 16:41:43.909432+00
\.


--
-- Data for Name: user_addresses; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_addresses (id, user_id, label, full_name, phone, address_line1, address_line2, city, state, pincode, is_default, created_at, updated_at, lat, lng, formatted_address) FROM stdin;
aba4794c-0375-457d-9089-5e198d5784c9	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Home	Test User	+919876543210	123 Test Street	\N	Ahmedabad	Gujarat	380006	t	2026-01-26 13:42:38.508504+00	2026-01-27 19:52:18.802217+00	\N	\N	\N
8c3cab28-4fca-4efd-995f-60f11ee9c4a3	0f804627-964a-4d3c-8fa3-410d32a7e6c7	Office	Test User	+919876543210	45 CG Road, Navrangpura	2nd Floor, Shreeji Complex	Ahmedabad	Gujarat	380009	f	2026-01-29 06:11:42.327227+00	2026-01-29 06:11:42.327227+00	\N	\N	\N
d9a3ccb0-b9b1-4c14-9219-39de5f099d02	fef515c7-74c2-44f8-875c-3a4ac0544af4	Home	Test Delivery	+919999900002	34 Maninagar Main Road	Opp. Swaminarayan Mandir	Ahmedabad	Gujarat	380008	t	2026-01-29 06:11:42.327227+00	2026-01-29 06:11:42.327227+00	\N	\N	\N
e7dd7f78-c6b5-47b5-bc94-c4ee3f59f93a	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	Home	Test Admin	+919999900001	Guru Cold Storage, BRTS, opposite Maruti Stone, near Motera, B/H, ONGC, Sabarmati	\N	Ahmedabad	Gujarat	380005	t	2026-01-29 06:11:42.327227+00	2026-01-30 08:13:42.784133+00	23.09285712	72.59073984	BRTS, opposite Maruti Stone, near Motera, B/H, ONGC, Sabarmati, Ahmedabad, Gujarat 380005, India
4242b834-24d7-48eb-964a-856dc8219e85	fef515c7-74c2-44f8-875c-3a4ac0544af4	Other	Test Delivery	+919999900002	56 Vastrapur Lake Road	Behind IIM Ahmedabad	Ahmedabad	Gujarat	380015	f	2026-01-29 06:11:42.327227+00	2026-01-29 06:11:42.327227+00	\N	\N	\N
eab90c15-bc12-4622-821a-85888fa29909	31ec2b11-f6ed-4900-91ca-6a0436a2fc47	Office	Test Admin	+919999900001	Statue Of Unity, Statue of Unity Road	\N	Kevadia	Gujarat	393151	f	2026-01-29 06:11:42.327227+00	2026-01-30 08:13:42.784133+00	21.83847590	73.71929500	Statue of Unity Rd, Kevadia, Gujarat 393151, India
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (id, phone, name, role, language, is_active, created_at, updated_at) FROM stdin;
fef515c7-74c2-44f8-875c-3a4ac0544af4	+919999900002	Test Delivery	delivery_staff	en	t	2026-01-26 14:03:15.429006+00	2026-01-29 04:59:21.713639+00
31ec2b11-f6ed-4900-91ca-6a0436a2fc47	+919999900001	Test Admin	customer	en	t	2026-01-26 14:03:15.429006+00	2026-01-29 06:27:48.413855+00
0f804627-964a-4d3c-8fa3-410d32a7e6c7	+919876543210	Demo user	admin	en	t	2026-01-26 13:38:21.317661+00	2026-01-30 08:54:55.200388+00
\.


--
-- Data for Name: weight_options; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.weight_options (id, product_id, weight_grams, weight_label, price_paise, is_available, display_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: buckets; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.buckets (id, name, owner, created_at, updated_at, public, avif_autodetection, file_size_limit, allowed_mime_types, owner_id) FROM stdin;
product-images	product-images	\N	2026-01-28 07:23:14.973138+00	2026-01-28 07:23:14.973138+00	t	f	5242880	{image/jpeg,image/png,image/webp}	\N
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
50395e11-9734-4dac-9e34-a91e480dc189	product-images	fecbd54a-f72c-4115-a725-5beb2931fa64/1769589729176.png	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-28 08:42:11.848478+00	2026-01-28 08:42:11.848478+00	2026-01-28 08:42:11.848478+00	{"eTag": "\\"b81c3bae1c0410ab42018f546cf79082\\"", "size": 944161, "mimetype": "image/png", "cacheControl": "no-cache", "lastModified": "2026-01-28T08:42:11.840Z", "contentLength": 944161, "httpStatusCode": 200}	829d3807-9927-46d7-8312-168962ed8939	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
87901478-8b70-4f1e-87f6-a9745566eb10	product-images	fecbd54a-f72c-4115-a725-5beb2931fa64/1769590031769.png	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-28 08:47:14.390034+00	2026-01-28 08:47:14.390034+00	2026-01-28 08:47:14.390034+00	{"eTag": "\\"b81c3bae1c0410ab42018f546cf79082\\"", "size": 944161, "mimetype": "image/png", "cacheControl": "no-cache", "lastModified": "2026-01-28T08:47:14.381Z", "contentLength": 944161, "httpStatusCode": 200}	4b3def85-9d6f-4947-b698-2bdf250fcf72	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
7f4d5630-03aa-43f6-a732-e7fddeb3ef5f	product-images	bfb1d26b-6584-41b0-940d-d1f0253614f2/1769590182481.png	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-28 08:49:45.69451+00	2026-01-28 08:49:45.69451+00	2026-01-28 08:49:45.69451+00	{"eTag": "\\"b81c3bae1c0410ab42018f546cf79082\\"", "size": 944161, "mimetype": "image/png", "cacheControl": "no-cache", "lastModified": "2026-01-28T08:49:45.685Z", "contentLength": 944161, "httpStatusCode": 200}	d466f2ec-3d4e-48d7-849b-4b05d606ef4b	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
1551bdcc-03c8-4a6d-b8f7-bd5a406ccce7	product-images	fecbd54a-f72c-4115-a725-5beb2931fa64/1769590675855.png	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-28 08:57:57.665474+00	2026-01-28 08:57:57.665474+00	2026-01-28 08:57:57.665474+00	{"eTag": "\\"b81c3bae1c0410ab42018f546cf79082\\"", "size": 944161, "mimetype": "image/png", "cacheControl": "no-cache", "lastModified": "2026-01-28T08:57:57.658Z", "contentLength": 944161, "httpStatusCode": 200}	9c7d3229-0581-421b-b8c7-ab397862d812	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
f037fdaf-db28-4bcf-80d6-915c8fe5a65b	product-images	fecbd54a-f72c-4115-a725-5beb2931fa64/1769590700769.png	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-28 09:01:48.164309+00	2026-01-28 09:01:48.164309+00	2026-01-28 09:01:48.164309+00	{"eTag": "\\"c21d0a1d60def0fcbbe17240cef429c8\\"", "size": 1477546, "mimetype": "image/png", "cacheControl": "no-cache", "lastModified": "2026-01-28T09:01:48.155Z", "contentLength": 1477546, "httpStatusCode": 200}	e6a263fb-1f55-440d-aa0f-b4be1e51fb5a	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
5e244d82-96ec-4c23-b912-a7b614646bb5	product-images	fecbd54a-f72c-4115-a725-5beb2931fa64/1769591134337.jpeg	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-28 09:05:34.346312+00	2026-01-28 09:05:34.346312+00	2026-01-28 09:05:34.346312+00	{"eTag": "\\"5f3c29e47a5b3fd6b612fdbff2e9c2f8\\"", "size": 56923, "mimetype": "image/jpeg", "cacheControl": "no-cache", "lastModified": "2026-01-28T09:05:34.342Z", "contentLength": 56923, "httpStatusCode": 200}	a7566227-8fdb-418b-aaa6-060fd87ac9ff	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
8c871fd8-63fc-46e9-95ab-f83dc6b38cfb	product-images	1983e5a5-8b23-4266-8d8c-9f3aa81a578d/1769593974360.png	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-28 09:52:58.621159+00	2026-01-28 09:52:58.621159+00	2026-01-28 09:52:58.621159+00	{"eTag": "\\"b81c3bae1c0410ab42018f546cf79082\\"", "size": 944161, "mimetype": "image/png", "cacheControl": "no-cache", "lastModified": "2026-01-28T09:52:58.602Z", "contentLength": 944161, "httpStatusCode": 200}	85abb1e7-8b56-4df8-8f3d-0ee49506dd70	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
46f0ed94-5ce4-4014-a4dd-80cb586768dc	product-images	1983e5a5-8b23-4266-8d8c-9f3aa81a578d/1769593999373.png	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-28 09:53:26.592281+00	2026-01-28 09:53:26.592281+00	2026-01-28 09:53:26.592281+00	{"eTag": "\\"c21d0a1d60def0fcbbe17240cef429c8\\"", "size": 1477546, "mimetype": "image/png", "cacheControl": "no-cache", "lastModified": "2026-01-28T09:53:26.581Z", "contentLength": 1477546, "httpStatusCode": 200}	2260f39b-8a5d-49e5-8c4d-8b5540b08a83	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
fd164326-993f-4502-83c0-89759008299d	product-images	1983e5a5-8b23-4266-8d8c-9f3aa81a578d/1769594228519.jpeg	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-28 09:57:12.790093+00	2026-01-28 09:57:12.790093+00	2026-01-28 09:57:12.790093+00	{"eTag": "\\"abd7e7b94fbf8d9c1ac0c9593244e7a2\\"", "size": 1910341, "mimetype": "image/jpeg", "cacheControl": "no-cache", "lastModified": "2026-01-28T09:57:12.775Z", "contentLength": 1910341, "httpStatusCode": 200}	53a0640b-60cc-4e14-9350-6aa9191246be	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
3f486ae5-8073-49fa-aa47-c652c102cf6b	product-images	5e2837e0-13ae-4d27-9cc5-94c9327c03c8/1769594755304.png	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-28 10:05:56.611919+00	2026-01-28 10:05:56.611919+00	2026-01-28 10:05:56.611919+00	{"eTag": "\\"b81c3bae1c0410ab42018f546cf79082\\"", "size": 944161, "mimetype": "image/png", "cacheControl": "no-cache", "lastModified": "2026-01-28T10:05:56.603Z", "contentLength": 944161, "httpStatusCode": 200}	0a1611ed-5a99-4589-a767-291ad02e022d	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
1231cdb5-f5de-4e17-a06b-df8c14c76549	product-images	89f27e16-064e-4981-901b-ed91a04f7062/1769785317033.jpg	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-30 15:01:57.472793+00	2026-01-30 15:01:57.472793+00	2026-01-30 15:01:57.472793+00	{"eTag": "\\"faa7e684cb67d5dd2d3e2b6ad5a5f53c\\"", "size": 49671, "mimetype": "image/jpeg", "cacheControl": "no-cache", "lastModified": "2026-01-30T15:01:57.465Z", "contentLength": 49671, "httpStatusCode": 200}	86f8dc28-8fce-45fe-a1c0-6f572a2be296	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
184f1963-6685-42f8-b9a2-80657c25a744	product-images	89f27e16-064e-4981-901b-ed91a04f7062/1769785351372.jpg	0f804627-964a-4d3c-8fa3-410d32a7e6c7	2026-01-30 15:02:32.804055+00	2026-01-30 15:02:32.804055+00	2026-01-30 15:02:32.804055+00	{"eTag": "\\"65d6ad137d3b1088367c2caa6cd02dca\\"", "size": 67259, "mimetype": "image/jpeg", "cacheControl": "no-cache", "lastModified": "2026-01-30T15:02:32.799Z", "contentLength": 67259, "httpStatusCode": 200}	fdef5c38-2c07-44e7-ac84-c3f4dde582d5	0f804627-964a-4d3c-8fa3-410d32a7e6c7	{}
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
-- Name: porter_deliveries porter_deliveries_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.porter_deliveries
    ADD CONSTRAINT porter_deliveries_order_id_key UNIQUE (order_id);


--
-- Name: porter_deliveries porter_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.porter_deliveries
    ADD CONSTRAINT porter_deliveries_pkey PRIMARY KEY (id);


--
-- Name: porter_webhooks porter_webhooks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.porter_webhooks
    ADD CONSTRAINT porter_webhooks_pkey PRIMARY KEY (id);


--
-- Name: product_images product_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_images
    ADD CONSTRAINT product_images_pkey PRIMARY KEY (id);


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
-- Name: idx_orders_delivery_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_delivery_type ON public.orders USING btree (delivery_type);


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
-- Name: idx_porter_deliveries_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_porter_deliveries_order ON public.porter_deliveries USING btree (order_id);


--
-- Name: idx_porter_deliveries_porter_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_porter_deliveries_porter_order ON public.porter_deliveries USING btree (porter_order_id);


--
-- Name: idx_porter_deliveries_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_porter_deliveries_status ON public.porter_deliveries USING btree (porter_status);


--
-- Name: idx_porter_webhooks_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_porter_webhooks_created ON public.porter_webhooks USING btree (created_at DESC);


--
-- Name: idx_porter_webhooks_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_porter_webhooks_order ON public.porter_webhooks USING btree (order_id);


--
-- Name: idx_porter_webhooks_porter_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_porter_webhooks_porter_order ON public.porter_webhooks USING btree (porter_order_id);


--
-- Name: idx_product_images_display_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_images_display_order ON public.product_images USING btree (product_id, display_order);


--
-- Name: idx_product_images_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_images_product_id ON public.product_images USING btree (product_id);


--
-- Name: idx_product_images_status_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_images_status_created ON public.product_images USING btree (status, created_at) WHERE ((status)::text = 'pending'::text);


--
-- Name: idx_product_images_upload_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_images_upload_token ON public.product_images USING btree (upload_token) WHERE (upload_token IS NOT NULL);


--
-- Name: idx_product_images_uploaded_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_images_uploaded_by ON public.product_images USING btree (uploaded_by);


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
-- Name: porter_deliveries update_porter_deliveries_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_porter_deliveries_updated_at BEFORE UPDATE ON public.porter_deliveries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: product_images update_product_images_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_product_images_updated_at BEFORE UPDATE ON public.product_images FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


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
-- Name: porter_deliveries porter_deliveries_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.porter_deliveries
    ADD CONSTRAINT porter_deliveries_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: porter_webhooks porter_webhooks_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.porter_webhooks
    ADD CONSTRAINT porter_webhooks_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- Name: product_images product_images_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_images
    ADD CONSTRAINT product_images_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: product_images product_images_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_images
    ADD CONSTRAINT product_images_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(id);


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

CREATE POLICY categories_public_read ON public.categories FOR SELECT TO authenticated, anon USING ((is_active = true));


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
-- Name: porter_deliveries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.porter_deliveries ENABLE ROW LEVEL SECURITY;

--
-- Name: porter_deliveries porter_deliveries_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY porter_deliveries_admin_all ON public.porter_deliveries TO authenticated USING (( SELECT auth.is_admin() AS is_admin)) WITH CHECK (( SELECT auth.is_admin() AS is_admin));


--
-- Name: porter_deliveries porter_deliveries_customer_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY porter_deliveries_customer_read ON public.porter_deliveries FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.orders
  WHERE ((orders.id = porter_deliveries.order_id) AND (orders.user_id = auth.uid())))));


--
-- Name: porter_webhooks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.porter_webhooks ENABLE ROW LEVEL SECURITY;

--
-- Name: porter_webhooks porter_webhooks_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY porter_webhooks_admin_insert ON public.porter_webhooks FOR INSERT TO authenticated WITH CHECK (( SELECT auth.is_admin() AS is_admin));


--
-- Name: porter_webhooks porter_webhooks_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY porter_webhooks_admin_read ON public.porter_webhooks FOR SELECT TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: product_images; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_images ENABLE ROW LEVEL SECURITY;

--
-- Name: product_images product_images_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_images_admin_delete ON public.product_images FOR DELETE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: product_images product_images_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_images_admin_insert ON public.product_images FOR INSERT TO authenticated WITH CHECK (( SELECT auth.is_admin() AS is_admin));


--
-- Name: product_images product_images_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_images_admin_read ON public.product_images FOR SELECT TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: product_images product_images_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_images_admin_update ON public.product_images FOR UPDATE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: product_images product_images_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY product_images_public_read ON public.product_images FOR SELECT TO authenticated, anon USING ((((status)::text = 'confirmed'::text) AND public.is_product_visible(product_id)));


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

CREATE POLICY products_public_read ON public.products FOR SELECT TO authenticated, anon USING (((is_available = true) AND (is_active = true)));


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
-- Name: app_settings settings_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY settings_admin_insert ON public.app_settings FOR INSERT TO authenticated WITH CHECK (( SELECT auth.is_admin() AS is_admin));


--
-- Name: app_settings settings_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY settings_admin_update ON public.app_settings FOR UPDATE TO authenticated USING (( SELECT auth.is_admin() AS is_admin));


--
-- Name: app_settings settings_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY settings_public_read ON public.app_settings FOR SELECT TO authenticated, anon USING (true);


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
-- Name: users users_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_admin_insert ON public.users FOR INSERT TO authenticated WITH CHECK (( SELECT auth.is_admin() AS is_admin));


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

CREATE POLICY weight_options_public_read ON public.weight_options FOR SELECT TO authenticated, anon USING (((is_available = true) AND public.is_product_visible(product_id)));


--
-- Name: buckets; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets buckets_read_anon; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY buckets_read_anon ON storage.buckets FOR SELECT TO anon USING ((public = true));


--
-- Name: buckets buckets_read_authenticated; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY buckets_read_authenticated ON storage.buckets FOR SELECT TO authenticated USING (true);


--
-- Name: migrations; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: objects product-images-delete; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY "product-images-delete" ON storage.objects FOR DELETE TO authenticated USING (((bucket_id = 'product-images'::text) AND ( SELECT auth.is_admin() AS is_admin)));


--
-- Name: objects product-images-read; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY "product-images-read" ON storage.objects FOR SELECT TO authenticated USING ((bucket_id = 'product-images'::text));


--
-- Name: objects product-images-update; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY "product-images-update" ON storage.objects FOR UPDATE TO authenticated USING (((bucket_id = 'product-images'::text) AND ( SELECT auth.is_admin() AS is_admin)));


--
-- Name: objects product-images-upload; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY "product-images-upload" ON storage.objects FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'product-images'::text) AND ( SELECT auth.is_admin() AS is_admin)));


--
-- Name: s3_multipart_uploads; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads_parts; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads_parts s3_parts_auth_all; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY s3_parts_auth_all ON storage.s3_multipart_uploads_parts TO authenticated USING (true) WITH CHECK (true);


--
-- Name: s3_multipart_uploads s3_uploads_auth_all; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY s3_uploads_auth_all ON storage.s3_multipart_uploads TO authenticated USING (true) WITH CHECK (true);


--
-- PostgreSQL database dump complete
--

