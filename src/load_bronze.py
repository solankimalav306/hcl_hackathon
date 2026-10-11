"""Load the 7 raw source files into the BigQuery `bronze` dataset unchanged.

Every source column is loaded as STRING so no row is lost to a type error;
typing and cleansing happen in silver. Audit columns are added for lineage.
"""
import csv
import json
import uuid
from datetime import datetime, timezone

from bq import PROJECT, ROOT, ensure_datasets, get_client  # first: silences google lib warnings
from google.cloud import bigquery

DATA_DIR = ROOT / "data"

SOURCES = {  # bronze table -> source file
    "customers": "customers.csv",
    "products": "products.csv",
    "orders": "orders.csv",
    "order_items": "order_items.csv",
    "payments": "payments.csv",
    "returns": "returns.csv",
    "suppliers": "suppliers_json.json",
}

AUDIT_FIELDS = [
    bigquery.SchemaField("_source_file", "STRING"),
    bigquery.SchemaField("_row_num", "INT64"),
    bigquery.SchemaField("_ingested_at", "TIMESTAMP"),
    bigquery.SchemaField("_batch_id", "STRING"),
]


def read_source(file_name: str):
    """Return (columns, rows) with every value as a string or None, plus the source line number."""
    path = DATA_DIR / file_name
    if path.suffix == ".json":
        records = json.loads(path.read_text(encoding="utf-8"))
        columns = list(records[0].keys())
        rows = [
            ({c: (None if r.get(c) is None else str(r[c])) for c in columns}, i + 1)
            for i, r in enumerate(records)
        ]
    else:
        with path.open(newline="", encoding="utf-8-sig") as fh:
            reader = csv.DictReader(fh)
            columns = reader.fieldnames
            rows = [(r, reader.line_num) for r in reader]
    return columns, rows


def load_table(client, table: str, file_name: str, batch_id: str, ingested_at: str) -> int:
    columns, rows = read_source(file_name)
    schema = [bigquery.SchemaField(c, "STRING") for c in columns] + AUDIT_FIELDS
    payload = [
        {**values, "_source_file": file_name, "_row_num": line, "_ingested_at": ingested_at, "_batch_id": batch_id}
        for values, line in rows
    ]
    job_config = bigquery.LoadJobConfig(schema=schema, write_disposition="WRITE_TRUNCATE")
    client.load_table_from_json(payload, f"{PROJECT}.bronze.{table}", job_config=job_config).result()
    return len(payload)


def main():
    client = get_client()
    ensure_datasets(client)
    batch_id = "b_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    ingested_at = datetime.now(timezone.utc).isoformat()
    print(f"Loading bronze (batch {batch_id})")
    for table, file_name in SOURCES.items():
        n = load_table(client, table, file_name, batch_id, ingested_at)
        print(f"  bronze.{table:<12} {n:>5} rows  <- {file_name}")


if __name__ == "__main__":
    main()
