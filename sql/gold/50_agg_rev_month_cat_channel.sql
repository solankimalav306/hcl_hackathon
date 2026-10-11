-- L3: revenue by month x category x channel (completed orders only)
-- Reads: ${gold}.fct_order_line, ${gold}.fct_order, ${gold}.dim_product
CREATE OR REPLACE VIEW ${gold}.agg_rev_month_cat_channel AS
SELECT
  o.order_month,
  COALESCE(p.category_std, 'Unknown') AS category_std,
  o.channel_std,
  SUM(l.qty)              AS units,
  SUM(l.line_net)         AS line_net,
  SUM(l.refund_amt)       AS refund_amt,
  SUM(l.net_after_refund) AS net_revenue
FROM ${gold}.fct_order_line AS l
JOIN ${gold}.fct_order      AS o ON o.order_id = l.order_id
LEFT JOIN ${gold}.dim_product AS p ON p.product_id = l.product_id
WHERE o.is_completed
GROUP BY 1, 2, 3;
