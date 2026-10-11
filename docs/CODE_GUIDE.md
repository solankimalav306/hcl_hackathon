# Code guide: what every file does and why

This guide walks through **every piece of code in the repo**, in the order data flows through it. Read section 1 for the
big picture, then jump to the file you care about. Status notes are honest: where something was written but not yet run, it says so.

---

## 1. The big picture

```
 data/*.csv, suppliers_json.json          (7 messy raw files)
        │   src/load_bronze.py
        ▼
 Cloud Storage  landing/<batch_id>/        raw files copied as-is, one immutable folder per load
        │   (same script reads them back)
        ▼
 BigQuery  bronze.*                        every column STRING + audit columns. Nothing is fixed or dropped here.
        │   src/run_silver.py  runs  sql/silver/*.sql   (+ seeds/ref_value_map.csv)
        ▼
 BigQuery  silver.*                        typed, standardized, de-duplicated, validated, DQ-audited
        │   src/run_gold.py  runs  sql/gold/*.sql   (+ config/config.yaml)
        ▼
 BigQuery  gold.*                          facts/dims (views) → aggregates (tables) → KPI views (Q1..Q8, margin risk)
        │
        ▼
 Looker Studio dashboard                   reads the gold KPI views
```

**Three ideas to hold on to**
1. **ELT, medallion layers.** Load raw first (bronze), clean in the warehouse with SQL (silver), then build business-ready tables (gold).
   Bronze is never edited, so any rule can be changed and silver rebuilt from it.
2. **Python is the automation, SQL is the logic.** The Python files are thin: they upload, load, run SQL files in order and run tests.
   Almost all business logic lives in `sql/`.
3. **Tests are SQL queries that return rows only on failure.** Zero rows = pass. Any row = the pipeline stops.

---

## 2. Repository map

```
src/                     Python automation (what you run)
  bq.py                  shared BigQuery/Cloud Storage helpers and environment settings
  load_bronze.py         land files in Cloud Storage and load bronze
  run_silver.py          build silver, run silver tests, export DQ summaries
  gold_sql.py            gold helper: reads config, fills SQL placeholders, picks view vs table
  run_gold.py            build gold, run gold tests
  run_pipeline.py        runs the three steps above in order
  test.py                one-off connectivity check
sql/silver/              cleansing SQL (bronze -> silver), run in filename order
sql/gold/                business-layer SQL (silver -> gold), run in filename order
sql/tests/               data-quality tests: silver_*.sql and gold_*.sql
seeds/ref_value_map.csv  label-variant -> standard-value mappings (54 rows)
config/config.yaml       project settings, business thresholds, view-vs-table choices
workflow.yaml            Cloud Workflows definition (the orchestration)
dataproc/dq_job.py       PySpark data-quality gate on silver (runs on Dataproc Serverless)
scripts/                 deploy.sh, land_files.sh, build_gold_script.py, looker_links.py
.gcloudignore            what is left out of the Cloud Run build
.python-version          Python version used by the Cloud Run build
.env / .env.example      local settings (project, bucket, location); .env is git-ignored
docs/                    this guide and the Looker Studio notes
kpi_layer_schemas.md     the design contract for the layers; simple_table_to_kpi_map.png is its picture
readme_datacleaning.md   the cleansing (bronze -> silver) write-up
```

---

## 3. Python code (`src/`)

### 3.1 `src/bq.py`: shared helpers
Imported by every runner. It is the only place that knows about environment settings.

- Loads `.env` from the repo root (`load_dotenv`). Required variables: `GCP_PROJECT_ID`, `GCS_BUCKET`. Optional: `BQ_LOCATION` (default `US`).
- `DATASETS = ["bronze", "silver", "gold"]`: the three warehouse layers.
- `get_client()`: a BigQuery client for the project/location. Credentials come from Application Default Credentials
  (`gcloud auth application-default login` locally, the service account on Cloud Run).
- `get_bucket()`: returns the landing bucket, **creating it if it doesn't exist** (in the BigQuery location).
- `ensure_datasets(client)`: creates `bronze`, `silver`, `gold` if missing (`exists_ok=True`, safe to repeat).
- `run_sql_file(client, path)`: reads a `.sql` file (it may contain many statements; BigQuery runs them as a script) and
  returns the rows of the last statement. Tests use this: returned rows are the failures.
- The `warnings.filterwarnings` line at the top just hides a harmless Python-version notice from Google libraries.

### 3.2 `src/load_bronze.py`: landing and bronze
Two jobs: put the raw files in Cloud Storage, then load them into BigQuery `bronze`.

- `SOURCES`: the map `bronze table -> source file` (customers, products, orders, order_items, payments, returns, suppliers).
- `AUDIT_FIELDS`: four extra columns added to every bronze table: `_source_file` (the `gs://` path), `_row_num` (line in the source file),
  `_ingested_at` (timestamp of the load), `_batch_id` (the landing folder). These give full lineage back to the exact file and line.
- `land_files(bucket, batch_id)`: uploads each file from `data/` to `landing/<batch_id>/<file>`.
- `parse_source(file_name, text)`: turns file text into `(columns, rows)`. JSON is read as an array of records (every value converted to a string,
  nulls kept as null). CSV is read with `csv.DictReader`; the line number is captured from the reader so `_row_num` points at the real line,
  including multi-line quoted fields. Files are decoded as `utf-8-sig` so a Windows BOM doesn't corrupt the first column name.
- `load_table(...)`: downloads the landed file **back from Cloud Storage**, parses it, builds a schema of all-STRING columns plus audit columns,
  and loads it with `WRITE_TRUNCATE` (the bronze table is replaced). All-STRING means a bad date or `₹` amount can never reject a row.
- `main(batch_id=None)`: with no batch id, it creates one (`b_YYYYMMDD_HHMMSS_<6 hex>`), lands the files, then loads. With `--batch <id>`
  it skips the upload and reloads an existing landed batch, which is what the cloud workflow does.
- Entry point: `python src/load_bronze.py [--batch <id>]`.

### 3.3 `src/run_silver.py`: build silver
- `load_seeds(client)`: reads `seeds/ref_value_map.csv`, lower-cases `raw_value`, loads it as `silver.ref_value_map`
  (columns `domain, raw_value, standard_value`). This must happen first because the silver SQL joins to it.
- It then runs `sql/silver/*.sql` in sorted filename order (`00_functions` first, `90_dq_log` last).
- `run_tests(client)`: runs each `sql/tests/silver_*.sql`; prints `PASS` or `FAIL (n rows)` and up to 10 offending rows; returns False if any failed.
- `export(client, table)`: reads a DQ table and writes it to `outputs/<table>.csv`; also returns the rows for printing.
- `main()`: seeds → SQL → tests → prints the bronze-to-silver reconciliation table (`dq_table_summary`) and the rules that fired
  (`dq_rule_summary`) → exports `dq_quarantine` → exits with an error message if any test failed. (`sys.stdout.reconfigure(encoding="utf-8")`
  is needed on Windows because rule text contains the `₹` symbol.)

### 3.4 `src/gold_sql.py`: gold helper (new, ours)
Prepares a gold SQL file before it is sent to BigQuery.

- `load_config()` reads `config/config.yaml`.
- `_kind(name, cfg)` returns `TABLE` if the object is listed under `materialization.table`, otherwise the default (`VIEW`).
- `objects(raw_sql, cfg)` finds every `CREATE OR REPLACE VIEW ${gold}.<name>` in a file and returns `(name, kind)` pairs.
- `render(raw_sql, cfg)` does two things: (1) a regex rewrites `CREATE OR REPLACE VIEW` into `... TABLE` for objects configured as tables;
  (2) replaces `${silver}`, `${gold}` and every `params:` value from the config with real text
  (`string.Template.substitute`, so a **missing placeholder fails loudly** instead of silently producing bad SQL).
- Why: the SQL files are always written as views. Whether an object is physically a table is a config choice, not a code change.

### 3.5 `src/run_gold.py`: build gold (new, ours)
- `reconcile_types(client, raw_sql, cfg)`: BigQuery refuses to `CREATE OR REPLACE VIEW` over an existing table (and vice versa).
  Before each file runs, if an object exists as the other type, it is dropped (and the change is printed: `gold.x: replaced TABLE with VIEW`).
  This is what makes flipping an object between view and table a one-line config change.
- `build(client, cfg)`: for each `sql/gold/*.sql` in order: reconcile types → render → run → print `ran <file> [VIEW|TABLE]`.
- `run_tests(client, cfg)`: same convention as silver, for `sql/tests/gold_*.sql`.
- `main()`: load config → ensure datasets → build → test → exit non-zero if a test fails.

### 3.6 `src/run_pipeline.py`: the whole thing locally
Runs `load_bronze.main()`, then `run_silver.main()`, then `run_gold.main()`. `python src/run_pipeline.py`.

### 3.7 Test and helper scripts
- `src/test.py`: runs `SELECT 1` against BigQuery to prove credentials work.
- Root `test.py` (older copy of the same check).

---

## 4. Silver SQL (`sql/silver/`)

General pattern for every table: **(1) a `stg_*` table** keeps every bronze row with typed/standardized values *next to* the raw values and
a duplicate rank (`key_rank`, `key_count`), **(2) the final table** keeps one trusted row per key. Standardizing never overwrites the raw value,
so the DQ log can show old vs new.

| File | Builds | What it does |
|---|---|---|
| `00_functions.sql` | 5 persistent UDFs in `silver` | `clean_str` (blank / `NA` / `N/A` / `null` / `none` / `unknown` / `XXXXXX` → NULL); `parse_date` (accepts `YYYY-MM-DD`, `DD-Mon-YYYY`, `NN/NN/YYYY`; for slashes: second part > 12 → MM/DD, otherwise DD/MM); `date_is_ambiguous` (true when both readings of a slash date are valid and differ); `parse_money` (strips everything but digits, `.`, `-`: handles `₹2,902.33`, `$1,234.50`, `73078.38 INR`); `parse_bool` (y/yes/true/t/1 → TRUE, n/no/false/f/0 → FALSE) |
| `10_customers.sql` | `stg_customers`, `stg_customers_ranked`, `customer_xref`, `customers` | Cleans names/email/phone (Indian 10-digit rule)/city/zip/dates/segment; ranks repeats of the same `customer_id` (keep the most complete row); `customer_xref` merges the same person under different ids (same first name + last name + phone → lowest id is the master); `customers` = one row per real person with `source_customer_ids` |
| `20_suppliers.sql` | `stg_suppliers`, `suppliers` | Resolves the duplicate supplier S004 (keep the row with a known country); normalizes ratings (above 5 means a 10-point scale): `rating_5` and `rating_norm` (0 to 1); missing country → `Unknown` |
| `30_products.sql` | `stg_products`, `products` | Maps category via the seed, infers a missing category from the sub-category, parses `₹` prices, resolves repeated product ids (the "(Revised)" row wins), flags cost > list price and unknown suppliers |
| `40_orders.sql` | `stg_orders`, `orders` | Standardizes status/channel/city via the seed, nulls placeholder promo codes, drops exact duplicates, re-points orders of merged customers to the master id (`customer_xref`), flags unknown customers and orders with no line items |
| `50_order_items.sql` | `stg_order_items`, `order_items` | Back-solves a blank price from the line total, replaces a negative price with the catalog price, back-solves an out-of-range discount, **recomputes** `net_line_amount = qty × price × (1 − discount%)`, flags `line_total_mismatch`, and **quarantines** lines with no order or an invalid quantity/price/discount |
| `60_payments.sql` | `stg_payments`, `payments` | Parses currency-formatted amounts (all treated as INR), standardizes status, drops exact duplicates; **keeps and flags** orphan payments, missing/early dates and method mismatches (reporting them is the point of KPI 8) |
| `70_returns.sql` | `stg_returns`, `returns` | Quarantines returns that can't be tied to a valid sale line; fills a blank refund with the full line value and caps a refund above the line value; nulls the placeholder date 2023-01-01; flags returns dated before the order or against a pending/cancelled order |
| `90_dq_log.sql` | `dq_issue_log`, `dq_quarantine`, `dq_rule_summary`, `dq_table_summary` | See 4.1 |

**Three treatments for every problem:** *fix* (the right value is certain), *flag* (keep the row, mark it), *quarantine* (the row would corrupt KPIs, so it goes to `dq_quarantine` with a reason).

### 4.1 `90_dq_log.sql`: the audit trail
Built **only from** the `stg_*` and final silver tables (no extra Python):
- `dq_issue_log`: one row per record per rule: `rule_id, table_name, record_key, column_name, issue, action, old_value, new_value`.
  Rule ids: `CUS` customers, `SUP` suppliers, `PRD` products, `ORD` orders, `OI` order items, `PAY` payments, `RET` returns.
  Example: `ORD-02` standardized an order status, `old_value` = the raw text, `new_value` = the clean one.
- `dq_quarantine`: the rejected rows (order items and returns) with `reject_reason` and the original bronze record as JSON.
- `dq_rule_summary`: `GROUP BY` of the issue log: how many records each rule touched.
- `dq_table_summary`: reconciliation per table: `bronze_rows = silver_rows + duplicates_removed + merged_into_master + quarantined`;
  the `balanced` column must be TRUE everywhere (a silver test enforces it).
**Casing convention:** the seed lookup is case-insensitive, so capitalisation and stray spaces are normalised silently. The seven
`STANDARDIZED` rules (`CUS-03`, `CUS-04`, `ORD-02`, `ORD-03`, `PAY-03`, `PRD-02`, `RET-08`) compare `LOWER(TRIM(raw))` with the clean value,
so they count only real variants (misspellings and aliases such as `Complted` or `Canceled`), not casing-only differences.
This removed 650 casing-only rows from the issue log (1,918 to 1,268); the other rules and the silver tables are unchanged.

### 4.2 Seeds: `seeds/ref_value_map.csv`
54 rows, `domain,raw_value,standard_value`. Domains: `channel`, `city`, `customer_segment`, `order_status`, `payment_status`,
`product_category`, `return_reason`, `return_status`. Version-controlled mappings instead of hard-coded `CASE` statements. A silver test fails if a new unmapped variant appears.

### 4.3 Silver tests (`sql/tests/silver_*.sql`)
| Test | Returns rows when... |
|---|---|
| `silver_01_primary_keys` | any silver table has a repeated key |
| `silver_02_reconciliation` | any table's `balanced` is FALSE in `dq_table_summary` |
| `silver_03_referential` | items point to missing orders, returns to missing items, or merged customers don't resolve to a master |
| `silver_04_value_ranges` | quantity ≤ 0, price ≤ 0, discount outside 0 to 100, refund above the line value, rating outside 0 to 1 |
| `silver_05_unmapped_and_dates` | a label is unmapped (`Unknown`) or a date failed to parse |

---

## 5. Gold SQL (`sql/gold/`)

All files are written as `CREATE OR REPLACE VIEW ${gold}.<name> AS ...` and read from `${silver}` / `${gold}`.
`config.yaml` decides which become tables. `${...}` placeholders are explained in section 7.

### 5.1 Core: facts and dimensions (views)
| File | Object | Logic |
|---|---|---|
| `10_agg_returns_by_item.sql` | `agg_returns_by_item` | Approved returns only, grouped by `order_item_id`: `return_count`, `returned_qty` (placeholder = count), `refund_amt` |
| `20_dim_product.sql` | `dim_product` | Selects from `silver.products`; `category` → `category_std` |
| `21_dim_customer.sql` | `dim_customer` | From `silver.customers`; **no names, email, phone or address** (those stay in silver); `customer_segment` → `segment_std` |
| `22_dim_supplier.sql` | `dim_supplier` | From `silver.suppliers`: name, country, `rating_norm`, `is_preferred` |
| `30_fct_order_line.sql` | `fct_order_line` | One row per order item. `line_net` = `net_line_amount`; `cost_amt = quantity × product cost_price`; `returned_qty` = full quantity if an approved return exists; `refund_amt` capped at the line amount; `net_after_refund = line_net − refund_amt` |
| `40_fct_order.sql` | `fct_order` | One row per order. `customer_key = customer_id`; `order_month = DATE_TRUNC(order_date, MONTH)`; `net_amt = SUM(line_net)`; `is_completed` = status is `Completed` or `Returned` |

### 5.2 Aggregates (tables)
| File | Object | Logic |
|---|---|---|
| `50_agg_rev_month_cat_channel.sql` | `agg_rev_month_cat_channel` | Completed orders only; sums units, `line_net`, refunds, `net_revenue` by month × category × channel (unknown product category = `Unknown`) |
| `51_agg_customer_ltv.sql` | `agg_customer_ltv` | Per customer: completed orders, `net_ltv = SUM(net_after_refund)`, last order date, `ltv_rank = RANK() OVER (ORDER BY net_ltv DESC)` |
| `52_customer_first_order.sql` | `customer_first_order` | First completed order date per customer, `orders_within_90d` (completed orders from the first date up to 90 days later, **including** the first), `is_repeat_90d = orders_within_90d >= 2` |
| `53_agg_product_returns.sql` | `agg_product_returns` | Per product (completed orders): `ordered_qty`, `returned_qty`, `return_rate = returned/ordered`, `meets_min_volume = ordered_qty >= min_return_volume` |
| `54_agg_supplier_scorecard.sql` | `agg_supplier_scorecard` | Per supplier: revenue (sum of `net_after_refund`), `avg_return_rate` (mean of product return rates that meet the minimum volume), `rating_norm`, and `composite_score = w_revenue × minmax(revenue) + w_returns × (1 − avg_return_rate) + w_rating × rating_norm` |
| `55_agg_order_payments.sql` | `agg_order_payments` | Per order: `order_total` vs `paid_amt` (sum of **Success** payments), `success_payment_count`, `duplicate_count` (extra Success payments with the same amount = likely double charge), `no_success_flag`, and `anomaly_type`: `not_applicable` (unpaid and not completed) → `no_success_payment` → `duplicate_payment` → `underpaid` → `overpaid` → `ok` (first match wins; tolerance = `payment_tolerance`) |

### 5.3 KPI views (what the dashboard reads)
| File | Views | Meaning |
|---|---|---|
| `60_q1_monthly_revenue.sql` | `q1_monthly_revenue`, `q1_revenue_by_cat_channel` | Net revenue per month; the same by category and channel |
| `61_q2_top_customers.sql` | `q2_top_customers` | Top 10 by net LTV, with city/state/segment (no personal data) |
| `62_q3_segments.sql` | `q3_segments` | Per segment: customers, completed orders, net revenue, average LTV, average order value |
| `63_q4_revenue_growth.sql` | `q4_revenue_growth`, `q4_growth_by_category` | Month-over-month growth using `LAG`: `(this − previous) / previous` |
| `64_q5_product_returns.sql` | `q5_product_returns` | Products meeting the minimum volume, ranked by return rate |
| `65_q6_supplier_scorecard.sql` | `q6_supplier_scorecard` | Suppliers ranked by `composite_score`, with name and country |
| `66_q7_repeat_rate.sql` | `q7_repeat_rate_cohort`, `q7_repeat_rate_overall` | 90-day repeat rate by first-order month, and overall |
| `67_q8_payment_anomalies.sql` | `q8_payment_anomalies`, `q8_anomaly_summary` | Detail rows (everything except `ok` / `not_applicable`) and a summary by type |
| `68_margin_risk.sql` | `margin_risk` | Per product: `margin_amt = net_revenue − cost_amt`, `margin_pct`, and `is_at_risk` when below `margin_risk_threshold` |

### 5.4 Gold tests (`sql/tests/gold_*.sql`)
- `gold_l2_keys`: `fct_order`, `fct_order_line` and the three dims have unique keys; no negative `net_after_refund`.
- `gold_l3_unique_keys`: the aggregates have unique keys.
- `gold_l3_rates_valid`: return rates within 0 to 1; no negative `paid_amt`.
- `gold_l3_reconcile_revenue`: aggregate revenue equals the sum of completed order lines (within 1 currency unit). This catches a join that fans out or drops rows.

---

## 6. Key business assumptions (all adjustable)
- **Completed order** = `Completed` or `Returned`; refunds are netted at line level. Pending and Cancelled never count as revenue.
- **Returns:** only `Approved` returns count. The data has no returned quantity, so an approved return counts as the **full item quantity**.
- **Customer key** = customer id (silver already merged duplicate people).
- **Payments:** only `Success` counts as paid; `Refunded`, `Failed`, `Pending` don't.
- **Currency:** everything is INR (including `$`-formatted amounts).
- **Thresholds and weights** (min volume 10, tolerance 1.00, margin risk 15%, score weights 0.4/0.3/0.3) are placeholders for the business to confirm.

---

## 7. Configuration (`config/config.yaml`)
| Section | Used by | Purpose |
|---|---|---|
| `infra:` | `scripts/deploy.sh`, `land_files.sh`, `looker_links.py` | project, region, BigQuery location, bucket, service account name, schedule, time zone |
| `params:` | gold SQL via `${name}` | `min_return_volume`, `payment_tolerance`, `margin_risk_threshold`, `w_revenue`, `w_returns`, `w_rating` |
| `materialization:` | `gold_sql.py` / `run_gold.py` | default `view`; the listed objects are built as tables |

**Scaling hint:** to materialize the facts at large scale, add `fct_order_line` and `fct_order` to `materialization.table`. That is a config-only change.
Python reads secrets-style settings from `.env`; `config.yaml` holds non-secret project settings.

---

## 8. Cloud orchestration (written; first deploy still in progress)

### 8.1 `workflow.yaml`: Cloud Workflows
Runs the pipeline from files already landed in Cloud Storage. Input (optional): `{"batch_id": "...", "dq_gate": false}`.
1. **init**: reads env vars (`PROJECT, REGION, BUCKET, JOB, SERVICE_ACCOUNT`), the optional inputs, and builds the Cloud Run job's full name.
2. **pick_batch**: if no `batch_id` is given, lists `landing/` folders in the bucket and takes the newest (folder names sort by time);
   raises a clear error if nothing is landed.
3. **log_start**: writes a log line.
4. **run_pipeline** (inside `try`/`except`):
   - `bronze`: runs the Cloud Run job with args `src/load_bronze.py --batch <id>`.
   - `silver`: runs the same job with `src/run_silver.py`.
   - `silver_dq_gate`: if enabled, starts a Dataproc Serverless batch running `dataproc/dq_job.py`.
   - `gold`: runs the job with `src/run_gold.py`.
   - `except`: logs `Pipeline FAILED for batch <id>` with the error, then re-raises it. **This is the hook for failure handling.**
5. **done**: returns `status: succeeded` with the batch id.
Each Cloud Run step waits for the job execution to finish; a non-zero exit code fails the step and therefore the workflow.

### 8.2 `scripts/deploy.sh`
Run it with `bash scripts/deploy.sh [run]`; safe to repeat.
1. Reads project/region/bucket/service account/schedule from `config.yaml`.
2. Enables the APIs (BigQuery, Storage, Cloud Run, Cloud Build, Artifact Registry, Dataproc, Workflows, Scheduler).
3. Creates the bucket if needed, and the service account `ecom-pipeline`.
4. Grants roles (BigQuery data editor + job user, storage object admin, Cloud Run developer, Dataproc editor/worker, Workflows invoker,
   service account user, log writer) with a **retry loop**, because a new service account takes seconds to propagate.
5. Grants bucket reader (needed because `get_bucket()` checks the bucket exists) and the Cloud Build role to the default compute account.
6. `gcloud run jobs deploy ecom-pipeline-job --source .`: Cloud Build packages the repo with Google buildpacks (no Dockerfile), using
   `requirements.txt` and `.python-version`. Environment variables `GCP_PROJECT_ID`, `GCS_BUCKET`, `BQ_LOCATION` are set on the job.
   Default command `python src/run_gold.py`; the workflow overrides the args per step. `--max-retries 0`: data errors are not blindly retried.
7. Uploads `dataproc/dq_job.py` to `gs://<bucket>/jobs/`.
8. Deploys the workflow and a daily Cloud Scheduler trigger.
9. With `run`: lands the files and runs the workflow once.

### 8.3 Other cloud files
- `scripts/land_files.sh`: checks all 7 files exist in `data/`, then uploads them to `gs://<bucket>/landing/b_<utc timestamp>_<hex>/`.
- `.gcloudignore`: keeps `.git`, `.venv`, `.env`, `data/`, `dist/`, `outputs/`, `docs/`, root `tests/` and images out of the build.
  Patterns are anchored with `/` so `sql/tests/` (needed at run time) is **not** excluded.
- `.python-version`: `3.13` (the Cloud Run builder offers only 3.13 and 3.14).
- `Procfile`: one line, `web: python src/run_gold.py`. The buildpack refuses to build without a default start command; the job's real command is overridden at deploy and by the workflow, so this only satisfies the build.
- `requirements.txt`: one package per line (`google-cloud-bigquery`, `-storage`, `-pubsub`, `db-dtypes`, `pandas`, `pyarrow`, `pyyaml`, `python-dotenv`).
- `dataproc/dq_job.py`: PySpark job. For each silver table it counts rows, null keys and duplicate keys, appends the result to `gold.dq_report`
  (via the spark-bigquery connector, staging through the bucket), and **raises an error** if any table is empty, has null keys or duplicate keys,
  which fails the batch and therefore the workflow.
- `scripts/build_gold_script.py`: joins all gold SQL and tests into `dist/run_gold.sql` (tests become `ASSERT NOT EXISTS (...)`).
  An alternative way to run gold as a single BigQuery script (e.g. a scheduled query). The workflow no longer uses it.
- `scripts/looker_links.py`: prints a Looker Studio "Linking API" URL that creates a report with one KPI view attached (the API cannot attach
  several data sources to a new report), plus the list of views to add by hand. Looker Studio has no CLI, so the charts are built by hand (see `docs/looker_studio.md`).

---

## 9. One run, start to finish (what actually happens)
1. `land_files.sh` (or `load_bronze.py`) copies the 7 raw files to `landing/<batch>/`.
2. **Bronze:** each file is read back from Cloud Storage and loaded as all-STRING tables with audit columns (tables replaced).
3. **Silver:** seeds load → UDFs → customers → suppliers → products → orders → order items → payments → returns → DQ log. Then 5 silver tests.
   A failing test stops the run with a non-zero exit.
4. **DQ gate (optional):** Dataproc checks keys on the silver tables.
5. **Gold:** views and tables are created in order (core, aggregates, KPIs); then 4 gold tests.
6. The dashboard reads the gold KPI views. Views are always live; the six aggregate tables are as fresh as the last run.

---

## 10. Cookbook: how to change things
| I want to... | Do this |
|---|---|
| Change a threshold or score weight | Edit `params:` in `config/config.yaml`, rerun `python src/run_gold.py` |
| Turn a view into a table (or back) | Edit `materialization.table` in the config, rerun `run_gold.py` (the type swap is automatic) |
| Add a new KPI | Add `sql/gold/NN_name.sql` with `CREATE OR REPLACE VIEW ${gold}.name AS ...`; use a number that runs after its dependencies |
| Add a new label mapping | Add a row to `seeds/ref_value_map.csv`, rerun `run_silver.py` (silver test 05 tells you when one is missing) |
| Add a data-quality check | Add `sql/tests/silver_NN_*.sql` or `gold_NN_*.sql`; make it return rows **only** when something is wrong |
| Reprocess an old batch | `python src/load_bronze.py --batch <batch_id>`, then `run_silver.py`, `run_gold.py` |
| Run only one layer | `python src/run_silver.py` or `python src/run_gold.py` |

---

## 11. Limitations and open items
- **The cloud deploy has not yet completed a successful run.** The first attempts found and fixed several issues (IAM propagation, a corrupted
  `requirements.txt` line, an unsupported Python version). The workflow, Dataproc step and scheduler are untested until the first run passes.
- **Everything is a full refresh.** Bronze is truncated and reloaded, silver is rebuilt, gold aggregates are rebuilt. Incremental loading is designed,
  not built (append bronze, track processed batches, keep the latest record per key, `MERGE` the facts, recompute only affected aggregates;
  rankings and min-max scoring remain full recomputes).
- **Failure handling is minimal.** Tests gate each layer and the workflow logs failures, but there are no retries with backoff, alerts, batch status table or
  protection against a half-built silver. This is the next piece of work.
- **Returned quantity is assumed** (full item) because the source has none.
- **Supplier score weights, margin threshold and the "completed" definition** need business confirmation.
