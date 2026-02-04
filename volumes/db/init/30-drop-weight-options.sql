-- =============================================
-- Migration: Drop weight_options Table Entirely
-- =============================================
-- Remove the weight_options table completely.
-- All products now use custom weights with pricing calculated from price_per_kg_paise.

BEGIN;

-- ============================================================
-- STEP 1: Migrate cart_items with weight_option_id to custom_weight_grams
-- ============================================================
UPDATE cart_items ci
SET custom_weight_grams = wo.weight_grams
FROM weight_options wo
WHERE ci.weight_option_id = wo.id
  AND ci.custom_weight_grams IS NULL;

-- ============================================================
-- STEP 2: Drop FK constraint from cart_items
-- ============================================================
ALTER TABLE cart_items DROP CONSTRAINT IF EXISTS cart_items_weight_option_id_fkey;

-- ============================================================
-- STEP 3: Drop weight_option_id column from cart_items
-- ============================================================
DROP INDEX IF EXISTS idx_cart_preset_weight;
ALTER TABLE cart_items DROP CONSTRAINT IF EXISTS chk_cart_weight_source;
ALTER TABLE cart_items DROP COLUMN IF EXISTS weight_option_id;

-- ============================================================
-- STEP 4: Update cart_items constraint (custom_weight_grams now required)
-- ============================================================
ALTER TABLE cart_items ALTER COLUMN custom_weight_grams SET NOT NULL;

-- Recreate unique index without weight_option_id
DROP INDEX IF EXISTS idx_cart_custom_weight;
CREATE UNIQUE INDEX idx_cart_unique_weight
    ON cart_items (user_id, product_id, custom_weight_grams);

-- ============================================================
-- STEP 5: Set order_items.weight_option_id to NULL, drop FK
-- ============================================================
UPDATE order_items SET weight_option_id = NULL WHERE weight_option_id IS NOT NULL;
ALTER TABLE order_items DROP CONSTRAINT IF EXISTS order_items_weight_option_id_fkey;
ALTER TABLE order_items DROP COLUMN IF EXISTS weight_option_id;

-- ============================================================
-- STEP 6: Drop RLS policies on weight_options
-- ============================================================
DROP POLICY IF EXISTS "weight_options_public_read" ON weight_options;
DROP POLICY IF EXISTS "weight_options_admin_read" ON weight_options;
DROP POLICY IF EXISTS "weight_options_admin_insert" ON weight_options;
DROP POLICY IF EXISTS "weight_options_admin_update" ON weight_options;
DROP POLICY IF EXISTS "weight_options_admin_delete" ON weight_options;

-- ============================================================
-- STEP 7: Drop weight_options table
-- ============================================================
DROP TABLE IF EXISTS weight_options CASCADE;

-- ============================================================
-- STEP 8: Update cart RPC functions (remove weight_options references)
-- ============================================================

-- get_cart() - simplified, no weight_options JOIN
CREATE OR REPLACE FUNCTION get_cart()
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_result JSON;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    SELECT COALESCE(json_agg(item ORDER BY item.created_at), '[]'::json)
    INTO v_result
    FROM (
        SELECT
            ci.id,
            ci.product_id,
            ci.custom_weight_grams AS weight_grams,
            format_weight_label(ci.custom_weight_grams) AS weight_label,
            ci.quantity,
            ci.created_at,
            ci.updated_at,
            p.name AS product_name,
            p.name_gu AS product_name_gu,
            p.image_url AS product_image_url,
            p.is_available AS product_is_available,
            p.is_active AS product_is_active,
            p.price_per_kg_paise,
            ROUND(p.price_per_kg_paise * ci.custom_weight_grams / 1000.0)::BIGINT AS unit_price_paise,
            ROUND(p.price_per_kg_paise * ci.custom_weight_grams / 1000.0)::BIGINT * ci.quantity AS line_total_paise
        FROM cart_items ci
        JOIN products p ON p.id = ci.product_id
        WHERE ci.user_id = v_user_id
    ) item;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- add_to_cart() - only custom weight, no weight_option_id
DROP FUNCTION IF EXISTS add_to_cart(UUID, UUID, INT, INTEGER);

CREATE OR REPLACE FUNCTION add_to_cart(
    p_product_id UUID,
    p_weight_grams INT,
    p_quantity INTEGER DEFAULT 1
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_cart_item_id UUID;
    v_result JSON;
    v_product_available BOOLEAN;
    v_price_per_kg_paise BIGINT;
    v_unit_price_paise BIGINT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    IF p_quantity < 1 OR p_quantity > 100 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY: Quantity must be between 1 and 100';
    END IF;

    IF p_weight_grams < 10 OR p_weight_grams > 25000 THEN
        RAISE EXCEPTION 'INVALID_WEIGHT: Weight must be between 10g and 25kg';
    END IF;

    SELECT (is_available AND is_active), price_per_kg_paise
    INTO v_product_available, v_price_per_kg_paise
    FROM products WHERE id = p_product_id;

    IF v_product_available IS NULL THEN
        RAISE EXCEPTION 'PRODUCT_NOT_FOUND: Product does not exist';
    END IF;

    IF NOT v_product_available THEN
        RAISE EXCEPTION 'PRODUCT_UNAVAILABLE: Product is not available';
    END IF;

    v_unit_price_paise := ROUND(v_price_per_kg_paise * p_weight_grams / 1000.0)::BIGINT;

    INSERT INTO cart_items (user_id, product_id, custom_weight_grams, quantity)
    VALUES (v_user_id, p_product_id, p_weight_grams, p_quantity)
    ON CONFLICT (user_id, product_id, custom_weight_grams)
    DO UPDATE SET quantity = EXCLUDED.quantity, updated_at = now()
    RETURNING id INTO v_cart_item_id;

    SELECT json_build_object(
        'id', ci.id,
        'product_id', ci.product_id,
        'weight_grams', ci.custom_weight_grams,
        'weight_label', format_weight_label(ci.custom_weight_grams),
        'quantity', ci.quantity,
        'created_at', ci.created_at,
        'updated_at', ci.updated_at,
        'product_name', p.name,
        'product_name_gu', p.name_gu,
        'product_image_url', p.image_url,
        'product_is_available', p.is_available,
        'product_is_active', p.is_active,
        'price_per_kg_paise', p.price_per_kg_paise,
        'unit_price_paise', v_unit_price_paise,
        'line_total_paise', v_unit_price_paise * ci.quantity
    )
    INTO v_result
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    WHERE ci.id = v_cart_item_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- update_cart_quantity() - simplified
CREATE OR REPLACE FUNCTION update_cart_quantity(
    p_cart_item_id UUID,
    p_quantity INTEGER
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

    IF p_quantity < 1 OR p_quantity > 100 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY: Quantity must be between 1 and 100';
    END IF;

    UPDATE cart_items
    SET quantity = p_quantity, updated_at = now()
    WHERE id = p_cart_item_id AND user_id = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'CART_ITEM_NOT_FOUND: Cart item not found';
    END IF;

    SELECT json_build_object(
        'id', ci.id,
        'product_id', ci.product_id,
        'weight_grams', ci.custom_weight_grams,
        'weight_label', format_weight_label(ci.custom_weight_grams),
        'quantity', ci.quantity,
        'created_at', ci.created_at,
        'updated_at', ci.updated_at,
        'product_name', p.name,
        'product_name_gu', p.name_gu,
        'product_image_url', p.image_url,
        'product_is_available', p.is_available,
        'product_is_active', p.is_active,
        'price_per_kg_paise', p.price_per_kg_paise,
        'unit_price_paise', ROUND(p.price_per_kg_paise * ci.custom_weight_grams / 1000.0)::BIGINT,
        'line_total_paise', ROUND(p.price_per_kg_paise * ci.custom_weight_grams / 1000.0)::BIGINT * ci.quantity
    )
    INTO v_result
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    WHERE ci.id = p_cart_item_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- get_cart_summary() - simplified
CREATE OR REPLACE FUNCTION get_cart_summary()
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_item_count INTEGER;
    v_subtotal_paise BIGINT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    SELECT
        COALESCE(SUM(ci.quantity), 0),
        COALESCE(SUM(ROUND(p.price_per_kg_paise * ci.custom_weight_grams / 1000.0)::BIGINT * ci.quantity), 0)
    INTO v_item_count, v_subtotal_paise
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    WHERE ci.user_id = v_user_id;

    RETURN json_build_object(
        'item_count', v_item_count,
        'subtotal_paise', v_subtotal_paise
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- STEP 9: Update grants for new function signature
-- ============================================================
GRANT EXECUTE ON FUNCTION add_to_cart(UUID, INT, INTEGER) TO authenticated;

COMMIT;
