-- =============================================
-- Image Optimizations Migration
-- =============================================
-- 1. Make product-images bucket public (for website <img> tags)
-- 2. Add register_and_confirm_product_image() combined RPC
--
-- Safe to run multiple times (idempotent).

-- =============================================
-- Make product-images bucket public
-- =============================================
-- Product images are displayed on the marketing website via <img> tags,
-- which cannot send auth headers. The public path (/object/public/...)
-- serves files without authentication.
-- The authenticated path (/object/authenticated/...) still works for
-- the mobile app which sends auth headers.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'public') THEN
        UPDATE storage.buckets SET public = true WHERE id = 'product-images';
    END IF;
END
$$;

-- =============================================
-- RPC: register_and_confirm_product_image
-- =============================================
-- Combined insert+confirm in a single round trip.
-- Skips the pending state — inserts as confirmed directly.

CREATE OR REPLACE FUNCTION register_and_confirm_product_image(
    p_product_id UUID,
    p_storage_path TEXT,
    p_original_filename VARCHAR(255),
    p_file_size INT,
    p_mime_type VARCHAR(50)
) RETURNS JSONB AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION register_and_confirm_product_image(UUID, TEXT, VARCHAR, INT, VARCHAR) TO authenticated;
