-- CUSTOMERS: standardize -> dedupe same key -> resolve same person under different IDs.

-- 1. Standardize (all bronze rows kept, raw values alongside clean ones for the DQ log)
CREATE OR REPLACE TABLE silver.stg_customers AS
WITH src AS (
  SELECT *, REGEXP_REPLACE(IFNULL(phone, ''), r'\D', '') AS phone_digits
  FROM bronze.customers
)
SELECT
  UPPER(TRIM(customer_id))                                   AS customer_id,
  TRIM(first_name)                                           AS first_name,
  TRIM(last_name)                                            AS last_name,
  LOWER(silver.clean_str(email))                             AS email,
  IFNULL(REGEXP_CONTAINS(LOWER(TRIM(email)), r'^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$'), FALSE)
                                                             AS email_valid,
  CASE  -- Indian mobile numbers: keep the 10-digit subscriber number
    WHEN LENGTH(phone_digits) = 10 THEN phone_digits
    WHEN LENGTH(phone_digits) = 11 AND STARTS_WITH(phone_digits, '0') THEN SUBSTR(phone_digits, 2)
    WHEN LENGTH(phone_digits) = 12 AND STARTS_WITH(phone_digits, '91') THEN SUBSTR(phone_digits, 3)
  END                                                        AS phone,
  TRIM(address_line1)                                        AS address_line1,
  COALESCE(city_map.standard_value, INITCAP(TRIM(city)))     AS city,
  TRIM(state)                                                AS state,
  IF(REGEXP_CONTAINS(TRIM(zip_code), r'^\d{6}$'), TRIM(zip_code), NULL) AS zip_code,
  TRIM(country)                                              AS country,
  silver.parse_date(signup_date)                             AS signup_date,
  silver.date_is_ambiguous(signup_date)                      AS signup_date_ambiguous,
  COALESCE(seg_map.standard_value, 'Unknown')                AS customer_segment,
  silver.parse_bool(is_active)                               AS is_active,
  -- raw values for audit
  email AS email_raw, phone AS phone_raw, city AS city_raw, zip_code AS zip_code_raw,
  signup_date AS signup_date_raw, customer_segment AS customer_segment_raw, is_active AS is_active_raw,
  first_name AS first_name_raw,
  _source_file, _row_num, _batch_id
FROM src
LEFT JOIN silver.ref_value_map seg_map
  ON seg_map.domain = 'customer_segment' AND seg_map.raw_value = LOWER(TRIM(src.customer_segment))
LEFT JOIN silver.ref_value_map city_map
  ON city_map.domain = 'city' AND city_map.raw_value = LOWER(TRIM(src.city));

-- 2. Same customer_id more than once: keep the most complete row, then the first in file.
--    (Profiling: all 5 repeated IDs differ only in email casing, so they are true duplicates.)
CREATE OR REPLACE TABLE silver.stg_customers_ranked AS
SELECT
  *,
  ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY (IF(email IS NULL, 1, 0) + IF(phone IS NULL, 1, 0) + IF(signup_date IS NULL, 1, 0)
              + IF(zip_code IS NULL, 1, 0) + IF(customer_segment = 'Unknown', 1, 0)), _row_num
  ) AS key_rank,
  COUNT(*) OVER (PARTITION BY customer_id) AS key_count
FROM silver.stg_customers;

-- 3. Same person under different IDs: identical first name + last name + normalized phone.
--    Profiling found 8 pairs (C0170-C0177 re-registered with @gmail.com copies of C0xxx records).
--    Survivor = lowest (original CRM) customer_id; all orders are re-pointed to it via the xref.
CREATE OR REPLACE TABLE silver.customer_xref AS
WITH k AS (
  SELECT
    customer_id,
    IF(phone IS NULL, customer_id, CONCAT(LOWER(first_name), '|', LOWER(last_name), '|', phone)) AS match_key
  FROM silver.stg_customers_ranked
  WHERE key_rank = 1
)
SELECT
  customer_id,
  FIRST_VALUE(customer_id) OVER (PARTITION BY match_key ORDER BY customer_id) AS master_customer_id,
  IF(COUNT(*) OVER (PARTITION BY match_key) > 1, 'NAME+PHONE', 'SELF') AS match_rule
FROM k;

-- 4. Final customer master: one row per real customer
CREATE OR REPLACE TABLE silver.customers AS
WITH merged AS (
  SELECT master_customer_id, ARRAY_AGG(customer_id ORDER BY customer_id) AS source_customer_ids
  FROM silver.customer_xref
  GROUP BY master_customer_id
)
SELECT
  c.customer_id, c.first_name, c.last_name, c.email, c.email_valid, c.phone,
  c.address_line1, c.city, c.state, c.zip_code, c.country,
  c.signup_date, c.signup_date_ambiguous, c.customer_segment, c.is_active,
  m.source_customer_ids,
  c._source_file, c._row_num, c._batch_id
FROM silver.stg_customers_ranked c
JOIN merged m ON m.master_customer_id = c.customer_id
WHERE c.key_rank = 1;
