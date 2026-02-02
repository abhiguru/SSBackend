-- 22-add-prices.sql
-- Set price_per_kg_paise for all 86 products.
-- Prices target mid-range local retail (loose/unbranded Gujarat masala shop level).

BEGIN;

-- Spices
UPDATE products SET price_per_kg_paise = 25000  WHERE name = 'Crushed Chilli (Local)';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Crushed Chilli (Medium)';
UPDATE products SET price_per_kg_paise = 40000  WHERE name = 'Crushed Chilli (Kashmiri)';
UPDATE products SET price_per_kg_paise = 15000  WHERE name = 'Whole Turmeric';
UPDATE products SET price_per_kg_paise = 20000  WHERE name = 'Turmeric Powder';
UPDATE products SET price_per_kg_paise = 15000  WHERE name = 'Whole Coriander Seeds';
UPDATE products SET price_per_kg_paise = 22000  WHERE name = 'Crushed Coriander-Cumin';
UPDATE products SET price_per_kg_paise = 28000  WHERE name = 'Spiced Coriander-Cumin Mix';
UPDATE products SET price_per_kg_paise = 40000  WHERE name = 'Cumin Seeds';
UPDATE products SET price_per_kg_paise = 45000  WHERE name = 'Cumin Powder';
UPDATE products SET price_per_kg_paise = 8000   WHERE name = 'Mustard Seeds';
UPDATE products SET price_per_kg_paise = 12000  WHERE name = 'Split Mustard Seeds (Yellow)';
UPDATE products SET price_per_kg_paise = 10000  WHERE name = 'Fenugreek Seeds';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Carom Seeds (Ajwain)';
UPDATE products SET price_per_kg_paise = 40000  WHERE name = 'Salted Kokum';
UPDATE products SET price_per_kg_paise = 15000  WHERE name = 'Tamarind';
UPDATE products SET price_per_kg_paise = 150000 WHERE name = 'Crushed Asafoetida';
UPDATE products SET price_per_kg_paise = 40000  WHERE name = 'Lentil & Veg Spice Mix';
UPDATE products SET price_per_kg_paise = 50000  WHERE name = 'Tea Masala';
UPDATE products SET price_per_kg_paise = 20000  WHERE name = 'Fennel Seeds';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Fennel Seeds (Lucknow)';
UPDATE products SET price_per_kg_paise = 20000  WHERE name = 'Roasted Split Coriander';
UPDATE products SET price_per_kg_paise = 20000  WHERE name = 'Sesame Seeds';
UPDATE products SET price_per_kg_paise = 25000  WHERE name = 'Black Sesame Seeds';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Flaxseed Masala';
UPDATE products SET price_per_kg_paise = 20000  WHERE name = 'Coriander Powder';
UPDATE products SET price_per_kg_paise = 25000  WHERE name = 'Garlic';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Dried Mango Slices';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Dry Mango Powder (Amchur)';
UPDATE products SET price_per_kg_paise = 12000  WHERE name = 'Tapioca Pearls';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Fenugreek Pickle Mix';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Sweet Mango Pickle Mix';
UPDATE products SET price_per_kg_paise = 12000  WHERE name = 'Split Mustard Seeds';
UPDATE products SET price_per_kg_paise = 15000  WHERE name = 'Split Fenugreek Seeds';
UPDATE products SET price_per_kg_paise = 20000  WHERE name = 'Split Coriander Seeds';
UPDATE products SET price_per_kg_paise = 150000 WHERE name = 'Poppy Seeds';
UPDATE products SET price_per_kg_paise = 80000  WHERE name = 'Black Pepper';
UPDATE products SET price_per_kg_paise = 120000 WHERE name = 'Cloves';
UPDATE products SET price_per_kg_paise = 60000  WHERE name = 'Cinnamon';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Bay Leaves';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Dried Round Chillies';
UPDATE products SET price_per_kg_paise = 250000 WHERE name = 'Green Cardamom';
UPDATE products SET price_per_kg_paise = 50000  WHERE name = 'Nutmeg';
UPDATE products SET price_per_kg_paise = 180000 WHERE name = 'Black Cardamom';
UPDATE products SET price_per_kg_paise = 80000  WHERE name = 'Star Anise';
UPDATE products SET price_per_kg_paise = 25000  WHERE name = 'Dried Fenugreek Leaves';
UPDATE products SET price_per_kg_paise = 200000 WHERE name = 'Mace';
UPDATE products SET price_per_kg_paise = 90000  WHERE name = 'Cinnamon (Export)';

-- Dried Goods
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Rice Papads';
UPDATE products SET price_per_kg_paise = 32000  WHERE name = 'Small Rice Papads';
UPDATE products SET price_per_kg_paise = 8000   WHERE name = 'Wheat Vermicelli';
UPDATE products SET price_per_kg_paise = 25000  WHERE name = 'Dried Potato Chips';
UPDATE products SET price_per_kg_paise = 28000  WHERE name = 'Potato Wafers (Netted)';
UPDATE products SET price_per_kg_paise = 28000  WHERE name = 'Potato Sticks';

-- Powders
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Dry Ginger Powder';
UPDATE products SET price_per_kg_paise = 40000  WHERE name = 'Pipramul Root Powder';
UPDATE products SET price_per_kg_paise = 6000   WHERE name = 'Baking Soda';
UPDATE products SET price_per_kg_paise = 12000  WHERE name = 'Citric Acid';
UPDATE products SET price_per_kg_paise = 8000   WHERE name = 'Rock Salt Powder';
UPDATE products SET price_per_kg_paise = 10000  WHERE name = 'Black Salt Powder';
UPDATE products SET price_per_kg_paise = 20000  WHERE name = 'Fenugreek Powder';
UPDATE products SET price_per_kg_paise = 90000  WHERE name = 'Black Pepper Powder';
UPDATE products SET price_per_kg_paise = 70000  WHERE name = 'Cinnamon Powder';
UPDATE products SET price_per_kg_paise = 50000  WHERE name = 'Tomato Powder';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Tamarind Powder';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Lemon Powder';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Psyllium Husk';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Chilli Flakes';
UPDATE products SET price_per_kg_paise = 50000  WHERE name = 'Oregano';
UPDATE products SET price_per_kg_paise = 25000  WHERE name = 'Onion Powder';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Garlic Powder';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Onion Flakes';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Garlic Flakes';
UPDATE products SET price_per_kg_paise = 40000  WHERE name = 'Degi Chilli Powder';

-- Spice Mixes
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Dabeli Masala';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Buttermilk Masala';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Chole Masala';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Pav Bhaji Masala';
UPDATE products SET price_per_kg_paise = 40000  WHERE name = 'Biryani Masala';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Chaat Masala';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Sambar Masala';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Kitchen King';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Peri Peri';
UPDATE products SET price_per_kg_paise = 25000  WHERE name = 'Khichdi Masala';
UPDATE products SET price_per_kg_paise = 30000  WHERE name = 'Jiralu Powder';
UPDATE products SET price_per_kg_paise = 35000  WHERE name = 'Vadapav Masala';

-- Verify: no products with 0 price
DO $$
DECLARE
  zero_count INT;
BEGIN
  SELECT COUNT(*) INTO zero_count FROM products WHERE price_per_kg_paise = 0;
  IF zero_count > 0 THEN
    RAISE WARNING '% products still have price_per_kg_paise = 0', zero_count;
  END IF;
END $$;

COMMIT;
