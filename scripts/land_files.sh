#!/usr/bin/env bash
# Land the 7 raw files from data/ in Cloud Storage as a new, immutable batch folder.
# The pipeline (workflow) then picks up the newest batch. Usage: bash scripts/land_files.sh
set -euo pipefail
cd "$(dirname "$0")/.."

BUCKET=$(python -c "import yaml; print(yaml.safe_load(open('config/config.yaml'))['infra']['bucket'])")
BATCH="b_$(date -u +%Y%m%d_%H%M%S)_$(head -c3 /dev/urandom | od -An -tx1 | tr -d ' \n')"

for f in customers.csv products.csv orders.csv order_items.csv payments.csv returns.csv suppliers_json.json; do
  [ -f "data/$f" ] || { echo "missing data/$f"; exit 1; }
done

gcloud storage cp data/customers.csv data/products.csv data/orders.csv data/order_items.csv \
  data/payments.csv data/returns.csv data/suppliers_json.json "gs://$BUCKET/landing/$BATCH/"
echo "Landed batch: $BATCH"
