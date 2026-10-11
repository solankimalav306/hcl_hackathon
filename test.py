from google.cloud import bigquery

client = bigquery.Client()          # credentials via ADC, project from your gcloud config
rows = client.query("SELECT 1 AS ok").result()
print([dict(r) for r in rows])