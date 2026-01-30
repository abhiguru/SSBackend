-- Seed: Add a mock address to every user that doesn't already have one

INSERT INTO user_addresses (user_id, label, full_name, phone, address_line1, address_line2, city, state, pincode, is_default)
SELECT
    u.id,
    'Home',
    COALESCE(u.name, 'Customer'),
    u.phone,
    '12, Shanti Nagar Society',
    'Near Swaminarayan Temple',
    'Ahmedabad',
    'Gujarat',
    '380013',
    true
FROM users u
WHERE NOT EXISTS (
    SELECT 1 FROM user_addresses ua WHERE ua.user_id = u.id
);
