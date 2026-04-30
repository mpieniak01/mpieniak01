from __future__ import annotations

import csv
import json
from collections import Counter, defaultdict
from pathlib import Path

import pytest

pytestmark = pytest.mark.data_quality

REPO_ROOT = Path(__file__).resolve().parents[2]
GITHUB_205C = REPO_ROOT / "artifacts" / "products_light" / "github_market" / "timeseries_agg_2026_v01.csv"
SOURCES_PACK = REPO_ROOT / "artifacts" / "processing" / "visualization" / "sources_pack_v01.json"
EXCEL_VERIFY = REPO_ROOT / "artifacts" / "products_light" / "visualization" / "excel_verify_v04.json"


def _require_file(path: Path) -> None:
    if not path.exists():
        pytest.skip(f"local artifact not found: {path}")


def test_local_github_205c_contains_complete_venom_series_without_truncation() -> None:
    _require_file(GITHUB_205C)
    rows = list(csv.DictReader(GITHUB_205C.open(newline="", encoding="utf-8")))
    assert rows

    by_repo: dict[str, list[dict[str, str]]] = defaultdict(list)
    keys = Counter()
    for row in rows:
        by_repo[row["project_key"]].append(row)
        keys[(row["project_key"], row["date"])] += 1

    assert "mpieniak01/Venom" in by_repo
    assert all(count == 1 for count in keys.values())
    assert {len(repo_rows) for repo_rows in by_repo.values()} == {90}

    venom = by_repo["mpieniak01/Venom"]
    assert {row["truncated"].lower() for row in venom} == {"false"}
    for field in ["commits", "authors", "additions", "deletions", "churn"]:
        assert all(int(row[field]) >= 0 for row in venom)


def test_local_sources_pack_uses_205c_for_w33_and_has_no_local_git_table() -> None:
    _require_file(SOURCES_PACK)
    pack = json.loads(SOURCES_PACK.read_text(encoding="utf-8"))

    assert pack["validation"]["source_keys"]["w33_code_flow_source"] == "src_205C_timeseries"
    assert "src_local_git_venom_timeseries" not in pack["tables"]

    w33 = pack["tables"]["tpl_W33_code_flow"]
    assert len(w33) == 90
    assert sum(int(row["additions"] or 0) for row in w33) > 0
    assert sum(int(row["deletions_negative"] or 0) for row in w33) < 0

    repo_count_205c = len({row["project_key"] for row in pack["tables"]["src_205C_timeseries"]})
    assert len(pack["tables"]["tpl_W31_commits"]) == repo_count_205c
    assert len(pack["tables"]["tpl_W32_additions"]) == repo_count_205c


def test_local_excel_verify_has_no_failed_charts() -> None:
    _require_file(EXCEL_VERIFY)
    verify = json.loads(EXCEL_VERIFY.read_text(encoding="utf-8-sig"))
    totals = verify["totals"]

    assert totals["charts_spec"] == 21
    assert totals["missing_sheets"] == 0
    assert totals["charts_failed"] == 0
