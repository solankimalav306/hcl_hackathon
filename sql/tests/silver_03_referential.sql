-- Hard links that silver guarantees (soft links like order -> customer are flagged, not enforced).
SELECT 'order_items -> orders' AS check_name, i.order_item_id AS key
FROM silver.order_items i LEFT JOIN silver.orders o USING (order_id) WHERE o.order_id IS NULL
UNION ALL
SELECT 'returns -> order_items', r.return_id
FROM silver.returns r LEFT JOIN silver.order_items i USING (order_item_id) WHERE i.order_item_id IS NULL
UNION ALL
SELECT 'orders.customer_id -> master', o.order_id
FROM silver.orders o LEFT JOIN silver.customers c USING (customer_id) WHERE o.customer_found AND c.customer_id IS NULL
