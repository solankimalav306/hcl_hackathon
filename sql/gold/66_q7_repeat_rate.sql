-- Q7: 90-day repeat rate by first-order month cohort, and overall
CREATE OR REPLACE VIEW ${gold}.q7_repeat_rate_cohort AS
SELECT
  DATE_TRUNC(first_completed_date, MONTH) AS first_order_month,
  COUNT(*)                                AS customers,
  COUNTIF(is_repeat_90d)                  AS repeat_customers,
  SAFE_DIVIDE(COUNTIF(is_repeat_90d), COUNT(*)) AS repeat_rate_90d
FROM ${gold}.customer_first_order
GROUP BY first_order_month;

CREATE OR REPLACE VIEW ${gold}.q7_repeat_rate_overall AS
SELECT
  COUNT(*)               AS customers,
  COUNTIF(is_repeat_90d) AS repeat_customers,
  SAFE_DIVIDE(COUNTIF(is_repeat_90d), COUNT(*)) AS repeat_rate_90d
FROM ${gold}.customer_first_order;
