-- RETURNS: dedupe, quarantine returns that cannot be tied to a valid sale line,
-- impute / cap refunds against the line value, flag date and status conflicts.

CREATE OR REPLACE TABLE silver.stg_returns AS
WITH s AS (
  SELECT
    UPPER(TRIM(r.return_id))                    AS return_id,
    UPPER(TRIM(r.order_item_id))                AS order_item_id,
    silver.parse_date(r.return_date)            AS return_date_parsed,
    silver.date_is_ambiguous(r.return_date)     AS return_date_ambiguous,
    COALESCE(rs.standard_value, 'Unknown')      AS return_reason,
    COALESCE(st.standard_value, 'Unknown')      AS return_status,
    silver.parse_money(r.refund_amount)         AS refund_src,
    r.return_date AS return_date_raw, r.return_reason AS return_reason_raw,
    r.return_status AS return_status_raw, r.refund_amount AS refund_amount_raw,
    ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.return_id)) ORDER BY r._row_num) AS key_rank,
    COUNT(*) OVER (PARTITION BY UPPER(TRIM(r.return_id))) AS key_count,
    r._source_file, r._row_num, r._batch_id
  FROM bronze.returns r
  LEFT JOIN silver.ref_value_map rs ON rs.domain = 'return_reason' AND rs.raw_value = LOWER(TRIM(r.return_reason))
  LEFT JOIN silver.ref_value_map st ON st.domain = 'return_status' AND st.raw_value = LOWER(TRIM(r.return_status))
)
SELECT
  s.*,
  -- 2023-01-01 appears on 5 returns, always before the order was placed: a system default, not a real date
  s.return_date_parsed = DATE '2023-01-01'                               AS return_date_placeholder,
  IF(s.return_date_parsed = DATE '2023-01-01', NULL, s.return_date_parsed) AS return_date,
  i.net_line_amount, i.order_id, o.order_date, o.order_status,
  CASE
    WHEN s.key_rank > 1 THEN NULL
    WHEN i.order_item_id IS NOT NULL THEN NULL
    WHEN q.order_item_id IS NOT NULL THEN 'ORDER_ITEM_QUARANTINED'       -- the sale line itself was rejected
    ELSE 'ORPHAN_ORDER_ITEM'                                              -- OI9xxxxx not in order_items
  END AS reject_reason
FROM s
LEFT JOIN silver.order_items i USING (order_item_id)
LEFT JOIN silver.orders o ON o.order_id = i.order_id
LEFT JOIN (SELECT DISTINCT order_item_id FROM silver.stg_order_items WHERE reject_reason IS NOT NULL) q
  ON q.order_item_id = s.order_item_id;

CREATE OR REPLACE TABLE silver.returns AS
SELECT
  r.return_id, r.order_item_id, r.order_id,
  r.return_date, r.return_date_ambiguous, r.return_date_placeholder,
  r.return_date < r.order_date                                     AS returned_before_order,
  r.return_reason, r.return_status,
  -- Refund rules: blank -> assume the full line value was refunded; above line value -> cap at line value
  LEAST(COALESCE(r.refund_src, r.net_line_amount), r.net_line_amount) AS refund_amount,
  r.refund_src                                                     AS source_refund_amount,
  r.refund_src IS NULL                                             AS refund_imputed,
  r.refund_src > r.net_line_amount                                 AS refund_capped,
  -- A return against an order that is still Pending or was Cancelled is a business-rule conflict
  r.order_status IN ('Pending', 'Cancelled')                      AS order_not_fulfilled,
  r._source_file, r._row_num, r._batch_id
FROM silver.stg_returns r
WHERE r.key_rank = 1 AND r.reject_reason IS NULL;
