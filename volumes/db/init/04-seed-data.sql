-- =============================================
-- Masala Spice Shop - Seed Data
-- =============================================

-- =============================================
-- CATEGORIES
-- =============================================

INSERT INTO categories (name, name_gu, slug, display_order, is_active) VALUES
    ('Whole Spices', 'આખા મસાલા', 'whole-spices', 1, true),
    ('Ground Spices', 'પીસેલા મસાલા', 'ground-spices', 2, true),
    ('Blended Masalas', 'મિશ્ર મસાલા', 'blended-masalas', 3, true),
    ('Seeds', 'બીજ', 'seeds', 4, true),
    ('Dried Herbs', 'સૂકી વનસ્પતિ', 'dried-herbs', 5, true)
ON CONFLICT (slug) DO NOTHING;

-- =============================================
-- SAMPLE PRODUCTS
-- =============================================

-- Get category IDs
DO $$
DECLARE
    whole_spices_id UUID;
    ground_spices_id UUID;
    blended_id UUID;
    seeds_id UUID;
BEGIN
    SELECT id INTO whole_spices_id FROM categories WHERE slug = 'whole-spices';
    SELECT id INTO ground_spices_id FROM categories WHERE slug = 'ground-spices';
    SELECT id INTO blended_id FROM categories WHERE slug = 'blended-masalas';
    SELECT id INTO seeds_id FROM categories WHERE slug = 'seeds';

    -- Whole Spices
    INSERT INTO products (id, category_id, name, name_gu, description, display_order) VALUES
        (uuid_generate_v4(), whole_spices_id, 'Cinnamon Sticks', 'તજ', 'Premium quality cinnamon sticks, aromatic and fresh', 1),
        (uuid_generate_v4(), whole_spices_id, 'Cloves', 'લવિંગ', 'Hand-picked whole cloves with intense aroma', 2),
        (uuid_generate_v4(), whole_spices_id, 'Black Cardamom', 'મોટી એલચી', 'Large black cardamom pods, smoky flavor', 3),
        (uuid_generate_v4(), whole_spices_id, 'Green Cardamom', 'લીલી એલચી', 'Fresh green cardamom, perfect for tea and desserts', 4),
        (uuid_generate_v4(), whole_spices_id, 'Bay Leaves', 'તેજપત્તા', 'Aromatic bay leaves for curries and biryanis', 5)
    ON CONFLICT DO NOTHING;

    -- Ground Spices
    INSERT INTO products (id, category_id, name, name_gu, description, display_order) VALUES
        (uuid_generate_v4(), ground_spices_id, 'Turmeric Powder', 'હળદર', 'Pure turmeric powder, vibrant color and flavor', 1),
        (uuid_generate_v4(), ground_spices_id, 'Red Chilli Powder', 'લાલ મરચું', 'Hot red chilli powder for authentic taste', 2),
        (uuid_generate_v4(), ground_spices_id, 'Coriander Powder', 'ધાણાજીરું', 'Freshly ground coriander, earthy and citrusy', 3),
        (uuid_generate_v4(), ground_spices_id, 'Cumin Powder', 'જીરું પાવડર', 'Aromatic cumin powder, essential for Indian cooking', 4)
    ON CONFLICT DO NOTHING;

    -- Blended Masalas
    INSERT INTO products (id, category_id, name, name_gu, description, display_order) VALUES
        (uuid_generate_v4(), blended_id, 'Garam Masala', 'ગરમ મસાલો', 'Traditional blend of aromatic spices', 1),
        (uuid_generate_v4(), blended_id, 'Chai Masala', 'ચા મસાલો', 'Perfect blend for authentic masala chai', 2),
        (uuid_generate_v4(), blended_id, 'Kitchen King Masala', 'કિચન કિંગ', 'All-purpose masala for vegetables and curries', 3),
        (uuid_generate_v4(), blended_id, 'Sambhar Masala', 'સાંભાર મસાલો', 'South Indian style sambhar spice mix', 4)
    ON CONFLICT DO NOTHING;

    -- Seeds
    INSERT INTO products (id, category_id, name, name_gu, description, display_order) VALUES
        (uuid_generate_v4(), seeds_id, 'Cumin Seeds', 'જીરું', 'Whole cumin seeds, essential tempering spice', 1),
        (uuid_generate_v4(), seeds_id, 'Mustard Seeds', 'રાઈ', 'Black mustard seeds for South Indian cooking', 2),
        (uuid_generate_v4(), seeds_id, 'Fenugreek Seeds', 'મેથી', 'Fenugreek seeds, slightly bitter, great for pickles', 3),
        (uuid_generate_v4(), seeds_id, 'Fennel Seeds', 'વરીયાળી', 'Sweet fennel seeds, perfect after-meal digestive', 4)
    ON CONFLICT DO NOTHING;
END $$;

-- =============================================
-- WEIGHT OPTIONS FOR ALL PRODUCTS
-- =============================================

-- Add weight options for each product
INSERT INTO weight_options (product_id, weight_grams, weight_label, price_paise, display_order)
SELECT
    p.id,
    50,
    '50g',
    CASE
        WHEN c.slug = 'whole-spices' THEN 4500
        WHEN c.slug = 'ground-spices' THEN 3500
        WHEN c.slug = 'blended-masalas' THEN 5500
        WHEN c.slug = 'seeds' THEN 2500
        ELSE 3500
    END,
    1
FROM products p
JOIN categories c ON p.category_id = c.id
ON CONFLICT DO NOTHING;

INSERT INTO weight_options (product_id, weight_grams, weight_label, price_paise, display_order)
SELECT
    p.id,
    100,
    '100g',
    CASE
        WHEN c.slug = 'whole-spices' THEN 8500
        WHEN c.slug = 'ground-spices' THEN 6500
        WHEN c.slug = 'blended-masalas' THEN 10000
        WHEN c.slug = 'seeds' THEN 4500
        ELSE 6500
    END,
    2
FROM products p
JOIN categories c ON p.category_id = c.id
ON CONFLICT DO NOTHING;

INSERT INTO weight_options (product_id, weight_grams, weight_label, price_paise, display_order)
SELECT
    p.id,
    250,
    '250g',
    CASE
        WHEN c.slug = 'whole-spices' THEN 19900
        WHEN c.slug = 'ground-spices' THEN 14900
        WHEN c.slug = 'blended-masalas' THEN 22900
        WHEN c.slug = 'seeds' THEN 9900
        ELSE 14900
    END,
    3
FROM products p
JOIN categories c ON p.category_id = c.id
ON CONFLICT DO NOTHING;

INSERT INTO weight_options (product_id, weight_grams, weight_label, price_paise, display_order)
SELECT
    p.id,
    500,
    '500g',
    CASE
        WHEN c.slug = 'whole-spices' THEN 37900
        WHEN c.slug = 'ground-spices' THEN 27900
        WHEN c.slug = 'blended-masalas' THEN 42900
        WHEN c.slug = 'seeds' THEN 17900
        ELSE 27900
    END,
    4
FROM products p
JOIN categories c ON p.category_id = c.id
ON CONFLICT DO NOTHING;

-- =============================================
-- Note: Super admin user should be created via edge function
-- after first deployment, not in seed data
-- =============================================
