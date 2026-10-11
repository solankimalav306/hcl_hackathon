import os

from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv()

client = bigquery.Client(project=os.environ["GCP_PROJECT_ID"])  # credentials via ADC
rows = client.query("SELECT 1 AS ok").result()
print([dict(r) for r in rows])
