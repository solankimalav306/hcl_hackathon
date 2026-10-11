-- Gold core: one row per order
-- ASSUMPTIONS:
--   * customer_key = customer_id (silver already remaps merged duplicate customers to the master id).
--   * is_completed = status Completed or Returned: the sale happened, refunds are netted out at line level.
--     Pending and Cancelled orders are excluded from revenue.
--   * net_amt = sum of line_net (before refunds).
CREATE OR REPLACE VIEW ${gold}.fct_order AS
SELECT
  o.order_id,
  o.customer_id                                AS customer_key,
  o.order_date,
  DATE_TRUNC(o.order_date, MONTH)              AS order_month,
  o.order_status                               AS status_std,
  o.channel                                    AS channel_std,
  COALESCE(SUM(l.line_net), 0)                 AS net_amt,
  LOWER(o.order_status) IN ('completed', 'returned') AS is_completed
FROM ${silver}.orders AS o
LEFT JOIN ${gold}.fct_order_line AS l ON l.order_id = o.order_id
GROUP BY o.order_id, o.customer_id, o.order_date, o.order_status, o.channel;
