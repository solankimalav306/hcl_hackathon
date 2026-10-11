-- Q2: top 10 customers by net LTV (no personal details; only city, state, segment)
-- ASSUMPTION: agg_customer_ltv.customer_key = dim_customer.customer_id
CREATE OR REPLACE VIEW ${gold}.q2_top_customers AS
SELECT
  l.ltv_rank,
  l.customer_key,
  c.city,
  c.state,
  c.segment_std,
  l.completed_orders,
  l.net_ltv,
  l.last_order_date
FROM ${gold}.agg_customer_ltv AS l
LEFT JOIN ${gold}.dim_customer AS c ON c.customer_id = l.customer_key
WHERE l.ltv_rank <= 10
ORDER BY l.ltv_rank;
