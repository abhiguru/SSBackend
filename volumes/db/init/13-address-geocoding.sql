-- Migration: Add geocoding columns to user_addresses
-- Stores cached lat/lng from Google Geocoding API so Porter doesn't re-geocode every booking

ALTER TABLE user_addresses
  ADD COLUMN IF NOT EXISTS lat DECIMAL(10,8),
  ADD COLUMN IF NOT EXISTS lng DECIMAL(11,8),
  ADD COLUMN IF NOT EXISTS formatted_address TEXT;
