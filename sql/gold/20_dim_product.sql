-- Gold core: product dimension (silver.products is already deduplicated and standardized)
CREATE OR REPLACE VIEW ${gold}.dim_product AS
SELECT
  product_id,
  product_name,
  category AS category_std,
  sub_category,
  cost_price,
  supplier_id,
  is_active
FROM ${silver}.products;
