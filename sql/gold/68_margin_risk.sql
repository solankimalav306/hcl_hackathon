-- Margin Risk: products whose margin is thin or negative after refunds (completed orders)
-- risk threshold: params.margin_risk_threshold (config/config.yaml)
CREATE OR REPLACE VIEW ${gold}.margin_risk AS
WITH p AS (
  SELECT
    l.product_id,
    SUM(l.qty)              AS units,
    SUM(l.net_after_refund) AS net_revenue,
    SUM(l.cost_amt)         AS cost_amt
  FROM ${gold}.fct_order_line AS l
  JOIN ${gold}.fct_order      AS o ON o.order_id = l.order_id
  WHERE o.is_completed
  GROUP BY l.product_id
)
SELECT
  p.product_id,
  d.product_name,
  d.category_std,
  p.units,
  p.net_revenue,
  p.cost_amt,
  p.net_revenue - p.cost_amt                                  AS margin_amt,
  SAFE_DIVIDE(p.net_revenue - p.cost_amt, p.net_revenue)      AS margin_pct,
  SAFE_DIVIDE(p.net_revenue - p.cost_amt, p.net_revenue) < ${margin_risk_threshold} AS is_at_risk
FROM p
LEFT JOIN ${gold}.dim_product AS d ON d.product_id = p.product_id;
