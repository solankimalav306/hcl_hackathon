# ShopSphere Analytics Platform — Data Cleansing (Silver Layer)

Raw order, customer, product, supplier, payment and return files from four source systems are landed in **Google Cloud Storage**, loaded unchanged into **BigQuery (bronze)**, and cleansed into a validated, analysis-ready **silver** layer. Every data-quality decision is logged and every row is accounted for.

## Architecture

```
data/ (7 raw files)
   │  src/load_bronze.py
   ▼
Cloud Storage  gs://<bucket>/landing/<batch_id>/     raw files, unchanged, one folder per load
   │
   ▼
BigQuery bronze   all columns STRING + audit columns (_source_file, _row_num, _ingested_at, _batch_id)
   │  src/run_silver.py  →  sql/silver/*.sql  +  seeds/ref_value_map.csv
   ▼
BigQuery silver   typed · standardized · deduplicated · validated
   ├── clean tables:   customers, suppliers, products, orders, order_items, payments, returns
   ├── lookups:        ref_value_map, customer_xref
   └── DQ audit:       dq_issue_log, dq_quarantine, dq_rule_summary, dq_table_summary
```

## Tech stack
- **Google Cloud Storage**: landing zone
- **BigQuery**: bronze and silver layers, cleansing SQL, reusable SQL functions (UDFs)
- **Python 3.10+**: `google-cloud-bigquery`, `google-cloud-storage`, `python-dotenv`

## Setup

1. Install dependencies:
   ```bash
   python -m venv .venv
   .venv\Scripts\activate          # Windows  (source .venv/bin/activate on macOS/Linux)
   pip install -r requirements.txt
   ```
2. Log in to Google Cloud (opens a browser):
   ```bash
   gcloud auth application-default login
   ```
3. Create `.env` from the template:
   ```bash
   copy .env.example .env          # cp on macOS/Linux
   ```
   ```
   GCP_PROJECT_ID=your-gcp-project-id
   BQ_LOCATION=US
   GCS_BUCKET=your-project-id-landing
   ```
   The project needs billing enabled (required by Cloud Storage). Your account needs the **BigQuery Data Editor**, **BigQuery Job User** and **Storage Object Admin** roles.
4. Put the 7 raw files in `data/`: `customers.csv`, `products.csv`, `orders.csv`, `order_items.csv`, `payments.csv`, `returns.csv`, `suppliers_json.json`.

## Run

```bash
python src/load_bronze.py      # upload data/ to Cloud Storage as a new batch, load it into bronze
python src/run_silver.py       # build silver, run data-quality tests, export DQ summaries to outputs/
```
`python src/load_bronze.py --batch <batch_id>` reloads an existing landed batch without uploading again.

Every silver step uses `CREATE OR REPLACE`, so re-running always produces the same result.

## Project structure

```
src/
  bq.py                 shared BigQuery / Cloud Storage helpers, test runner
  load_bronze.py        landing (GCS) + bronze load
  run_silver.py         builds silver, runs tests, exports DQ summaries
sql/silver/
  00_functions.sql      UDFs: parse_date, date_is_ambiguous, parse_money, parse_bool, clean_str
  10_customers.sql      standardize, deduplicate, merge same person under different IDs
  20_suppliers.sql      resolve conflicting supplier, normalize rating scale
  30_products.sql       standardize categories, resolve "(Revised)" duplicates
  40_orders.sql         standardize status/channel, re-point merged customers
  50_order_items.sql    repair price/discount, recompute line totals, quarantine bad lines
  60_payments.sql       parse currency amounts, standardize status, flag orphans
  70_returns.sql        impute/cap refunds, flag date and status conflicts, quarantine orphans
  90_dq_log.sql         issue log, quarantine, rule summary, reconciliation
sql/tests/silver_*.sql  data-quality tests (each returns rows only on failure)
seeds/ref_value_map.csv label variants → standard values (54 mappings)
docs/DQ_REPORT.md       full profiling & cleansing report
docs/AI_USAGE_LOG.md    AI tools used and how output was validated
outputs/                dq_table_summary.csv, dq_rule_summary.csv, dq_quarantine.csv
```

## How the cleansing works

Each table is built in two steps:
1. **`stg_*`**: every bronze row, with typed and standardized values next to the raw values and a duplicate rank.
2. **Final table**: one trusted row per key.

Every issue gets one of three treatments:

| Treatment | When | Example |
|---|---|---|
| **Fix** | The correct value can be worked out with confidence | `Glod` → `Gold`; `₹2,902.33` → `2902.33`; blank unit price back-solved from line total |
| **Flag** | The row is usable but suspicious, so it is kept and marked | Order from a customer missing in CRM; payment dated before its order |
| **Quarantine** | The row would corrupt KPIs, so it moves to `dq_quarantine` with a reason | Order line with quantity ≤ 0; return for a non-existent order item |

Label variants are mapped through a version-controlled seed file (`seeds/ref_value_map.csv`) rather than hard-coded SQL. A test fails if a new, unmapped variant appears.

## Results

| Table | Bronze | Duplicates / conflicts removed | Merged | Quarantined | Silver |
|---|---:|---:|---:|---:|---:|
| customers | 163 | 5 | 8 | 0 | **150** |
| suppliers | 19 | 1 | 0 | 0 | **18** |
| products | 75 | 5 | 0 | 0 | **70** |
| orders | 323 | 3 | 0 | 0 | **320** |
| order_items | 802 | 5 | 0 | 20 | **777** |
| payments | 329 | 4 | 0 | 0 | **325** |
| returns | 68 | 3 | 0 | 6 | **59** |

`bronze = silver + removed + merged + quarantined` holds for every table and is enforced by a test. 55 rules fired in total; see `outputs/dq_rule_summary.csv`.

## Key issues found and decisions made

| Issue | Decision |
|---|---|
| **Mixed date formats**, including DD/MM and MM/DD in the same column | `YYYY-MM-DD` and `DD-Mon-YYYY` are parsed directly. For `NN/NN/YYYY`: second number > 12 → MM/DD, otherwise DD/MM (Indian convention). Dates valid under both readings are flagged as ambiguous (63 orders). |
| **Same customer under two IDs** (C0170–C0177 copy earlier customers, using `@gmail.com` emails) | Matched on name + normalized phone and merged into the original ID via `customer_xref`; 14 orders re-pointed. |
| **Duplicate product IDs**: an original and a "(Revised)" record with different prices | The Revised record wins. Every order line for those products is priced at the Revised price. |
| **Supplier S004 twice with different names** | The record with a known country wins; the other is logged for review. |
| **Supplier ratings on 5- and 10-point scales** | Ratings above 5 are treated as out of 10 and normalized to `rating_5` and `rating_norm` (0–1). |
| **`line_total` doesn't match qty × price × (1 − discount)** (39 lines) | Recalculated from the inputs; source value kept in `source_line_total`. |
| **Discount 150% / −10%** | Back-solved from `line_total`. All 7 cases resolve to standard levels (0/5/15/20%). |
| **P003 sold at −70.38** (copied from a bad catalog record) | Replaced with the surviving catalog price and flagged. |
| **Orphans** | Kept and flagged where the money is real (unknown customer, product, or order for a payment). Quarantined where the row can't be placed (item without order, return without item). |
| **Refund blank / larger than the line value** | Blank → full line value assumed; too large → capped at the line value. Both flagged. |
| **Placeholder return date `2023-01-01`** | Set to NULL. |
| **Payment amounts as `₹…`, `$…`, `… INR`** | Parsed; `$` treated as INR (same magnitude, India-only business). |

Full details, with every rule and its row count: **[docs/DQ_REPORT.md](docs/DQ_REPORT.md)**.

## Data-quality tests

| Test | Guarantees |
|---|---|
| `silver_01_primary_keys` | One row per key in every silver table |
| `silver_02_reconciliation` | No bronze row disappears without being counted |
| `silver_03_referential` | Items → orders, returns → items, merged customers → master |
| `silver_04_value_ranges` | qty > 0, price > 0, discount 0–100, refund ≤ line value, rating 0–1 |
| `silver_05_unmapped_and_dates` | No unmapped label variants, no unparsed dates |

## Using the silver tables
- Revenue: use `order_items.net_line_amount` (recalculated), not `source_line_total`.
- Customers: `orders.customer_id` already points to the merged master ID; `customer_found = FALSE` marks customers missing from the CRM.
- Ratings: use `suppliers.rating_norm` (0–1) or `rating_5`.
- Every table carries `_source_file`, `_row_num` and `_batch_id`, which trace each row back to its file and line in Cloud Storage.