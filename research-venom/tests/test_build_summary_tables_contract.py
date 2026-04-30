from __future__ import annotations

import build_summary_tables as bst


def test_phase_background_all_null_is_warning_not_failure() -> None:
    pack = {"tables": {"tpl_demo": [{"date": "2026-01-01", "phase_i": None, "value": 5}]}}
    chart_spec = {
        "charts": [
            {
                "chart_id": "C_DEMO",
                "source_sheet": "tpl_demo",
                "x_series": "date",
                "series_plan": [
                    {"role": "y", "field": "phase_i"},
                    {"role": "y", "field": "value"},
                ],
            }
        ]
    }

    rows = bst._series_health_rows(pack, chart_spec)
    by_metric = {row["metric_name"]: row for row in rows}

    assert by_metric["y:phase_i"]["aggregation"] == "series_all_null_background"
    assert "severity=warn" in by_metric["y:phase_i"]["notes"]
    assert by_metric["y:value"]["aggregation"] == "ok"


def test_missing_required_series_column_is_failure() -> None:
    pack = {"tables": {"tpl_demo": [{"date": "2026-01-01", "value": 5}]}}
    chart_spec = {
        "charts": [
            {
                "chart_id": "C_DEMO",
                "source_sheet": "tpl_demo",
                "x_series": "date",
                "series_plan": [{"role": "y", "field": "missing_metric"}],
            }
        ]
    }

    rows = bst._series_health_rows(pack, chart_spec)

    assert rows[-1]["aggregation"] == "source_metric_missing"
    assert "severity=fail" in rows[-1]["notes"]


def test_optional_all_null_series_is_warning_not_failure() -> None:
    pack = {"tables": {"tpl_demo": [{"date": "2026-01-01", "optional_metric": None}]}}
    chart_spec = {
        "charts": [
            {
                "chart_id": "C_DEMO",
                "source_sheet": "tpl_demo",
                "x_series": "date",
                "series_plan": [{"role": "optional_y", "field": "optional_metric"}],
            }
        ]
    }

    rows = bst._series_health_rows(pack, chart_spec)

    assert rows[-1]["aggregation"] == "series_all_null_optional"
    assert "severity=warn" in rows[-1]["notes"]
