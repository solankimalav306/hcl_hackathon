-- SUPPLIERS: standardize, resolve the conflicting S004 records, normalize ratings to one scale.

CREATE OR REPLACE TABLE silver.stg_suppliers AS
SELECT
  UPPER(TRIM(supplier_id))                      AS supplier_id,
  TRIM(supplier_name)                           AS supplier_name,
  silver.clean_str(country)                     AS country,
  SAFE_CAST(rating AS NUMERIC)                  AS rating_raw,
  silver.parse_date(contract_start_date)        AS contract_start_date,
  silver.parse_bool(is_preferred)               AS is_preferred,
  country AS country_raw, is_preferred AS is_preferred_raw, contract_start_date AS contract_start_date_raw,
  -- S004 appears twice with different names. Survivor: the record with a known country,
  -- then the first in file. The losing record goes to the issue log for supplier-master review.
  ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(supplier_id))
                     ORDER BY IF(silver.clean_str(country) IS NULL, 1, 0), _row_num) AS key_rank,
  COUNT(*) OVER (PARTITION BY UPPER(TRIM(supplier_id))) AS key_count,
  _source_file, _row_num, _batch_id
FROM bronze.suppliers;

-- Ratings were captured on two scales: most are 1-5, a few are 1-10 (7.5, 7.7, 9.4).
-- Any rating > 5 is treated as out of 10. Stored both as a 0-5 value and a 0-1 score.
CREATE OR REPLACE TABLE silver.suppliers AS
SELECT
  supplier_id, supplier_name,
  COALESCE(country, 'Unknown')                          AS country,
  rating_raw,
  IF(rating_raw > 5, 10, 5)                             AS rating_scale,
  ROUND(rating_raw * 5 / IF(rating_raw > 5, 10, 5), 2)  AS rating_5,
  ROUND(rating_raw / IF(rating_raw > 5, 10, 5), 3)      AS rating_norm,
  contract_start_date, is_preferred,
  _source_file, _row_num, _batch_id
FROM silver.stg_suppliers
WHERE key_rank = 1;
