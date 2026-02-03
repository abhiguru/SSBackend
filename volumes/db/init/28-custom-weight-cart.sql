-- =============================================
-- Migration: Custom Weight Support for Cart
-- =============================================
-- Extends cart to support custom weights alongside pre-defined weight options.
-- Checkout already supports custom weights; this brings cart to parity.

-- =============================================
-- HELPER FUNCTION: Format weight as human-readable label
-- =============================================

CREATE OR REPLACE FUNCTION format_weight_label(grams INT) RETURNS TEXT AS $$
BEGIN
    IF grams IS NULL THEN
        RETURN NULL;
    ELSIF grams >= 1000 AND grams % 1000 = 0 THEN
        RETURN (grams / 1000)::TEXT || ' kg';
    ELSIF grams >= 1000 THEN
        RETURN ROUND(grams / 1000.0, 2)::TEXT || ' kg';
    ELSE
        RETURN grams::TEXT || ' g';
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- =============================================
-- SCHEMA CHANGES
-- =============================================

-- Make weight_option_id nullable
ALTER TABLE cart_items ALTER COLUMN weight_option_id DROP NOT NULL;

-- Add custom_weight_grams column
ALTER TABLE cart_items ADD COLUMN IF NOT EXISTS custom_weight_grams INT;

-- Constraint: must have either weight_option_id OR custom_weight_grams (not both, not neither)
ALTER TABLE cart_items ADD CONSTRAINT chk_cart_weight_source
    CHECK (
        (weight_option_id IS NOT NULL AND custom_weight_grams IS NULL) OR
        (weight_option_id IS NULL AND custom_weight_grams IS NOT NULL)
    );

-- Constraint: custom weight must be reasonable (10g to 25kg)
ALTER TABLE cart_items ADD CONSTRAINT chk_custom_weight_range
    CHECK (custom_weight_grams IS NULL OR (custom_weight_grams >= 10 AND custom_weight_grams <= 25000));

-- Drop the old unique constraint
ALTER TABLE cart_items DROP CONSTRAINT IF EXISTS cart_items_user_id_product_id_weight_option_id_key;
DROP INDEX IF EXISTS cart_items_user_id_product_id_weight_option_id_key;

-- Create partial indexes for uniqueness
-- Pre-defined weights: one entry per user/product/weight_option combo
CREATE UNIQUE INDEX IF NOT EXISTS idx_cart_preset_weight
    ON cart_items (user_id, product_id, weight_option_id)
    WHERE weight_option_id IS NOT NULL;

-- Custom weights: one entry per user/product/custom_weight combo
CREATE UNIQUE INDEX IF NOT EXISTS idx_cart_custom_weight
    ON cart_items (user_id, product_id, custom_weight_grams)
    WHERE custom_weight_grams IS NOT NULL;

-- =============================================
-- UPDATED RPC FUNCTIONS
-- =============================================

-- ---------------------------------------------
-- get_cart() - Get cart with full product details
-- Updated to handle both pre-defined and custom weights
-- ---------------------------------------------
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
            ci.weight_option_id,
            ci.custom_weight_grams,
            ci.quantity,
            ci.created_at,
            ci.updated_at,
            p.name AS product_name,
            p.name_gu AS product_name_gu,
            p.image_url AS product_image_url,
            p.is_available AS product_is_available,
            p.is_active AS product_is_active,
            p.price_per_kg_paise,
            -- Weight in grams (from weight_option or custom)
            CASE
                WHEN ci.weight_option_id IS NOT NULL THEN wo.weight_grams
                ELSE ci.custom_weight_grams
            END AS weight_grams,
            -- Weight label (from weight_option or formatted custom)
            CASE
                WHEN ci.weight_option_id IS NOT NULL THEN wo.weight_label
                ELSE format_weight_label(ci.custom_weight_grams)
            END AS weight_label,
            -- Unit price (from weight_option or calculated from price_per_kg)
            CASE
                WHEN ci.weight_option_id IS NOT NULL THEN wo.price_paise
                ELSE ROUND(p.price_per_kg_paise * ci.custom_weight_grams / 1000.0)::BIGINT
            END AS unit_price_paise,
            -- Weight option availability (NULL for custom weights)
            CASE
                WHEN ci.weight_option_id IS NOT NULL THEN wo.is_available
                ELSE TRUE
            END AS weight_option_is_available,
            -- Line total
            CASE
                WHEN ci.weight_option_id IS NOT NULL THEN wo.price_paise * ci.quantity
                ELSE ROUND(p.price_per_kg_paise * ci.custom_weight_grams / 1000.0)::BIGINT * ci.quantity
            END AS line_total_paise,
            -- Flag to indicate if this is a custom weight
            (ci.custom_weight_grams IS NOT NULL) AS is_custom_weight
        FROM cart_items ci
        JOIN products p ON p.id = ci.product_id
        LEFT JOIN weight_options wo ON wo.id = ci.weight_option_id
        WHERE ci.user_id = v_user_id
    ) item;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ---------------------------------------------
-- add_to_cart() - Add or update cart item
-- Updated to support both pre-defined and custom weights
-- ---------------------------------------------
DROP FUNCTION IF EXISTS add_to_cart(UUID, UUID, INTEGER);

CREATE OR REPLACE FUNCTION add_to_cart(
    p_product_id UUID,
    p_weight_option_id UUID DEFAULT NULL,
    p_custom_weight_grams INT DEFAULT NULL,
    p_quantity INTEGER DEFAULT 1
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_cart_item_id UUID;
    v_result JSON;
    v_product_available BOOLEAN;
    v_price_per_kg_paise BIGINT;
    v_weight_option_available BOOLEAN;
    v_weight_option_product_id UUID;
    v_unit_price_paise BIGINT;
    v_weight_grams INT;
    v_weight_label TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Validate: exactly one of weight_option_id or custom_weight_grams must be provided
    IF (p_weight_option_id IS NOT NULL AND p_custom_weight_grams IS NOT NULL) THEN
        RAISE EXCEPTION 'INVALID_WEIGHT: Provide either weight_option_id or custom_weight_grams, not both';
    END IF;

    IF (p_weight_option_id IS NULL AND p_custom_weight_grams IS NULL) THEN
        RAISE EXCEPTION 'INVALID_WEIGHT: Must provide either weight_option_id or custom_weight_grams';
    END IF;

    -- Validate quantity
    IF p_quantity < 1 OR p_quantity > 100 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY: Quantity must be between 1 and 100';
    END IF;

    -- Validate custom weight range
    IF p_custom_weight_grams IS NOT NULL AND (p_custom_weight_grams < 10 OR p_custom_weight_grams > 25000) THEN
        RAISE EXCEPTION 'INVALID_WEIGHT: Custom weight must be between 10g and 25kg';
    END IF;

    -- Check product exists and is available
    SELECT (is_available AND is_active), price_per_kg_paise
    INTO v_product_available, v_price_per_kg_paise
    FROM products
    WHERE id = p_product_id;

    IF v_product_available IS NULL THEN
        RAISE EXCEPTION 'PRODUCT_NOT_FOUND: Product does not exist';
    END IF;

    IF NOT v_product_available THEN
        RAISE EXCEPTION 'PRODUCT_UNAVAILABLE: Product is not available';
    END IF;

    -- Handle pre-defined weight option
    IF p_weight_option_id IS NOT NULL THEN
        -- Check weight option exists, is available, and belongs to product
        SELECT is_available, product_id
        INTO v_weight_option_available, v_weight_option_product_id
        FROM weight_options
        WHERE id = p_weight_option_id;

        IF v_weight_option_available IS NULL THEN
            RAISE EXCEPTION 'WEIGHT_OPTION_NOT_FOUND: Weight option does not exist';
        END IF;

        IF v_weight_option_product_id != p_product_id THEN
            RAISE EXCEPTION 'WEIGHT_OPTION_MISMATCH: Weight option does not belong to this product';
        END IF;

        IF NOT v_weight_option_available THEN
            RAISE EXCEPTION 'WEIGHT_OPTION_UNAVAILABLE: Weight option is not available';
        END IF;

        -- Upsert cart item for pre-defined weight
        INSERT INTO cart_items (user_id, product_id, weight_option_id, custom_weight_grams, quantity)
        VALUES (v_user_id, p_product_id, p_weight_option_id, NULL, p_quantity)
        ON CONFLICT (user_id, product_id, weight_option_id) WHERE weight_option_id IS NOT NULL
        DO UPDATE SET
            quantity = EXCLUDED.quantity,
            updated_at = now()
        RETURNING id INTO v_cart_item_id;

        -- Get weight option details for response
        SELECT wo.price_paise, wo.weight_grams, wo.weight_label
        INTO v_unit_price_paise, v_weight_grams, v_weight_label
        FROM weight_options wo
        WHERE wo.id = p_weight_option_id;
    ELSE
        -- Handle custom weight
        v_unit_price_paise := ROUND(v_price_per_kg_paise * p_custom_weight_grams / 1000.0)::BIGINT;
        v_weight_grams := p_custom_weight_grams;
        v_weight_label := format_weight_label(p_custom_weight_grams);

        -- Upsert cart item for custom weight
        INSERT INTO cart_items (user_id, product_id, weight_option_id, custom_weight_grams, quantity)
        VALUES (v_user_id, p_product_id, NULL, p_custom_weight_grams, p_quantity)
        ON CONFLICT (user_id, product_id, custom_weight_grams) WHERE custom_weight_grams IS NOT NULL
        DO UPDATE SET
            quantity = EXCLUDED.quantity,
            updated_at = now()
        RETURNING id INTO v_cart_item_id;
    END IF;

    -- Return the cart item with product details
    SELECT json_build_object(
        'id', ci.id,
        'product_id', ci.product_id,
        'weight_option_id', ci.weight_option_id,
        'custom_weight_grams', ci.custom_weight_grams,
        'quantity', ci.quantity,
        'created_at', ci.created_at,
        'updated_at', ci.updated_at,
        'product_name', p.name,
        'product_name_gu', p.name_gu,
        'product_image_url', p.image_url,
        'product_is_available', p.is_available,
        'product_is_active', p.is_active,
        'price_per_kg_paise', p.price_per_kg_paise,
        'weight_grams', v_weight_grams,
        'weight_label', v_weight_label,
        'unit_price_paise', v_unit_price_paise,
        'weight_option_is_available', CASE WHEN ci.weight_option_id IS NOT NULL THEN TRUE ELSE TRUE END,
        'line_total_paise', v_unit_price_paise * ci.quantity,
        'is_custom_weight', (ci.custom_weight_grams IS NOT NULL)
    )
    INTO v_result
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    WHERE ci.id = v_cart_item_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ---------------------------------------------
-- update_cart_quantity() - Update cart item quantity
-- Updated to handle both pre-defined and custom weights
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION update_cart_quantity(
    p_cart_item_id UUID,
    p_quantity INTEGER
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_result JSON;
    v_item_exists BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Validate quantity
    IF p_quantity < 1 OR p_quantity > 100 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY: Quantity must be between 1 and 100';
    END IF;

    -- Check cart item exists and belongs to user
    SELECT EXISTS(
        SELECT 1 FROM cart_items
        WHERE id = p_cart_item_id AND user_id = v_user_id
    ) INTO v_item_exists;

    IF NOT v_item_exists THEN
        RAISE EXCEPTION 'CART_ITEM_NOT_FOUND: Cart item not found';
    END IF;

    -- Update quantity
    UPDATE cart_items
    SET quantity = p_quantity, updated_at = now()
    WHERE id = p_cart_item_id AND user_id = v_user_id;

    -- Return the updated cart item with product details
    SELECT json_build_object(
        'id', ci.id,
        'product_id', ci.product_id,
        'weight_option_id', ci.weight_option_id,
        'custom_weight_grams', ci.custom_weight_grams,
        'quantity', ci.quantity,
        'created_at', ci.created_at,
        'updated_at', ci.updated_at,
        'product_name', p.name,
        'product_name_gu', p.name_gu,
        'product_image_url', p.image_url,
        'product_is_available', p.is_available,
        'product_is_active', p.is_active,
        'price_per_kg_paise', p.price_per_kg_paise,
        'weight_grams', CASE
            WHEN ci.weight_option_id IS NOT NULL THEN wo.weight_grams
            ELSE ci.custom_weight_grams
        END,
        'weight_label', CASE
            WHEN ci.weight_option_id IS NOT NULL THEN wo.weight_label
            ELSE format_weight_label(ci.custom_weight_grams)
        END,
        'unit_price_paise', CASE
            WHEN ci.weight_option_id IS NOT NULL THEN wo.price_paise
            ELSE ROUND(p.price_per_kg_paise * ci.custom_weight_grams / 1000.0)::BIGINT
        END,
        'weight_option_is_available', CASE
            WHEN ci.weight_option_id IS NOT NULL THEN wo.is_available
            ELSE TRUE
        END,
        'line_total_paise', CASE
            WHEN ci.weight_option_id IS NOT NULL THEN wo.price_paise * ci.quantity
            ELSE ROUND(p.price_per_kg_paise * ci.custom_weight_grams / 1000.0)::BIGINT * ci.quantity
        END,
        'is_custom_weight', (ci.custom_weight_grams IS NOT NULL)
    )
    INTO v_result
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    LEFT JOIN weight_options wo ON wo.id = ci.weight_option_id
    WHERE ci.id = p_cart_item_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ---------------------------------------------
-- get_cart_summary() - Get cart totals only
-- Updated to handle both pre-defined and custom weights
-- ---------------------------------------------
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
        COALESCE(SUM(
            CASE
                WHEN ci.weight_option_id IS NOT NULL THEN wo.price_paise * ci.quantity
                ELSE ROUND(p.price_per_kg_paise * ci.custom_weight_grams / 1000.0)::BIGINT * ci.quantity
            END
        ), 0)
    INTO v_item_count, v_subtotal_paise
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    LEFT JOIN weight_options wo ON wo.id = ci.weight_option_id
    WHERE ci.user_id = v_user_id;

    RETURN json_build_object(
        'item_count', v_item_count,
        'subtotal_paise', v_subtotal_paise
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- GRANTS
-- =============================================

GRANT EXECUTE ON FUNCTION format_weight_label(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION add_to_cart(UUID, UUID, INT, INTEGER) TO authenticated;
