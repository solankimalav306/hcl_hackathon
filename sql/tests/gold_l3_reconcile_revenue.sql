-- Test: aggregate revenue must equal the sum of completed order lines in fct_order_line (within 1 currency unit).
WITH agg AS (SELECT SUM(net_revenue) AS v FROM ${gold}.agg_rev_month_cat_channel),
     core AS (
       SELECT SUM(l.net_after_refund) AS v
       FROM ${gold}.fct_order_line l JOIN ${gold}.fct_order o ON o.order_id = l.order_id
       WHERE o.is_completed
     )
SELECT agg.v AS agg_revenue, core.v AS core_revenue
FROM agg, core
WHERE ABS(COALESCE(agg.v, 0) - COALESCE(core.v, 0)) > 1;
