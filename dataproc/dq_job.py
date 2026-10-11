"""Dataproc Serverless PySpark job: data-quality gate on the silver layer (BigQuery silver).

Reads each silver table through the spark-bigquery connector, checks row count and duplicate keys,
appends the results to gold.dq_report, and FAILS the job (so the workflow stops) if a check is violated.
Args: --project <id> --bucket <temp bucket for BigQuery writes>
"""
import argparse
from datetime import datetime, timezone

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

# table -> business key. Mirrors the silver contract in kpi_layer_schemas.md.
SILVER_KEYS = {
    "silver.orders": "order_id",
    "silver.order_items": "order_item_id",
    "silver.products": "product_id",
    "silver.customers": "customer_id",
    "silver.suppliers": "supplier_id",
    "silver.payments": "payment_id",
    "silver.returns": "return_id",
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--bucket", required=True)
    args = ap.parse_args()

    spark = SparkSession.builder.appName("silver-dq").getOrCreate()
    run_ts = datetime.now(timezone.utc).isoformat()
    rows, failed = [], []

    for table, key in SILVER_KEYS.items():
        df = spark.read.format("bigquery").option("table", f"{args.project}.{table}").load()
        total = df.count()
        null_keys = df.filter(F.col(key).isNull()).count()
        dup_keys = df.groupBy(key).count().filter("count > 1").count()
        ok = total > 0 and null_keys == 0 and dup_keys == 0
        rows.append((run_ts, table, key, total, null_keys, dup_keys, ok))
        print(f"{table}: rows={total} null_keys={null_keys} dup_keys={dup_keys} ok={ok}")
        if not ok:
            failed.append(table)

    report = spark.createDataFrame(
        rows, "run_ts string, table_name string, key_col string, row_count long, null_keys long, dup_keys long, passed boolean"
    )
    (report.write.format("bigquery")
        .option("table", f"{args.project}.gold.dq_report")
        .option("temporaryGcsBucket", args.bucket)
        .mode("append").save())

    if failed:
        raise SystemExit(f"Silver DQ failed for: {', '.join(failed)}")


if __name__ == "__main__":
    main()
