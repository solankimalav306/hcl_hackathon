-- Business rules that must hold after cleansing.
SELECT 'order_items: quantity <= 0' AS check_name, order_item_id AS key FROM silver.order_items WHERE quantity <= 0
UNION ALL SELECT 'order_items: unit_price <= 0', order_item_id FROM silver.order_items WHERE unit_price <= 0
UNION ALL SELECT 'order_items: discount outside 0-100', order_item_id FROM silver.order_items WHERE discount_pct NOT BETWEEN 0 AND 100
UNION ALL SELECT 'order_items: net amount negative', order_item_id FROM silver.order_items WHERE net_line_amount < 0
UNION ALL SELECT 'returns: refund negative or above line value', r.return_id
  FROM silver.returns r JOIN silver.order_items i USING (order_item_id)
  WHERE r.refund_amount < 0 OR r.refund_amount > i.net_line_amount
UNION ALL SELECT 'suppliers: normalized rating outside 0-1', supplier_id FROM silver.suppliers WHERE rating_norm NOT BETWEEN 0 AND 1
UNION ALL SELECT 'payments: amount not parsed', payment_id FROM silver.payments WHERE amount IS NULL
