-- Test: returns rows ONLY when something is wrong (the runner fails the pipeline if any row comes back).
SELECT 'agg_customer_ltv' AS tbl, customer_key AS dup_key FROM ${gold}.agg_customer_ltv GROUP BY customer_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'customer_first_order', customer_key FROM ${gold}.customer_first_order GROUP BY customer_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'agg_product_returns', product_id FROM ${gold}.agg_product_returns GROUP BY product_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'agg_supplier_scorecard', supplier_id FROM ${gold}.agg_supplier_scorecard GROUP BY supplier_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'agg_order_payments', order_id FROM ${gold}.agg_order_payments GROUP BY order_id HAVING COUNT(*) > 1;
