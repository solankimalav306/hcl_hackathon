-- Q5: product return-rate ranking (only products meeting the minimum volume)
CREATE OR REPLACE VIEW ${gold}.q5_product_returns AS
SELECT
  RANK() OVER (ORDER BY r.return_rate DESC) AS return_rank,
  r.product_id,
  p.product_name,
  p.category_std,
  r.ordered_qty,
  r.returned_qty,
  r.return_rate
FROM ${gold}.agg_product_returns AS r
LEFT JOIN ${gold}.dim_product AS p ON p.product_id = r.product_id
WHERE r.meets_min_volume;
