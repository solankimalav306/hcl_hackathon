-- Primary keys are unique, and every fact foreign key exists in its dimension.
SELECT 'dim_customer pk' AS check_name, CAST(customer_sk AS STRING) AS key FROM gold.dim_customer GROUP BY customer_sk HAVING COUNT(*) > 1
UNION ALL SELECT 'dim_product pk', CAST(product_sk AS STRING) FROM gold.dim_product GROUP BY product_sk HAVING COUNT(*) > 1
UNION ALL SELECT 'dim_supplier pk', CAST(supplier_sk AS STRING) FROM gold.dim_supplier GROUP BY supplier_sk HAVING COUNT(*) > 1
UNION ALL SELECT 'dim_date pk', CAST(date_key AS STRING) FROM gold.dim_date GROUP BY date_key HAVING COUNT(*) > 1
UNION ALL SELECT 'fact_order_line pk', order_item_id FROM gold.fact_order_line GROUP BY order_item_id HAVING COUNT(*) > 1
UNION ALL SELECT 'fact_return pk', return_id FROM gold.fact_return GROUP BY return_id HAVING COUNT(*) > 1
UNION ALL SELECT 'fact_payment pk', payment_id FROM gold.fact_payment GROUP BY payment_id HAVING COUNT(*) > 1
UNION ALL SELECT 'fact_order_line -> dim_customer', f.order_item_id
  FROM gold.fact_order_line f LEFT JOIN gold.dim_customer d USING (customer_sk) WHERE d.customer_sk IS NULL
UNION ALL SELECT 'fact_order_line -> dim_product', f.order_item_id
  FROM gold.fact_order_line f LEFT JOIN gold.dim_product d USING (product_sk) WHERE d.product_sk IS NULL
UNION ALL SELECT 'fact_order_line -> dim_date', f.order_item_id
  FROM gold.fact_order_line f LEFT JOIN gold.dim_date d ON d.date_key = f.order_date_key WHERE d.date_key IS NULL
UNION ALL SELECT 'fact_return -> dim_date', f.return_id
  FROM gold.fact_return f LEFT JOIN gold.dim_date d ON d.date_key = f.return_date_key WHERE d.date_key IS NULL
UNION ALL SELECT 'fact_payment -> dim_customer', f.payment_id
  FROM gold.fact_payment f LEFT JOIN gold.dim_customer d USING (customer_sk) WHERE d.customer_sk IS NULL
UNION ALL SELECT 'fact_payment -> dim_date', f.payment_id
  FROM gold.fact_payment f LEFT JOIN gold.dim_date d ON d.date_key = f.payment_date_key WHERE d.date_key IS NULL
UNION ALL SELECT 'dim_product -> dim_supplier', p.product_id
  FROM gold.dim_product p LEFT JOIN gold.dim_supplier s USING (supplier_sk) WHERE s.supplier_sk IS NULL
