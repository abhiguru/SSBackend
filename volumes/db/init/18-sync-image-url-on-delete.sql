-- Migration 18: Sync products.image_url when a product_images row is deleted
-- When an image is deleted, update products.image_url to the next confirmed image or NULL.

CREATE OR REPLACE FUNCTION sync_product_image_url_on_delete()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE products
    SET image_url = (
        SELECT storage_path
        FROM product_images
        WHERE product_id = OLD.product_id
          AND status = 'confirmed'
        ORDER BY display_order ASC, created_at ASC
        LIMIT 1
    )
    WHERE id = OLD.product_id;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_product_image_url_on_delete
    AFTER DELETE ON product_images
    FOR EACH ROW
    EXECUTE FUNCTION sync_product_image_url_on_delete();
