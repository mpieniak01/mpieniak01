#!/usr/bin/env python3
"""S01: Prepare standardized source pack from the benchmark inputs.

Outputs:
- JSON pack with source/work tables and validation report
- Flat CSV export (table_name + row payload) for easy audit/import
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import math
import json
import sys
from pathlib import Path
from typing import Any

from path_config import (
    choose_dataset_value,
    cfg_get,
    load_pipeline_config,
    repo_root_from_script,
    resolve_dataset_path,
)

REQUIRED_COLUMNS = {
    "205B": [
        "project_key",
        "date",
        "issues",
        "technical_debt_days",
        "lines_of_code",
        "line_coverage_pct",
        "unit_tests",
    ],
    "205C": [
        "project_key",
        "date",
        "commits",
        "authors",
        "additions",
        "deletions",
        "churn",
        "truncated",
    ],
    "205D": [
        "project_key",
        "date",
        "pr_opened_count_daily",
        "pr_merged_count_daily",
        "pr_closed_not_merged_daily",
        "pr_active_daily",
        "pr_daily_avg_lead_time_hours",
        "pr_daily_median_lead_time_hours",
        "pr_daily_avg_review_latency_hours",
        "lead_time_sample_size",
    ],
    "205E": [
        "project_key",
        "date",
        "closed_pr_count_daily",
        "merged_pr_count_daily",
        "avg_comments_closed_daily",
        "median_comments_closed_daily",
        "avg_comments_merged_daily",
        "median_comments_merged_daily",
    ],
}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build standardized source pack.")
    parser.add_argument(
        "--config",
        default="config/process_pipeline_v01.json",
        help="Central pipeline config path (relative to repo root or absolute).",
    )
    parser.add_argument(
        "--dataset-id",
        default="",
        help="Dataset identifier from config.process.steps (default: visualization_sources_pack).",
    )
    parser.add_argument(
        "--in-205b",
        default="",
    )
    parser.add_argument(
        "--in-205c",
        default="",
    )
    parser.add_argument(
        "--in-205d",
        default="",
    )
    parser.add_argument(
        "--in-205e-daily",
        default="",
    )
    parser.add_argument(
        "--layout-csv",
        default="",
    )
    parser.add_argument(
        "--date-from",
        default="2026-01-01",
    )
    parser.add_argument(
        "--date-to",
        default="2026-03-31",
    )
    parser.add_argument(
        "--venom-205b-key",
        default="",
    )
    parser.add_argument(
        "--venom-205d-key",
        default="",
    )
    parser.add_argument(
        "--venom-205c-key",
        default="",
    )
    parser.add_argument(
        "--out-json",
        default="",
    )
    parser.add_argument(
        "--out-csv",
        default="",
    )
    return parser.parse_args()


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader)


def _ensure_columns(
    rows: list[dict[str, str]], expected: list[str], label: str
) -> None:
    if not rows:
        raise RuntimeError(f"{label}: input has no rows.")
    columns = list(rows[0].keys())
    missing = [name for name in expected if name not in columns]
    if missing:
        raise RuntimeError(f"{label}: missing required columns: {missing}")


def _parse_date(value: str) -> dt.date:
    return dt.date.fromisoformat(value)


def _to_int(value: str) -> int | None:
    text = (value or "").strip()
    if not text:
        return None
    return int(float(text))


def _to_float(value: str) -> float | None:
    text = (value or "").strip()
    if not text:
        return None
    return float(text)


def _in_range(date_value: str, start: dt.date, end: dt.date) -> bool:
    try:
        d = _parse_date(date_value)
    except ValueError:
        return False
    return start <= d <= end


def _filter_date_range(
    rows: list[dict[str, str]],
    start: dt.date,
    end: dt.date,
) -> tuple[list[dict[str, str]], int]:
    filtered: list[dict[str, str]] = []
    out_of_range = 0
    for row in rows:
        if _in_range(row.get("date", ""), start, end):
            filtered.append(row)
        else:
            out_of_range += 1
    return filtered, out_of_range


def _duplicate_count(rows: list[dict[str, str]]) -> int:
    seen: set[tuple[str, str]] = set()
    dup = 0
    for row in rows:
        key = ((row.get("project_key") or "").strip(), (row.get("date") or "").strip())
        if key in seen:
            dup += 1
        else:
            seen.add(key)
    return dup


def _std_205b(rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for row in rows:
        out.append(
            {
                "project_key": row["project_key"],
                "date": row["date"],
                "issues": _to_int(row["issues"]),
                "technical_debt_days": _to_float(row["technical_debt_days"]),
                "lines_of_code": _to_int(row["lines_of_code"]),
                "line_coverage_pct": _to_float(row["line_coverage_pct"]),
                "unit_tests": _to_int(row["unit_tests"]),
            }
        )
    return out


def _std_205c(rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for row in rows:
        out.append(
            {
                "project_key": row["project_key"],
                "date": row["date"],
                "commits": _to_int(row["commits"]) or 0,
                "authors": _to_int(row["authors"]) or 0,
                "additions": _to_int(row["additions"]) or 0,
                "deletions": _to_int(row["deletions"]) or 0,
                "churn": _to_int(row["churn"]) or 0,
                "truncated": str(row["truncated"]).strip().lower() == "true",
            }
        )
    return out


def _std_205d(rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for row in rows:
        out.append(
            {
                "project_key": row["project_key"],
                "date": row["date"],
                "pr_opened_count_daily": _to_int(row["pr_opened_count_daily"]) or 0,
                "pr_merged_count_daily": _to_int(row["pr_merged_count_daily"]) or 0,
                "pr_closed_not_merged_daily": _to_int(row["pr_closed_not_merged_daily"])
                or 0,
                "pr_active_daily": _to_int(row["pr_active_daily"]) or 0,
                "pr_daily_avg_lead_time_hours": _to_float(
                    row["pr_daily_avg_lead_time_hours"]
                ),
                "pr_daily_median_lead_time_hours": _to_float(
                    row["pr_daily_median_lead_time_hours"]
                ),
                "pr_daily_avg_review_latency_hours": _to_float(
                    row["pr_daily_avg_review_latency_hours"]
                ),
                "lead_time_sample_size": _to_int(row["lead_time_sample_size"]) or 0,
            }
        )
    return out


def _std_205e(rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for row in rows:
        out.append(
            {
                "project_key": row["project_key"],
                "date": row["date"],
                "closed_pr_count_daily": _to_int(row["closed_pr_count_daily"]) or 0,
                "merged_pr_count_daily": _to_int(row["merged_pr_count_daily"]) or 0,
                "avg_comments_closed_daily": _to_float(
                    row["avg_comments_closed_daily"]
                ),
                "median_comments_closed_daily": _to_float(
                    row["median_comments_closed_daily"]
                ),
                "avg_comments_merged_daily": _to_float(
                    row["avg_comments_merged_daily"]
                ),
                "median_comments_merged_daily": _to_float(
                    row["median_comments_merged_daily"]
                ),
            }
        )
    return out


PHASES = [
    ("phase_i", dt.date(2026, 1, 1), dt.date(2026, 2, 5)),
    ("phase_ii", dt.date(2026, 2, 6), dt.date(2026, 3, 6)),
    ("phase_iii", dt.date(2026, 3, 7), dt.date(2026, 3, 31)),
]

PHASE_BACKGROUND_VALUE = 100


def _phase_columns(date_value: str, height: float | int) -> dict[str, float | int | None]:
    current = _parse_date(date_value)
    return {
        name: height if start <= current <= end else None
        for name, start, end in PHASES
    }


def _group_by_project(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        grouped.setdefault(str(row["project_key"]), []).append(row)
    return grouped


def _select_anchor_peer_group(
    rows: list[dict[str, Any]],
    *,
    anchor_project_key: str,
    max_projects: int,
    metric_field: str,
) -> list[dict[str, Any]]:
    if max_projects <= 0:
        return []

    anchor_row = None
    for row in rows:
        if str(row.get("project_key") or "") == anchor_project_key:
            anchor_row = row
            break
    if anchor_row is None:
        raise RuntimeError(f"Missing anchor project in comparison table: {anchor_project_key}")

    anchor_metric = anchor_row.get(metric_field)
    if anchor_metric is None:
        raise RuntimeError(
            f"Missing metric '{metric_field}' for anchor project {anchor_project_key}"
        )
    anchor_value = float(anchor_metric)

    def _sort_key(row: dict[str, Any]) -> tuple[int, float, str]:
        project_key = str(row.get("project_key") or "")
        metric_value = row.get(metric_field)
        if project_key == anchor_project_key:
            return (0, 0.0, project_key)
        if metric_value is None:
            return (2, float("inf"), project_key)
        return (1, abs(float(metric_value) - anchor_value), project_key)

    selected = sorted(rows, key=_sort_key)
    return selected[:max_projects]


def _rows_for_project(rows: list[dict[str, Any]], project_key: str) -> list[dict[str, Any]]:
    return [row for row in rows if row["project_key"] == project_key]


def _date_range(start: dt.date, end: dt.date) -> list[dt.date]:
    days = (end - start).days
    return [start + dt.timedelta(days=offset) for offset in range(days + 1)]


def _max_numeric_value(
    rows: list[dict[str, Any]],
    fields: list[str],
) -> float | None:
    values: list[float] = []
    for row in rows:
        for field in fields:
            value = row.get(field)
            if isinstance(value, (int, float)):
                values.append(float(value))
    if not values:
        return None
    return max(values)


def _ceil_to_step(value: float | int | None, step: int) -> int:
    if value is None:
        return 0
    if step <= 0:
        raise ValueError("step must be positive")
    return int(math.ceil(float(value) / float(step)) * step)


def _value_index(value: Any, min_value: float | None, max_value: float | None) -> float | None:
    if value is None or min_value is None or max_value is None:
        return None
    value_f = float(value)
    if math.isclose(max_value, min_value):
        return 100.0
    return round(((value_f - min_value) / (max_value - min_value)) * 100.0, 4)


def _improvement_index(value: Any, min_value: float | None, max_value: float | None) -> float | None:
    idx = _value_index(value, min_value, max_value)
    if idx is None:
        return None
    return round(100.0 - idx, 4)


def _metric_min_max(rows: list[dict[str, Any]], field: str) -> tuple[float | None, float | None]:
    values = [float(row[field]) for row in rows if row.get(field) is not None]
    if not values:
        return None, None
    return min(values), max(values)


def _mk_template_w31_commits(src_205c: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for project_key, items in sorted(_group_by_project(src_205c).items()):
        out.append(
            {
                "project_key": project_key,
                "commits_sum_q1": sum(int(row["commits"]) for row in items),
            }
        )
    return out


def _mk_template_w32_additions(src_205c: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for project_key, items in sorted(_group_by_project(src_205c).items()):
        out.append(
            {
                "project_key": project_key,
                "additions_sum_q1": sum(int(row["additions"]) for row in items),
            }
        )
    return out


def _mk_template_w36_debt(src_205b: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for project_key, items in sorted(_group_by_project(src_205b).items()):
        debt_values = [
            float(row["technical_debt_days"])
            for row in items
            if row["technical_debt_days"] is not None
        ]
        out.append(
            {
                "project_key": project_key,
                "technical_debt_days_max_q1": round(max(debt_values), 4) if debt_values else None,
            }
        )
    return out


def _mk_template_w37_debt_issues(
    wrk_205b_venom: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    debt_min, debt_max = _metric_min_max(wrk_205b_venom, "technical_debt_days")
    issues_min, issues_max = _metric_min_max(wrk_205b_venom, "issues")
    for row in wrk_205b_venom:
        out.append(
            {
                "date": row["date"],
                "project_key": row.get("project_key", "mpieniak01/Venom"),
                "technical_debt_days": row["technical_debt_days"],
                "issues": row["issues"],
                "technical_debt_days_index": _value_index(row["technical_debt_days"], debt_min, debt_max),
                "issues_index": _value_index(row["issues"], issues_min, issues_max),
                "technical_debt_improvement_index": _improvement_index(row["technical_debt_days"], debt_min, debt_max),
                "issues_improvement_index": _improvement_index(row["issues"], issues_min, issues_max),
                **_phase_columns(row["date"], PHASE_BACKGROUND_VALUE),
            }
        )
    return out


def _mk_template_w35_quality(wrk_205b_venom: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    coverage_min, coverage_max = _metric_min_max(wrk_205b_venom, "line_coverage_pct")
    issues_min, issues_max = _metric_min_max(wrk_205b_venom, "issues")
    tests_min, tests_max = _metric_min_max(wrk_205b_venom, "unit_tests")
    for row in wrk_205b_venom:
        out.append(
            {
                "date": row["date"],
                "project_key": row.get("project_key", "mpieniak01/Venom"),
                "issues": row["issues"],
                "line_coverage_pct": row["line_coverage_pct"],
                "unit_tests": row["unit_tests"],
                "coverage_index": _value_index(row["line_coverage_pct"], coverage_min, coverage_max),
                "issues_improvement_index": _improvement_index(row["issues"], issues_min, issues_max),
                "unit_tests_index": _value_index(row["unit_tests"], tests_min, tests_max),
                **_phase_columns(row["date"], PHASE_BACKGROUND_VALUE),
            }
        )
    return out


def _mk_template_w42_phase2_quality(
    wrk_205b_venom: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    phase2_start = dt.date(2026, 2, 6)
    phase2_end = dt.date(2026, 3, 6)
    phase_rows = [
        row
        for row in wrk_205b_venom
        if phase2_start <= _parse_date(row["date"]) <= phase2_end
    ]
    issues_min, issues_max = _metric_min_max(phase_rows, "issues")
    loc_min, loc_max = _metric_min_max(phase_rows, "lines_of_code")
    tests_min, tests_max = _metric_min_max(phase_rows, "unit_tests")
    out: list[dict[str, Any]] = []
    for row in phase_rows:
        d = _parse_date(row["date"])
        if not (phase2_start <= d <= phase2_end):
            continue
        out.append(
            {
                "date": row["date"],
                "project_key": row.get("project_key", "mpieniak01/Venom"),
                "issues": row["issues"],
                "lines_of_code": row["lines_of_code"],
                "unit_tests": row["unit_tests"],
                "issues_improvement_index": _improvement_index(row["issues"], issues_min, issues_max),
                "loc_index": _value_index(row["lines_of_code"], loc_min, loc_max),
                "unit_tests_index": _value_index(row["unit_tests"], tests_min, tests_max),
                **_phase_columns(row["date"], PHASE_BACKGROUND_VALUE),
            }
        )
    return out


def _mk_template_w43_phase2_debt_coverage(
    wrk_205b_venom: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    phase2_start = dt.date(2026, 2, 6)
    phase2_end = dt.date(2026, 3, 6)
    phase_rows = [
        row
        for row in wrk_205b_venom
        if phase2_start <= _parse_date(row["date"]) <= phase2_end
    ]
    debt_min, debt_max = _metric_min_max(phase_rows, "technical_debt_days")
    coverage_min, coverage_max = _metric_min_max(phase_rows, "line_coverage_pct")
    out: list[dict[str, Any]] = []
    for row in phase_rows:
        d = _parse_date(row["date"])
        if not (phase2_start <= d <= phase2_end):
            continue
        out.append(
            {
                "date": row["date"],
                "project_key": row.get("project_key", "mpieniak01/Venom"),
                "technical_debt_days": row["technical_debt_days"],
                "line_coverage_pct": row["line_coverage_pct"],
                "technical_debt_improvement_index": _improvement_index(row["technical_debt_days"], debt_min, debt_max),
                "coverage_index": _value_index(row["line_coverage_pct"], coverage_min, coverage_max),
                **_phase_columns(row["date"], PHASE_BACKGROUND_VALUE),
            }
        )
    return out


def _mk_template_w33_code_flow(
    src_205c: list[dict[str, Any]], venom_key: str
) -> list[dict[str, Any]]:
    venom_rows = _rows_for_project(src_205c, venom_key)
    out: list[dict[str, Any]] = []
    for row in venom_rows:
        out.append(
            {
                "date": row["date"],
                "project_key": venom_key,
                "additions": row["additions"],
                "deletions_negative": -int(row["deletions"]),
                **_phase_columns(row["date"], PHASE_BACKGROUND_VALUE),
            }
        )
    return out


def _mk_template_wp1_pr_volume(
    wrk_205d_repo_summary: list[dict[str, Any]],
    *,
    anchor_project_key: str,
    max_projects: int,
    metric_field: str,
) -> list[dict[str, Any]]:
    selected = _select_anchor_peer_group(
        wrk_205d_repo_summary,
        anchor_project_key=anchor_project_key,
        max_projects=max_projects,
        metric_field=metric_field,
    )
    return [
        {
            "project_key": row["project_key"],
            "total_opened_pr": row["total_opened_pr"],
            "total_merged_pr": row["total_merged_pr"],
            "total_closed_not_merged_pr": row["total_closed_not_merged_pr"],
        }
        for row in selected
    ]


def _mk_template_wp2_lead_time(
    src_205d: list[dict[str, Any]],
    *,
    anchor_project_key: str,
    max_projects: int,
    metric_field: str,
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for project_key, items in sorted(_group_by_project(src_205d).items()):
        weighted_num = 0.0
        weighted_den = 0
        avg_daily = []
        median_daily = []
        for row in items:
            sample = int(row["lead_time_sample_size"])
            avg_value = row["pr_daily_avg_lead_time_hours"]
            if avg_value is not None and sample > 0:
                weighted_num += float(avg_value) * sample
                weighted_den += sample
            if avg_value is not None:
                avg_daily.append(float(avg_value))
            median_value = row["pr_daily_median_lead_time_hours"]
            if median_value is not None:
                median_daily.append(float(median_value))
        out.append(
            {
                "project_key": project_key,
                "weighted_avg_lead_time_hours": round(weighted_num / weighted_den, 4)
                if weighted_den
                else None,
                "avg_lead_time_hours": round(_avg(avg_daily), 4)
                if avg_daily
                else None,
                "median_lead_time_hours": round(_median(median_daily), 4)
                if median_daily
                else None,
                "lead_time_sample_size": weighted_den,
            }
        )
    selected = _select_anchor_peer_group(
        out,
        anchor_project_key=anchor_project_key,
        max_projects=max_projects,
        metric_field=metric_field,
    )
    return selected


def _mk_template_wp3_merge_rate(
    wrk_205d_repo_summary: list[dict[str, Any]],
    *,
    anchor_project_key: str,
    max_projects: int,
    metric_field: str,
) -> list[dict[str, Any]]:
    annotated: list[dict[str, Any]] = []
    for row in wrk_205d_repo_summary:
        opened = int(row["total_opened_pr"])
        merged = int(row["total_merged_pr"])
        annotated.append(
            {
                "project_key": row["project_key"],
                "total_opened_pr": opened,
                "total_merged_pr": merged,
                "merge_rate_pct": round((merged / opened) * 100, 4)
                if opened
                else None,
            }
        )
    selected = _select_anchor_peer_group(
        annotated,
        anchor_project_key=anchor_project_key,
        max_projects=max_projects,
        metric_field=metric_field,
    )
    return selected


def _mk_template_wp4_backlog(
    wrk_205d_repo_summary: list[dict[str, Any]],
    *,
    anchor_project_key: str,
    max_projects: int,
    metric_field: str,
) -> list[dict[str, Any]]:
    selected = _select_anchor_peer_group(
        wrk_205d_repo_summary,
        anchor_project_key=anchor_project_key,
        max_projects=max_projects,
        metric_field=metric_field,
    )
    return [
        {"project_key": row["project_key"], "avg_active_pr": row["avg_active_pr"]}
        for row in selected
    ]


def _mk_template_wp5_pr_daily(wrk_205d_venom: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for row in wrk_205d_venom:
        out.append(
            {
                "date": row["date"],
                "project_key": row.get("project_key", "mpieniak01/Venom"),
                "pr_opened_count_daily": row["pr_opened_count_daily"],
                "pr_merged_count_daily": row["pr_merged_count_daily"],
                "pr_closed_not_merged_daily": row["pr_closed_not_merged_daily"],
                **_phase_columns(row["date"], PHASE_BACKGROUND_VALUE),
            }
        )
    return out


def _mk_template_wp6_lead_time(wrk_205d_venom: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    productive_rows = [
        row for row in wrk_205d_venom if int(row.get("lead_time_sample_size") or 0) > 0
    ]
    weighted_avg_num = 0.0
    weighted_avg_den = 0
    avg_daily: list[float] = []
    median_daily: list[float] = []
    for row in productive_rows:
        sample = int(row.get("lead_time_sample_size") or 0)
        avg_value = row.get("pr_daily_avg_lead_time_hours")
        if avg_value is not None:
            avg_daily.append(float(avg_value))
            weighted_avg_num += float(avg_value) * sample
            weighted_avg_den += sample
        median_value = row.get("pr_daily_median_lead_time_hours")
        if median_value is not None:
            median_daily.append(float(median_value))

    period_avg_ref = (
        round(weighted_avg_num / weighted_avg_den, 4)
        if weighted_avg_den
        else (round(_avg(avg_daily), 4) if avg_daily else None)
    )
    period_median_ref = round(_median(median_daily), 4) if median_daily else None

    for row in wrk_205d_venom:
        out.append(
            {
                "date": row["date"],
                "project_key": row.get("project_key", "mpieniak01/Venom"),
                "pr_daily_avg_lead_time_hours": row["pr_daily_avg_lead_time_hours"],
                "pr_daily_median_lead_time_hours": row[
                    "pr_daily_median_lead_time_hours"
                ],
                "lead_time_sample_size": row.get("lead_time_sample_size"),
                "period_avg_lead_time_hours_ref": period_avg_ref,
                "period_median_lead_time_hours_ref": period_median_ref,
                **_phase_columns(row["date"], PHASE_BACKGROUND_VALUE),
            }
        )
    return out


def _mk_wrk_205d_repo_summary(src_205d: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_project: dict[str, list[dict[str, Any]]] = {}
    for row in src_205d:
        by_project.setdefault(row["project_key"], []).append(row)

    out: list[dict[str, Any]] = []
    for project_key in sorted(by_project):
        items = by_project[project_key]
        active = [float(r["pr_active_daily"]) for r in items]
        median_lead_non_null = [
            float(v)
            for v in (r["pr_daily_median_lead_time_hours"] for r in items)
            if v is not None
        ]
        avg_lead_non_null = [
            float(v)
            for v in (r["pr_daily_avg_lead_time_hours"] for r in items)
            if v is not None
        ]
        total_opened = sum(int(r["pr_opened_count_daily"]) for r in items)
        total_merged = sum(int(r["pr_merged_count_daily"]) for r in items)
        total_closed_not_merged = sum(
            int(r["pr_closed_not_merged_daily"]) for r in items
        )

        out.append(
            {
                "project_key": project_key,
                "days_in_window": len(items),
                "avg_active_pr": round(sum(active) / len(active), 4)
                if active
                else None,
                "median_lead_time_hours": round(_median(median_lead_non_null), 4)
                if median_lead_non_null
                else None,
                "avg_lead_time_hours": round(
                    sum(avg_lead_non_null) / len(avg_lead_non_null), 4
                )
                if avg_lead_non_null
                else None,
                "total_opened_pr": total_opened,
                "total_merged_pr": total_merged,
                "total_closed_not_merged_pr": total_closed_not_merged,
            }
        )
    return out


def _mk_wrk_summary_benchmark(
    src_205b: list[dict[str, Any]], src_205c: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []

    b_groups: dict[str, list[dict[str, Any]]] = {}
    for row in src_205b:
        b_groups.setdefault(row["project_key"], []).append(row)
    for project_key, items in sorted(b_groups.items()):
        issues = [float(x["issues"]) for x in items if x["issues"] is not None]
        debt = [
            float(x["technical_debt_days"])
            for x in items
            if x["technical_debt_days"] is not None
        ]
        loc = [
            float(x["lines_of_code"]) for x in items if x["lines_of_code"] is not None
        ]
        cov = [
            float(x["line_coverage_pct"])
            for x in items
            if x["line_coverage_pct"] is not None
        ]
        tests = [float(x["unit_tests"]) for x in items if x["unit_tests"] is not None]

        metrics: dict[str, float | None] = {
            "issues_avg_q1": _avg(issues),
            "technical_debt_days_avg_q1": _avg(debt),
            "lines_of_code_avg_q1": _avg(loc),
            "line_coverage_pct_avg_q1": _avg(cov),
            "unit_tests_avg_q1": _avg(tests),
        }
        for metric_name, metric_value in metrics.items():
            out.append(
                {
                    "source_domain": "sonarqube",
                    "project_key": project_key,
                    "metric_name": metric_name,
                    "metric_value": round(metric_value, 4)
                    if metric_value is not None
                    else None,
                }
            )

    c_groups: dict[str, list[dict[str, Any]]] = {}
    for row in src_205c:
        c_groups.setdefault(row["project_key"], []).append(row)
    for project_key, items in sorted(c_groups.items()):
        commits = [float(x["commits"]) for x in items]
        authors = [float(x["authors"]) for x in items]
        additions = [float(x["additions"]) for x in items]
        deletions = [float(x["deletions"]) for x in items]
        churn = [float(x["churn"]) for x in items]
        truncated_days = sum(1 for x in items if bool(x["truncated"]))

        metrics2: dict[str, float | None] = {
            "commits_sum_q1": sum(commits),
            "authors_avg_q1": _avg(authors),
            "additions_sum_q1": sum(additions),
            "deletions_sum_q1": sum(deletions),
            "churn_sum_q1": sum(churn),
            "truncated_days_q1": float(truncated_days),
        }
        for metric_name, metric_value in metrics2.items():
            out.append(
                {
                    "source_domain": "github",
                    "project_key": project_key,
                    "metric_name": metric_name,
                    "metric_value": round(metric_value, 4)
                    if metric_value is not None
                    else None,
                }
            )
    return out


def _avg(values: list[float]) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)


def _median(values: list[float]) -> float:
    sorted_vals = sorted(values)
    n = len(sorted_vals)
    mid = n // 2
    if n % 2 == 1:
        return sorted_vals[mid]
    return (sorted_vals[mid - 1] + sorted_vals[mid]) / 2.0


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def _write_flat_csv(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    headers = ["table_name", "row_index", "row_json"]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        for table_name in sorted(payload["tables"]):
            rows = payload["tables"][table_name]
            for idx, row in enumerate(rows, start=1):
                writer.writerow(
                    {
                        "table_name": table_name,
                        "row_index": idx,
                        "row_json": json.dumps(
                            row, ensure_ascii=False, separators=(",", ":")
                        ),
                    }
                )


def main() -> int:
    args = _parse_args()
    repo_root = repo_root_from_script(__file__)
    cfg = load_pipeline_config(args.config, __file__)
    script_cfg = cfg_get(cfg, "scripts", "prepare_sources", default={}) or {}
    dataset_id = choose_dataset_value(
        cfg,
        "visualization_sources_pack",
        "dataset_id",
        args.dataset_id,
        script_cfg,
        "visualization_sources_pack",
    )

    args.in_205b = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "in_205b",
        args.in_205b,
        script_cfg,
        "artifacts/products_light/sonar_market/timeseries_agg_2026_v01.csv",
        for_input=True,
    )
    args.in_205c = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "in_205c",
        args.in_205c,
        script_cfg,
        "artifacts/products_light/github_market/timeseries_agg_2026_v01.csv",
        for_input=True,
    )
    args.in_205d = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "in_205d",
        args.in_205d,
        script_cfg,
        "artifacts/products_light/pr_flow/timeseries_agg_2026_v01.csv",
        for_input=True,
    )
    args.in_205e_daily = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "in_205e_daily",
        args.in_205e_daily,
        script_cfg,
        "artifacts/products_light/pr_comments/comments_daily_2026_v01.csv",
        for_input=True,
    )
    args.layout_csv = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "layout_csv",
        args.layout_csv,
        script_cfg,
        "artifacts/inputs/visualization/excel_sheet_layout_v01.csv",
        for_input=True,
    )
    args.venom_205b_key = choose_dataset_value(
        cfg,
        dataset_id,
        "venom_205b_key",
        args.venom_205b_key,
        script_cfg,
        "mpieniak01_Venom",
    )
    args.venom_205d_key = choose_dataset_value(
        cfg,
        dataset_id,
        "venom_205d_key",
        args.venom_205d_key,
        script_cfg,
        "mpieniak01/Venom",
    )
    args.venom_205c_key = choose_dataset_value(
        cfg,
        dataset_id,
        "venom_205c_key",
        args.venom_205c_key,
        script_cfg,
        "mpieniak01/Venom",
    )
    comparison_cfg = cfg_get(cfg, "process", "steps", dataset_id, default={}) or {}
    comparison_anchor_project_key = str(
        comparison_cfg.get("comparison_anchor_project_key") or args.venom_205d_key
    )
    comparison_peer_group_size = int(
        comparison_cfg.get("comparison_peer_group_size") or 6
    )
    comparison_metrics = comparison_cfg.get("comparison_metrics")
    if not isinstance(comparison_metrics, dict):
        comparison_metrics = {}
    args.out_json = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "out_json",
        args.out_json,
        script_cfg,
        "artifacts/processing/visualization/sources_pack_v01.json",
    )
    args.out_csv = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "out_csv",
        args.out_csv,
        script_cfg,
        "artifacts/processing/visualization/sources_pack_v01.csv",
    )
    date_from = dt.date.fromisoformat(args.date_from)
    date_to = dt.date.fromisoformat(args.date_to)
    if date_to < date_from:
        raise RuntimeError("--date-to must be >= --date-from")

    path_205b = Path(args.in_205b)
    path_205c = Path(args.in_205c)
    path_205d = Path(args.in_205d)
    path_205e = Path(args.in_205e_daily)
    path_layout = Path(args.layout_csv)

    rows_205b = _read_csv(path_205b)
    rows_205c = _read_csv(path_205c)
    rows_205d = _read_csv(path_205d)
    rows_205e = _read_csv(path_205e)
    rows_layout = _read_csv(path_layout)

    _ensure_columns(rows_205b, REQUIRED_COLUMNS["205B"], "205B")
    _ensure_columns(rows_205c, REQUIRED_COLUMNS["205C"], "205C")
    _ensure_columns(rows_205d, REQUIRED_COLUMNS["205D"], "205D")
    _ensure_columns(rows_205e, REQUIRED_COLUMNS["205E"], "205E")

    rows_205b, b_out_of_range = _filter_date_range(rows_205b, date_from, date_to)
    rows_205c, c_out_of_range = _filter_date_range(rows_205c, date_from, date_to)
    rows_205d, d_out_of_range = _filter_date_range(rows_205d, date_from, date_to)
    rows_205e, e_out_of_range = _filter_date_range(rows_205e, date_from, date_to)

    src_205b = _std_205b(rows_205b)
    src_205c = _std_205c(rows_205c)
    src_205d = _std_205d(rows_205d)
    src_205e_daily = _std_205e(rows_205e)
    src_205c_venom = _rows_for_project(src_205c, args.venom_205c_key)
    if not src_205c_venom:
        raise RuntimeError(
            f"Missing {args.venom_205c_key} in 205C GitHub API timeseries. "
            "Run github_market_benchmark.py for repo list including Venom before S01."
        )
    w33_code_flow_source = "src_205C_timeseries"
    w33_code_flow_project = args.venom_205c_key

    wrk_205b_venom = [
        row for row in src_205b if row["project_key"] == args.venom_205b_key
    ]
    wrk_205d_venom = [
        row for row in src_205d if row["project_key"] == args.venom_205d_key
    ]
    wrk_205d_repo_summary = _mk_wrk_205d_repo_summary(src_205d)
    wrk_205e_comments_daily = list(src_205e_daily)
    wrk_summary_benchmark = _mk_wrk_summary_benchmark(src_205b, src_205c)

    tpl_w31_commits = _mk_template_w31_commits(src_205c)
    tpl_w32_additions = _mk_template_w32_additions(src_205c)
    tpl_w36_debt_projects = _mk_template_w36_debt(src_205b)
    tpl_w37_debt_issues = _mk_template_w37_debt_issues(wrk_205b_venom)
    tpl_w35_quality = _mk_template_w35_quality(wrk_205b_venom)
    tpl_w42_phase2_quality = _mk_template_w42_phase2_quality(wrk_205b_venom)
    tpl_w43_phase2_debt_coverage = _mk_template_w43_phase2_debt_coverage(
        wrk_205b_venom
    )
    tpl_w33_code_flow = _mk_template_w33_code_flow(
        src_205c_venom,
        args.venom_205c_key,
    )
    tpl_wp1_pr_volume = _mk_template_wp1_pr_volume(
        wrk_205d_repo_summary,
        anchor_project_key=comparison_anchor_project_key,
        max_projects=comparison_peer_group_size,
        metric_field=str(
            comparison_metrics.get("tpl_WP1_pr_volume") or "total_opened_pr"
        ),
    )
    tpl_wp2_lead_time = _mk_template_wp2_lead_time(
        src_205d,
        anchor_project_key=comparison_anchor_project_key,
        max_projects=comparison_peer_group_size,
        metric_field=str(
            comparison_metrics.get("tpl_WP2_lead_time")
            or "weighted_avg_lead_time_hours"
        ),
    )
    tpl_wp3_merge_rate = _mk_template_wp3_merge_rate(
        wrk_205d_repo_summary,
        anchor_project_key=comparison_anchor_project_key,
        max_projects=comparison_peer_group_size,
        metric_field=str(
            comparison_metrics.get("tpl_WP3_merge_rate") or "merge_rate_pct"
        ),
    )
    tpl_wp4_backlog = _mk_template_wp4_backlog(
        wrk_205d_repo_summary,
        anchor_project_key=comparison_anchor_project_key,
        max_projects=comparison_peer_group_size,
        metric_field=str(comparison_metrics.get("tpl_WP4_backlog") or "avg_active_pr"),
    )
    tpl_wp5_pr_daily = _mk_template_wp5_pr_daily(wrk_205d_venom)
    tpl_wp6_lead_time = _mk_template_wp6_lead_time(wrk_205d_venom)

    tables: dict[str, list[dict[str, Any]]] = {
        "layout_205F_excel_sheet_layout": rows_layout,
        "src_205B_timeseries": src_205b,
        "src_205C_timeseries": src_205c,
        "src_205D_timeseries": src_205d,
        "src_205E_daily": src_205e_daily,
        "wrk_205B_venom": wrk_205b_venom,
        "wrk_205D_venom": wrk_205d_venom,
        "wrk_205D_repo_summary": wrk_205d_repo_summary,
        "wrk_205E_comments_daily": wrk_205e_comments_daily,
        "wrk_summary_benchmark": wrk_summary_benchmark,
        "tpl_W31_commits": tpl_w31_commits,
        "tpl_W32_additions": tpl_w32_additions,
        "tpl_W36_debt_projects": tpl_w36_debt_projects,
        "tpl_W37_debt_issues": tpl_w37_debt_issues,
        "tpl_W35_quality": tpl_w35_quality,
        "tpl_W42_phase2_quality": tpl_w42_phase2_quality,
        "tpl_W43_phase2_debt_coverage": tpl_w43_phase2_debt_coverage,
        "tpl_W33_code_flow": tpl_w33_code_flow,
        "tpl_WP1_pr_volume": tpl_wp1_pr_volume,
        "tpl_WP2_lead_time": tpl_wp2_lead_time,
        "tpl_WP3_merge_rate": tpl_wp3_merge_rate,
        "tpl_WP4_backlog": tpl_wp4_backlog,
        "tpl_WP5_pr_daily": tpl_wp5_pr_daily,
        "tpl_WP6_lead_time": tpl_wp6_lead_time,
    }

    validation = {
        "date_window": {"from": args.date_from, "to": args.date_to},
        "out_of_range_rows": {
            "205B": b_out_of_range,
            "205C": c_out_of_range,
            "205D": d_out_of_range,
            "205E": e_out_of_range,
        },
        "duplicate_project_date": {
            "205B": _duplicate_count(rows_205b),
            "205C": _duplicate_count(rows_205c),
            "205D": _duplicate_count(rows_205d),
            "205E": _duplicate_count(rows_205e),
        },
        "row_counts": {name: len(rows) for name, rows in tables.items()},
        "checks": {
            "required_columns_present": True,
            "date_range_filtered": True,
            "duplicate_key_check_done": True,
            "venom_205c_present_in_github_market": bool(src_205c_venom),
            "venom_205c_key_fallback_used": False,
            "comparison_anchor_project_key": comparison_anchor_project_key,
            "comparison_peer_group_size": comparison_peer_group_size,
        },
        "source_keys": {
            "venom_205b_key": args.venom_205b_key,
            "venom_205c_key_requested": args.venom_205c_key,
            "venom_205c_key_effective": args.venom_205c_key,
            "w33_code_flow_source": w33_code_flow_source,
            "w33_code_flow_project": w33_code_flow_project,
            "venom_205d_key": args.venom_205d_key,
        },
    }

    payload = {
        "artifact": "205F_sources_pack",
        "version": "v01",
        "generated_at": dt.datetime.now(dt.UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "inputs": {
            "in_205b": str(path_205b),
            "in_205c": str(path_205c),
            "in_205d": str(path_205d),
            "in_205e_daily": str(path_205e),
            "layout_csv": str(path_layout),
            "venom_205b_key": args.venom_205b_key,
            "venom_205c_key": args.venom_205c_key,
            "venom_205c_key_effective": args.venom_205c_key,
            "venom_205d_key": args.venom_205d_key,
        },
        "validation": validation,
        "tables": tables,
    }

    out_json = Path(args.out_json)
    out_csv = Path(args.out_csv)
    _write_json(out_json, payload)
    _write_flat_csv(out_csv, payload)

    print(f"[S01] JSON: {out_json}")
    print(f"[S01] CSV:  {out_csv}")
    print(f"[S01] Row counts: {validation['row_counts']}")
    print(f"[S01] Duplicate key counts: {validation['duplicate_project_date']}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
