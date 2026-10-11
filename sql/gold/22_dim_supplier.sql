-- Gold core: supplier dimension
CREATE OR REPLACE VIEW ${gold}.dim_supplier AS
SELECT supplier_id, supplier_name, country, rating_norm, is_preferred
FROM ${silver}.suppliers;
