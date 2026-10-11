"""Land the 7 raw source files in Cloud Storage, then load them into BigQuery `bronze` unchanged.

1. Landing: each file is uploaded as-is to gs://<GCS_BUCKET>/landing/<batch_id>/<file>.
   Every run is a new, immutable batch folder, so past loads can always be replayed.
2. Bronze: each landed file is read back from Cloud Storage and loaded with every
   source column as STRING (no row is lost to a type error; typing happens in silver),
   plus audit columns for lineage back to the exact file and line.

Usage:  python src/load_bronze.py                      # upload data/ as a new batch, then load it
        python src/load_bronze.py --batch <batch_id>   # reload an existing landed batch
"""
import argparse
import csv
import io
import json
import uuid
from datetime import datetime, timezone

from bq import PROJECT, ROOT, ensure_datasets, get_bucket, get_client  # first: silences google lib warnings
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


def land_files(bucket, batch_id: str) -> None:
    for file_name in SOURCES.values():
        blob = bucket.blob(f"landing/{batch_id}/{file_name}")
        blob.upload_from_filename(str(DATA_DIR / file_name))
        print(f"  landed  gs://{bucket.name}/{blob.name}")


def parse_source(file_name: str, text: str):
    """Return (columns, rows) with every value as a string or None, plus the source line number."""
    if file_name.endswith(".json"):
        records = json.loads(text)
        columns = list(records[0].keys())
        rows = [
            ({c: (None if r.get(c) is None else str(r[c])) for c in columns}, i + 1)
            for i, r in enumerate(records)
        ]
    else:
        reader = csv.DictReader(io.StringIO(text, newline=""))
        columns = reader.fieldnames
        rows = [(r, reader.line_num) for r in reader]
    return columns, rows


def load_table(client, bucket, table: str, file_name: str, batch_id: str, ingested_at: str) -> int:
    uri_path = f"landing/{batch_id}/{file_name}"
    text = bucket.blob(uri_path).download_as_bytes().decode("utf-8-sig")
    columns, rows = parse_source(file_name, text)
    schema = [bigquery.SchemaField(c, "STRING") for c in columns] + AUDIT_FIELDS
    source_uri = f"gs://{bucket.name}/{uri_path}"
    payload = [
        {**values, "_source_file": source_uri, "_row_num": line, "_ingested_at": ingested_at, "_batch_id": batch_id}
        for values, line in rows
    ]
    job_config = bigquery.LoadJobConfig(schema=schema, write_disposition="WRITE_TRUNCATE")
    client.load_table_from_json(payload, f"{PROJECT}.bronze.{table}", job_config=job_config).result()
    return len(payload)


def main(batch_id: str | None = None):
    client = get_client()
    bucket = get_bucket()
    ensure_datasets(client)
    if batch_id is None:
        batch_id = "b_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
        print(f"Landing raw files (batch {batch_id})")
        land_files(bucket, batch_id)
    ingested_at = datetime.now(timezone.utc).isoformat()
    print(f"Loading bronze from gs://{bucket.name}/landing/{batch_id}/")
    for table, file_name in SOURCES.items():
        n = load_table(client, bucket, table, file_name, batch_id, ingested_at)
        print(f"  bronze.{table:<12} {n:>5} rows  <- {file_name}")
    return batch_id


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", help="reload an existing landed batch instead of uploading data/")
    main(parser.parse_args().batch)
