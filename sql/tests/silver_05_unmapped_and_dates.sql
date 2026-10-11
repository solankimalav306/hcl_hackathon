-- New label variants that the mapping seeds do not cover yet, and dates that failed to parse.
SELECT 'customer_segment unmapped' AS check_name, customer_id AS key, customer_segment_raw AS value
  FROM silver.stg_customers WHERE customer_segment = 'Unknown'
UNION ALL SELECT 'category unmapped', product_id, category_raw FROM silver.stg_products WHERE category = 'Unknown'
UNION ALL SELECT 'order_status unmapped', order_id, order_status_raw FROM silver.stg_orders WHERE order_status = 'Unknown'
UNION ALL SELECT 'channel unmapped', order_id, channel_raw FROM silver.stg_orders WHERE channel = 'Unknown'
UNION ALL SELECT 'payment_status unmapped', payment_id, payment_status_raw FROM silver.stg_payments WHERE payment_status = 'Unknown'
UNION ALL SELECT 'return_status unmapped', return_id, return_status_raw FROM silver.stg_returns WHERE return_status = 'Unknown'
UNION ALL SELECT 'return_reason unmapped', return_id, return_reason_raw FROM silver.stg_returns WHERE return_reason = 'Unknown'
UNION ALL SELECT 'order_date unparsed', order_id, order_date_raw FROM silver.stg_orders WHERE order_date IS NULL
UNION ALL SELECT 'return_date unparsed', return_id, return_date_raw FROM silver.stg_returns WHERE return_date_parsed IS NULL
UNION ALL SELECT 'launch_date unparsed', product_id, launch_date_raw FROM silver.stg_products WHERE launch_date IS NULL
UNION ALL SELECT 'payment_date unparsed (non-blank)', payment_id, payment_date_raw
  FROM silver.stg_payments WHERE payment_date IS NULL AND TRIM(payment_date_raw) != ''
