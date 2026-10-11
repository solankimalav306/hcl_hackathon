-- Gold core: approved returns rolled up to order item
-- ASSUMPTIONS:
--   * Only Approved returns count (Rejected and Pending are ignored).
--   * The source has no returned quantity, so returned_qty here is a placeholder (= return count);
--     the real value (full item qty when an approved return exists) is set in fct_order_line.
--   * silver.returns.refund_amount is already imputed/capped by the silver layer.
CREATE OR REPLACE VIEW ${gold}.agg_returns_by_item AS
SELECT
  order_item_id,
  COUNT(*)           AS return_count,
  COUNT(*)           AS returned_qty,
  SUM(refund_amount) AS refund_amt
FROM ${silver}.returns
WHERE UPPER(return_status) = 'APPROVED'
GROUP BY order_item_id;
