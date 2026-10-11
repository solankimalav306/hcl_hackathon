-- Q8: payment anomalies - detail rows and a summary by anomaly type
CREATE OR REPLACE VIEW ${gold}.q8_payment_anomalies AS
SELECT
  order_id, anomaly_type, order_total, paid_amt, order_total - paid_amt AS gap,
  success_payment_count, duplicate_count
FROM ${gold}.agg_order_payments
WHERE anomaly_type NOT IN ('ok', 'not_applicable');

CREATE OR REPLACE VIEW ${gold}.q8_anomaly_summary AS
SELECT
  anomaly_type,
  COUNT(*)                        AS orders,
  SUM(order_total)                AS order_total,
  SUM(paid_amt)                   AS paid_amt,
  SUM(order_total - paid_amt)     AS gap
FROM ${gold}.agg_order_payments
GROUP BY anomaly_type;
