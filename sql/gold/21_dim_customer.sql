-- Gold core: customer dimension. Personal details (name, email, phone, address) stay in silver.
CREATE OR REPLACE VIEW ${gold}.dim_customer AS
SELECT
  customer_id,
  city,
  state,
  signup_date,
  customer_segment AS segment_std,
  is_active
FROM ${silver}.customers;
