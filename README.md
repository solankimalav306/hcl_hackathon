# ShopSphere e-commerce analytics: bronze → silver → gold → Looker Studio

End-to-end analytics pipeline on **Google Cloud** (Cloud Storage + BigQuery, Python, optional Dataproc and Cloud Workflows).
Seven messy source files go in; cleaned, validated tables and eight business KPIs come out, ready for a Looker Studio dashboard.

```
data/ (7 raw files)
  │ src/load_bronze.py
  ▼
Cloud Storage  gs://<bucket>/landing/<batch_id>/        raw files, unchanged, one folder per load
  ▼
BigQuery  bronze   all STRING + audit columns            raw copy, nothing lost
  │ src/run_silver.py  (sql/silver + seeds)
  ▼
BigQuery  silver   typed, standardized, deduplicated, validated, DQ-audited
  │ src/run_gold.py    (sql/gold, config/config.yaml)
  ▼
BigQuery  gold     facts/dims (views) → aggregates (tables) → KPI views Q1-Q8 + Margin Risk
  ▼
Looker Studio      reads the gold KPI views
```

| Layer | Owner doc |
|---|---|
| Bronze + silver (cleansing, DQ rules, decisions) | [readme_datacleaning.md](readme_datacleaning.md) |
| Gold (facts, dims, aggregates, KPIs) | this file |
| Lineage / table contract | [kpi_layer_schemas.md](kpi_layer_schemas.md), [simple_table_to_kpi_map.png](simple_table_to_kpi_map.png) |

## Setup

```bash
python -m venv .venv
.venv\Scripts\activate                 # macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
gcloud auth application-default login
```
Create `.env` in the repo root (never commit it):
```
GCP_PROJECT_ID=your-gcp-project-id
BQ_LOCATION=US
GCS_BUCKET=your-project-id-landing
```
Your account needs **BigQuery Data Editor**, **BigQuery Job User** and **Storage Object Admin**. Put the 7 raw files in `data/`
(`customers.csv`, `products.csv`, `orders.csv`, `order_items.csv`, `payments.csv`, `returns.csv`, `suppliers_json.json`).

## Run

```bash
python src/load_bronze.py      # land raw files in Cloud Storage as a new batch, load bronze
python src/run_silver.py       # build silver, run silver tests, export DQ summaries to outputs/
python src/run_gold.py         # build gold (facts/dims, aggregates, KPI views) and run gold tests
```
`python src/run_pipeline.py` chains all three steps (bronze -> silver -> gold). `.env.example` shows the variables `.env` needs.
Every step uses `CREATE OR REPLACE`, so a rerun gives the same result.

## Gold layer

All gold objects live in the BigQuery dataset `gold`. SQL is in `sql/gold/` and runs in filename order.

| Files | Objects | Built as |
|---|---|---|
| `10`-`40` | `agg_returns_by_item`, `dim_product`, `dim_customer`, `dim_supplier`, `fct_order_line`, `fct_order` | views |
| `50`-`55` | `agg_rev_month_cat_channel`, `agg_customer_ltv`, `customer_first_order`, `agg_product_returns`, `agg_supplier_scorecard`, `agg_order_payments` | **tables** |
| `60`-`68` | KPI views (below) | views |

### KPI views
| KPI | Views |
|---|---|
| Q1 monthly revenue | `q1_monthly_revenue`, `q1_revenue_by_cat_channel` |
| Q2 top 10 customers by net LTV | `q2_top_customers` |
| Q3 customer segments | `q3_segments` |
| Q4 revenue growth (month over month) | `q4_revenue_growth`, `q4_growth_by_category` |
| Q5 product return-rate ranking | `q5_product_returns` |
| Q6 supplier scorecard | `q6_supplier_scorecard` |
| Q7 90-day repeat rate | `q7_repeat_rate_cohort`, `q7_repeat_rate_overall` |
| Q8 payment anomalies | `q8_payment_anomalies`, `q8_anomaly_summary` |
| Margin risk | `margin_risk` |

### Configuration (`config/config.yaml`)
- `params:` business thresholds injected into the SQL as `${name}` (min return volume, payment tolerance, supplier score weights, margin-risk threshold).
- `materialization:` which gold objects are tables; everything else is a view. Flipping an object is a config change only; `run_gold.py` swaps the object type automatically.
  At large scale, move `fct_order_line` and `fct_order` into the `table:` list (see "Scaling").
- `infra:` project, region, bucket and schedule used by `scripts/deploy.sh`.

### Gold tests (`sql/tests/gold_*.sql`)
Each file passes when it returns **zero rows**: unique keys, rates within range, no negative payments, and aggregate revenue reconciling to the line-level facts.

### Business assumptions (confirm with the business)
- An order is **completed** when its status is `Completed` or `Returned`; refunds are netted out at line level. Pending and Cancelled are excluded from revenue.
- Only **Approved** returns count. The source has no returned quantity, so an approved return counts as the full item quantity.
- Refunds are capped at the line amount.
- Payments: only `Success` counts as paid; orders that are not completed and unpaid are `not_applicable`, not anomalies. Tolerance comes from config.
- `customer_key` is the customer id (silver already remaps merged duplicate customers).
- Supplier `composite_score` weights and the margin-risk threshold are placeholders in `config.yaml`.

## Looker Studio
Looker Studio has no CLI. `python scripts/looker_links.py` prints a link that creates a report with one KPI view attached (add the rest from inside Looker Studio);
chart layout suggestions are in [docs/looker_studio.md](docs/looker_studio.md).

## Cloud orchestration (Cloud Run Job + Cloud Workflows, written but not yet executed)
The Python scripts are the automation; `workflow.yaml` is the orchestration. No Docker is needed: `gcloud run jobs deploy --source .`
builds the container from the repo (`.gcloudignore` keeps data, docs and secrets out).

```
gs://<bucket>/landing/<batch_id>/   (bash scripts/land_files.sh uploads data/ as a new batch)
        |
Cloud Scheduler (daily)  ->  Cloud Workflows "ecom-pipeline"
        1. Cloud Run Job: python src/load_bronze.py --batch <newest batch>    bronze
        2. Cloud Run Job: python src/run_silver.py                             silver + silver tests
        3. Dataproc Serverless: dataproc/dq_job.py                             silver DQ gate (skip with {"dq_gate": false})
        4. Cloud Run Job: python src/run_gold.py                               gold + gold tests
```
Deploy and run (all CLI):
```bash
bash scripts/deploy.sh                    # APIs, service account + roles, Cloud Run Job, workflow, daily schedule
bash scripts/land_files.sh                # land data/ in Cloud Storage as a new batch
gcloud workflows run ecom-pipeline --location=us-central1
```
The workflow processes the newest landed batch, or one you pass: `--data='{"batch_id": "b_...", "dq_gate": false}'`.
A failure in any step is logged with the batch id and re-raised, which is where failure handling plugs in.
`scripts/build_gold_script.py` (a single-file gold script for scheduled queries) is no longer used by the workflow.

## Scaling and incremental loading (design, not built)
The pipeline currently does a **full refresh** at every layer, which is fine at this data size. For large data:
append to bronze (keep `_batch_id`), track processed batches in an ops table, keep the latest record per key in silver, make
`fct_*` partitioned tables updated by `MERGE`, and recompute aggregates only for affected months/customers/suppliers.
Rankings and min-max scoring (LTV rank, return rank, supplier score) remain full recomputations because they depend on all rows.

## Known gaps (checked against the repo)
1. `docs/DQ_REPORT.md` and `docs/AI_USAGE_LOG.md` are referenced by the cleansing README but absent.
2. The root `tests/` folder (`gold_01_keys`, `gold_02_scd2`, `gold_03_reconciliation`) targets a different gold design (star schema with SCD2) and is not run by this pipeline. Only `sql/tests/` is run.

## Repository layout
```
src/            bq.py, load_bronze.py, run_silver.py, run_gold.py, gold_sql.py, run_pipeline.py
sql/silver/     cleansing SQL (bronze -> silver)
sql/gold/       gold SQL (see above)
sql/tests/      silver_*.sql and gold_*.sql data-quality tests
config/         config.yaml
scripts/        deploy.sh, build_gold_script.py, looker_links.py
dataproc/       dq_job.py (PySpark data-quality gate)
workflow.yaml   Cloud Workflows definition
docs/           looker_studio.md
```
