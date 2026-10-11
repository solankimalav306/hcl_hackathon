#!/usr/bin/env bash
# One-shot CLI deploy of the orchestrated pipeline. No Docker needed: Cloud Run builds the container from source.
#   1. APIs, bucket, service account and roles
#   2. Cloud Run Job "ecom-pipeline-job"  (runs src/*.py; the workflow picks which script)
#   3. Dataproc DQ script uploaded to GCS
#   4. Cloud Workflows "ecom-pipeline" (workflow.yaml) + daily Cloud Scheduler trigger
# Usage: bash scripts/deploy.sh          (reads config/config.yaml and .env-style values from it)
#        bash scripts/deploy.sh run      (also lands data/ as a batch and runs the workflow once)
set -euo pipefail
cd "$(dirname "$0")/.."

cfg() { python -c "import yaml; print(yaml.safe_load(open('config/config.yaml'))['infra']['$1'])"; }
PROJECT=$(cfg project); REGION=$(cfg region); BQ_LOCATION=$(cfg bq_location); BUCKET=$(cfg bucket)
SA_NAME=$(cfg service_account); SCHEDULE=$(cfg schedule); TZ_NAME=$(cfg time_zone)
SA="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
JOB=ecom-pipeline-job; WORKFLOW=ecom-pipeline

gcloud config set project "$PROJECT"
gcloud services enable bigquery.googleapis.com storage.googleapis.com run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com dataproc.googleapis.com workflows.googleapis.com workflowexecutions.googleapis.com \
  cloudscheduler.googleapis.com

gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 || gcloud storage buckets create "gs://$BUCKET" --location="$BQ_LOCATION"

gcloud iam service-accounts describe "$SA" >/dev/null 2>&1 || gcloud iam service-accounts create "$SA_NAME" --display-name="Ecom pipeline"
# A just-created service account takes a few seconds to propagate, so retry each binding.
bind_role() {
  for attempt in 1 2 3 4 5 6; do
    gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$SA" --role="$1" --condition=None >/dev/null 2>&1 && return 0
    echo "  waiting for service account to propagate (attempt $attempt)..."; sleep 10
  done
  echo "could not grant $1 to $SA"; return 1
}
for role in roles/bigquery.dataEditor roles/bigquery.jobUser roles/storage.objectAdmin roles/run.developer \
            roles/dataproc.editor roles/dataproc.worker roles/workflows.invoker roles/iam.serviceAccountUser \
            roles/logging.logWriter; do
  bind_role "$role"
done
# load_bronze.py calls bucket.exists(), which needs buckets.get (not part of objectAdmin)
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" --member="serviceAccount:$SA" \
  --role=roles/storage.legacyBucketReader >/dev/null
# Cloud Build (used by --source) runs as the default compute service account in newer projects
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role=roles/cloudbuild.builds.builder --condition=None >/dev/null || true

# 2. Cloud Run Job built from this repo (see .gcloudignore for what is left out)
gcloud run jobs deploy "$JOB" --source . --region "$REGION" --service-account "$SA" \
  --set-env-vars "GCP_PROJECT_ID=$PROJECT,GCS_BUCKET=$BUCKET,BQ_LOCATION=$BQ_LOCATION" \
  --max-retries 0 --task-timeout 1800s

# 3. Dataproc DQ gate script
gcloud storage cp dataproc/dq_job.py "gs://$BUCKET/jobs/dq_job.py"

# 4. Workflow + schedule
gcloud workflows deploy "$WORKFLOW" --location="$REGION" --source=workflow.yaml --service-account="$SA" \
  --set-env-vars="PROJECT=$PROJECT,REGION=$REGION,BUCKET=$BUCKET,JOB=$JOB,SERVICE_ACCOUNT=$SA_NAME"

URI="https://workflowexecutions.googleapis.com/v1/projects/${PROJECT}/locations/${REGION}/workflows/${WORKFLOW}/executions"
gcloud scheduler jobs create http "${WORKFLOW}-daily" --location="$REGION" --schedule="$SCHEDULE" --time-zone="$TZ_NAME" \
  --uri="$URI" --http-method=POST --oauth-service-account-email="$SA" 2>/dev/null \
|| gcloud scheduler jobs update http "${WORKFLOW}-daily" --location="$REGION" --schedule="$SCHEDULE" --time-zone="$TZ_NAME" \
  --uri="$URI" --http-method=POST --oauth-service-account-email="$SA"

if [ "${1:-}" = "run" ]; then
  bash scripts/land_files.sh
  gcloud workflows run "$WORKFLOW" --location="$REGION"
fi
echo "Deployed. Land a batch:  bash scripts/land_files.sh"
echo "Run the pipeline:        gcloud workflows run $WORKFLOW --location=$REGION"
echo "Skip the Dataproc gate:  gcloud workflows run $WORKFLOW --location=$REGION --data='{\"dq_gate\": false}'"
