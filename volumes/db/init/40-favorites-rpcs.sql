-- =============================================
-- Migration: Favorites RPC Functions
-- =============================================

-- =============================================
-- get_favorite_ids() - Get array of favorited product IDs
-- =============================================
CREATE OR REPLACE FUNCTION get_favorite_ids()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_ids JSON;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    SELECT COALESCE(json_agg(f.product_id), '[]'::json)
    INTO v_ids
    FROM favorites f
    WHERE f.user_id = v_user_id;

    RETURN v_ids;
END;
$$;

-- =============================================
-- toggle_favorite(p_product_id) - Add or remove a favorite
-- =============================================
CREATE OR REPLACE FUNCTION toggle_favorite(p_product_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_exists BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM favorites
        WHERE user_id = v_user_id AND product_id = p_product_id
    ) INTO v_exists;

    IF v_exists THEN
        DELETE FROM favorites
        WHERE user_id = v_user_id AND product_id = p_product_id;
        RETURN json_build_object('action', 'removed', 'product_id', p_product_id);
    ELSE
        INSERT INTO favorites (user_id, product_id)
        VALUES (v_user_id, p_product_id);
        RETURN json_build_object('action', 'added', 'product_id', p_product_id);
    END IF;
END;
$$;

-- =============================================
-- add_favorite(p_product_id) - Add a product to favorites
-- =============================================
CREATE OR REPLACE FUNCTION add_favorite(p_product_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    INSERT INTO favorites (user_id, product_id)
    VALUES (v_user_id, p_product_id)
    ON CONFLICT (user_id, product_id) DO NOTHING;

    RETURN json_build_object('product_id', p_product_id);
END;
$$;

-- =============================================
-- remove_favorite(p_product_id) - Remove a product from favorites
-- =============================================
CREATE OR REPLACE FUNCTION remove_favorite(p_product_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    DELETE FROM favorites
    WHERE user_id = v_user_id AND product_id = p_product_id;

    RETURN json_build_object('product_id', p_product_id);
END;
$$;

-- =============================================
-- is_favorite(p_product_id) - Check if a product is favorited
-- =============================================
CREATE OR REPLACE FUNCTION is_favorite(p_product_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    RETURN EXISTS(
        SELECT 1 FROM favorites
        WHERE user_id = v_user_id AND product_id = p_product_id
    );
END;
$$;

-- =============================================
-- Grants
-- =============================================
GRANT EXECUTE ON FUNCTION get_favorite_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION toggle_favorite(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION add_favorite(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION remove_favorite(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION is_favorite(UUID) TO authenticated;
