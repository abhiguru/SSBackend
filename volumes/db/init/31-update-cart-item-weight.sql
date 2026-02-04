BEGIN;

CREATE OR REPLACE FUNCTION update_cart_item_weight(
    p_cart_item_id UUID,
    p_new_weight_grams INT,
    p_new_quantity INT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_product_id UUID;
    v_current_quantity INT;
    v_existing_item_id UUID;
    v_existing_quantity INT;
    v_merged_quantity INT;
BEGIN
    -- Auth check
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    -- Validate weight range
    IF p_new_weight_grams < 10 OR p_new_weight_grams > 25000 THEN
        RETURN json_build_object('success', false, 'error', 'INVALID_WEIGHT');
    END IF;

    -- Validate quantity if provided
    IF p_new_quantity IS NOT NULL AND (p_new_quantity < 1 OR p_new_quantity > 99) THEN
        RETURN json_build_object('success', false, 'error', 'INVALID_QUANTITY');
    END IF;

    -- Get current cart item (verify ownership)
    SELECT product_id, quantity INTO v_product_id, v_current_quantity
    FROM cart_items
    WHERE id = p_cart_item_id AND user_id = v_user_id;

    IF v_product_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'CART_ITEM_NOT_FOUND');
    END IF;

    -- Check if another cart item exists with target weight
    SELECT id, quantity INTO v_existing_item_id, v_existing_quantity
    FROM cart_items
    WHERE user_id = v_user_id
      AND product_id = v_product_id
      AND custom_weight_grams = p_new_weight_grams
      AND id != p_cart_item_id;

    IF v_existing_item_id IS NOT NULL THEN
        -- Merge: add quantities (cap at 99)
        v_merged_quantity := LEAST(
            v_existing_quantity + COALESCE(p_new_quantity, v_current_quantity),
            99
        );

        -- Update the existing item's quantity
        UPDATE cart_items
        SET quantity = v_merged_quantity, updated_at = now()
        WHERE id = v_existing_item_id;

        -- Delete the original item
        DELETE FROM cart_items WHERE id = p_cart_item_id;

        RETURN json_build_object('success', true, 'merged', true);
    ELSE
        -- Update in-place
        UPDATE cart_items
        SET custom_weight_grams = p_new_weight_grams,
            quantity = COALESCE(p_new_quantity, quantity),
            updated_at = now()
        WHERE id = p_cart_item_id;

        RETURN json_build_object('success', true, 'merged', false);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_cart_item_weight(UUID, INT, INT) TO authenticated;

COMMIT;
