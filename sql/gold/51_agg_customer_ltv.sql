-- L3: net lifetime value per customer (completed orders, net of refunds)
-- Reads: ${gold}.fct_order, ${gold}.fct_order_line
CREATE OR REPLACE VIEW ${gold}.agg_customer_ltv AS
WITH per_customer AS (
  SELECT
    o.customer_key,
    COUNT(DISTINCT o.order_id)  AS completed_orders,
    SUM(l.net_after_refund)     AS net_ltv,
    MAX(o.order_date)           AS last_order_date
  FROM ${gold}.fct_order AS o
  JOIN ${gold}.fct_order_line AS l ON l.order_id = o.order_id
  WHERE o.is_completed
  GROUP BY o.customer_key
)
SELECT
  customer_key,
  completed_orders,
  net_ltv,
  last_order_date,
  RANK() OVER (ORDER BY net_ltv DESC) AS ltv_rank
FROM per_customer;
