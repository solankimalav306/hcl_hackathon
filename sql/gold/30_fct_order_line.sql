-- Gold core: one row per order item
-- ASSUMPTIONS:
--   * silver.order_items already has bad lines quarantined; net_line_amount is the validated line amount.
--   * cost_amt = quantity * product cost_price (NULL if the product is unknown to the catalog).
--   * returned_qty = full item quantity when an approved return exists (source has no return quantity).
--   * refund_amt is capped at the line amount so net_after_refund is never negative.
CREATE OR REPLACE VIEW ${gold}.fct_order_line AS
SELECT
  i.order_item_id,
  i.order_id,
  i.product_id,
  i.quantity                                       AS qty,
  i.unit_price,
  i.net_line_amount                                AS line_net,
  i.quantity * p.cost_price                        AS cost_amt,
  i.line_total_mismatch,
  IF(r.order_item_id IS NULL, 0, i.quantity)       AS returned_qty,
  LEAST(COALESCE(r.refund_amt, 0), i.net_line_amount) AS refund_amt,
  i.net_line_amount - LEAST(COALESCE(r.refund_amt, 0), i.net_line_amount) AS net_after_refund
FROM ${silver}.order_items AS i
JOIN ${silver}.orders AS o ON o.order_id = i.order_id
LEFT JOIN ${silver}.products AS p ON p.product_id = i.product_id
LEFT JOIN ${gold}.agg_returns_by_item AS r ON r.order_item_id = i.order_item_id;
