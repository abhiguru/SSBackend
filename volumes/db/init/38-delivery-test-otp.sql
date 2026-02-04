-- 38-delivery-test-otp.sql
-- Add fixed test OTP for delivery staff test account

INSERT INTO test_otp_records (phone_number, fixed_otp, description)
VALUES ('+919999900002', '123456', 'Delivery staff test account')
ON CONFLICT (phone_number) DO UPDATE SET
    fixed_otp = EXCLUDED.fixed_otp,
    description = EXCLUDED.description,
    updated_at = NOW();
