-- L3: supplier scorecard
-- avg_return_rate: mean product return rate over products that meet the min volume.
-- composite_score (ASSUMPTION, weights come from config params):
--   w_revenue * revenue (min-max scaled) + w_returns * (1 - avg_return_rate) + w_rating * rating_norm
-- Reads: ${gold}.fct_order_line, ${gold}.fct_order, ${gold}.dim_product, ${gold}.dim_supplier, ${gold}.agg_product_returns
CREATE OR REPLACE VIEW ${gold}.agg_supplier_scorecard AS
WITH rev AS (
  SELECT p.supplier_id, SUM(l.net_after_refund) AS revenue
  FROM ${gold}.fct_order_line AS l
  JOIN ${gold}.fct_order      AS o ON o.order_id = l.order_id
  JOIN ${gold}.dim_product    AS p ON p.product_id = l.product_id
  WHERE o.is_completed
  GROUP BY p.supplier_id
),
ret AS (
  SELECT p.supplier_id, AVG(r.return_rate) AS avg_return_rate
  FROM ${gold}.agg_product_returns AS r
  JOIN ${gold}.dim_product         AS p ON p.product_id = r.product_id
  WHERE r.meets_min_volume
  GROUP BY p.supplier_id
),
joined AS (
  SELECT
    s.supplier_id,
    COALESCE(rev.revenue, 0)           AS revenue,
    COALESCE(ret.avg_return_rate, 0)   AS avg_return_rate,
    s.rating_norm
  FROM ${gold}.dim_supplier AS s
  LEFT JOIN rev USING (supplier_id)
  LEFT JOIN ret USING (supplier_id)
)
SELECT
  supplier_id,
  revenue,
  avg_return_rate,
  rating_norm,
  ${w_revenue} * COALESCE(SAFE_DIVIDE(revenue - MIN(revenue) OVER (), MAX(revenue) OVER () - MIN(revenue) OVER ()), 0)
  + ${w_returns} * (1 - avg_return_rate)
  + ${w_rating} * COALESCE(rating_norm, 0) AS composite_score
FROM joined;
