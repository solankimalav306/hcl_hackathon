-- Q3: customer segments - size, revenue, LTV and average order value
-- ASSUMPTION: customer_key = dim_customer.customer_id
CREATE OR REPLACE VIEW ${gold}.q3_segments AS
WITH ltv AS (
  SELECT
    COALESCE(c.segment_std, 'Unknown') AS segment_std,
    COUNT(*)                           AS customers,
    SUM(l.completed_orders)            AS completed_orders,
    SUM(l.net_ltv)                     AS net_revenue,
    AVG(l.net_ltv)                     AS avg_ltv
  FROM ${gold}.agg_customer_ltv AS l
  LEFT JOIN ${gold}.dim_customer AS c ON c.customer_id = l.customer_key
  GROUP BY 1
),
aov AS (
  SELECT
    COALESCE(c.segment_std, 'Unknown') AS segment_std,
    AVG(o.net_amt)                     AS avg_order_value
  FROM ${gold}.fct_order AS o
  LEFT JOIN ${gold}.dim_customer AS c ON c.customer_id = o.customer_key
  WHERE o.is_completed
  GROUP BY 1
)
SELECT ltv.*, aov.avg_order_value
FROM ltv LEFT JOIN aov USING (segment_std);
