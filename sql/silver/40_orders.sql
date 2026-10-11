-- ORDERS: standardize labels/dates, remove exact duplicates, re-point merged customers.

CREATE OR REPLACE TABLE silver.stg_orders AS
SELECT
  UPPER(TRIM(o.order_id))                                  AS order_id,
  UPPER(TRIM(o.customer_id))                               AS customer_id,
  silver.parse_date(o.order_date)                          AS order_date,
  silver.date_is_ambiguous(o.order_date)                   AS order_date_ambiguous,
  COALESCE(st.standard_value, 'Unknown')                   AS order_status,
  TRIM(o.payment_method)                                   AS payment_method,
  COALESCE(ch.standard_value, 'Unknown')                   AS channel,
  UPPER(silver.clean_str(o.promo_code))                    AS promo_code,   -- NA / N/A / None / null / blank -> NULL
  COALESCE(city.standard_value, INITCAP(TRIM(o.shipping_city))) AS shipping_city,
  o.order_date AS order_date_raw, o.order_status AS order_status_raw, o.channel AS channel_raw,
  o.promo_code AS promo_code_raw,
  ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(o.order_id)) ORDER BY o._row_num) AS key_rank,
  COUNT(*) OVER (PARTITION BY UPPER(TRIM(o.order_id))) AS key_count,
  o._source_file, o._row_num, o._batch_id
FROM bronze.orders o
LEFT JOIN silver.ref_value_map st   ON st.domain = 'order_status' AND st.raw_value = LOWER(TRIM(o.order_status))
LEFT JOIN silver.ref_value_map ch   ON ch.domain = 'channel'      AND ch.raw_value = LOWER(TRIM(o.channel))
LEFT JOIN silver.ref_value_map city ON city.domain = 'city'       AND city.raw_value = LOWER(TRIM(o.shipping_city));

-- Orders whose customer_id is not in the CRM (C9xxx) are KEPT: the sale happened and counts
-- toward revenue. They are flagged and later linked to an "Unknown customer" member in gold.
CREATE OR REPLACE TABLE silver.orders AS
WITH orders_with_items AS (
  SELECT DISTINCT UPPER(TRIM(order_id)) AS order_id FROM bronze.order_items
)
SELECT
  o.order_id,
  o.customer_id                                   AS source_customer_id,
  COALESCE(x.master_customer_id, o.customer_id)   AS customer_id,
  x.customer_id IS NOT NULL                       AS customer_found,
  o.order_date, o.order_date_ambiguous, o.order_status, o.payment_method, o.channel,
  o.promo_code, o.shipping_city,
  w.order_id IS NOT NULL                          AS has_items,
  o._source_file, o._row_num, o._batch_id
FROM silver.stg_orders o
LEFT JOIN silver.customer_xref x ON x.customer_id = o.customer_id
LEFT JOIN orders_with_items w ON w.order_id = o.order_id
WHERE o.key_rank = 1;
