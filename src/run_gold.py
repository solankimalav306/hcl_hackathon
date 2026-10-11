"""Build the gold layer in BigQuery from silver: core facts/dims, aggregates and KPI views,
then run the gold data-quality tests.

Continues run_silver.py. Usage:  python src/run_gold.py
Which gold objects are views and which are tables is set in config/config.yaml (`materialization:`).
(A test file in sql/tests/gold_*.sql passes when it returns zero rows.)
"""
import sys

from bq import PROJECT, ensure_datasets, get_client  # first: silences google lib warnings
from google.api_core.exceptions import NotFound
from gold_sql import SQL_DIR, TEST_DIR, load_config, objects, render


def reconcile_types(client, raw_sql: str, cfg: dict) -> None:
    """If an object exists as the other type (view <-> table), drop it so CREATE OR REPLACE can succeed."""
    for name, kind in objects(raw_sql, cfg):
        try:
            existing = client.get_table(f"{PROJECT}.gold.{name}")
        except NotFound:
            continue
        if existing.table_type != kind:
            client.delete_table(existing)
            print(f"  gold.{name}: replaced {existing.table_type} with {kind}")


def run_rendered(client, raw_sql: str, cfg: dict):
    return list(client.query(render(raw_sql, cfg)).result())


def build(client, cfg: dict) -> None:
    for path in sorted(SQL_DIR.glob("*.sql")):
        raw = path.read_text(encoding="utf-8")
        reconcile_types(client, raw, cfg)
        run_rendered(client, raw, cfg)
        kinds = ", ".join(sorted({k for _, k in objects(raw, cfg)}))
        print(f"  ran {path.name:<36} [{kinds}]")


def run_tests(client, cfg: dict) -> bool:
    ok = True
    for path in sorted(TEST_DIR.glob("gold_*.sql")):
        failures = run_rendered(client, path.read_text(encoding="utf-8"), cfg)
        status = "PASS" if not failures else f"FAIL ({len(failures)} rows)"
        print(f"  {path.stem:<35} {status}")
        for row in failures[:10]:
            print("      ", dict(row))
        ok = ok and not failures
    return ok


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    cfg = load_config()
    client = get_client()
    ensure_datasets(client)
    print("Building gold")
    build(client, cfg)
    print("\nGold data-quality tests")
    if not run_tests(client, cfg):
        sys.exit("Gold data-quality tests failed")


if __name__ == "__main__":
    main()
