-- Gold facts keep the silver grain and totals exactly (nothing lost, nothing double-counted).
WITH checks AS (
  SELECT 'order lines' AS check_name,
         (SELECT COUNT(*) FROM silver.order_items) AS silver_value,
         (SELECT COUNT(*) FROM gold.fact_order_line) AS gold_value
  UNION ALL SELECT 'net revenue',
         (SELECT ROUND(SUM(net_line_amount), 2) FROM silver.order_items),
         (SELECT ROUND(SUM(net_line_amount), 2) FROM gold.fact_order_line)
  UNION ALL SELECT 'returns', (SELECT COUNT(*) FROM silver.returns), (SELECT COUNT(*) FROM gold.fact_return)
  UNION ALL SELECT 'refunds',
         (SELECT ROUND(SUM(refund_amount), 2) FROM silver.returns),
         (SELECT ROUND(SUM(refund_amount), 2) FROM gold.fact_return)
  UNION ALL SELECT 'payments', (SELECT COUNT(*) FROM silver.payments), (SELECT COUNT(*) FROM gold.fact_payment)
  UNION ALL SELECT 'payment amount',
         (SELECT ROUND(SUM(amount), 2) FROM silver.payments),
         (SELECT ROUND(SUM(amount), 2) FROM gold.fact_payment)
  UNION ALL SELECT 'current customers (+ unknown)',
         (SELECT COUNT(*) + 1 FROM silver.customers),
         (SELECT COUNTIF(is_current) FROM gold.dim_customer)
)
SELECT * FROM checks WHERE silver_value != gold_value
