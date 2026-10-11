-- Test: return rates in [0, 1] and no negative payment totals.
SELECT 'bad_return_rate' AS issue, product_id AS id FROM ${gold}.agg_product_returns WHERE return_rate < 0 OR return_rate > 1
UNION ALL
SELECT 'bad_paid_amt', order_id FROM ${gold}.agg_order_payments WHERE paid_amt < 0;
