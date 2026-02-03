-- =============================================
-- Migration: Cart Items Table and RPC Functions
-- =============================================

-- =============================================
-- CART_ITEMS TABLE
-- =============================================

CREATE TABLE IF NOT EXISTS cart_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    weight_option_id UUID REFERENCES weight_options(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0 AND quantity <= 100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, product_id, weight_option_id)
);

CREATE INDEX IF NOT EXISTS idx_cart_items_user ON cart_items(user_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_product ON cart_items(product_id);

-- Updated_at trigger
CREATE TRIGGER update_cart_items_updated_at
    BEFORE UPDATE ON cart_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================
-- RLS POLICIES
-- =============================================

ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;

-- Users can read their own cart items
CREATE POLICY cart_items_read_own ON cart_items
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- Users can insert their own cart items
CREATE POLICY cart_items_insert_own ON cart_items
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- Users can update their own cart items
CREATE POLICY cart_items_update_own ON cart_items
    FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Users can delete their own cart items
CREATE POLICY cart_items_delete_own ON cart_items
    FOR DELETE
    TO authenticated
    USING (user_id = auth.uid());

-- =============================================
-- RPC FUNCTIONS
-- =============================================

-- ---------------------------------------------
-- get_cart() - Get cart with full product details
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
            ci.quantity,
            ci.created_at,
            ci.updated_at,
            p.name AS product_name,
            p.name_gu AS product_name_gu,
            p.image_url AS product_image_url,
            p.is_available AS product_is_available,
            p.is_active AS product_is_active,
            p.price_per_kg_paise,
            wo.weight_grams,
            wo.weight_label,
            wo.price_paise AS unit_price_paise,
            wo.is_available AS weight_option_is_available,
            (wo.price_paise * ci.quantity) AS line_total_paise
        FROM cart_items ci
        JOIN products p ON p.id = ci.product_id
        JOIN weight_options wo ON wo.id = ci.weight_option_id
        WHERE ci.user_id = v_user_id
    ) item;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ---------------------------------------------
-- add_to_cart() - Add or update cart item
-- Returns the cart item with product details
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION add_to_cart(
    p_product_id UUID,
    p_weight_option_id UUID,
    p_quantity INTEGER DEFAULT 1
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_cart_item_id UUID;
    v_result JSON;
    v_product_available BOOLEAN;
    v_weight_option_available BOOLEAN;
    v_weight_option_product_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Validate quantity
    IF p_quantity < 1 OR p_quantity > 100 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY: Quantity must be between 1 and 100';
    END IF;

    -- Check product exists and is available
    SELECT (is_available AND is_active)
    INTO v_product_available
    FROM products
    WHERE id = p_product_id;

    IF v_product_available IS NULL THEN
        RAISE EXCEPTION 'PRODUCT_NOT_FOUND: Product does not exist';
    END IF;

    IF NOT v_product_available THEN
        RAISE EXCEPTION 'PRODUCT_UNAVAILABLE: Product is not available';
    END IF;

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

    -- Upsert cart item (add or update quantity)
    INSERT INTO cart_items (user_id, product_id, weight_option_id, quantity)
    VALUES (v_user_id, p_product_id, p_weight_option_id, p_quantity)
    ON CONFLICT (user_id, product_id, weight_option_id)
    DO UPDATE SET
        quantity = EXCLUDED.quantity,
        updated_at = now()
    RETURNING id INTO v_cart_item_id;

    -- Return the cart item with product details
    SELECT json_build_object(
        'id', ci.id,
        'product_id', ci.product_id,
        'weight_option_id', ci.weight_option_id,
        'quantity', ci.quantity,
        'created_at', ci.created_at,
        'updated_at', ci.updated_at,
        'product_name', p.name,
        'product_name_gu', p.name_gu,
        'product_image_url', p.image_url,
        'product_is_available', p.is_available,
        'product_is_active', p.is_active,
        'price_per_kg_paise', p.price_per_kg_paise,
        'weight_grams', wo.weight_grams,
        'weight_label', wo.weight_label,
        'unit_price_paise', wo.price_paise,
        'weight_option_is_available', wo.is_available,
        'line_total_paise', wo.price_paise * ci.quantity
    )
    INTO v_result
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    JOIN weight_options wo ON wo.id = ci.weight_option_id
    WHERE ci.id = v_cart_item_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ---------------------------------------------
-- update_cart_quantity() - Update cart item quantity
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
        'quantity', ci.quantity,
        'created_at', ci.created_at,
        'updated_at', ci.updated_at,
        'product_name', p.name,
        'product_name_gu', p.name_gu,
        'product_image_url', p.image_url,
        'product_is_available', p.is_available,
        'product_is_active', p.is_active,
        'price_per_kg_paise', p.price_per_kg_paise,
        'weight_grams', wo.weight_grams,
        'weight_label', wo.weight_label,
        'unit_price_paise', wo.price_paise,
        'weight_option_is_available', wo.is_available,
        'line_total_paise', wo.price_paise * ci.quantity
    )
    INTO v_result
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    JOIN weight_options wo ON wo.id = ci.weight_option_id
    WHERE ci.id = p_cart_item_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ---------------------------------------------
-- remove_from_cart() - Remove item from cart
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION remove_from_cart(p_cart_item_id UUID)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_deleted_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    -- Delete the cart item (only if it belongs to user)
    DELETE FROM cart_items
    WHERE id = p_cart_item_id AND user_id = v_user_id
    RETURNING id INTO v_deleted_id;

    IF v_deleted_id IS NULL THEN
        RAISE EXCEPTION 'CART_ITEM_NOT_FOUND: Cart item not found';
    END IF;

    RETURN json_build_object(
        'success', true,
        'removed_id', v_deleted_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ---------------------------------------------
-- clear_cart() - Remove all items from user's cart
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION clear_cart()
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_count INTEGER;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required';
    END IF;

    DELETE FROM cart_items
    WHERE user_id = v_user_id;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object(
        'success', true,
        'items_removed', v_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ---------------------------------------------
-- get_cart_summary() - Get cart totals only
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
        COALESCE(SUM(wo.price_paise * ci.quantity), 0)
    INTO v_item_count, v_subtotal_paise
    FROM cart_items ci
    JOIN weight_options wo ON wo.id = ci.weight_option_id
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

GRANT SELECT, INSERT, UPDATE, DELETE ON cart_items TO authenticated;
GRANT EXECUTE ON FUNCTION get_cart() TO authenticated;
GRANT EXECUTE ON FUNCTION add_to_cart(UUID, UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION update_cart_quantity(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION remove_from_cart(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION clear_cart() TO authenticated;
GRANT EXECUTE ON FUNCTION get_cart_summary() TO authenticated;
