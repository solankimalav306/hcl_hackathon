-- DQ LOG: one row per record per rule (issue log), the rejected rows (quarantine),
-- a per-rule rollup, and a per-table bronze -> silver reconciliation.
-- Built entirely from the stg_* tables (raw values sit next to clean ones) and the final silver tables.
-- Capitalisation and stray spaces are normalised silently (the seed lookup is case-insensitive), so STANDARDIZED rules
-- count only real variants such as misspellings and aliases, not casing-only differences.
-- Rule ids: CUS customers, SUP suppliers, PRD products, ORD orders, OI order_items, PAY payments, RET returns.

CREATE OR REPLACE TABLE silver.dq_issue_log AS

-- ---------------------------------------------------------------- customers
SELECT 'CUS-01' AS rule_id, 'customers' AS table_name, customer_id AS record_key, 'customer_id' AS column_name,
       'Repeated customer_id (rows differ only by email casing)' AS issue, 'REMOVED_DUPLICATE' AS action,
       email_raw AS old_value, CAST(NULL AS STRING) AS new_value
FROM silver.stg_customers_ranked WHERE key_rank > 1
UNION ALL
SELECT 'CUS-02', 'customers', customer_id, 'customer_id',
       'Same person under a different customer_id (name + phone match)', 'MERGED_INTO_MASTER',
       customer_id, master_customer_id
FROM silver.customer_xref WHERE customer_id != master_customer_id
UNION ALL
SELECT 'CUS-03', 'customers', customer_id, 'customer_segment',
       'Non-standard segment label (misspelling / alias)', 'STANDARDIZED', customer_segment_raw, customer_segment
FROM silver.stg_customers_ranked WHERE key_rank = 1 AND LOWER(TRIM(customer_segment_raw)) IS DISTINCT FROM LOWER(customer_segment)
UNION ALL
SELECT 'CUS-04', 'customers', customer_id, 'city',
       'Non-standard city name (alias / Bengaluru / New Delhi)', 'STANDARDIZED', city_raw, city
FROM silver.stg_customers_ranked WHERE key_rank = 1 AND LOWER(TRIM(city_raw)) IS DISTINCT FROM LOWER(city)
UNION ALL
SELECT 'CUS-05', 'customers', customer_id, 'phone',
       'Phone in non-standard format', 'STANDARDIZED', phone_raw, phone
FROM silver.stg_customers_ranked WHERE key_rank = 1 AND phone IS NOT NULL AND phone_raw IS DISTINCT FROM phone
UNION ALL
SELECT 'CUS-05', 'customers', customer_id, 'phone',
       'Phone in non-standard format', 'SET_NULL', phone_raw, CAST(NULL AS STRING)
FROM silver.stg_customers_ranked WHERE key_rank = 1 AND phone IS NULL AND NULLIF(TRIM(phone_raw), '') IS NOT NULL
UNION ALL
SELECT 'CUS-06', 'customers', customer_id, 'email', 'Email missing', 'FLAGGED', email_raw, CAST(NULL AS STRING)
FROM silver.stg_customers_ranked WHERE key_rank = 1 AND email IS NULL
UNION ALL
SELECT 'CUS-06', 'customers', customer_id, 'email', 'Email has invalid format', 'FLAGGED', email_raw, email
FROM silver.stg_customers_ranked WHERE key_rank = 1 AND email IS NOT NULL AND NOT email_valid
UNION ALL
SELECT 'CUS-07', 'customers', customer_id, 'zip_code',
       'Zip code missing or placeholder (N/A, XXXXXX)', 'SET_NULL', zip_code_raw, CAST(NULL AS STRING)
FROM silver.stg_customers_ranked WHERE key_rank = 1 AND zip_code IS NULL
UNION ALL
SELECT 'CUS-08', 'customers', customer_id, 'signup_date',
       'Signup date missing or unparseable', 'SET_NULL', signup_date_raw, CAST(NULL AS STRING)
FROM silver.stg_customers_ranked WHERE key_rank = 1 AND signup_date IS NULL
UNION ALL
SELECT 'CUS-09', 'customers', customer_id, 'signup_date',
       'Ambiguous NN/NN/YYYY date (read as DD/MM)', 'FLAGGED', signup_date_raw, CAST(signup_date AS STRING)
FROM silver.stg_customers_ranked WHERE key_rank = 1 AND signup_date_ambiguous
UNION ALL
SELECT 'CUS-10', 'customers', customer_id, 'is_active',
       'Boolean in non-standard form (Y/yes/1/...)', 'STANDARDIZED', is_active_raw, CAST(is_active AS STRING)
FROM silver.stg_customers_ranked WHERE key_rank = 1 AND LOWER(TRIM(is_active_raw)) NOT IN ('true', 'false')
UNION ALL
SELECT 'CUS-11', 'customers', customer_id, 'first_name',
       'Leading/trailing whitespace in name', 'TRIMMED', first_name_raw, first_name
FROM silver.stg_customers_ranked WHERE key_rank = 1 AND first_name_raw IS DISTINCT FROM first_name

-- ---------------------------------------------------------------- suppliers
UNION ALL
SELECT 'SUP-01', 'suppliers', supplier_id, 'supplier_id',
       'Same supplier_id with a different supplier name (conflict)', 'REJECTED_CONFLICT', supplier_name, CAST(NULL AS STRING)
FROM silver.stg_suppliers WHERE key_rank > 1
UNION ALL
SELECT 'SUP-02', 'suppliers', supplier_id, 'rating',
       'Rating entered on a 10-point scale', 'RESCALED_TO_5', CAST(rating_raw AS STRING), CAST(ROUND(rating_raw / 2, 2) AS STRING)
FROM silver.stg_suppliers WHERE key_rank = 1 AND rating_raw > 5
UNION ALL
SELECT 'SUP-03', 'suppliers', supplier_id, 'country',
       'Country missing or "Unknown"', 'DEFAULTED', country_raw, 'Unknown'
FROM silver.stg_suppliers WHERE key_rank = 1 AND country IS NULL
UNION ALL
SELECT 'SUP-04', 'suppliers', supplier_id, 'is_preferred',
       'Boolean in non-standard form', 'STANDARDIZED', is_preferred_raw, CAST(is_preferred AS STRING)
FROM silver.stg_suppliers WHERE key_rank = 1 AND LOWER(TRIM(is_preferred_raw)) NOT IN ('true', 'false')

-- ---------------------------------------------------------------- products
UNION ALL
SELECT 'PRD-01', 'products', product_id, 'product_id',
       'Repeated product_id with conflicting name/price (Revised record kept)', 'REJECTED_CONFLICT',
       product_name_raw, CAST(NULL AS STRING)
FROM silver.stg_products WHERE key_rank > 1
UNION ALL
SELECT 'PRD-02', 'products', product_id, 'category',
       'Category missing - inferred from sub_category', 'INFERRED', category_raw, category
FROM silver.stg_products WHERE key_rank = 1 AND category_inferred AND category != 'Unknown'
UNION ALL
SELECT 'PRD-02', 'products', product_id, 'category',
       'Non-standard category label (misspelling / alias)', 'STANDARDIZED', category_raw, category
FROM silver.stg_products WHERE key_rank = 1 AND NOT category_inferred AND LOWER(TRIM(category_raw)) IS DISTINCT FROM LOWER(category)
UNION ALL
SELECT 'PRD-03', 'products', product_id, 'product_name',
       'Product name missing', 'DEFAULTED', product_name_raw, product_name
FROM silver.stg_products WHERE key_rank = 1 AND product_name_missing
UNION ALL
SELECT 'PRD-04', 'products', product_id, 'unit_price',
       'List price zero or negative', 'SET_NULL', unit_price_raw, CAST(NULL AS STRING)
FROM silver.stg_products WHERE key_rank = 1 AND list_price IS NULL
UNION ALL
SELECT 'PRD-05', 'products', product_id, 'unit_price',
       'Currency-formatted price (₹, thousands separator)', 'PARSED', unit_price_raw, CAST(list_price AS STRING)
FROM silver.stg_products WHERE key_rank = 1 AND REGEXP_CONTAINS(unit_price_raw, r'[^0-9.\-]')
UNION ALL
SELECT 'PRD-06', 'products', product_id, 'supplier_id',
       'Supplier not found in supplier master', 'FLAGGED', supplier_id, CAST(NULL AS STRING)
FROM silver.products WHERE NOT supplier_found
UNION ALL
SELECT 'PRD-07', 'products', product_id, 'cost_price',
       'Cost price exceeds list price (margin risk)', 'FLAGGED', CAST(cost_price AS STRING), CAST(list_price AS STRING)
FROM silver.products WHERE cost_exceeds_list_price

-- ---------------------------------------------------------------- orders
UNION ALL
SELECT 'ORD-01', 'orders', order_id, 'order_id', 'Exact duplicate row', 'REMOVED_DUPLICATE', order_id, CAST(NULL AS STRING)
FROM silver.stg_orders WHERE key_rank > 1
UNION ALL
SELECT 'ORD-02', 'orders', order_id, 'order_status',
       'Non-standard status (misspelling / alias)', 'STANDARDIZED', order_status_raw, order_status
FROM silver.stg_orders WHERE key_rank = 1 AND LOWER(TRIM(order_status_raw)) IS DISTINCT FROM LOWER(order_status)
UNION ALL
SELECT 'ORD-03', 'orders', order_id, 'channel',
       'Non-standard channel label (misspelling / alias)', 'STANDARDIZED', channel_raw, channel
FROM silver.stg_orders WHERE key_rank = 1 AND LOWER(TRIM(channel_raw)) IS DISTINCT FROM LOWER(channel)
UNION ALL
SELECT 'ORD-04', 'orders', order_id, 'promo_code',
       'Placeholder promo code (NA, N/A, None, null)', 'SET_NULL', promo_code_raw, CAST(NULL AS STRING)
FROM silver.stg_orders WHERE key_rank = 1 AND promo_code IS NULL AND NULLIF(TRIM(promo_code_raw), '') IS NOT NULL
UNION ALL
SELECT 'ORD-05', 'orders', order_id, 'customer_id',
       'Customer not found in CRM (orphan)', 'FLAGGED_UNKNOWN_CUSTOMER', source_customer_id, CAST(NULL AS STRING)
FROM silver.orders WHERE NOT customer_found
UNION ALL
SELECT 'ORD-06', 'orders', order_id, 'customer_id',
       'Order placed under a merged duplicate customer ID', 'REMAPPED_TO_MASTER', source_customer_id, customer_id
FROM silver.orders WHERE source_customer_id != customer_id
UNION ALL
SELECT 'ORD-07', 'orders', order_id, 'order_id', 'Order has no line items', 'FLAGGED', order_id, CAST(NULL AS STRING)
FROM silver.orders WHERE NOT has_items
UNION ALL
SELECT 'ORD-08', 'orders', o.order_id, 'order_date',
       'Ambiguous NN/NN/YYYY date (read as DD/MM)', 'FLAGGED', s.order_date_raw, CAST(o.order_date AS STRING)
FROM silver.orders o JOIN silver.stg_orders s ON s.order_id = o.order_id AND s.key_rank = 1
WHERE o.order_date_ambiguous

-- ---------------------------------------------------------------- order_items
UNION ALL
SELECT 'OI-01', 'order_items', order_item_id, 'order_item_id', 'Exact duplicate row', 'REMOVED_DUPLICATE',
       order_item_id, CAST(NULL AS STRING)
FROM silver.stg_order_items WHERE key_rank > 1
UNION ALL
SELECT 'OI-02', 'order_items', order_item_id,
       CASE reject_reason WHEN 'ORPHAN_ORDER' THEN 'order_id' WHEN 'INVALID_QUANTITY' THEN 'quantity'
                          WHEN 'INVALID_PRICE' THEN 'unit_price' ELSE 'discount_pct' END,
       CONCAT('Line rejected: ', reject_reason), 'QUARANTINED',
       CASE reject_reason WHEN 'ORPHAN_ORDER' THEN order_id WHEN 'INVALID_QUANTITY' THEN quantity_raw
                          WHEN 'INVALID_PRICE' THEN unit_price_raw ELSE discount_pct_raw END,
       CAST(NULL AS STRING)
FROM silver.stg_order_items WHERE key_rank = 1 AND reject_reason IS NOT NULL
UNION ALL
SELECT 'OI-03', 'order_items', order_item_id, 'unit_price',
       'Unit price blank - back-solved from line total', 'DERIVED_FROM_LINE_TOTAL', unit_price_raw, CAST(unit_price AS STRING)
FROM silver.stg_order_items WHERE key_rank = 1 AND reject_reason IS NULL AND unit_price_fix = 'DERIVED_FROM_LINE_TOTAL'
UNION ALL
SELECT 'OI-03', 'order_items', order_item_id, 'unit_price',
       'Negative unit price - replaced with catalog price', 'REPLACED_WITH_CATALOG_PRICE', unit_price_raw, CAST(unit_price AS STRING)
FROM silver.stg_order_items WHERE key_rank = 1 AND reject_reason IS NULL AND unit_price_fix = 'REPLACED_WITH_CATALOG_PRICE'
UNION ALL
SELECT 'OI-04', 'order_items', order_item_id, 'discount_pct',
       'Discount outside 0-100% - back-solved from line total', 'DERIVED_FROM_LINE_TOTAL', discount_pct_raw, CAST(discount_pct AS STRING)
FROM silver.stg_order_items WHERE key_rank = 1 AND reject_reason IS NULL AND discount_fixed
UNION ALL
SELECT 'OI-05', 'order_items', order_item_id, 'line_total',
       'line_total does not equal qty x price x (1 - discount)', 'RECOMPUTED',
       CAST(source_line_total AS STRING), CAST(net_line_amount AS STRING)
FROM silver.order_items WHERE line_total_mismatch
UNION ALL
SELECT 'OI-06', 'order_items', order_item_id, 'product_id',
       'Product not found in catalog (orphan)', 'FLAGGED_UNKNOWN_PRODUCT', product_id, CAST(NULL AS STRING)
FROM silver.order_items WHERE NOT product_found

-- ---------------------------------------------------------------- payments
UNION ALL
SELECT 'PAY-01', 'payments', payment_id, 'payment_id', 'Exact duplicate row', 'REMOVED_DUPLICATE',
       payment_id, CAST(NULL AS STRING)
FROM silver.stg_payments WHERE key_rank > 1
UNION ALL
SELECT 'PAY-02', 'payments', payment_id, 'amount',
       CONCAT('Currency-formatted amount (', amount_format, ')'),
       IF(amount_format = 'DOLLAR_SYMBOL', 'PARSED_ASSUMED_INR', 'PARSED'), amount_raw, CAST(amount AS STRING)
FROM silver.stg_payments WHERE key_rank = 1 AND amount_format != 'PLAIN'
UNION ALL
SELECT 'PAY-03', 'payments', payment_id, 'payment_status',
       'Non-standard status (misspelling / alias)', 'STANDARDIZED', payment_status_raw, payment_status
FROM silver.stg_payments WHERE key_rank = 1 AND LOWER(TRIM(payment_status_raw)) IS DISTINCT FROM LOWER(payment_status)
UNION ALL
SELECT 'PAY-04', 'payments', payment_id, 'payment_date', 'Payment date missing', 'FLAGGED',
       CAST(NULL AS STRING), CAST(NULL AS STRING)
FROM silver.payments WHERE payment_date_missing
UNION ALL
SELECT 'PAY-05', 'payments', payment_id, 'order_id',
       'Payment for an order that does not exist (orphan)', 'FLAGGED', order_id, CAST(NULL AS STRING)
FROM silver.payments WHERE NOT order_found
UNION ALL
SELECT 'PAY-06', 'payments', payment_id, 'payment_date',
       'Payment dated before its order', 'FLAGGED', CAST(payment_date AS STRING), CAST(NULL AS STRING)
FROM silver.payments WHERE paid_before_order

-- ---------------------------------------------------------------- returns
UNION ALL
SELECT 'RET-01', 'returns', return_id, 'return_id', 'Exact duplicate row', 'REMOVED_DUPLICATE',
       return_id, CAST(NULL AS STRING)
FROM silver.stg_returns WHERE key_rank > 1
UNION ALL
SELECT 'RET-02', 'returns', return_id, 'order_item_id',
       CONCAT('Return rejected: ', reject_reason), 'QUARANTINED', order_item_id, CAST(NULL AS STRING)
FROM silver.stg_returns WHERE key_rank = 1 AND reject_reason IS NOT NULL
UNION ALL
SELECT 'RET-03', 'returns', return_id, 'refund_amount',
       'Refund amount missing - assumed full line value', 'IMPUTED', CAST(source_refund_amount AS STRING), CAST(refund_amount AS STRING)
FROM silver.returns WHERE refund_imputed
UNION ALL
SELECT 'RET-04', 'returns', return_id, 'refund_amount',
       'Refund exceeds the net value of the returned line', 'CAPPED', CAST(source_refund_amount AS STRING), CAST(refund_amount AS STRING)
FROM silver.returns WHERE refund_capped
UNION ALL
SELECT 'RET-05', 'returns', return_id, 'return_date',
       'Placeholder return date 2023-01-01', 'SET_NULL', '2023-01-01', CAST(NULL AS STRING)
FROM silver.returns WHERE return_date_placeholder
UNION ALL
SELECT 'RET-06', 'returns', return_id, 'return_date',
       'Return dated before the order date', 'FLAGGED', CAST(return_date AS STRING), CAST(NULL AS STRING)
FROM silver.returns WHERE returned_before_order
UNION ALL
SELECT 'RET-07', 'returns', r.return_id, 'order_status',
       'Return against an order that is Pending or Cancelled', 'FLAGGED', o.order_status, CAST(NULL AS STRING)
FROM silver.returns r JOIN silver.orders o USING (order_id) WHERE r.order_not_fulfilled
UNION ALL
SELECT 'RET-08', 'returns', return_id, 'return_reason',
       'Non-standard return reason (misspelling / alias)', 'STANDARDIZED', return_reason_raw, return_reason
FROM silver.stg_returns WHERE key_rank = 1 AND reject_reason IS NULL AND LOWER(TRIM(return_reason_raw)) IS DISTINCT FROM LOWER(return_reason);


-- Rows the pipeline refused to carry into silver, with the reason and the original record.
CREATE OR REPLACE TABLE silver.dq_quarantine AS
SELECT 'order_items' AS table_name, i.order_item_id AS record_key, i.reject_reason AS reject_reason,
       TO_JSON_STRING(b) AS raw_record, i._source_file, i._row_num, i._batch_id
FROM silver.stg_order_items i
JOIN bronze.order_items b ON b._source_file = i._source_file AND b._row_num = i._row_num
WHERE i.key_rank = 1 AND i.reject_reason IS NOT NULL
UNION ALL
SELECT 'returns', r.return_id, r.reject_reason, TO_JSON_STRING(b), r._source_file, r._row_num, r._batch_id
FROM silver.stg_returns r
JOIN bronze.returns b ON b._source_file = r._source_file AND b._row_num = r._row_num
WHERE r.key_rank = 1 AND r.reject_reason IS NOT NULL;


-- One row per rule: how many records it touched.
CREATE OR REPLACE TABLE silver.dq_rule_summary AS
SELECT rule_id, table_name, column_name, issue, action, COUNT(*) AS records_affected
FROM silver.dq_issue_log
GROUP BY rule_id, table_name, column_name, issue, action
ORDER BY rule_id, action, issue;


-- Reconciliation: every bronze row must be accounted for (bronze = silver + duplicates + merged + quarantined).
CREATE OR REPLACE TABLE silver.dq_table_summary AS
WITH t AS (
  SELECT 'customers' AS table_name,
         (SELECT COUNT(*) FROM bronze.customers) AS bronze_rows,
         (SELECT COUNTIF(key_rank > 1) FROM silver.stg_customers_ranked) AS duplicates_removed,
         (SELECT COUNTIF(customer_id != master_customer_id) FROM silver.customer_xref) AS merged_into_master,
         0 AS quarantined,
         (SELECT COUNT(*) FROM silver.customers) AS silver_rows
  UNION ALL
  SELECT 'suppliers', (SELECT COUNT(*) FROM bronze.suppliers),
         (SELECT COUNTIF(key_rank > 1) FROM silver.stg_suppliers), 0, 0, (SELECT COUNT(*) FROM silver.suppliers)
  UNION ALL
  SELECT 'products', (SELECT COUNT(*) FROM bronze.products),
         (SELECT COUNTIF(key_rank > 1) FROM silver.stg_products), 0, 0, (SELECT COUNT(*) FROM silver.products)
  UNION ALL
  SELECT 'orders', (SELECT COUNT(*) FROM bronze.orders),
         (SELECT COUNTIF(key_rank > 1) FROM silver.stg_orders), 0, 0, (SELECT COUNT(*) FROM silver.orders)
  UNION ALL
  SELECT 'order_items', (SELECT COUNT(*) FROM bronze.order_items),
         (SELECT COUNTIF(key_rank > 1) FROM silver.stg_order_items), 0,
         (SELECT COUNTIF(key_rank = 1 AND reject_reason IS NOT NULL) FROM silver.stg_order_items),
         (SELECT COUNT(*) FROM silver.order_items)
  UNION ALL
  SELECT 'payments', (SELECT COUNT(*) FROM bronze.payments),
         (SELECT COUNTIF(key_rank > 1) FROM silver.stg_payments), 0, 0, (SELECT COUNT(*) FROM silver.payments)
  UNION ALL
  SELECT 'returns', (SELECT COUNT(*) FROM bronze.returns),
         (SELECT COUNTIF(key_rank > 1) FROM silver.stg_returns), 0,
         (SELECT COUNTIF(key_rank = 1 AND reject_reason IS NOT NULL) FROM silver.stg_returns),
         (SELECT COUNT(*) FROM silver.returns)
)
SELECT *, bronze_rows = silver_rows + duplicates_removed + merged_into_master + quarantined AS balanced
FROM t
ORDER BY table_name;
