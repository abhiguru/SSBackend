-- Insert default weight options (100g, 200g, 500g) for all products
-- Skips products that already have a given weight_grams entry

INSERT INTO weight_options (product_id, weight_grams, label, label_gu, display_order)
SELECT p.id, w.weight_grams, w.label, w.label_gu, w.display_order
FROM products p
CROSS JOIN (VALUES
    (100, '100g', '૧૦૦ ગ્રામ', 0),
    (200, '200g', '૨૦૦ ગ્રામ', 1),
    (500, '500g', '૫૦૦ ગ્રામ', 2)
) AS w(weight_grams, label, label_gu, display_order)
ON CONFLICT (product_id, weight_grams) DO UPDATE
    SET label = EXCLUDED.label,
        label_gu = EXCLUDED.label_gu,
        display_order = EXCLUDED.display_order
    WHERE weight_options.label IS NULL OR weight_options.label = '';
