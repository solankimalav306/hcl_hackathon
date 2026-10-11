"""Helpers for the gold layer: read config/config.yaml and prepare sql/gold/*.sql.

* Placeholders: ${silver} / ${gold} (dataset names) plus everything under `params:` in config.yaml.
* Materialization: the SQL files are written as `CREATE OR REPLACE VIEW ${gold}.<name>`. The
  `materialization:` section of config.yaml decides which objects become TABLEs instead (default: view),
  so flipping an object to a table (e.g. when data grows) is a config change, not a SQL rewrite.
"""
import re
from pathlib import Path
from string import Template

import yaml

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql" / "gold"
TEST_DIR = ROOT / "sql" / "tests"

_CREATE = re.compile(r"CREATE OR REPLACE (?:VIEW|TABLE) \$\{gold\}\.(\w+)")


def load_config() -> dict:
    return yaml.safe_load((ROOT / "config" / "config.yaml").read_text(encoding="utf-8"))


def _kind(name: str, cfg: dict) -> str:
    mat = cfg.get("materialization", {})
    if name in mat.get("table", []):
        return "TABLE"
    return mat.get("default", "view").upper()


def objects(raw_sql: str, cfg: dict | None = None) -> list[tuple[str, str]]:
    """(name, 'VIEW' | 'TABLE') for every gold object a SQL file creates."""
    cfg = cfg or load_config()
    return [(n, _kind(n, cfg)) for n in _CREATE.findall(raw_sql)]


def render(raw_sql: str, cfg: dict | None = None) -> str:
    cfg = cfg or load_config()
    sql = _CREATE.sub(lambda m: f"CREATE OR REPLACE {_kind(m.group(1), cfg)} ${{gold}}.{m.group(1)}", raw_sql)
    params = {"silver": "silver", "gold": "gold", **cfg["params"]}
    return Template(sql).substitute(params)  # substitute (not safe_): a missing placeholder should fail loudly
