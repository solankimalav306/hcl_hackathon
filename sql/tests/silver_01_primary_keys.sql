-- Every silver table has a unique primary key. Returns rows on failure.
SELECT 'customers' AS table_name, customer_id AS key, COUNT(*) AS n FROM silver.customers GROUP BY 2 HAVING n > 1
UNION ALL SELECT 'suppliers', supplier_id, COUNT(*) FROM silver.suppliers GROUP BY 2 HAVING COUNT(*) > 1
UNION ALL SELECT 'products', product_id, COUNT(*) FROM silver.products GROUP BY 2 HAVING COUNT(*) > 1
UNION ALL SELECT 'orders', order_id, COUNT(*) FROM silver.orders GROUP BY 2 HAVING COUNT(*) > 1
UNION ALL SELECT 'order_items', order_item_id, COUNT(*) FROM silver.order_items GROUP BY 2 HAVING COUNT(*) > 1
UNION ALL SELECT 'payments', payment_id, COUNT(*) FROM silver.payments GROUP BY 2 HAVING COUNT(*) > 1
UNION ALL SELECT 'returns', return_id, COUNT(*) FROM silver.returns GROUP BY 2 HAVING COUNT(*) > 1
