-- PAYMENTS: dedupe, parse currency-formatted amounts, standardize statuses.
-- Orphan / mismatched payments are KEPT and flagged: reporting them is the point of KPI 8.

CREATE OR REPLACE TABLE silver.stg_payments AS
SELECT
  UPPER(TRIM(p.payment_id))                    AS payment_id,
  UPPER(TRIM(p.order_id))                      AS order_id,
  silver.parse_date(p.payment_date)            AS payment_date,
  silver.date_is_ambiguous(p.payment_date)     AS payment_date_ambiguous,
  silver.parse_money(p.amount)                 AS amount,
  CASE  -- what formatting the amount arrived with
    WHEN STRPOS(p.amount, '₹') > 0 THEN 'RUPEE_SYMBOL'
    WHEN STRPOS(p.amount, '$') > 0 THEN 'DOLLAR_SYMBOL'
    WHEN REGEXP_CONTAINS(UPPER(p.amount), r'INR') THEN 'INR_SUFFIX'
    ELSE 'PLAIN'
  END                                          AS amount_format,
  COALESCE(st.standard_value, 'Unknown')       AS payment_status,
  TRIM(p.payment_method)                       AS payment_method,
  p.amount AS amount_raw, p.payment_status AS payment_status_raw, p.payment_date AS payment_date_raw,
  ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(p.payment_id)) ORDER BY p._row_num) AS key_rank,
  COUNT(*) OVER (PARTITION BY UPPER(TRIM(p.payment_id))) AS key_count,
  p._source_file, p._row_num, p._batch_id
FROM bronze.payments p
LEFT JOIN silver.ref_value_map st ON st.domain = 'payment_status' AND st.raw_value = LOWER(TRIM(p.payment_status));

CREATE OR REPLACE TABLE silver.payments AS
SELECT
  p.payment_id, p.order_id,
  o.order_id IS NOT NULL                       AS order_found,
  p.payment_date, p.payment_date_ambiguous,
  p.payment_date IS NULL                       AS payment_date_missing,
  p.payment_date < o.order_date                AS paid_before_order,
  -- All amounts are treated as INR: '$' amounts are the same magnitude as the rest and
  -- the business only sells in India, so the symbol is a formatting defect, not a currency.
  p.amount, p.amount_format,
  p.payment_status, p.payment_method,
  p.payment_method != o.payment_method         AS method_differs_from_order,
  p._source_file, p._row_num, p._batch_id
FROM silver.stg_payments p
LEFT JOIN silver.orders o USING (order_id)
WHERE p.key_rank = 1;
