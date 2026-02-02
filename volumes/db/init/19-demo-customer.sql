-- 19-demo-customer.sql
-- Seed a demo customer account with a fixed test OTP for development/testing.
-- Phone: +916000000001 | OTP: 123456

BEGIN;

-- 1. Fixed test OTP so send-otp/verify-otp work without MSG91
INSERT INTO test_otp_records (phone_number, fixed_otp, description)
VALUES ('+916000000001', '123456', 'Demo customer account')
ON CONFLICT (phone_number) DO NOTHING;

-- 2. Demo user
INSERT INTO users (phone, name, role, language, is_active)
VALUES ('+916000000001', 'Priya Shah', 'customer', 'en', true)
ON CONFLICT (phone) DO NOTHING;

-- 3. Demo address (Ahmedabad 380001 — already in serviceable pincodes)
INSERT INTO user_addresses (user_id, label, full_name, phone, address_line1, address_line2, city, state, pincode, is_default)
SELECT id, 'Home', 'Priya Shah', '+916000000001',
       '42, Sahjanand Society', 'Near Paldi Cross Road',
       'Ahmedabad', 'Gujarat', '380001', true
FROM users WHERE phone = '+916000000001'
ON CONFLICT DO NOTHING;

COMMIT;
