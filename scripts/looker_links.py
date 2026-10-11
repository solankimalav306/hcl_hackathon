"""Print Looker Studio (formerly Data Studio) "Linking API" URLs for the gold KPI views.

How the Linking API works (https://developers.google.com/looker-studio/integrate/linking-api):
  * A link WITHOUT a template report creates a default report with exactly ONE embedded data source,
    and its ds.* parameters take NO alias. (Aliases such as ds0 only exist inside an existing template report.)
  * So you cannot attach several data sources to a new report from a URL. Open one link, then add the remaining
    views from inside Looker Studio (see docs/looker_studio.md).
Looker Studio has no CLI. Usage: python scripts/looker_links.py [view_name]
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
BASE = "https://datastudio.google.com/reporting/create"  # Looker Studio (formerly Data Studio): the address the Linking API docs use


def link(project: str, view: str, report_name: str = "E-commerce KPI dashboard") -> str:
    return (f"{BASE}?c.mode=edit&r.reportName={quote(report_name)}"
            f"&ds.connector=bigQuery&ds.type=TABLE&ds.projectId={project}"
            f"&ds.datasetId=gold&ds.tableId={view}")


def main() -> None:
    project = load_config()["infra"]["project"]
    if len(sys.argv) > 1:
        print(link(project, sys.argv[1]))
        return
    print("START HERE: this creates the report with the Q1 view attached; then add the other views from inside Looker Studio.\n")
    print(link(project, VIEWS[0]))
    print("\nTo add the other views: Resource > Manage added data sources > Add a data source > BigQuery >")
    print(f"{project} > gold > pick the view. Views to add:\n")
    for v in VIEWS[1:]:
        print(f"  gold.{v}")
    print("\nOr a standalone starter report per view:\n")
    for v in VIEWS:
        print(f"  {v}:\n    {link(project, v, v)}")


if __name__ == "__main__":
    main()
