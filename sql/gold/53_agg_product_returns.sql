-- L3: return rate per product (completed orders)
-- meets_min_volume: ASSUMPTION - at least params.min_return_volume units ordered (config/config.yaml).
-- Reads: ${gold}.fct_order_line, ${gold}.fct_order
CREATE OR REPLACE VIEW ${gold}.agg_product_returns AS
SELECT
  l.product_id,
  SUM(l.qty)                                      AS ordered_qty,
  SUM(l.returned_qty)                             AS returned_qty,
  SAFE_DIVIDE(SUM(l.returned_qty), SUM(l.qty))    AS return_rate,
  SUM(l.qty) >= ${min_return_volume}              AS meets_min_volume
FROM ${gold}.fct_order_line AS l
JOIN ${gold}.fct_order      AS o ON o.order_id = l.order_id
WHERE o.is_completed
GROUP BY l.product_id;
