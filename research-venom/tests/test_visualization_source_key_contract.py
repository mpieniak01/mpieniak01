from __future__ import annotations

import csv
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CHART_SPEC = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "chart_spec_v04.json"
SUMMARY_TABLES = (
    REPO_ROOT / "artifacts" / "processing" / "visualization" / "summary_tables_v04.csv"
)


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _load_summary_ids(path: Path) -> set[str]:
    if not path.exists():
        return set()
    with path.open("r", encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh))
    return {str(r.get("chart_id", "")).strip() for r in rows if r.get("chart_id")}


def test_visualization_charts_expose_source_domain_and_project_key_contract() -> None:
    chart_spec = _load_json(CHART_SPEC)
    summary_ids = _load_summary_ids(SUMMARY_TABLES)

    for chart in chart_spec["charts"]:
        chart_id = chart["chart_id"]
        source_domain = chart.get("source_domain")
        input_project_count = chart.get("input_project_count")
        rendered_project_count = chart.get("rendered_project_count")
        table_description = chart.get("table_description", "")

        assert source_domain in {"GitHub API", "SonarCloud API", "PR flow"}, chart_id
        assert isinstance(input_project_count, int) and input_project_count > 0, chart_id
        assert isinstance(rendered_project_count, int) and rendered_project_count > 0, chart_id
        assert table_description.startswith(f"Zrodlo: {source_domain}"), chart_id
        assert str(input_project_count) in table_description, chart_id
        assert str(rendered_project_count) in table_description, chart_id

        rendered_keys = chart.get("rendered_project_keys")
        if rendered_keys is not None:
            assert isinstance(rendered_keys, list), chart_id
            assert len(rendered_keys) == rendered_project_count, chart_id
            assert all(isinstance(key, str) and key.strip() for key in rendered_keys), chart_id
            assert all("inne" not in key.lower() for key in rendered_keys), chart_id

        if chart.get("x_series") == "project_key":
            assert chart.get("project_key_label_mode") == "full", chart_id
            assert chart.get("project_key_labels_truncated") is False, chart_id
            assert chart.get("focus_project_key") is None, chart_id
        else:
            if chart.get("focus_project_key") is not None:
                assert chart["focus_project_key"] == "mpieniak01/Venom", chart_id

        if summary_ids:
            assert chart_id in summary_ids, chart_id
