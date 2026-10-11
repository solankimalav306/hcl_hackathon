-- ORDER ITEMS: dedupe, repair price/discount where the true value is recoverable,
-- recompute line totals, quarantine lines that cannot be trusted.

CREATE OR REPLACE TABLE silver.stg_order_items AS
WITH s AS (
  SELECT
    UPPER(TRIM(order_item_id))           AS order_item_id,
    UPPER(TRIM(order_id))                AS order_id,
    UPPER(TRIM(product_id))              AS product_id,
    SAFE_CAST(TRIM(quantity) AS INT64)   AS quantity,
    silver.parse_money(unit_price)       AS unit_price_src,
    SAFE_CAST(TRIM(discount_pct) AS NUMERIC) AS discount_src,
    silver.parse_money(line_total)       AS line_total_src,
    unit_price AS unit_price_raw, discount_pct AS discount_pct_raw, line_total AS line_total_raw, quantity AS quantity_raw,
    ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(order_item_id)) ORDER BY _row_num) AS key_rank,
    COUNT(*) OVER (PARTITION BY UPPER(TRIM(order_item_id))) AS key_count,
    _source_file, _row_num, _batch_id
  FROM bronze.order_items
),
price_fixed AS (
  SELECT
    s.*,
    CASE
      -- blank price: back-solve from the line total when the discount is valid
      WHEN s.unit_price_src IS NULL AND s.quantity > 0 AND s.discount_src BETWEEN 0 AND 99 AND s.line_total_src > 0
        THEN ROUND(s.line_total_src / (s.quantity * (1 - s.discount_src / 100)), 2)
      -- negative price (P003 sold at -70.38, copied from the bad catalog record): use the surviving catalog price
      WHEN s.unit_price_src < 0 THEN p.list_price
      ELSE s.unit_price_src
    END AS unit_price,
    CASE
      WHEN s.unit_price_src IS NULL THEN 'DERIVED_FROM_LINE_TOTAL'
      WHEN s.unit_price_src < 0 AND p.list_price IS NOT NULL THEN 'REPLACED_WITH_CATALOG_PRICE'
    END AS unit_price_fix
  FROM s
  LEFT JOIN silver.products p USING (product_id)
),
discount_fixed AS (
  SELECT
    f.*,
    CASE
      WHEN f.discount_src BETWEEN 0 AND 100 THEN f.discount_src
      -- out-of-range discount (150, -10): back-solve from the line total if that gives a valid 0-100%
      WHEN f.quantity > 0 AND f.unit_price > 0 AND f.line_total_src >= 0
           AND 1 - f.line_total_src / (f.quantity * f.unit_price) BETWEEN 0 AND 1
        THEN ROUND(100 * (1 - f.line_total_src / (f.quantity * f.unit_price)), 2)
    END AS discount_pct,
    NOT (f.discount_src BETWEEN 0 AND 100) AS discount_fixed
  FROM price_fixed f
)
SELECT
  d.*,
  CASE
    WHEN d.key_rank > 1                         THEN NULL  -- duplicate, not quarantined
    WHEN o.order_id IS NULL                     THEN 'ORPHAN_ORDER'        -- order_id not in orders (O9xxxx)
    WHEN d.quantity IS NULL OR d.quantity <= 0  THEN 'INVALID_QUANTITY'    -- 0 or negative units
    WHEN d.unit_price IS NULL OR d.unit_price <= 0 THEN 'INVALID_PRICE'
    WHEN d.discount_pct IS NULL                 THEN 'INVALID_DISCOUNT'
  END AS reject_reason
FROM discount_fixed d
LEFT JOIN silver.orders o USING (order_id);

CREATE OR REPLACE TABLE silver.order_items AS
SELECT
  i.order_item_id, i.order_id, i.product_id,
  p.product_id IS NOT NULL                                     AS product_found,  -- P9xx not in catalog: kept, category Unknown
  i.quantity, i.unit_price, i.discount_pct,
  ROUND(i.quantity * i.unit_price, 2)                          AS gross_amount,
  -- Net line revenue is always recomputed from its inputs; the source line_total is kept for audit
  ROUND(i.quantity * i.unit_price * (1 - i.discount_pct / 100), 2) AS net_line_amount,
  i.line_total_src                                             AS source_line_total,
  ABS(ROUND(i.quantity * i.unit_price * (1 - i.discount_pct / 100), 2) - IFNULL(i.line_total_src, 0)) > 0.05
                                                               AS line_total_mismatch,
  i.unit_price_fix, i.discount_fixed,
  i._source_file, i._row_num, i._batch_id
FROM silver.stg_order_items i
LEFT JOIN silver.products p USING (product_id)
WHERE i.key_rank = 1 AND i.reject_reason IS NULL;
