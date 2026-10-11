-- Q4: month-over-month revenue growth, overall and by category
CREATE OR REPLACE VIEW ${gold}.q4_revenue_growth AS
WITH m AS (
  SELECT order_month, SUM(net_revenue) AS net_revenue
  FROM ${gold}.agg_rev_month_cat_channel
  GROUP BY order_month
)
SELECT
  order_month,
  net_revenue,
  LAG(net_revenue) OVER (ORDER BY order_month) AS prev_month_revenue,
  SAFE_DIVIDE(net_revenue - LAG(net_revenue) OVER (ORDER BY order_month),
              LAG(net_revenue) OVER (ORDER BY order_month)) AS mom_growth
FROM m;

CREATE OR REPLACE VIEW ${gold}.q4_growth_by_category AS
WITH m AS (
  SELECT order_month, category_std, SUM(net_revenue) AS net_revenue
  FROM ${gold}.agg_rev_month_cat_channel
  GROUP BY order_month, category_std
)
SELECT
  order_month,
  category_std,
  net_revenue,
  LAG(net_revenue) OVER (PARTITION BY category_std ORDER BY order_month) AS prev_month_revenue,
  SAFE_DIVIDE(net_revenue - LAG(net_revenue) OVER (PARTITION BY category_std ORDER BY order_month),
              LAG(net_revenue) OVER (PARTITION BY category_std ORDER BY order_month)) AS mom_growth
FROM m;
