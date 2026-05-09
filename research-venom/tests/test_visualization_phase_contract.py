from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CONTROL_PROFILE = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "chart_control_profile_v04.json"
PIPELINE_CONFIG = REPO_ROOT / "config" / "process_pipeline_v04.json"
CHART_SPEC = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "chart_spec_v04.json"
LAYOUT_SPEC = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "workbook_layout_v04.json"
EXCEL_ADD_CHARTS = REPO_ROOT / "tools" / "excel_add_charts.ps1"
EXCEL_VERIFY = REPO_ROOT / "tools" / "verify_excel_product.ps1"


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_phase_background_profile_defines_global_scale_contract() -> None:
    profile = _load_json(CONTROL_PROFILE)
    phase_background = profile["phase_background"]

    assert phase_background["series_fields"] == ["phase_i", "phase_ii", "phase_iii"]
    assert phase_background["background_value"] == 100
    assert phase_background["fill_transparency"] == 0.75
    assert phase_background["line_visible"] is False
    assert phase_background["render_mode"] == "column"
    assert phase_background["gap_width"] == 0
    assert phase_background["overlap"] == 100
    assert phase_background["dynamic_scale_enabled"] is True
    assert phase_background["dynamic_scale_padding_pct"] == 0.10
    assert phase_background["sheet_synthesis_fill_transparency"] == 0.35
    assert phase_background["secondary_axis_scale"] == {
        "minimum": 0,
        "maximum": 100,
        "major_unit": 20,
        "minimum_is_auto": False,
        "maximum_is_auto": False,
        "major_unit_is_auto": False,
    }
    assert [row["field"] for row in phase_background["date_ranges"]] == [
        "phase_i",
        "phase_ii",
        "phase_iii",
    ]


def test_date_axis_profile_defines_global_weekly_date_contract() -> None:
    profile = _load_json(CONTROL_PROFILE)
    date_axis = profile["date_axis"]

    assert date_axis["category_type"] == "category"
    assert date_axis["tick_label_spacing"] == 7
    assert date_axis["tick_mark_spacing"] == 7
    assert date_axis["number_format"] == "mm-dd"


def test_visualization_sources_pack_defines_venom_anchor_peer_group_contract() -> None:
    cfg = _load_json(PIPELINE_CONFIG)
    step = cfg["process"]["steps"]["visualization_sources_pack"]

    assert step["comparison_anchor_project_key"] == "mpieniak01/Venom"
    assert step["comparison_peer_group_size"] == 11
    assert step["comparison_metrics"] == {
        "tpl_WP1_pr_volume": "total_opened_pr",
        "tpl_WP2_lead_time": "weighted_avg_lead_time_hours",
        "tpl_WP3_merge_rate": "merge_rate_pct",
        "tpl_WP4_backlog": "avg_active_pr",
    }


def test_workbook_layout_descriptions_are_source_first() -> None:
    layout = _load_json(LAYOUT_SPEC)

    for sheet in layout["sheets"]:
        desc = sheet.get("sheet_description")
        if not desc:
            continue
        assert desc.startswith("Zrodlo:"), sheet["sheet_name"]
        assert "Dane pipeline" not in desc, sheet["sheet_name"]


def test_workbook_layout_source_types_match_declared_data_domain() -> None:
    layout = _load_json(LAYOUT_SPEC)
    expected = {
        "Surowe_GitHub_Q1": "github",
        "Surowe_SonarQube_Q1": "sonarqube",
        "Surowe_PRFlow_Q1": "git_prflow",
        "W31_Commity": "github",
        "W32_LOC": "github",
        "W36_Dlug_Projekty": "sonarqube",
        "W37_Trajektoria_Dlug": "sonarqube",
        "W35_Trajektoria_Q1": "sonarqube",
        "W42_FazaII": "sonarqube",
        "W43_FazaII": "sonarqube",
        "W33_Dzienny_Przeplyw": "github",
        "WP1_PR_Wolumen": "git_prflow",
        "WP2_Lead_Time": "git_prflow",
        "WP3_Merge_Rate": "git_prflow",
        "WP4_Backlog": "git_prflow",
        "WP5_Venom_PR_Daily": "git_prflow",
        "WP6_Venom_Lead_Time": "git_prflow",
    }

    by_name = {sheet["sheet_name"]: sheet["source_type"] for sheet in layout["sheets"]}
    assert by_name == expected


def test_w36_debt_comparison_uses_max_snapshot_not_sum() -> None:
    chart_spec = _load_json(CHART_SPEC)
    layout = _load_json(LAYOUT_SPEC)

    chart = next(chart for chart in chart_spec["charts"] if chart["chart_id"] == "C_W36_DEBT_PROJECTS_03")
    assert chart["y_series"] == ["technical_debt_days_max_q1"]
    assert chart["series_plan"][0]["field"] == "technical_debt_days_max_q1"
    assert "maksymalnym dziennym stanem" in chart["table_description"]
    assert "sum" not in chart["table_description"].lower()
    assert "skumulowany" not in chart["analysis_caption"].lower()
    assert "nie jest sumowana" in chart["analysis_caption"].lower()

    sheet = next(sheet for sheet in layout["sheets"] if sheet["sheet_name"] == "W36_Dlug_Projekty")
    assert "maksymalnym dziennym stanem" in sheet["sheet_description"]
    assert "sum" not in sheet["sheet_description"].lower()


def test_worksheet_banner_matches_template_contract() -> None:
    style = _load_json(REPO_ROOT / "artifacts" / "inputs" / "visualization" / "chart_style_profile_v04.json")

    assert style["chart_title"]["font_size"] == 14
    assert style["chart_title"]["font_color_rgb"] == "0F172A"
    assert style["axis_labels"]["font_size"] == 10
    assert style["axis_labels"]["font_color_rgb"] == "374151"
    assert style["worksheet_style"]["show_gridlines_for_analysis"] is False
    # sheet_title follows the current worksheet contract: white row, domain/header colored font.
    assert style["sheet_title"]["fill_color_rgb"] == "FFFFFF"
    assert style["sheet_title"]["font_color_source"] == "table_header_fill"


def test_chart_table_descriptions_are_source_first() -> None:
    chart_spec = _load_json(CHART_SPEC)

    for chart in chart_spec["charts"]:
        desc = chart.get("table_description")
        assert desc, chart["chart_id"]
        assert desc.startswith("Zrodlo:"), chart["chart_id"]
        assert "Dane pipeline" not in desc, chart["chart_id"]


def test_phase_series_are_rendered_as_secondary_columns() -> None:
    chart_spec = _load_json(CHART_SPEC)

    for chart in chart_spec["charts"]:
        phase_series = [s for s in chart.get("series_plan", []) if str(s.get("field", "")).startswith("phase_")]
        if not phase_series:
            continue
        assert all(s["chart_type"] == "column" for s in phase_series), chart["chart_id"]
        assert all(s["axis_group"] == "secondary" for s in phase_series), chart["chart_id"]


def test_excel_generator_reenforces_phase_axis_after_combo_grouping() -> None:
    script = EXCEL_ADD_CHARTS.read_text(encoding="utf-8")

    assert "function Enforce-PhaseSeriesAsSecondaryColumns" in script
    assert script.count("Enforce-PhaseSeriesAsSecondaryColumns -Chart $chart -ChartCfg $chartCfg") >= 2
    assert "Get-PhaseSeriesLabels -ChartCfg $ChartCfg" in script
    assert "try { $series.AxisGroup = 2 } catch {}" in script


def test_excel_generator_uses_unmerged_template_banner_rows() -> None:
    script = (REPO_ROOT / "tools" / "excel_build_workbook.ps1").read_text(encoding="utf-8")

    assert "Merge() | Out-Null" not in script
    assert "WrapText = $true" not in script
    assert "RowHeight = 17.25" in script
    assert "NumberFormat = 'dd\".\"mm\".\"yyyy'" in script
    assert 'NumberFormatLocal = "dd.mm.rrrr"' in script
    assert "function Try-ParseDateValue" in script
    assert ".Value2 = [double]$dateValue.ToOADate()" in script
    assert "Formula = $formula" not in script
    assert "=DATE($" not in script
    assert "$Worksheet.Range($Worksheet.Cells.Item($HeaderRow, 1), $Worksheet.Cells.Item($lastRow, $headers.Count)).Columns.AutoFit()" in script or "$dataRange.Columns.AutoFit()" in script


def test_excel_generator_filters_chart_rows_by_configured_date_axis_scope() -> None:
    script = EXCEL_ADD_CHARTS.read_text(encoding="utf-8")

    assert "function Get-ScopedDataRowBounds" in script
    assert "x_axis_scope_mode" in script
    assert "x_axis_start" in script
    assert "x_axis_end" in script
    assert "$chartDataStartRow" in script
    assert "$chartLastRow" in script


def test_excel_verifier_fails_when_phase_series_leave_secondary_axis() -> None:
    script = EXCEL_VERIFY.read_text(encoding="utf-8")

    assert "phase_series_axis_group_ok" in script
    assert "$axisGroup -ne 2" in script
    assert "$check.phase_series_axis_group_ok = $false" in script
    assert 'if ($SeriesName -like "phase_*") {' in script
    assert '$result.status = "ok"' in script


def test_excel_verifier_checks_rendered_date_axis_scope() -> None:
    script = EXCEL_VERIFY.read_text(encoding="utf-8")

    assert "date_axis_scope_ok" in script
    assert "x_axis_scope_mode" in script
    assert "x_axis_start" in script
    assert "x_axis_end" in script
    assert "Convert-ExcelDateToIso" in script


def test_excel_verifier_supports_dynamic_phase_secondary_axis_scale() -> None:
    script = EXCEL_VERIFY.read_text(encoding="utf-8")
    assert "function Get-MaxSourceMetricValue" in script
    assert "function Get-SourceMetricBounds" in script
    assert "function Try-ConvertToDouble" in script
    assert "dynamic_scale_enabled" in script
    assert "secondary_axis_scale_mode = \"dynamic_phase\"" in script
    assert "primary_source_min_metric_value" in script
    assert "primary_source_max_metric_value" in script
    assert "secondary_source_min_metric_value" in script
    assert "secondary_source_max_metric_value" in script
    assert "primary_axis_scale_ok" in script
    assert "[double]$secondaryAxis.MinimumScale -le ([double]$secondarySourceBounds.min + 0.01)" in script
    assert "[double]$secondaryAxis.MaximumScale -ge ([double]$secondarySourceBounds.max - 0.01)" in script


def test_excel_generator_enforces_stacked_bar_shared_plane() -> None:
    script = EXCEL_ADD_CHARTS.read_text(encoding="utf-8")
    assert '$chartType -eq "bar_stacked"' in script
    assert "if ($null -eq $overlap) { $overlap = 100 }" in script
    assert "SeriesCollection($si).AxisGroup = 1" in script


def test_excel_generator_enforces_phase_background_shared_plane() -> None:
    script = EXCEL_ADD_CHARTS.read_text(encoding="utf-8")
    assert "function Apply-PhaseBackgroundLayout" in script
    assert "$groupAxisGroup = [int]$group.AxisGroup" in script
    assert "if ($groupHasPhase -and" in script
    assert "$groupAxisGroup -eq 2" in script
    assert "$phaseGroupsStyled += 1" in script
    assert "if ($phaseGroupsStyled -eq 0 -and $phaseLabels.Count -gt 0)" in script
    assert '$ChartCfg.PSObject.Properties.Name -contains "column_gap_width"' in script
    assert "$phaseGroup = $groups[$groups.Count - 1]" in script
    assert "try { $group.GapWidth = $gapWidth } catch {}" in script
    assert "try { $group.Overlap = $overlap } catch {}" in script


def test_excel_generator_applies_dynamic_phase_scale_from_data() -> None:
    script = EXCEL_ADD_CHARTS.read_text(encoding="utf-8")
    assert "function Get-ChartDataSeriesMax" in script
    assert "function Get-ChartDataSeriesBounds" in script
    assert "function Convert-ComRangeValuesToFlatArray" in script
    assert "function Get-RenderedChartSeriesBounds" in script
    assert "function Test-IsPhaseSeriesName" in script
    assert "function Test-IsPhaseSeriesObject" in script
    assert "function Get-PhaseSeriesIndexes" in script
    assert "function Get-LeadingPhaseSeriesCount" in script
    assert "function Apply-PrimaryAxisScale" in script
    assert "function Apply-ValueAxisScale" in script
    assert "function Try-ConvertToDouble" in script
    assert "function Convert-ComSeriesValuesToArray" in script
    assert "function Apply-DynamicPhaseScale" in script
    assert "$Worksheet.Range($Worksheet.Cells.Item($DataStartRow, $col), $Worksheet.Cells.Item($LastDataRow, $col))" in script


def test_chart_specific_axis_overrides_are_configuration_driven() -> None:
    spec = _load_json(CHART_SPEC)
    by_id = {chart["chart_id"]: chart for chart in spec["charts"]}
    w43 = by_id["C_W43_PHASE2_COVERAGE_DEBT_SYNTHESIS_04"]
    script = EXCEL_ADD_CHARTS.read_text(encoding="utf-8")

    assert w43["primary_axis_scale"]["maximum"] == 90
    assert w43["secondary_axis_scale"]["maximum"] == 20
    assert w43["phase_background_value"] == 20
    assert "phase_background_value" in script
    assert 'if ($chartId -eq "C_W43_PHASE2_COVERAGE_DEBT_SYNTHESIS_04")' not in script
    assert "dynamic_scale_enabled" in script
    assert "dynamic_scale_padding_pct" in script
    assert "Convert-ComSeriesValuesToArray -Values $ser.Values" in script
    assert "$active = (Try-ConvertToDouble -Value $raw -Result ([ref]$num)) -and $num -gt 0" in script
    assert "$vals[$pi] = $null" in script
    assert "Get-RenderedChartSeriesBounds -Chart $chart -ChartCfg $chartCfg -AxisGroup 1" in script
    assert "Get-RenderedChartSeriesBounds -Chart $chart -ChartCfg $chartCfg -AxisGroup 2" in script
    assert "Apply-DynamicPhaseScale -Chart $chart -ChartCfg $chartCfg -ControlProfile $controlProfile -PrimaryDataBounds $primaryDataBounds -SecondaryDataBounds $secondaryDataBounds" in script
    assert "sheet_synthesis_fill_transparency" in script
