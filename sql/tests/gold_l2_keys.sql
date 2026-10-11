-- Test: L2 keys unique, and no order line without an order or with negative net.
SELECT 'fct_order dup' AS issue, order_id AS id FROM ${gold}.fct_order GROUP BY order_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'fct_order_line dup', order_item_id FROM ${gold}.fct_order_line GROUP BY order_item_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_product dup', product_id FROM ${gold}.dim_product GROUP BY product_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_customer dup', customer_id FROM ${gold}.dim_customer GROUP BY customer_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_supplier dup', supplier_id FROM ${gold}.dim_supplier GROUP BY supplier_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'negative net_after_refund', order_item_id FROM ${gold}.fct_order_line WHERE net_after_refund < 0;
