-- Q1: monthly net revenue (completed orders, net of refunds)
CREATE OR REPLACE VIEW ${gold}.q1_monthly_revenue AS
SELECT
  order_month,
  SUM(units)       AS units,
  SUM(line_net)    AS line_net,
  SUM(refund_amt)  AS refund_amt,
  SUM(net_revenue) AS net_revenue
FROM ${gold}.agg_rev_month_cat_channel
GROUP BY order_month;

-- Q1 breakdown for filters/charts in the dashboard
CREATE OR REPLACE VIEW ${gold}.q1_revenue_by_cat_channel AS
SELECT order_month, category_std, channel_std, units, line_net, refund_amt, net_revenue
FROM ${gold}.agg_rev_month_cat_channel;
