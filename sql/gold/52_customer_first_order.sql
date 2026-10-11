-- L3: first completed order per customer and 90-day repeat flag
-- orders_within_90d counts completed orders in [first_date, first_date + 90 days],
-- including the first order itself, so is_repeat_90d = orders_within_90d >= 2.
-- Reads: ${gold}.fct_order
CREATE OR REPLACE VIEW ${gold}.customer_first_order AS
WITH completed AS (
  SELECT customer_key, order_id, order_date
  FROM ${gold}.fct_order
  WHERE is_completed
),
first_dt AS (
  SELECT customer_key, MIN(order_date) AS first_completed_date
  FROM completed
  GROUP BY customer_key
)
SELECT
  f.customer_key,
  f.first_completed_date,
  COUNTIF(c.order_date <= DATE_ADD(f.first_completed_date, INTERVAL 90 DAY)) AS orders_within_90d,
  COUNTIF(c.order_date <= DATE_ADD(f.first_completed_date, INTERVAL 90 DAY)) >= 2 AS is_repeat_90d
FROM first_dt AS f
JOIN completed AS c USING (customer_key)
GROUP BY f.customer_key, f.first_completed_date;
