"""Shared BigQuery helpers: client from .env and a SQL-file runner."""
import os
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", category=FutureWarning)  # Python 3.10 end-of-life notice from google libs

from dotenv import load_dotenv  # noqa: E402
from google.cloud import bigquery, storage  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env")

PROJECT = os.environ["GCP_PROJECT_ID"]
LOCATION = os.getenv("BQ_LOCATION", "US")
BUCKET = os.environ["GCS_BUCKET"]
DATASETS = ["bronze", "silver", "gold"]


def get_client() -> bigquery.Client:
    return bigquery.Client(project=PROJECT, location=LOCATION)


def get_bucket() -> storage.Bucket:
    """Landing-zone bucket; created in the BigQuery location on first use."""
    client = storage.Client(project=PROJECT)
    bucket = client.bucket(BUCKET)
    if not bucket.exists():
        bucket = client.create_bucket(bucket, location=LOCATION)
    return bucket


def ensure_datasets(client: bigquery.Client) -> None:
    for name in DATASETS:
        ds = bigquery.Dataset(f"{PROJECT}.{name}")
        ds.location = LOCATION
        client.create_dataset(ds, exists_ok=True)


def run_sql_file(client: bigquery.Client, path: Path):
    """Run a .sql file (may contain several statements) and return the result rows of the last one."""
    job = client.query(path.read_text(encoding="utf-8"))
    return list(job.result())
