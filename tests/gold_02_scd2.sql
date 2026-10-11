-- SCD 2 integrity on dim_customer: exactly one current version per customer,
-- valid_from <= valid_to, and no overlapping validity ranges.
SELECT 'not exactly one current version' AS check_name, customer_id AS key
FROM gold.dim_customer GROUP BY customer_id HAVING COUNTIF(is_current) != 1
UNION ALL
SELECT 'valid_from after valid_to', CAST(customer_sk AS STRING)
FROM gold.dim_customer WHERE valid_from > valid_to
UNION ALL
SELECT 'overlapping versions', a.customer_id
FROM gold.dim_customer a
JOIN gold.dim_customer b
  ON a.customer_id = b.customer_id AND a.customer_sk < b.customer_sk
 AND a.valid_from <= b.valid_to AND b.valid_from <= a.valid_to
