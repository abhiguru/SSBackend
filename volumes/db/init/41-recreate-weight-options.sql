-- 41-recreate-weight-options.sql
-- Recreate weight_options table for catalog/display purposes.
-- Cart/checkout still uses custom_weight_grams with price_per_kg_paise calculations.

BEGIN;

-- (a) Create table
CREATE TABLE IF NOT EXISTS weight_options (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    weight_grams INT NOT NULL,
    label VARCHAR(50),
    label_gu VARCHAR(50),
    is_available BOOLEAN NOT NULL DEFAULT true,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(product_id, weight_grams)
);

CREATE INDEX IF NOT EXISTS idx_weight_product ON weight_options(product_id);

-- (b) updated_at trigger
CREATE TRIGGER update_weight_options_updated_at
    BEFORE UPDATE ON weight_options
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- (c) RLS
ALTER TABLE weight_options ENABLE ROW LEVEL SECURITY;

CREATE POLICY "weight_options_public_read" ON weight_options
    FOR SELECT TO anon, authenticated
    USING (is_available = true);

CREATE POLICY "weight_options_admin_all" ON weight_options
    FOR ALL TO authenticated
    USING ((SELECT auth.is_admin()))
    WITH CHECK ((SELECT auth.is_admin()));

-- (d) Permissions
GRANT SELECT ON weight_options TO anon, authenticated;
GRANT ALL ON weight_options TO authenticated;

-- (e) Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
