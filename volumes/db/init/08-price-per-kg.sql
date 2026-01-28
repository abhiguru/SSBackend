-- =============================================
-- Migration: Add price_per_kg_paise to products
-- =============================================

-- Add column
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS price_per_kg_paise INT NOT NULL DEFAULT 0
    CHECK (price_per_kg_paise >= 0);

-- Set per-product prices (paise per kg, based on Jan 2026 Indian market rates)
-- Uses actual product names from the database
UPDATE products SET price_per_kg_paise = CASE name
  -- Spices
  WHEN 'Bay Leaves'                   THEN 12000
  WHEN 'Black Cardamom'               THEN 180000
  WHEN 'Black Pepper'                 THEN 65000
  WHEN 'Black Sesame Seeds'           THEN 25000
  WHEN 'Carom Seeds (Ajwain)'         THEN 22000
  WHEN 'Cinnamon'                     THEN 60000
  WHEN 'Cinnamon (Export)'            THEN 90000
  WHEN 'Cloves'                       THEN 90000
  WHEN 'Crushed Asafoetida'           THEN 150000
  WHEN 'Crushed Chilli (Kashmiri)'    THEN 50000
  WHEN 'Crushed Chilli (Local)'       THEN 30000
  WHEN 'Crushed Chilli (Medium)'      THEN 38000
  WHEN 'Crushed Coriander-Cumin'      THEN 28000
  WHEN 'Cumin Seeds'                  THEN 35000
  WHEN 'Dried Fenugreek Leaves'       THEN 40000
  WHEN 'Dried Mango Slices'           THEN 30000
  WHEN 'Dried Round Chillies'         THEN 35000
  WHEN 'Dry Mango Powder (Amchur)'    THEN 25000
  WHEN 'Fennel Seeds'                 THEN 20000
  WHEN 'Fennel Seeds (Lucknow)'       THEN 30000
  WHEN 'Fenugreek Pickle Mix'         THEN 22000
  WHEN 'Fenugreek Seeds'              THEN 12000
  WHEN 'Flaxseed Masala'              THEN 28000
  WHEN 'Garlic'                       THEN 15000
  WHEN 'Green Cardamom'               THEN 280000
  WHEN 'Lentil & Veg Spice Mix'       THEN 35000
  WHEN 'Mace'                         THEN 250000
  WHEN 'Mustard Seeds'                THEN 8000
  WHEN 'Nutmeg'                       THEN 200000
  WHEN 'Poppy Seeds'                  THEN 55000
  WHEN 'Roasted Split Coriander'      THEN 18000
  WHEN 'Salted Kokum'                 THEN 25000
  WHEN 'Sesame Seeds'                 THEN 20000
  WHEN 'Spiced Coriander-Cumin Mix'   THEN 30000
  WHEN 'Split Coriander Seeds'        THEN 16000
  WHEN 'Split Fenugreek Seeds'        THEN 14000
  WHEN 'Split Mustard Seeds'          THEN 10000
  WHEN 'Split Mustard Seeds (Yellow)' THEN 11000
  WHEN 'Star Anise'                   THEN 80000
  WHEN 'Sweet Mango Pickle Mix'       THEN 22000
  WHEN 'Tamarind'                     THEN 15000
  WHEN 'Tapioca Pearls'              THEN 12000
  WHEN 'Whole Coriander Seeds'       THEN 15000
  WHEN 'Whole Turmeric'              THEN 22000

  -- Spice Mixes
  WHEN 'Biryani Masala'               THEN 80000
  WHEN 'Buttermilk Masala'            THEN 60000
  WHEN 'Chaat Masala'                 THEN 55000
  WHEN 'Chole Masala'                 THEN 65000
  WHEN 'Dabeli Masala'                THEN 55000
  WHEN 'Jiralu Powder'               THEN 45000
  WHEN 'Khichdi Masala'              THEN 50000
  WHEN 'Kitchen King'                 THEN 70000
  WHEN 'Pav Bhaji Masala'            THEN 65000
  WHEN 'Peri Peri'                    THEN 80000
  WHEN 'Sambar Masala'                THEN 50000
  WHEN 'Tea Masala'                   THEN 120000
  WHEN 'Vadapav Masala'               THEN 55000

  -- Powders
  WHEN 'Baking Soda'                  THEN 8000
  WHEN 'Black Pepper Powder'          THEN 70000
  WHEN 'Black Salt Powder'            THEN 10000
  WHEN 'Chilli Flakes'                THEN 40000
  WHEN 'Cinnamon Powder'              THEN 65000
  WHEN 'Citric Acid'                  THEN 15000
  WHEN 'Coriander Powder'             THEN 25000
  WHEN 'Cumin Powder'                 THEN 40000
  WHEN 'Degi Chilli Powder'           THEN 45000
  WHEN 'Dry Ginger Powder'            THEN 35000
  WHEN 'Fenugreek Powder'             THEN 18000
  WHEN 'Garlic Flakes'                THEN 30000
  WHEN 'Garlic Powder'                THEN 32000
  WHEN 'Lemon Powder'                 THEN 25000
  WHEN 'Onion Flakes'                 THEN 28000
  WHEN 'Onion Powder'                 THEN 22000
  WHEN 'Oregano'                      THEN 50000
  WHEN 'Pipramul Root Powder'         THEN 60000
  WHEN 'Psyllium Husk'                THEN 25000
  WHEN 'Rock Salt Powder'             THEN 8000
  WHEN 'Tamarind Powder'              THEN 20000
  WHEN 'Tomato Powder'                THEN 35000
  WHEN 'Turmeric Powder'              THEN 30000

  -- Dried Goods
  WHEN 'Dried Potato Chips'           THEN 18000
  WHEN 'Potato Sticks'                THEN 20000
  WHEN 'Potato Wafers (Netted)'       THEN 22000
  WHEN 'Rice Papads'                  THEN 16000
  WHEN 'Small Rice Papads'            THEN 17000
  WHEN 'Wheat Vermicelli'             THEN 12000

  ELSE 0
END
WHERE price_per_kg_paise = 0;
