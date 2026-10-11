-- PRODUCTS: standardize, infer missing categories, resolve "(Revised)" duplicates.

CREATE OR REPLACE TABLE silver.stg_products AS
WITH base AS (
  SELECT
    p.*,
    UPPER(TRIM(p.product_id))                                          AS pid,
    REGEXP_CONTAINS(LOWER(p.product_name), r'\(revised\)')              AS is_revised,
    NULLIF(TRIM(REGEXP_REPLACE(p.product_name, r'(?i)\s*\(revised\)', '')), '') AS name_clean,
    cat_map.standard_value                                             AS category_mapped,
    silver.parse_money(p.unit_price)                                   AS unit_price_num,
    silver.parse_money(p.cost_price)                                   AS cost_price_num
  FROM bronze.products p
  LEFT JOIN silver.ref_value_map cat_map
    ON cat_map.domain = 'product_category' AND cat_map.raw_value = LOWER(TRIM(p.category))
),
-- Each sub_category belongs to exactly one category in the clean rows; use that to fill blanks.
sub_to_cat AS (
  SELECT TRIM(sub_category) AS sub_category,
         APPROX_TOP_COUNT(category_mapped, 1)[OFFSET(0)].value AS category
  FROM base
  WHERE category_mapped IS NOT NULL
  GROUP BY 1
)
SELECT
  b.pid                                                   AS product_id,
  COALESCE(b.name_clean, CONCAT('Unnamed product ', b.pid)) AS product_name,
  b.name_clean IS NULL                                    AS product_name_missing,
  b.is_revised,
  COALESCE(b.category_mapped, s.category, 'Unknown')      AS category,
  b.category_mapped IS NULL                               AS category_inferred,
  TRIM(b.sub_category)                                    AS sub_category,
  IF(b.unit_price_num > 0, b.unit_price_num, NULL)        AS list_price,   -- 0 or negative is not a valid list price
  b.cost_price_num                                        AS cost_price,
  UPPER(TRIM(b.supplier_id))                              AS supplier_id,
  silver.parse_bool(b.is_active)                          AS is_active,
  silver.parse_date(b.launch_date)                        AS launch_date,
  silver.date_is_ambiguous(b.launch_date)                 AS launch_date_ambiguous,
  b.product_name AS product_name_raw, b.category AS category_raw, b.unit_price AS unit_price_raw,
  b.is_active AS is_active_raw, b.launch_date AS launch_date_raw,
  -- Survivorship for repeated product_id: the "(Revised)" record wins (it is the newer catalog
  -- entry, and every order line for P001/P039/P060/P070 is priced at the Revised price),
  -- then a valid list price, then the first row in file.
  ROW_NUMBER() OVER (PARTITION BY b.pid
                     ORDER BY IF(b.is_revised, 0, 1), IF(b.unit_price_num > 0, 0, 1), b._row_num) AS key_rank,
  COUNT(*) OVER (PARTITION BY b.pid) AS key_count,
  b._source_file, b._row_num, b._batch_id
FROM base b
LEFT JOIN sub_to_cat s ON s.sub_category = TRIM(b.sub_category);

CREATE OR REPLACE TABLE silver.products AS
SELECT
  p.product_id, p.product_name, p.product_name_missing, p.category, p.category_inferred, p.sub_category,
  p.list_price, p.cost_price,
  p.list_price IS NOT NULL AND p.cost_price > p.list_price AS cost_exceeds_list_price,
  p.supplier_id,
  s.supplier_id IS NOT NULL                               AS supplier_found,  -- S92/S93/S96/S98 do not exist
  p.is_active, p.launch_date, p.launch_date_ambiguous,
  p._source_file, p._row_num, p._batch_id
FROM silver.stg_products p
LEFT JOIN silver.suppliers s USING (supplier_id)
WHERE p.key_rank = 1;
