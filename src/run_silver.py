"""Build the silver layer in BigQuery: load mapping seeds, run sql/silver in order,
run the data-quality tests, and export the DQ summaries to outputs/.

Usage:  python src/load_bronze.py   (once, or whenever the raw files change)
        python src/run_silver.py
"""
import csv
import sys

from bq import PROJECT, ROOT, ensure_datasets, get_client, run_sql_file  # first: silences google lib warnings
from google.cloud import bigquery

SQL_DIR = ROOT / "sql" / "silver"
TEST_DIR = ROOT / "sql" / "tests"
OUT_DIR = ROOT / "outputs"


def load_seeds(client):
    with (ROOT / "seeds" / "ref_value_map.csv").open(newline="", encoding="utf-8") as fh:
        rows = [{**r, "raw_value": r["raw_value"].strip().lower()} for r in csv.DictReader(fh)]
    schema = [bigquery.SchemaField(c, "STRING") for c in ("domain", "raw_value", "standard_value")]
    job_config = bigquery.LoadJobConfig(schema=schema, write_disposition="WRITE_TRUNCATE")
    client.load_table_from_json(rows, f"{PROJECT}.silver.ref_value_map", job_config=job_config).result()
    print(f"  seeds -> silver.ref_value_map ({len(rows)} mappings)")


def run_tests(client) -> bool:
    ok = True
    for path in sorted(TEST_DIR.glob("silver_*.sql")):
        failures = run_sql_file(client, path)
        status = "PASS" if not failures else f"FAIL ({len(failures)} rows)"
        print(f"  {path.stem:<35} {status}")
        for row in failures[:10]:
            print("      ", dict(row))
        ok = ok and not failures
    return ok


def export(client, table: str):
    rows = list(client.query(f"SELECT * FROM silver.{table}").result())
    OUT_DIR.mkdir(exist_ok=True)
    path = OUT_DIR / f"{table}.csv"
    with path.open("w", newline="", encoding="utf-8") as fh:
        if rows:
            writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(dict(r) for r in rows)
    return rows


def main():
    sys.stdout.reconfigure(encoding="utf-8")  # rule text contains ₹; Windows console defaults to cp1252
    client = get_client()
    ensure_datasets(client)
    print("Building silver")
    load_seeds(client)
    for path in sorted(SQL_DIR.glob("*.sql")):
        run_sql_file(client, path)
        print(f"  ran {path.name}")

    print("\nData-quality tests")
    passed = run_tests(client)

    print("\nBronze -> silver reconciliation")
    print(f"  {'table':<12} {'bronze':>6} {'dups':>5} {'merged':>6} {'quarant':>7} {'silver':>6}  ok")
    for r in export(client, "dq_table_summary"):
        print(f"  {r['table_name']:<12} {r['bronze_rows']:>6} {r['duplicates_removed']:>5} "
              f"{r['merged_into_master']:>6} {r['quarantined']:>7} {r['silver_rows']:>6}  {r['balanced']}")

    print("\nRules fired")
    for r in export(client, "dq_rule_summary"):
        print(f"  {r['rule_id']:<7} {r['records_affected']:>4}  {r['action']:<26} {r['issue']}")
    export(client, "dq_quarantine")
    print(f"\nExported DQ summaries to {OUT_DIR}")

    if not passed:
        sys.exit("Data-quality tests failed")


if __name__ == "__main__":
    main()
