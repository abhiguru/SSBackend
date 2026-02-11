-- 20-replace-products.sql
-- Replace entire product catalog with new canonical list.
-- Prices in paise (₹1 = 100 paise), mid-range local retail Gujarat level.
-- Gujarati names transliterated from Romanized Gujarati source.

BEGIN;

-- Step 1: Delete dependent data (order matters due to foreign keys)
DELETE FROM order_items;
DELETE FROM order_status_history;
DELETE FROM orders;
DELETE FROM favorites;
DELETE FROM weight_options;
DELETE FROM product_images;
DELETE FROM products;

-- Step 2: Replace categories with canonical set using fixed UUIDs
DELETE FROM categories;
INSERT INTO categories (id, name, name_gu, slug, display_order, is_active) VALUES
    ('a1000000-0000-0000-0000-000000000001', 'Spices',      'મસાલા',         'spices',      1, true),
    ('a1000000-0000-0000-0000-000000000002', 'Dried Goods',  'સૂકી વસ્તુઓ',    'dried-goods',  2, true),
    ('a1000000-0000-0000-0000-000000000003', 'Powders',      'પાવડર',          'powders',      3, true),
    ('a1000000-0000-0000-0000-000000000004', 'Spice Mixes',  'મસાલા મિશ્રણ',   'spice-mixes',  4, true)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, name_gu = EXCLUDED.name_gu, slug = EXCLUDED.slug, display_order = EXCLUDED.display_order;

-- Step 3: Insert new products
-- Using the fixed category UUIDs from the live database.

-- ============================================================
-- SPICES (48 products)
-- ============================================================
INSERT INTO products (category_id, name, name_gu, price_per_kg_paise, is_available, is_active, display_order) VALUES
('a1000000-0000-0000-0000-000000000001', 'Crushed Chilli (Local)',        'મરચું ખાંડેલું (દેશી)',          25000, true, true, 1),
('a1000000-0000-0000-0000-000000000001', 'Crushed Chilli (Medium)',       'મરચું ખાંડેલું (રેશમપટ્ટી)',     30000, true, true, 2),
('a1000000-0000-0000-0000-000000000001', 'Crushed Chilli (Kashmiri)',     'મરચું ખાંડેલું (કાશ્મીરી)',      40000, true, true, 3),
('a1000000-0000-0000-0000-000000000001', 'Whole Turmeric',               'હળદર આખી',                    15000, true, true, 4),
('a1000000-0000-0000-0000-000000000001', 'Turmeric Powder',              'હળદર દળેલી',                  20000, true, true, 5),
('a1000000-0000-0000-0000-000000000001', 'Whole Coriander Seeds',        'ધાણી આખી',                    15000, true, true, 6),
('a1000000-0000-0000-0000-000000000001', 'Crushed Coriander-Cumin',      'ધાણાજીરું ખાંડેલું',            22000, true, true, 7),
('a1000000-0000-0000-0000-000000000001', 'Spiced Coriander-Cumin Mix',   'મસાલા ધાણાજીરું',              28000, true, true, 8),
('a1000000-0000-0000-0000-000000000001', 'Cumin Seeds',                  'જીરું',                        40000, true, true, 9),
('a1000000-0000-0000-0000-000000000001', 'Cumin Powder',                 'જીરું પાવડર',                  45000, true, true, 10),
('a1000000-0000-0000-0000-000000000001', 'Mustard Seeds',                'રાઈ',                         8000, true, true, 11),
('a1000000-0000-0000-0000-000000000001', 'Split Mustard Seeds (Yellow)', 'રાઈ ખમણી',                    12000, true, true, 12),
('a1000000-0000-0000-0000-000000000001', 'Fenugreek Seeds',              'મેથી',                        10000, true, true, 13),
('a1000000-0000-0000-0000-000000000001', 'Carom Seeds (Ajwain)',         'અજમો',                        30000, true, true, 14),
('a1000000-0000-0000-0000-000000000001', 'Salted Kokum',                 'લૂણાવાળા કોકમ',               40000, true, true, 15),
('a1000000-0000-0000-0000-000000000001', 'Tamarind',                     'આંબલી',                       15000, true, true, 16),
('a1000000-0000-0000-0000-000000000001', 'Crushed Asafoetida',           'હીંગ ખાંડેલી',                 150000, true, true, 17),
('a1000000-0000-0000-0000-000000000001', 'Lentil & Veg Spice Mix',      'દાળ-શાક નો મસાલો',             40000, true, true, 18),
('a1000000-0000-0000-0000-000000000001', 'Tea Masala',                   'ચા નો મસાલો',                 50000, true, true, 19),
('a1000000-0000-0000-0000-000000000001', 'Fennel Seeds',                 'વરિયાળી',                     20000, true, true, 20),
('a1000000-0000-0000-0000-000000000001', 'Fennel Seeds (Lucknow)',       'વરિયાળી (લખનૌ)',               35000, true, true, 21),
('a1000000-0000-0000-0000-000000000001', 'Roasted Split Coriander',      'ધાણાદાળ (ભગત)',               20000, true, true, 22),
('a1000000-0000-0000-0000-000000000001', 'Sesame Seeds',                 'તલ',                          20000, true, true, 23),
('a1000000-0000-0000-0000-000000000001', 'Black Sesame Seeds',           'કાળા તલ',                     25000, true, true, 24),
('a1000000-0000-0000-0000-000000000001', 'Flaxseed Masala',              'અળસી મસાલા',                  30000, true, true, 25),
('a1000000-0000-0000-0000-000000000001', 'Coriander Powder',             'ધાણા પાવડર',                  20000, true, true, 26),
('a1000000-0000-0000-0000-000000000001', 'Garlic',                       'લસણ',                         25000, true, true, 27),
('a1000000-0000-0000-0000-000000000001', 'Dried Mango Slices',           'આંબોળિયા',                    35000, true, true, 28),
('a1000000-0000-0000-0000-000000000001', 'Dry Mango Powder (Amchur)',    'આંબોળિયા પાવડર',              30000, true, true, 29),
('a1000000-0000-0000-0000-000000000001', 'Tapioca Pearls',               'સાબુદાણા',                    12000, true, true, 30),
('a1000000-0000-0000-0000-000000000001', 'Fenugreek Pickle Mix',         'મેથી નો મસાલો',                35000, true, true, 31),
('a1000000-0000-0000-0000-000000000001', 'Sweet Mango Pickle Mix',       'ગોળકેરી નો મસાલો',             35000, true, true, 32),
('a1000000-0000-0000-0000-000000000001', 'Split Mustard Seeds',          'રાઈ ના કુરિયા',                12000, true, true, 33),
('a1000000-0000-0000-0000-000000000001', 'Split Fenugreek Seeds',        'મેથી ના કુરિયા',               15000, true, true, 34),
('a1000000-0000-0000-0000-000000000001', 'Split Coriander Seeds',        'ધાણાકુરિયા',                  20000, true, true, 35),
('a1000000-0000-0000-0000-000000000001', 'Poppy Seeds',                  'ખસખસ',                        150000, true, true, 36),
('a1000000-0000-0000-0000-000000000001', 'Black Pepper',                 'કાળા મરી',                    80000, true, true, 37),
('a1000000-0000-0000-0000-000000000001', 'Cloves',                       'લવિંગ',                       120000, true, true, 38),
('a1000000-0000-0000-0000-000000000001', 'Cinnamon',                     'તજ',                          60000, true, true, 39),
('a1000000-0000-0000-0000-000000000001', 'Bay Leaves',                   'તમાલપત્ર',                    30000, true, true, 40),
('a1000000-0000-0000-0000-000000000001', 'Dried Round Chillies',         'વઘારિયા મરચાં',                35000, true, true, 41),
('a1000000-0000-0000-0000-000000000001', 'Green Cardamom',               'ઈલાયચી',                     250000, true, true, 42),
('a1000000-0000-0000-0000-000000000001', 'Nutmeg',                       'જાયફળ',                       50000, true, true, 43),
('a1000000-0000-0000-0000-000000000001', 'Black Cardamom',               'એલચા',                        180000, true, true, 44),
('a1000000-0000-0000-0000-000000000001', 'Star Anise',                   'બાદિયાન',                     80000, true, true, 45),
('a1000000-0000-0000-0000-000000000001', 'Dried Fenugreek Leaves',       'કસૂરી મેથી',                   25000, true, true, 46),
('a1000000-0000-0000-0000-000000000001', 'Mace',                         'જાવંત્રી',                     200000, true, true, 47),
('a1000000-0000-0000-0000-000000000001', 'Cinnamon (Export)',            'તજ એક્સપોર્ટ',                 90000, true, true, 48);

-- ============================================================
-- DRIED GOODS (6 products)
-- ============================================================
INSERT INTO products (category_id, name, name_gu, price_per_kg_paise, is_available, is_active, display_order) VALUES
('a1000000-0000-0000-0000-000000000002', 'Rice Papads',                  'સરેવડા',                      30000, true, true, 1),
('a1000000-0000-0000-0000-000000000002', 'Small Rice Papads',            'ડિસ્કો સરેવડા',                32000, true, true, 2),
('a1000000-0000-0000-0000-000000000002', 'Wheat Vermicelli',             'ઘઉં ની સેવ',                   8000, true, true, 3),
('a1000000-0000-0000-0000-000000000002', 'Dried Potato Chips',           'બટાકા કાતરી',                 25000, true, true, 4),
('a1000000-0000-0000-0000-000000000002', 'Potato Wafers (Netted)',       'બટાકા જાળીવાળી',              28000, true, true, 5),
('a1000000-0000-0000-0000-000000000002', 'Potato Sticks',                'બટાકા સળીવાળી',               28000, true, true, 6);

-- ============================================================
-- POWDERS (20 products)
-- ============================================================
INSERT INTO products (category_id, name, name_gu, price_per_kg_paise, is_available, is_active, display_order) VALUES
('a1000000-0000-0000-0000-000000000003', 'Dry Ginger Powder',            'સૂંઠ પાવડર',                  30000, true, true, 1),
('a1000000-0000-0000-0000-000000000003', 'Pipramul Root Powder',         'ગાંઠોડા પાવડર',               40000, true, true, 2),
('a1000000-0000-0000-0000-000000000003', 'Baking Soda',                  'ખાવાનો સોડા',                 6000, true, true, 3),
('a1000000-0000-0000-0000-000000000003', 'Citric Acid',                  'લીંબુ ના ફૂલ',                 12000, true, true, 4),
('a1000000-0000-0000-0000-000000000003', 'Rock Salt Powder',             'સિંધવ પાવડર',                 8000, true, true, 5),
('a1000000-0000-0000-0000-000000000003', 'Black Salt Powder',            'સંચળ પાવડર',                  10000, true, true, 6),
('a1000000-0000-0000-0000-000000000003', 'Fenugreek Powder',             'મેથી પાવડર',                  20000, true, true, 7),
('a1000000-0000-0000-0000-000000000003', 'Black Pepper Powder',          'મરી પાવડર',                   90000, true, true, 8),
('a1000000-0000-0000-0000-000000000003', 'Cinnamon Powder',              'તજ પાવડર',                    70000, true, true, 9),
('a1000000-0000-0000-0000-000000000003', 'Tomato Powder',                'ટમેટો પાવડર',                 50000, true, true, 10),
('a1000000-0000-0000-0000-000000000003', 'Tamarind Powder',              'આંબલી પાવડર',                 30000, true, true, 11),
('a1000000-0000-0000-0000-000000000003', 'Lemon Powder',                 'લીંબુ પાવડર',                  35000, true, true, 12),
('a1000000-0000-0000-0000-000000000003', 'Psyllium Husk',                'ઈસબગુલ',                     30000, true, true, 13),
('a1000000-0000-0000-0000-000000000003', 'Chilli Flakes',                'ચિલી ફ્લેક્સ',                 35000, true, true, 14),
('a1000000-0000-0000-0000-000000000003', 'Oregano',                      'ઓરેગાનો',                     50000, true, true, 15),
('a1000000-0000-0000-0000-000000000003', 'Onion Powder',                 'ડુંગળી પાવડર',                 25000, true, true, 16),
('a1000000-0000-0000-0000-000000000003', 'Garlic Powder',                'લસણ પાવડર',                   30000, true, true, 17),
('a1000000-0000-0000-0000-000000000003', 'Onion Flakes',                 'ડુંગળી ફ્લેક્સ',                30000, true, true, 18),
('a1000000-0000-0000-0000-000000000003', 'Garlic Flakes',                'લસણ ફ્લેક્સ',                  35000, true, true, 19),
('a1000000-0000-0000-0000-000000000003', 'Degi Chilli Powder',           'દેગી મરચું (એક્સ્ટ્રા હોટ)',     40000, true, true, 20);

-- ============================================================
-- SPICE MIXES (12 products)
-- ============================================================
INSERT INTO products (category_id, name, name_gu, price_per_kg_paise, is_available, is_active, display_order) VALUES
('a1000000-0000-0000-0000-000000000004', 'Dabeli Masala',                'દાબેલી નો મસાલો',              35000, true, true, 1),
('a1000000-0000-0000-0000-000000000004', 'Buttermilk Masala',            'છાશ નો મસાલો',                30000, true, true, 2),
('a1000000-0000-0000-0000-000000000004', 'Chole Masala',                 'છોલે ચણા નો મસાલો',            35000, true, true, 3),
('a1000000-0000-0000-0000-000000000004', 'Pav Bhaji Masala',             'ભાજી પાવ નો મસાલો',            35000, true, true, 4),
('a1000000-0000-0000-0000-000000000004', 'Biryani Masala',               'બિરયાની નો મસાલો',             40000, true, true, 5),
('a1000000-0000-0000-0000-000000000004', 'Chaat Masala',                 'ચાટ મસાલો',                   35000, true, true, 6),
('a1000000-0000-0000-0000-000000000004', 'Sambar Masala',                'સાંભાર મસાલો',                 30000, true, true, 7),
('a1000000-0000-0000-0000-000000000004', 'Kitchen King',                 'કિચન કિંગ મસાલો',              35000, true, true, 8),
('a1000000-0000-0000-0000-000000000004', 'Peri Peri',                    'પેરી પેરી મસાલો',               30000, true, true, 9),
('a1000000-0000-0000-0000-000000000004', 'Khichdi Masala',               'ખીચડી નો મસાલો',               25000, true, true, 10),
('a1000000-0000-0000-0000-000000000004', 'Jiralu Powder',                'જીરાળું (સ્પે. ખાખરા)',          30000, true, true, 11),
('a1000000-0000-0000-0000-000000000004', 'Vadapav Masala',               'વડાપાવ નો મસાલો',              35000, true, true, 12);

-- Clean up orphaned storage objects (if storage tables exist)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        DELETE FROM storage.objects WHERE bucket_id = 'product-images';
    END IF;
END
$$;

COMMIT;
