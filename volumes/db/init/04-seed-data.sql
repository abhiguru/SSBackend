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

    -- Whole Spices (price_per_kg_paise based on Jan 2026 Indian market rates)
    INSERT INTO products (id, category_id, name, name_gu, description, price_per_kg_paise, display_order) VALUES
        (uuid_generate_v4(), whole_spices_id, 'Cinnamon Sticks', 'તજ', 'Premium quality cinnamon sticks, aromatic and fresh', 60000, 1),
        (uuid_generate_v4(), whole_spices_id, 'Cloves', 'લવિંગ', 'Hand-picked whole cloves with intense aroma', 90000, 2),
        (uuid_generate_v4(), whole_spices_id, 'Black Cardamom', 'મોટી એલચી', 'Large black cardamom pods, smoky flavor', 180000, 3),
        (uuid_generate_v4(), whole_spices_id, 'Green Cardamom', 'લીલી એલચી', 'Fresh green cardamom, perfect for tea and desserts', 280000, 4),
        (uuid_generate_v4(), whole_spices_id, 'Bay Leaves', 'તેજપત્તા', 'Aromatic bay leaves for curries and biryanis', 12000, 5)
    ON CONFLICT DO NOTHING;

    -- Ground Spices
    INSERT INTO products (id, category_id, name, name_gu, description, price_per_kg_paise, display_order) VALUES
        (uuid_generate_v4(), ground_spices_id, 'Turmeric Powder', 'હળદર', 'Pure turmeric powder, vibrant color and flavor', 30000, 1),
        (uuid_generate_v4(), ground_spices_id, 'Red Chilli Powder', 'લાલ મરચું', 'Hot red chilli powder for authentic taste', 35000, 2),
        (uuid_generate_v4(), ground_spices_id, 'Coriander Powder', 'ધાણાજીરું', 'Freshly ground coriander, earthy and citrusy', 25000, 3),
        (uuid_generate_v4(), ground_spices_id, 'Cumin Powder', 'જીરું પાવડર', 'Aromatic cumin powder, essential for Indian cooking', 40000, 4)
    ON CONFLICT DO NOTHING;

    -- Blended Masalas
    INSERT INTO products (id, category_id, name, name_gu, description, price_per_kg_paise, display_order) VALUES
        (uuid_generate_v4(), blended_id, 'Garam Masala', 'ગરમ મસાલો', 'Traditional blend of aromatic spices', 100000, 1),
        (uuid_generate_v4(), blended_id, 'Chai Masala', 'ચા મસાલો', 'Perfect blend for authentic masala chai', 120000, 2),
        (uuid_generate_v4(), blended_id, 'Kitchen King Masala', 'કિચન કિંગ', 'All-purpose masala for vegetables and curries', 70000, 3),
        (uuid_generate_v4(), blended_id, 'Sambhar Masala', 'સાંભાર મસાલો', 'South Indian style sambhar spice mix', 50000, 4)
    ON CONFLICT DO NOTHING;

    -- Seeds
    INSERT INTO products (id, category_id, name, name_gu, description, price_per_kg_paise, display_order) VALUES
        (uuid_generate_v4(), seeds_id, 'Cumin Seeds', 'જીરું', 'Whole cumin seeds, essential tempering spice', 35000, 1),
        (uuid_generate_v4(), seeds_id, 'Mustard Seeds', 'રાઈ', 'Black mustard seeds for South Indian cooking', 8000, 2),
        (uuid_generate_v4(), seeds_id, 'Fenugreek Seeds', 'મેથી', 'Fenugreek seeds, slightly bitter, great for pickles', 12000, 3),
        (uuid_generate_v4(), seeds_id, 'Fennel Seeds', 'વરીયાળી', 'Sweet fennel seeds, perfect after-meal digestive', 20000, 4)
    ON CONFLICT DO NOTHING;
END $$;

-- =============================================
-- WEIGHT OPTIONS
-- No predefined rows — weight is a custom value
-- sent from the frontend. Price is computed at
-- checkout as: price_per_kg_paise * weight_grams / 1000
-- =============================================

-- =============================================
-- Note: Super admin user should be created via edge function
-- after first deployment, not in seed data
-- =============================================
