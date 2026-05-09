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
    assert "column_style" in style
    assert "stacked_status_bar_style" in style
    assert "status_series_palette" in style
    assert "highlight" in style
    assert style["highlight"]["project_key"] == "mpieniak01/Venom"
    assert style["bar_style"]["gap_width"] == 45
    assert style["bar_style"]["series_border_visible"] is True
    assert style["bar_style"]["series_border_rgb"] == "000000"
    assert style["column_style"]["series_border_visible"] is False
    assert style["stacked_status_bar_style"]["overlap"] == 100
    assert style["stacked_status_bar_style"]["series_border_visible"] is True


def test_v4_wp1_stacked_bar_uses_status_palette_and_template_like_contract() -> None:
    spec = _load_json(CHART_SPEC_V4)
    wp1 = next(chart for chart in spec["charts"] if chart["chart_id"] == "C_WP1_PR_VOLUME_03")
    assert wp1["chart_type"] == "bar_stacked"
    assert wp1["legend_position"] == "bottom"
    assert wp1["data_labels_mode"] == "none"
    assert wp1["disable_point_highlight"] is True
    assert wp1["x_axis_title"] == "Liczba PR"
    assert wp1["y_axis_title"] == "Projekt"
    assert wp1["series_palette_override"] == ["9DC3E6", "5BB370", "E89B7C"]
    assert wp1["series_plan"][0]["chart_type"] == "bar_stacked"
    assert wp1["series_plan"][0]["axis_group"] == "primary"
    assert wp1["analysis_caption"].startswith("Wolumen PR Venom")


def test_v4_chart_legends_follow_template_bottom_contract() -> None:
    spec = _load_json(CHART_SPEC_V4)
    for chart in spec["charts"]:
        assert chart.get("legend_position") in {"bottom", "none"}, chart["chart_id"]


def test_v4_w33_code_flow_uses_narrow_business_columns() -> None:
    spec = _load_json(CHART_SPEC_V4)
    w33 = next(chart for chart in spec["charts"] if chart["chart_id"] == "C_W33_CODE_FLOW_03")
    assert w33["legend_position"] == "bottom"
    assert w33["column_gap_width"] == 120
    assert w33["column_overlap"] == 0


def test_v4_wp6_uses_period_reference_lines() -> None:
    spec = _load_json(CHART_SPEC_V4)
    style = _load_json(STYLE_PROFILE_V4)
    wp6 = next(chart for chart in spec["charts"] if chart["chart_id"] == "C_WP6_LEAD_TIME_DAILY_03")
    fields = [item["field"] for item in wp6["series_plan"]]
    assert "period_avg_lead_time_hours_ref" in fields
    assert "period_median_lead_time_hours_ref" in fields
    assert fields.index("period_avg_lead_time_hours_ref") > fields.index("pr_daily_median_lead_time_hours")
    assert fields.index("period_median_lead_time_hours_ref") > fields.index("pr_daily_median_lead_time_hours")
    by_field = {item["field"]: item for item in wp6["series_plan"]}
    assert by_field["period_avg_lead_time_hours_ref"]["chart_type"] == "line"
    assert by_field["period_median_lead_time_hours_ref"]["chart_type"] == "line"
    assert by_field["period_avg_lead_time_hours_ref"]["axis_group"] == "primary"
    assert by_field["period_median_lead_time_hours_ref"]["axis_group"] == "primary"
    assert by_field["period_avg_lead_time_hours_ref"]["metric_semantics"] == "period_reference_line"
    assert by_field["period_median_lead_time_hours_ref"]["metric_semantics"] == "period_reference_line"
    assert wp6["series_palette_override"][-2:] == ["F59E0B", "F97316"]
    assert "poziome linie odniesienia Q1" in wp6["table_description"]
    assert "period_avg_lead_time_hours_ref" in style["column_aliases"]
    assert "period_median_lead_time_hours_ref" in style["column_aliases"]


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


def test_v4_synthetic_multi_series_charts_use_distinct_palettes() -> None:
    spec = _load_json(CHART_SPEC_V4)
    by_id = {chart["chart_id"]: chart for chart in spec["charts"]}
    expectations = {
        "C_W35_QUALITY_SYNTHESIS_04": 5,
        "C_W37_DEBT_ISSUES_SYNTHESIS_04": 4,
        "C_W42_PHASE2_REFACTORING_SYNTHESIS_04": 4,
        "C_W43_PHASE2_COVERAGE_DEBT_SYNTHESIS_04": 3,
        "C_WP2_LEAD_TIME_SYNTHESIS_04": 2,
    }
    for chart_id, expected_len in expectations.items():
        palette = by_id[chart_id]["series_palette_override"]
        assert isinstance(palette, list), chart_id
        assert len(palette) == expected_len, chart_id
        assert len(set(palette)) == len(palette), chart_id
        assert all(len(color) == 6 for color in palette), chart_id


def test_v4_synthetic_charts_use_raw_units_not_indices() -> None:
    spec = _load_json(CHART_SPEC_V4)
    by_id = {chart["chart_id"]: chart for chart in spec["charts"]}
    assert by_id["C_W35_QUALITY_SYNTHESIS_04"]["y_series"] == [
        "phase_ii",
        "phase_iii",
        "line_coverage_pct",
        "issues",
        "unit_tests",
    ]
    assert by_id["C_W37_DEBT_ISSUES_SYNTHESIS_04"]["y_series"] == [
        "phase_ii",
        "phase_iii",
        "technical_debt_days",
        "issues",
    ]
    assert by_id["C_W42_PHASE2_REFACTORING_SYNTHESIS_04"]["y_series"] == [
        "phase_ii",
        "issues",
        "lines_of_code",
        "unit_tests",
    ]
    assert by_id["C_W43_PHASE2_COVERAGE_DEBT_SYNTHESIS_04"]["y_series"] == [
        "phase_ii",
        "line_coverage_pct",
        "technical_debt_days",
    ]
    assert "index" not in json.dumps(
        {
            key: by_id[key]["y_series"]
            for key in (
                "C_W35_QUALITY_SYNTHESIS_04",
                "C_W37_DEBT_ISSUES_SYNTHESIS_04",
                "C_W42_PHASE2_REFACTORING_SYNTHESIS_04",
                "C_W43_PHASE2_COVERAGE_DEBT_SYNTHESIS_04",
            )
        }
    ).lower()


def test_v4_control_profile_exposes_synthetic_combo_mode() -> None:
    control = _load_json(CONTROL_PROFILE_V4)
    assert control["version"] == "v04"
    assert "synthetic_combo" in control["chart_modes"]
    assert "sheet_synthesis" in control["chart_modes"]
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


# --- 213A: domain palettes and academic style ---

def test_v4_style_profile_has_domain_highlight() -> None:
    style = _load_json(STYLE_PROFILE_V4)
    dh = style["highlight"]["domain_highlight"]
    assert set(dh.keys()) == {"github", "sonarqube", "git_prflow"}
    for domain, colors in dh.items():
        assert "venom_fill_rgb" in colors, f"domain_highlight.{domain} missing venom_fill_rgb"
        assert "peer_fill_rgb" in colors, f"domain_highlight.{domain} missing peer_fill_rgb"
        assert len(colors["venom_fill_rgb"]) == 6
        assert len(colors["peer_fill_rgb"]) == 6


def test_v4_style_profile_has_domain_highlight_academic() -> None:
    style = _load_json(STYLE_PROFILE_V4)
    dh = style["highlight"]["domain_highlight_academic"]
    assert set(dh.keys()) == {"github", "sonarqube", "git_prflow"}
    for domain, colors in dh.items():
        assert "venom_fill_rgb" in colors
        assert "peer_fill_rgb" in colors


def test_v4_style_profile_has_series_palette_by_source_type() -> None:
    style = _load_json(STYLE_PROFILE_V4)
    palette = style["series_palette_by_source_type"]
    for domain in ("github", "sonarqube", "git_prflow"):
        assert domain in palette, f"series_palette_by_source_type missing {domain}"
        assert len(palette[domain]) == 8, f"expected 8 colors for {domain}"


def test_v4_style_profile_has_series_palette_academic() -> None:
    style = _load_json(STYLE_PROFILE_V4)
    palette = style["series_palette_academic"]
    for domain in ("github", "sonarqube", "git_prflow"):
        assert domain in palette
        assert len(palette[domain]) == 8


def test_v4_style_profile_has_line_style() -> None:
    style = _load_json(STYLE_PROFILE_V4)
    ls = style["line_style"]
    assert "primary_line_width_pt" in ls
    assert "secondary_line_width_pt" in ls
    assert "marker_style" in ls
    assert "marker_size_pt" in ls
    assert "phase_series_line_visible" in ls
    assert "reference_line_dash_style" in ls
    assert ls["primary_line_width_pt"] == 2.0
    assert ls["phase_series_line_visible"] is False
    assert ls["reference_line_dash_style"] == 4


def test_v4_style_profile_has_data_labels_comparison_bar() -> None:
    style = _load_json(STYLE_PROFILE_V4)
    dl = style["data_labels"]["comparison_bar"]
    assert "font_size" in dl
    assert "font_color_rgb" in dl
    assert "number_format" in dl
    assert dl["font_size"] == 9


def test_v4_style_profile_has_bar_style_academic() -> None:
    style = _load_json(STYLE_PROFILE_V4)
    bsa = style["bar_style_academic"]
    assert "gap_width" in bsa
    assert "overlap" in bsa
    assert bsa["gap_width"] == 60


def test_v4_style_profile_has_academic_style() -> None:
    style = _load_json(STYLE_PROFILE_V4)
    ac = style["academic_style"]
    assert "enabled" in ac
    assert "chart_area_fill_rgb" in ac
    assert "plot_area_fill_rgb" in ac
    assert "chart_border" in ac
    assert "axis" in ac
    assert "gridlines" in ac
    assert ac["chart_area_fill_rgb"] == "FFFFFF"
    assert ac["plot_area_fill_rgb"] == "FFFFFF"


def test_v4_style_profile_has_academic_typography() -> None:
    style = _load_json(STYLE_PROFILE_V4)
    at = style["academic_typography"]
    for key in ("chart_title", "axis_labels", "legend", "data_labels", "caption"):
        assert key in at, f"academic_typography missing {key}"
    assert at["chart_title"]["font_size"] == 12
    assert at["chart_title"]["bold"] is False
    assert at["axis_labels"]["font_size"] == 8


def test_v4_control_profile_has_phase_fill_colors() -> None:
    control = _load_json(CONTROL_PROFILE_V4)
    pfc = control["phase_background"]["phase_fill_colors"]
    assert set(pfc.keys()) == {"phase_i", "phase_ii", "phase_iii"}
    for k, v in pfc.items():
        assert len(v) == 6, f"{k} color should be 6-char hex"


def test_v4_control_profile_has_phase_fill_colors_academic() -> None:
    control = _load_json(CONTROL_PROFILE_V4)
    pfc = control["phase_background"]["phase_fill_colors_academic"]
    assert set(pfc.keys()) == {"phase_i", "phase_ii", "phase_iii"}


def test_v4_control_profile_has_legend_position_by_mode() -> None:
    control = _load_json(CONTROL_PROFILE_V4)
    lp = control["legend_position_by_mode"]
    assert "comparison" in lp
    assert "synthetic_combo" in lp
    assert lp["comparison"] == "bottom"
    assert lp["synthetic_combo"] == "bottom"
    assert set(lp.values()) == {"bottom"}


def test_v4_chart_spec_all_charts_have_analysis_caption() -> None:
    spec = _load_json(CHART_SPEC_V4)
    missing = [c["chart_id"] for c in spec["charts"] if not c.get("analysis_caption", "").strip()]
    assert missing == [], f"charts missing analysis_caption: {missing}"


def test_v4_chart_spec_has_sheet_synthesis_contract() -> None:
    spec = _load_json(CHART_SPEC_V4)
    charts = spec["charts"]
    assert len(charts) >= 26
    by_id = {c["chart_id"]: c for c in charts}
    synthesis = [c for c in charts if c.get("chart_mode") == "sheet_synthesis"]
    assert len(synthesis) == 5
    for chart in synthesis:
        assert chart.get("synthesis_of"), f"{chart['chart_id']} missing synthesis_of"
        for source_id in chart["synthesis_of"]:
            assert source_id in by_id, f"{chart['chart_id']} references missing chart {source_id}"
            assert by_id[source_id]["sheet"] == chart["sheet"], f"{chart['chart_id']} synthesis_of crosses sheets"


def test_v4_sonar_sheet_synthesis_uses_raw_units() -> None:
    spec = _load_json(CHART_SPEC_V4)
    by_id = {c["chart_id"]: c for c in spec["charts"]}
    expected = {
        "C_W35_QUALITY_SYNTHESIS_04": {
            "line_coverage_pct",
            "issues",
            "unit_tests",
        },
        "C_W37_DEBT_ISSUES_SYNTHESIS_04": {
            "technical_debt_days",
            "issues",
        },
        "C_W42_PHASE2_REFACTORING_SYNTHESIS_04": {
            "issues",
            "lines_of_code",
            "unit_tests",
        },
        "C_W43_PHASE2_COVERAGE_DEBT_SYNTHESIS_04": {
            "line_coverage_pct",
            "technical_debt_days",
        },
    }
    for chart_id, expected_fields in expected.items():
        fields = {
            s["field"]
            for s in by_id[chart_id]["series_plan"]
            if not str(s["field"]).startswith("phase_")
        }
        assert fields == expected_fields
        caption = by_id[chart_id]["analysis_caption"].lower()
        assert "0..100" not in caption
