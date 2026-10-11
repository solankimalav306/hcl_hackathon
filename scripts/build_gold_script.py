"""Concatenate sql/gold/*.sql plus the gold tests into one BigQuery script: dist/run_gold.sql (placeholders filled).

Used by the Cloud Workflow (workflow.yaml), which downloads it from GCS and runs it as a single BigQuery job.
Tests (sql/tests/gold_*.sql) become ASSERT NOT EXISTS (...), so the run fails if a check returns rows.
Usage: python scripts/build_gold_script.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))
from gold_sql import ROOT, SQL_DIR, TEST_DIR, load_config, render  # noqa: E402

cfg = load_config()
parts = ["CREATE SCHEMA IF NOT EXISTS gold;"]
for f in sorted(SQL_DIR.glob("*.sql")):
    parts.append(f"-- gold/{f.name}\n{f.read_text(encoding='utf-8').strip()}")
for f in sorted(TEST_DIR.glob("gold_*.sql")):
    body = f.read_text(encoding="utf-8").strip().rstrip(";")
    parts.append(f"-- tests/{f.name}\nASSERT NOT EXISTS (\n{body}\n) AS 'Test failed: {f.name}';")

out = ROOT / "dist" / "run_gold.sql"
out.parent.mkdir(exist_ok=True)
out.write_text(render("\n\n".join(parts) + "\n", cfg), encoding="utf-8")
print(f"Wrote {out} ({len(parts)} statements)")
