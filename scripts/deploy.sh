#!/usr/bin/env bash
# One-shot CLI deploy: bucket, service account, IAM, upload job + SQL, workflow, daily schedule.
# Usage: bash scripts/deploy.sh            (reads config/config.yaml)
#        bash scripts/deploy.sh run        (also triggers one execution and waits)
set -euo pipefail
cd "$(dirname "$0")/.."

cfg() { python -c "import yaml,sys; c=yaml.safe_load(open('config/config.yaml')); print(c['infra']['$1'])"; }
PROJECT=$(cfg project); REGION=$(cfg region); BQ_LOCATION=$(cfg bq_location); BUCKET=$(cfg bucket)
SA_NAME=$(cfg service_account); SCHEDULE=$(cfg schedule); TZ_NAME=$(cfg time_zone)
SA="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

gcloud config set project "$PROJECT"
gcloud services enable bigquery.googleapis.com dataproc.googleapis.com workflows.googleapis.com \
  workflowexecutions.googleapis.com cloudscheduler.googleapis.com storage.googleapis.com

gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 || gcloud storage buckets create "gs://$BUCKET" --location="$REGION"

gcloud iam service-accounts describe "$SA" >/dev/null 2>&1 || gcloud iam service-accounts create "$SA_NAME" --display-name="Ecom pipeline"
for role in roles/bigquery.dataEditor roles/bigquery.jobUser roles/dataproc.editor roles/dataproc.worker \
            roles/storage.objectAdmin roles/workflows.invoker roles/iam.serviceAccountUser; do
  gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$SA" --role="$role" --condition=None >/dev/null
done

# Build the gold SQL (config applied) and upload everything the workflow needs
python scripts/build_gold_script.py
gcloud storage cp dist/run_gold.sql "gs://$BUCKET/sql/run_gold.sql"
gcloud storage cp dataproc/dq_job.py "gs://$BUCKET/jobs/dq_job.py"
gcloud storage cp config/config.yaml "gs://$BUCKET/config/config.yaml"

gcloud workflows deploy ecom-pipeline --location="$REGION" --source=workflow.yaml --service-account="$SA" \
  --set-env-vars="PROJECT=$PROJECT,REGION=$REGION,BUCKET=$BUCKET,BQ_LOCATION=$BQ_LOCATION,SERVICE_ACCOUNT=$SA_NAME"

URI="https://workflowexecutions.googleapis.com/v1/projects/${PROJECT}/locations/${REGION}/workflows/ecom-pipeline/executions"
gcloud scheduler jobs create http ecom-pipeline-daily --location="$REGION" --schedule="$SCHEDULE" --time-zone="$TZ_NAME" \
  --uri="$URI" --http-method=POST --oauth-service-account-email="$SA" 2>/dev/null \
|| gcloud scheduler jobs update http ecom-pipeline-daily --location="$REGION" --schedule="$SCHEDULE" --time-zone="$TZ_NAME" \
  --uri="$URI" --http-method=POST --oauth-service-account-email="$SA"

if [ "${1:-}" = "run" ]; then
  gcloud workflows run ecom-pipeline --location="$REGION"
fi
echo "Deployed. Manual run: gcloud workflows run ecom-pipeline --location=$REGION"
