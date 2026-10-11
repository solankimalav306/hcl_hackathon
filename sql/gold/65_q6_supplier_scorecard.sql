-- Q6: supplier scorecard ranked by composite score
CREATE OR REPLACE VIEW ${gold}.q6_supplier_scorecard AS
SELECT
  RANK() OVER (ORDER BY s.composite_score DESC) AS score_rank,
  s.supplier_id,
  d.supplier_name,
  d.country,
  d.is_preferred,
  s.revenue,
  s.avg_return_rate,
  s.rating_norm,
  s.composite_score
FROM ${gold}.agg_supplier_scorecard AS s
LEFT JOIN ${gold}.dim_supplier AS d ON d.supplier_id = s.supplier_id;
