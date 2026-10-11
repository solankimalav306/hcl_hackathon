# Looker Studio (formerly Data Studio) setup: data sources are the BigQuery `gold` views

## 1. Give the dashboard viewers access (CLI)
```bash
# whoever opens the report needs to read the views (the report owner's credentials are used if "owner" auth is chosen)
gcloud projects add-iam-policy-binding <project> --member="user:<email>" --role="roles/bigquery.dataViewer"
gcloud projects add-iam-policy-binding <project> --member="user:<email>" --role="roles/bigquery.jobUser"
```

## 2. Create the report
Looker Studio has no CLI. The Linking API can create a report with **one** data source attached (a new report takes no
data source aliases; aliases like `ds0` only exist inside an existing template report). So:
```bash
python scripts/looker_links.py          # prints the starter link (Q1 view attached) and the list of views to add
```
1. Open the printed link while signed in to a Google account with BigQuery access to the project, then authorize the data source.
2. Add the other views: **Resource > Manage added data sources > Add a data source > BigQuery > hcl-hackathon-cloud9 > gold >** pick a view.
   Repeat for each view in the list the script printed (12 more). Name each source after its view.
3. Optional: once the report has all 13 sources, keep it as your template. Copy it instead of rebuilding.
All views live in dataset `gold`.

## 3. Pages and charts (one page per theme)

| Page | View | Chart |
|---|---|---|
| Overview | `q1_monthly_revenue` | Scorecards (net revenue, units, refunds) + time series by `order_month` |
| Growth | `q4_revenue_growth`, `q4_growth_by_category` | Line for `net_revenue`, bars for `mom_growth`, filter by category |
| Customers | `q2_top_customers`, `q3_segments` | Top-10 table; bar of `net_revenue` by segment, `avg_order_value` as a second metric |
| Retention | `q7_repeat_rate_overall`, `q7_repeat_rate_cohort` | Scorecard `repeat_rate_90d`; cohort bar by `first_order_month` |
| Products | `q5_product_returns`, `margin_risk` | Table ranked by `return_rate`; scatter of `margin_pct` vs `net_revenue`, highlight `is_at_risk` |
| Suppliers | `q6_supplier_scorecard` | Table sorted by `score_rank`, bar of `composite_score` |
| Payments | `q8_anomaly_summary`, `q8_payment_anomalies` | Bar of `orders` by `anomaly_type`; detail table |

## 4. Refresh
Views are live, so the dashboard shows whatever the last pipeline run produced. Set the data freshness
in Looker Studio (Resource -> Manage added data sources -> Data freshness) to 1 hour or 4 hours.
