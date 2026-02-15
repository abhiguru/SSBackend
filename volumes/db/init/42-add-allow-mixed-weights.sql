-- Add allow_mixed_weights flag to products table
-- When true (default): customer accumulates weight via preset buttons into one cart item
-- When false: each weight option is a separate selectable variant (like a size picker)

ALTER TABLE products
ADD COLUMN IF NOT EXISTS allow_mixed_weights BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN products.allow_mixed_weights IS
  'When true, weight presets accumulate into a single total. When false, each weight option is a distinct variant selected individually.';
