-- Gold aggregate: per-order payment reconciliation
-- ASSUMPTIONS:
--   * silver.payments already has exact duplicate rows removed (PAY-01), so duplicate_count here means
--     EXTRA successful payments on the same order with the same amount (a likely double charge).
--   * paid_amt = sum of Success payments. Refunded / Failed / Pending payments are not counted as paid.
--   * Orders that are not completed (Pending/Cancelled) and have no successful payment are 'not_applicable', not anomalies.
--   * Tolerance params.payment_tolerance when comparing paid_amt to order_total (config/config.yaml).
CREATE OR REPLACE VIEW ${gold}.agg_order_payments AS
WITH pay AS (
  SELECT
    order_id,
    SUM(IF(UPPER(payment_status) = 'SUCCESS', amount, 0)) AS paid_amt,
    COUNTIF(UPPER(payment_status) = 'SUCCESS')            AS success_payment_count,
    COUNTIF(UPPER(payment_status) = 'SUCCESS')
      - COUNT(DISTINCT IF(UPPER(payment_status) = 'SUCCESS', CAST(amount AS STRING), NULL)) AS duplicate_count
  FROM ${silver}.payments
  GROUP BY order_id
),
base AS (
  SELECT
    o.order_id,
    o.net_amt AS order_total,
    o.is_completed,
    COALESCE(p.paid_amt, 0)               AS paid_amt,
    COALESCE(p.success_payment_count, 0)  AS success_payment_count,
    COALESCE(p.duplicate_count, 0)        AS duplicate_count
  FROM ${gold}.fct_order AS o
  LEFT JOIN pay AS p USING (order_id)
)
SELECT
  * EXCEPT (is_completed),
  success_payment_count = 0 AS no_success_flag,
  CASE
    WHEN NOT is_completed AND success_payment_count = 0 THEN 'not_applicable'  -- pending/cancelled: no payment expected
    WHEN success_payment_count = 0                     THEN 'no_success_payment'
    WHEN duplicate_count > 0                           THEN 'duplicate_payment'
    WHEN paid_amt < order_total - ${payment_tolerance} THEN 'underpaid'
    WHEN paid_amt > order_total + ${payment_tolerance} THEN 'overpaid'
    ELSE 'ok'
  END AS anomaly_type
FROM base;
