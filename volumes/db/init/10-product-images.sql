-- =============================================
-- Masala Spice Shop - Product Images (Storage)
-- =============================================
-- Two-phase upload pattern: register → confirm/cancel
-- Supports multi-image per product with display ordering
-- Orphan cleanup for abandoned uploads

-- =============================================
-- STORAGE BUCKET
-- =============================================

-- Storage bucket creation is deferred — the storage service adds columns
-- (public, file_size_limit, allowed_mime_types) via its own migrations.
-- The bucket is created after storage service init via a separate step.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'public') THEN
        INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
        VALUES (
            'product-images',
            'product-images',
            true,
            5242880,
            ARRAY['image/jpeg', 'image/png', 'image/webp']
        ) ON CONFLICT (id) DO UPDATE SET public = true;
    ELSE
        -- Just insert minimal bucket; storage service will add columns later
        INSERT INTO storage.buckets (id, name)
        VALUES ('product-images', 'product-images')
        ON CONFLICT (id) DO NOTHING;
        RAISE NOTICE 'storage.buckets missing public column — bucket created with defaults';
    END IF;
END
$$;

-- =============================================
-- PRODUCT_IMAGES TABLE
-- =============================================

CREATE TABLE IF NOT EXISTS product_images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    file_size INT NOT NULL,
    mime_type VARCHAR(50) NOT NULL,
    display_order INT DEFAULT 0,
    uploaded_by UUID REFERENCES users(id),
    status VARCHAR(20) DEFAULT 'pending',
    upload_token UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT product_images_status_check CHECK (status IN ('pending', 'confirmed')),
    CONSTRAINT product_images_valid_file_size CHECK (file_size > 0 AND file_size <= 5242880),
    CONSTRAINT product_images_valid_mime_type CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp'))
);

-- =============================================
-- INDEXES
-- =============================================

CREATE INDEX IF NOT EXISTS idx_product_images_product_id
    ON product_images(product_id);

CREATE INDEX IF NOT EXISTS idx_product_images_status_created
    ON product_images(status, created_at)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_product_images_upload_token
    ON product_images(upload_token)
    WHERE upload_token IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_product_images_uploaded_by
    ON product_images(uploaded_by);

CREATE INDEX IF NOT EXISTS idx_product_images_display_order
    ON product_images(product_id, display_order);

-- =============================================
-- UPDATED_AT TRIGGER
-- =============================================

CREATE TRIGGER update_product_images_updated_at
    BEFORE UPDATE ON product_images
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================
-- RLS ON product_images
-- =============================================

ALTER TABLE product_images ENABLE ROW LEVEL SECURITY;

-- Public read: confirmed images for available products
CREATE POLICY "product_images_public_read" ON product_images
    FOR SELECT TO anon, authenticated
    USING (
        status = 'confirmed'
        AND is_product_visible(product_id)
    );

-- Admin can read all images (including pending)
CREATE POLICY "product_images_admin_read" ON product_images
    FOR SELECT TO authenticated
    USING ((select auth.is_admin()));

-- Admin can insert images
CREATE POLICY "product_images_admin_insert" ON product_images
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.is_admin()));

-- Admin can update images
CREATE POLICY "product_images_admin_update" ON product_images
    FOR UPDATE TO authenticated
    USING ((select auth.is_admin()));

-- Admin can delete images
CREATE POLICY "product_images_admin_delete" ON product_images
    FOR DELETE TO authenticated
    USING ((select auth.is_admin()));

-- =============================================
-- RLS ON storage.objects FOR product-images BUCKET
-- =============================================

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        CREATE POLICY "product-images-read" ON storage.objects
            FOR SELECT TO authenticated
            USING (bucket_id = 'product-images');
        CREATE POLICY "product-images-upload" ON storage.objects
            FOR INSERT TO authenticated
            WITH CHECK (
                bucket_id = 'product-images'
                AND (select auth.is_admin())
            );
        CREATE POLICY "product-images-update" ON storage.objects
            FOR UPDATE TO authenticated
            USING (
                bucket_id = 'product-images'
                AND (select auth.is_admin())
            );
        CREATE POLICY "product-images-delete" ON storage.objects
            FOR DELETE TO authenticated
            USING (
                bucket_id = 'product-images'
                AND (select auth.is_admin())
            );
    ELSE
        RAISE NOTICE 'storage.objects not yet created — skipping storage RLS policies';
    END IF;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- RLS ON storage.buckets
-- =============================================
-- The storage service switches to authenticated/anon to evaluate RLS.
-- Without these policies, bucket lookups fail with 42501.

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
        CREATE POLICY "buckets_read_authenticated" ON storage.buckets
            FOR SELECT TO authenticated USING (true);
        -- Only create anon policy if 'public' column exists (added by storage service)
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'public') THEN
            CREATE POLICY "buckets_read_anon" ON storage.buckets
                FOR SELECT TO anon USING (public = true);
        END IF;
    END IF;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 's3_multipart_uploads') THEN
        CREATE POLICY "s3_uploads_auth_all" ON storage.s3_multipart_uploads
            FOR ALL TO authenticated USING (true) WITH CHECK (true);
    END IF;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 's3_multipart_uploads_parts') THEN
        CREATE POLICY "s3_parts_auth_all" ON storage.s3_multipart_uploads_parts
            FOR ALL TO authenticated USING (true) WITH CHECK (true);
    END IF;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- TABLE GRANTS
-- =============================================

GRANT SELECT ON product_images TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON product_images TO authenticated;

-- =============================================
-- RPC: confirm_product_image_upload
-- =============================================

CREATE OR REPLACE FUNCTION confirm_product_image_upload(
    p_image_id UUID,
    p_upload_token UUID
)
RETURNS JSONB AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- RPC: cleanup_orphaned_product_images
-- =============================================

CREATE OR REPLACE FUNCTION cleanup_orphaned_product_images(
    p_max_age_hours INT DEFAULT 1
)
RETURNS JSONB AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- RPC: register_and_confirm_product_image
-- =============================================
-- Combined insert+confirm in a single round trip.
-- Skips the pending state entirely — inserts as confirmed directly.

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

-- Grant RPC access
GRANT EXECUTE ON FUNCTION confirm_product_image_upload(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION register_and_confirm_product_image(UUID, TEXT, VARCHAR, INT, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_orphaned_product_images(INT) TO service_role;
