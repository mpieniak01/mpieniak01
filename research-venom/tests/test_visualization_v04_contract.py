from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_V4 = REPO_ROOT / "config" / "process_pipeline_v04.json"
STYLE_PROFILE_V4 = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "chart_style_profile_v04.json"
CONTROL_PROFILE_V4 = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "chart_control_profile_v04.json"
CHART_SPEC_V4 = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "chart_spec_v04.json"
WORKBOOK_LAYOUT_V4 = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "workbook_layout_v04.json"


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_v4_config_points_to_versioned_artifacts() -> None:
    config = _load_json(CONFIG_V4)
    assert config["project"]["config_version"] == "v04"
    assert config["project"]["migration_phase"] == "G4_legacy_adoption"
    assert config["paths"]["excel_workbook"].endswith("workbook_v04.xlsx")
    assert config["paths"]["excel_verify_json"].endswith("excel_verify_v04.json")
    assert config["paths"]["word_input_docx"].endswith("embed_canvas_v04.docx")
    assert config["paths"]["word_output_docx"].endswith("embed_canvas_bookmarked_v04.docx")


def test_v4_style_profile_contains_legacy_adopted_extensions() -> None:
    style = _load_json(STYLE_PROFILE_V4)
    assert style["version"] == "v04"
    assert "worksheet_style" in style
    assert "source_type_palette" in style
    assert "bar_style" in style
    assert "highlight" in style
    assert style["highlight"]["project_key"] == "mpieniak01/Venom"
    assert style["bar_style"]["gap_width"] == 45


def test_v4_chart_spec_uses_versioned_workbook_and_stable_core_charts() -> None:
    spec = _load_json(CHART_SPEC_V4)
    assert spec["version"] == "v04"
    assert spec["workbook"].endswith("workbook_v04.xlsx")
    assert len(spec["charts"]) >= 21
    chart_ids = {chart["chart_id"] for chart in spec["charts"]}
    assert "C_W37_DEBT_03" in chart_ids
    assert "C_WP6_LEAD_TIME_DAILY_03" in chart_ids
    synthetic_chart_ids = {
        chart["chart_id"]
        for chart in spec["charts"]
        if chart.get("chart_mode") == "synthetic_combo"
    }
    assert {
        "C_W37_DEBT_03",
        "C_W35_ISSUES_03",
        "C_W35_COVERAGE_03",
        "C_WP5_PR_DAILY_03",
        "C_WP6_LEAD_TIME_DAILY_03",
    }.issubset(synthetic_chart_ids)
    for chart in spec["charts"]:
        if chart["chart_id"] in synthetic_chart_ids:
            assert chart.get("analysis_caption")


def test_v4_control_profile_exposes_synthetic_combo_mode() -> None:
    control = _load_json(CONTROL_PROFILE_V4)
    assert control["version"] == "v04"
    assert "synthetic_combo" in control["chart_modes"]
    assert "highlight" in control["series_roles"]


def test_v4_workbook_layout_is_versioned() -> None:
    layout = _load_json(WORKBOOK_LAYOUT_V4)
    assert layout["version"] == "v04"
    assert "legacy-inspired styling" in layout["notes"]
