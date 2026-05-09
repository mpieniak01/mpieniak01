from __future__ import annotations

import csv
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CHART_SPEC = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "chart_spec_v04.json"
WORD_MAP = REPO_ROOT / "artifacts" / "inputs" / "visualization" / "word_embed_map_v04.csv"
PHASE_RANGES = {
    "phase_i": ("2026-01-01", "2026-02-05"),
    "phase_ii": ("2026-02-06", "2026-03-06"),
    "phase_iii": ("2026-03-07", "2026-03-31"),
}


def _charts() -> list[dict]:
    return json.loads(CHART_SPEC.read_text(encoding="utf-8"))["charts"]


def test_v4_chart_spec_has_expected_chart_count_with_sheet_synthesis() -> None:
    assert len(_charts()) == 26


def test_v4_chart_spec_excludes_removed_market_benchmark() -> None:
    chart_ids = {chart["chart_id"] for chart in _charts()}
    assert "C_WP6_MARKET_BENCHMARK_03" not in chart_ids
    assert "C_WP6_LEAD_TIME_DAILY_03" in chart_ids


def test_combo_phase_background_series_are_first() -> None:
    for chart in _charts():
        plan = chart.get("series_plan") or []
        active_phase_fields = chart.get("active_phase_fields") or ["phase_i", "phase_ii", "phase_iii"]
        phase_count = len(active_phase_fields)
        fields = [item.get("field") for item in plan[:phase_count] if isinstance(item, dict)]
        has_phase_series = any(
            isinstance(item, dict) and str(item.get("field", "")).startswith("phase_")
            for item in plan
        )
        if chart.get("chart_type") == "combo" and has_phase_series:
            assert fields == active_phase_fields, chart["chart_id"]
            assert all(
                isinstance(item, dict)
                and str(item.get("field", "")).startswith("phase_")
                and item.get("axis_group") == "secondary"
                for item in plan[:phase_count]
            ), chart["chart_id"]


def test_wp6_matches_template_series_without_review_latency() -> None:
    wp6 = next(chart for chart in _charts() if chart["chart_id"] == "C_WP6_LEAD_TIME_DAILY_03")
    fields = [item["field"] for item in wp6["series_plan"]]
    assert fields == [
        "phase_i",
        "phase_ii",
        "phase_iii",
        "pr_daily_avg_lead_time_hours",
        "pr_daily_median_lead_time_hours",
        "period_avg_lead_time_hours_ref",
        "period_median_lead_time_hours_ref",
    ]
    assert "pr_daily_avg_review_latency_hours" not in fields
    metric_types = {
        item["field"]: item.get("chart_type")
        for item in wp6["series_plan"]
        if not str(item.get("field", "")).startswith("phase_")
    }
    assert metric_types == {
        "pr_daily_avg_lead_time_hours": "column",
        "pr_daily_median_lead_time_hours": "column",
        "period_avg_lead_time_hours_ref": "line",
        "period_median_lead_time_hours_ref": "line",
    }
    assert fields.index("period_avg_lead_time_hours_ref") > fields.index("pr_daily_median_lead_time_hours")
    assert fields.index("period_median_lead_time_hours_ref") > fields.index("pr_daily_median_lead_time_hours")


def test_event_metrics_are_not_rendered_as_lines() -> None:
    for chart in _charts():
        for item in chart.get("series_plan", []):
            if item.get("metric_semantics") in {"daily_event", "sparse_event"}:
                assert item.get("chart_type") != "line", (chart["chart_id"], item["field"])


def test_phase_scope_matches_active_phase_series() -> None:
    for chart in _charts():
        phase_series = [
            item["field"]
            for item in chart.get("series_plan", [])
            if str(item.get("field", "")).startswith("phase_")
        ]
        if not phase_series:
            continue
        assert chart.get("phase_scope_mode") in {
            "active_data_only",
            "declared_phase_only",
            "full_project",
        }, chart["chart_id"]
        assert phase_series == chart.get("active_phase_fields"), chart["chart_id"]


def test_phase_scoped_date_axis_matches_active_phase_range() -> None:
    for chart in _charts():
        active_phase_fields = chart.get("active_phase_fields")
        if not active_phase_fields or chart.get("x_series") != "date":
            continue
        expected_start = min(PHASE_RANGES[field][0] for field in active_phase_fields)
        expected_end = max(PHASE_RANGES[field][1] for field in active_phase_fields)
        assert chart.get("x_axis_scope_mode") == "active_phase_range", chart["chart_id"]
        assert chart.get("x_axis_start") == expected_start, chart["chart_id"]
        assert chart.get("x_axis_end") == expected_end, chart["chart_id"]


def test_declared_phase_charts_render_only_declared_phase() -> None:
    for chart in _charts():
        if chart.get("phase_scope_mode") == "declared_phase_only":
            assert chart.get("active_phase_fields") == ["phase_ii"], chart["chart_id"]
            phase_series = [
                item["field"]
                for item in chart.get("series_plan", [])
                if str(item.get("field", "")).startswith("phase_")
            ]
            assert phase_series == ["phase_ii"], chart["chart_id"]


def test_word_embed_map_references_existing_chart_ids() -> None:
    chart_ids = {chart["chart_id"] for chart in _charts()}
    with WORD_MAP.open(newline="", encoding="utf-8") as handle:
        mapped = [row["chart_id"] for row in csv.DictReader(handle)]
    assert mapped
    assert set(mapped).issubset(chart_ids)
