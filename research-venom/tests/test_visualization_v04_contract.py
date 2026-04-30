from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_V4 = REPO_ROOT / "config" / "process_pipeline_v04.json"
CONFIG_V4_TEST = REPO_ROOT / "config" / "process_pipeline_v04_test.json"
CONFIG_V4_LOCAL_REAL = REPO_ROOT / "config" / "process_pipeline_v04_local_real.json"
STYLE_PROFILE_V4 = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "chart_style_profile_v04.json"
CONTROL_PROFILE_V4 = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "chart_control_profile_v04.json"
CHART_SPEC_V4 = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "chart_spec_v04.json"
WORKBOOK_LAYOUT_V4 = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "workbook_layout_v04.json"
MAKEFILE = REPO_ROOT / "Makefile"
WORD_CREATE_CANVAS = REPO_ROOT / "tools" / "word_create_embed_canvas.ps1"
WORD_INSERT_BOOKMARKS = REPO_ROOT / "tools" / "word_insert_bookmarks.ps1"
WORD_VERIFY_EMBEDDINGS = REPO_ROOT / "tools" / "verify_word_embeddings.ps1"


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_v4_config_points_to_versioned_artifacts() -> None:
    config = _load_json(CONFIG_V4)
    assert config["project"]["config_version"] == "v04"
    assert config["project"]["migration_phase"] == "G4_legacy_adoption"
    assert config["paths"]["excel_workbook"].endswith("workbook_v04.xlsx")
    assert config["paths"]["excel_verify_json"].endswith("excel_verify_v04.json")
    assert config["paths"]["word_input_docx"].endswith("embed_canvas_v04.docx")
    assert config["paths"]["word_output_docx"].endswith("embed_canvas_bookmarked_v04.docx")


def test_v4_configs_export_inputs_recursively() -> None:
    for path in (CONFIG_V4, CONFIG_V4_TEST, CONFIG_V4_LOCAL_REAL):
        config = _load_json(path)
        full_profile = config["profiles"]["export"]["full"]
        assert "artifacts/inputs/**" in full_profile
        assert "artifacts/inputs/*" not in full_profile


def test_v4_sample_key_paths_are_exact_public_contract_paths() -> None:
    expected_sonar = "artifacts/inputs/sonar_market/project_keys_selected_v01.txt"
    expected_github = "artifacts/inputs/github_market/repo_keys_selected_v01.txt"
    for path in (CONFIG_V4, CONFIG_V4_TEST):
        config = _load_json(path)
        sonar_paths = config["process"]["steps"]["sonar_market"]["paths"]
        github_paths = config["process"]["steps"]["github_market"]["paths"]
        assert sonar_paths["project_key_file"] == expected_sonar
        assert github_paths["repo_file"] == expected_github
        assert github_paths["selection_keys"] == expected_github


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


def test_makefile_defaults_use_active_v4_contract() -> None:
    text = _read(MAKEFILE)
    assert "fetch-sonar: require-api-confirm\n\t$(PYTHON) tools/sonar_market_benchmark.py --config $(CONFIG_V4)" in text
    assert "fetch-github-market: require-api-confirm\n\t$(PYTHON) tools/github_market_benchmark.py --config $(CONFIG_V4)" in text
    assert "process-sources:\n\t$(PYTHON) tools/prepare_sources.py --config $(CONFIG_V4)" in text
    assert "process-summary:\n\t$(PYTHON) tools/build_summary_tables.py --config $(CONFIG_V4)" in text
    assert "product-excel-only:\n\tpowershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_pipeline.ps1 -ConfigPath $(CONFIG_V4)" in text
    assert "product-all:\n\tpowershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_pipeline.ps1 -ConfigPath $(CONFIG_V4)" in text
    assert "process-v3:" in text
    assert "product-all-v3:" in text


def test_word_helpers_default_to_active_v4_artifacts() -> None:
    for path in (WORD_CREATE_CANVAS, WORD_INSERT_BOOKMARKS, WORD_VERIFY_EMBEDDINGS):
        text = _read(path)
        assert "word_embed_map_v04.csv" in text
        assert "_v02" not in text


def test_word_bookmark_insert_filters_inactive_map_rows() -> None:
    text = _read(WORD_INSERT_BOOKMARKS)
    assert 'status -ne "disabled"' in text
    assert 'status -ne "skip"' in text
    assert 'status -ne "inactive"' in text
