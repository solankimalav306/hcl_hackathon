"""Print Looker Studio "Linking API" URLs that create a report with BigQuery gold KPI views already connected.

Looker Studio has no CLI, so these links are the closest thing: open one, click "Edit and share",
and the data sources are attached. Usage: python scripts/looker_links.py
"""
import sys
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))
from gold_sql import load_config  # noqa: E402

VIEWS = [
    "q1_monthly_revenue", "q1_revenue_by_cat_channel", "q2_top_customers", "q3_segments",
    "q4_revenue_growth", "q4_growth_by_category", "q5_product_returns", "q6_supplier_scorecard",
    "q7_repeat_rate_cohort", "q7_repeat_rate_overall", "q8_payment_anomalies", "q8_anomaly_summary",
    "margin_risk",
]
BASE = "https://lookerstudio.google.com/reporting/create"


def ds_params(i: int, project: str, view: str) -> str:
    p = f"ds.ds{i}"
    return (f"{p}.connector=bigQuery&{p}.type=TABLE&{p}.projectId={project}"
            f"&{p}.datasetId=gold&{p}.tableId={view}&{p}.datasourceName={view}")


def main() -> None:
    project = load_config()["infra"]["project"]
    name = quote("E-commerce KPI dashboard")
    print("ONE REPORT WITH ALL KPI DATA SOURCES:\n")
    print(f"{BASE}?r.reportName={name}&" + "&".join(ds_params(i, project, v) for i, v in enumerate(VIEWS)))
    print("\nPER-VIEW LINKS:\n")
    for v in VIEWS:
        print(f"{v}:\n  {BASE}?r.reportName={quote(v)}&{ds_params(0, project, v)}\n")


if __name__ == "__main__":
    main()
