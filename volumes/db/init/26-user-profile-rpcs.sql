-- =============================================
-- Migration: User Profile & Address RPC Functions
-- =============================================

-- =============================================
-- get_profile() - Get user profile with addresses
-- =============================================
CREATE OR REPLACE FUNCTION get_profile()
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_user JSON;
    v_addresses JSON;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Get user profile
    SELECT json_build_object(
        'id', u.id,
        'phone', u.phone,
        'name', u.name,
        'language', u.language,
        'created_at', u.created_at
    )
    INTO v_user
    FROM users u
    WHERE u.id = v_user_id AND u.is_active = true;

    IF v_user IS NULL THEN
        RAISE EXCEPTION 'USER_NOT_FOUND: User not found or inactive';
    END IF;

    -- Get addresses sorted by is_default DESC, created_at
    SELECT COALESCE(json_agg(addr ORDER BY addr.is_default DESC, addr.created_at), '[]'::json)
    INTO v_addresses
    FROM (
        SELECT
            a.id,
            a.label,
            a.full_name,
            a.phone,
            a.address_line1,
            a.address_line2,
            a.city,
            a.state,
            a.pincode,
            a.is_default,
            a.lat,
            a.lng,
            a.formatted_address,
            a.created_at,
            a.updated_at
        FROM user_addresses a
        WHERE a.user_id = v_user_id
    ) addr;

    -- Return combined result
    RETURN json_build_object(
        'id', v_user->>'id',
        'phone', v_user->>'phone',
        'name', v_user->>'name',
        'language', v_user->>'language',
        'created_at', v_user->>'created_at',
        'addresses', v_addresses
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- update_profile(p_name, p_language) - Update user profile
-- =============================================
CREATE OR REPLACE FUNCTION update_profile(
    p_name TEXT DEFAULT NULL,
    p_language TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_result JSON;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Validate name length
    IF p_name IS NOT NULL AND length(p_name) > 100 THEN
        RAISE EXCEPTION 'INVALID_NAME: Name must be 100 characters or less';
    END IF;

    -- Validate language
    IF p_language IS NOT NULL AND p_language NOT IN ('en', 'gu') THEN
        RAISE EXCEPTION 'INVALID_LANGUAGE: Language must be "en" or "gu"';
    END IF;

    -- Update profile (only provided fields)
    UPDATE users
    SET
        name = COALESCE(p_name, name),
        language = COALESCE(p_language, language),
        updated_at = now()
    WHERE id = v_user_id AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'USER_NOT_FOUND: User not found or inactive';
    END IF;

    -- Return updated user
    SELECT json_build_object(
        'id', u.id,
        'phone', u.phone,
        'name', u.name,
        'language', u.language,
        'created_at', u.created_at,
        'updated_at', u.updated_at
    )
    INTO v_result
    FROM users u
    WHERE u.id = v_user_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- get_addresses() - Get all user addresses
-- =============================================
CREATE OR REPLACE FUNCTION get_addresses()
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_result JSON;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    SELECT COALESCE(json_agg(addr ORDER BY addr.is_default DESC, addr.created_at), '[]'::json)
    INTO v_result
    FROM (
        SELECT
            a.id,
            a.label,
            a.full_name,
            a.phone,
            a.address_line1,
            a.address_line2,
            a.city,
            a.state,
            a.pincode,
            a.is_default,
            a.lat,
            a.lng,
            a.formatted_address,
            a.created_at,
            a.updated_at
        FROM user_addresses a
        WHERE a.user_id = v_user_id
    ) addr;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- add_address() - Add new address
-- =============================================
CREATE OR REPLACE FUNCTION add_address(
    p_label TEXT DEFAULT 'Home',
    p_full_name TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL,
    p_address_line1 TEXT DEFAULT NULL,
    p_address_line2 TEXT DEFAULT NULL,
    p_city TEXT DEFAULT NULL,
    p_state TEXT DEFAULT 'Gujarat',
    p_pincode TEXT DEFAULT NULL,
    p_is_default BOOLEAN DEFAULT false,
    p_lat DECIMAL(10,8) DEFAULT NULL,
    p_lng DECIMAL(11,8) DEFAULT NULL,
    p_formatted_address TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_address_id UUID;
    v_result JSON;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Validate required fields
    IF p_full_name IS NULL OR length(trim(p_full_name)) = 0 THEN
        RAISE EXCEPTION 'INVALID_FULL_NAME: Full name is required';
    END IF;

    IF p_phone IS NULL OR length(trim(p_phone)) = 0 THEN
        RAISE EXCEPTION 'INVALID_PHONE: Phone is required';
    END IF;

    IF p_address_line1 IS NULL OR length(trim(p_address_line1)) = 0 THEN
        RAISE EXCEPTION 'INVALID_ADDRESS: Address line 1 is required';
    END IF;

    IF p_city IS NULL OR length(trim(p_city)) = 0 THEN
        RAISE EXCEPTION 'INVALID_CITY: City is required';
    END IF;

    IF p_pincode IS NULL OR length(trim(p_pincode)) = 0 THEN
        RAISE EXCEPTION 'INVALID_PINCODE: Pincode is required';
    END IF;

    -- Validate phone format (+91XXXXXXXXXX)
    IF p_phone !~ '^\+91[6-9][0-9]{9}$' THEN
        RAISE EXCEPTION 'INVALID_PHONE_FORMAT: Phone must be in format +91XXXXXXXXXX (10 digits starting with 6-9)';
    END IF;

    -- Validate pincode format (6 digits)
    IF p_pincode !~ '^[0-9]{6}$' THEN
        RAISE EXCEPTION 'INVALID_PINCODE_FORMAT: Pincode must be 6 digits';
    END IF;

    -- Validate field lengths
    IF length(p_full_name) > 100 THEN
        RAISE EXCEPTION 'INVALID_FULL_NAME: Full name must be 100 characters or less';
    END IF;

    IF length(p_label) > 50 THEN
        RAISE EXCEPTION 'INVALID_LABEL: Label must be 50 characters or less';
    END IF;

    IF length(p_address_line1) > 200 THEN
        RAISE EXCEPTION 'INVALID_ADDRESS: Address line 1 must be 200 characters or less';
    END IF;

    IF p_address_line2 IS NOT NULL AND length(p_address_line2) > 200 THEN
        RAISE EXCEPTION 'INVALID_ADDRESS: Address line 2 must be 200 characters or less';
    END IF;

    IF length(p_city) > 100 THEN
        RAISE EXCEPTION 'INVALID_CITY: City must be 100 characters or less';
    END IF;

    IF length(p_state) > 100 THEN
        RAISE EXCEPTION 'INVALID_STATE: State must be 100 characters or less';
    END IF;

    -- If this is the first address, make it default
    IF NOT EXISTS (SELECT 1 FROM user_addresses WHERE user_id = v_user_id) THEN
        p_is_default := true;
    END IF;

    -- If setting as default, clear other defaults first
    IF p_is_default THEN
        UPDATE user_addresses
        SET is_default = false
        WHERE user_id = v_user_id AND is_default = true;
    END IF;

    -- Insert the address
    INSERT INTO user_addresses (
        user_id,
        label,
        full_name,
        phone,
        address_line1,
        address_line2,
        city,
        state,
        pincode,
        is_default,
        lat,
        lng,
        formatted_address
    ) VALUES (
        v_user_id,
        COALESCE(p_label, 'Home'),
        trim(p_full_name),
        trim(p_phone),
        trim(p_address_line1),
        NULLIF(trim(COALESCE(p_address_line2, '')), ''),
        trim(p_city),
        COALESCE(p_state, 'Gujarat'),
        trim(p_pincode),
        p_is_default,
        p_lat,
        p_lng,
        p_formatted_address
    )
    RETURNING id INTO v_address_id;

    -- Return the new address
    SELECT json_build_object(
        'id', a.id,
        'label', a.label,
        'full_name', a.full_name,
        'phone', a.phone,
        'address_line1', a.address_line1,
        'address_line2', a.address_line2,
        'city', a.city,
        'state', a.state,
        'pincode', a.pincode,
        'is_default', a.is_default,
        'lat', a.lat,
        'lng', a.lng,
        'formatted_address', a.formatted_address,
        'created_at', a.created_at,
        'updated_at', a.updated_at
    )
    INTO v_result
    FROM user_addresses a
    WHERE a.id = v_address_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- update_address() - Update existing address
-- =============================================
CREATE OR REPLACE FUNCTION update_address(
    p_address_id UUID,
    p_label TEXT DEFAULT NULL,
    p_full_name TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL,
    p_address_line1 TEXT DEFAULT NULL,
    p_address_line2 TEXT DEFAULT NULL,
    p_city TEXT DEFAULT NULL,
    p_state TEXT DEFAULT NULL,
    p_pincode TEXT DEFAULT NULL,
    p_is_default BOOLEAN DEFAULT NULL,
    p_lat DECIMAL(10,8) DEFAULT NULL,
    p_lng DECIMAL(11,8) DEFAULT NULL,
    p_formatted_address TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_result JSON;
    v_existing_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Check address exists and belongs to user
    SELECT user_id INTO v_existing_user_id
    FROM user_addresses
    WHERE id = p_address_id;

    IF v_existing_user_id IS NULL THEN
        RAISE EXCEPTION 'ADDRESS_NOT_FOUND: Address not found';
    END IF;

    IF v_existing_user_id != v_user_id THEN
        RAISE EXCEPTION 'FORBIDDEN: Address does not belong to this user';
    END IF;

    -- Validate phone format if provided
    IF p_phone IS NOT NULL AND p_phone !~ '^\+91[6-9][0-9]{9}$' THEN
        RAISE EXCEPTION 'INVALID_PHONE_FORMAT: Phone must be in format +91XXXXXXXXXX (10 digits starting with 6-9)';
    END IF;

    -- Validate pincode format if provided
    IF p_pincode IS NOT NULL AND p_pincode !~ '^[0-9]{6}$' THEN
        RAISE EXCEPTION 'INVALID_PINCODE_FORMAT: Pincode must be 6 digits';
    END IF;

    -- Validate field lengths
    IF p_full_name IS NOT NULL AND length(p_full_name) > 100 THEN
        RAISE EXCEPTION 'INVALID_FULL_NAME: Full name must be 100 characters or less';
    END IF;

    IF p_label IS NOT NULL AND length(p_label) > 50 THEN
        RAISE EXCEPTION 'INVALID_LABEL: Label must be 50 characters or less';
    END IF;

    IF p_address_line1 IS NOT NULL AND length(p_address_line1) > 200 THEN
        RAISE EXCEPTION 'INVALID_ADDRESS: Address line 1 must be 200 characters or less';
    END IF;

    IF p_address_line2 IS NOT NULL AND length(p_address_line2) > 200 THEN
        RAISE EXCEPTION 'INVALID_ADDRESS: Address line 2 must be 200 characters or less';
    END IF;

    IF p_city IS NOT NULL AND length(p_city) > 100 THEN
        RAISE EXCEPTION 'INVALID_CITY: City must be 100 characters or less';
    END IF;

    IF p_state IS NOT NULL AND length(p_state) > 100 THEN
        RAISE EXCEPTION 'INVALID_STATE: State must be 100 characters or less';
    END IF;

    -- If setting as default, clear other defaults first
    IF p_is_default = true THEN
        UPDATE user_addresses
        SET is_default = false
        WHERE user_id = v_user_id AND id != p_address_id AND is_default = true;
    END IF;

    -- Update the address (only provided fields)
    UPDATE user_addresses
    SET
        label = COALESCE(p_label, label),
        full_name = COALESCE(trim(p_full_name), full_name),
        phone = COALESCE(trim(p_phone), phone),
        address_line1 = COALESCE(trim(p_address_line1), address_line1),
        address_line2 = CASE
            WHEN p_address_line2 IS NOT NULL THEN NULLIF(trim(p_address_line2), '')
            ELSE address_line2
        END,
        city = COALESCE(trim(p_city), city),
        state = COALESCE(p_state, state),
        pincode = COALESCE(trim(p_pincode), pincode),
        is_default = COALESCE(p_is_default, is_default),
        lat = CASE WHEN p_lat IS NOT NULL THEN p_lat ELSE lat END,
        lng = CASE WHEN p_lng IS NOT NULL THEN p_lng ELSE lng END,
        formatted_address = CASE WHEN p_formatted_address IS NOT NULL THEN p_formatted_address ELSE formatted_address END,
        updated_at = now()
    WHERE id = p_address_id;

    -- Return updated address
    SELECT json_build_object(
        'id', a.id,
        'label', a.label,
        'full_name', a.full_name,
        'phone', a.phone,
        'address_line1', a.address_line1,
        'address_line2', a.address_line2,
        'city', a.city,
        'state', a.state,
        'pincode', a.pincode,
        'is_default', a.is_default,
        'lat', a.lat,
        'lng', a.lng,
        'formatted_address', a.formatted_address,
        'created_at', a.created_at,
        'updated_at', a.updated_at
    )
    INTO v_result
    FROM user_addresses a
    WHERE a.id = p_address_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- delete_address() - Delete an address
-- =============================================
CREATE OR REPLACE FUNCTION delete_address(p_address_id UUID)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_deleted_id UUID;
    v_was_default BOOLEAN;
    v_remaining_count INTEGER;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Check if address belongs to user and get is_default status
    SELECT is_default INTO v_was_default
    FROM user_addresses
    WHERE id = p_address_id AND user_id = v_user_id;

    IF v_was_default IS NULL THEN
        RAISE EXCEPTION 'ADDRESS_NOT_FOUND: Address not found';
    END IF;

    -- Delete the address
    DELETE FROM user_addresses
    WHERE id = p_address_id AND user_id = v_user_id
    RETURNING id INTO v_deleted_id;

    -- If deleted address was default, make the first remaining address default
    IF v_was_default THEN
        UPDATE user_addresses
        SET is_default = true
        WHERE id = (
            SELECT id FROM user_addresses
            WHERE user_id = v_user_id
            ORDER BY created_at
            LIMIT 1
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'deleted_id', v_deleted_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- set_default_address() - Set address as default
-- =============================================
CREATE OR REPLACE FUNCTION set_default_address(p_address_id UUID)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_result JSON;
    v_existing_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Check address exists and belongs to user
    SELECT user_id INTO v_existing_user_id
    FROM user_addresses
    WHERE id = p_address_id;

    IF v_existing_user_id IS NULL THEN
        RAISE EXCEPTION 'ADDRESS_NOT_FOUND: Address not found';
    END IF;

    IF v_existing_user_id != v_user_id THEN
        RAISE EXCEPTION 'FORBIDDEN: Address does not belong to this user';
    END IF;

    -- Clear all other defaults for this user
    UPDATE user_addresses
    SET is_default = false
    WHERE user_id = v_user_id AND is_default = true;

    -- Set this address as default
    UPDATE user_addresses
    SET is_default = true, updated_at = now()
    WHERE id = p_address_id;

    -- Return updated address
    SELECT json_build_object(
        'id', a.id,
        'label', a.label,
        'full_name', a.full_name,
        'phone', a.phone,
        'address_line1', a.address_line1,
        'address_line2', a.address_line2,
        'city', a.city,
        'state', a.state,
        'pincode', a.pincode,
        'is_default', a.is_default,
        'lat', a.lat,
        'lng', a.lng,
        'formatted_address', a.formatted_address,
        'created_at', a.created_at,
        'updated_at', a.updated_at
    )
    INTO v_result
    FROM user_addresses a
    WHERE a.id = p_address_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- GRANTS
-- =============================================

GRANT EXECUTE ON FUNCTION get_profile() TO authenticated;
GRANT EXECUTE ON FUNCTION update_profile(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_addresses() TO authenticated;
GRANT EXECUTE ON FUNCTION add_address(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, DECIMAL, DECIMAL, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION update_address(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, DECIMAL, DECIMAL, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_address(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION set_default_address(UUID) TO authenticated;
