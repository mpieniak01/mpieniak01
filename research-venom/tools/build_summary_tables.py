#!/usr/bin/env python3
"""S02: Build summary tables from the source pack.

Outputs:
- Single long CSV with summary metrics ready for Excel import
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
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


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build summary tables from sources pack."
    )
    parser.add_argument(
        "--config",
        default="config/process_pipeline_v01.json",
        help="Central pipeline config path (relative to repo root or absolute).",
    )
    parser.add_argument(
        "--dataset-id",
        default="",
        help="Dataset identifier from config.process.steps (default: visualization_summary_tables).",
    )
    parser.add_argument(
        "--in-pack-json",
        default="",
    )
    parser.add_argument(
        "--chart-spec-json",
        default="",
    )
    parser.add_argument(
        "--style-profile-json",
        default="",
    )
    parser.add_argument(
        "--control-profile-json",
        default="",
    )
    parser.add_argument(
        "--out-summary-csv",
        default="",
    )
    return parser.parse_args()


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _avg(values: list[float]) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)


def _median(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    n = len(ordered)
    mid = n // 2
    if n % 2 == 1:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2.0


def _as_float(value: Any) -> float | None:
    if value is None:
        return None
    return float(value)


def _as_int(value: Any) -> int | None:
    if value is None:
        return None
    return int(value)




def _chart_series_definitions(chart: dict[str, Any]) -> list[tuple[str, str, str]]:
    defs: list[tuple[str, str, str]] = []
    x_field = str(chart.get("x_series") or chart.get("category_field") or chart.get("category_series") or "").strip()
    if x_field:
        defs.append(("x", x_field, ""))

    plan = chart.get("series_plan") or []
    if plan:
        for item in plan:
            if isinstance(item, dict):
                if item.get("hidden") is True or item.get("render") is False:
                    continue
                field = str(item.get("field") or item.get("name") or item.get("series") or "").strip()
                if not field:
                    continue
                role = str(item.get("role") or "y").strip() or "y"
                label = str(item.get("label") or "").strip()
                defs.append((role, field, label))
        return defs

    y_series = [str(v) for v in (chart.get("y_series") or []) if str(v)]
    labels = [str(v) for v in (chart.get("series_labels") or []) if str(v)]
    for idx, field in enumerate(y_series):
        label = labels[idx] if idx < len(labels) else ""
        defs.append(("y", field, label))
    return defs

def _append_metric(
    out: list[dict[str, Any]],
    *,
    table_name: str,
    metric_scope: str,
    project_key: str,
    metric_name: str,
    metric_value: float | int | None,
    aggregation: str,
    source_table: str,
    sample_size: int | None,
    notes: str = "",
) -> None:
    out.append(
        {
            "table_name": table_name,
            "metric_scope": metric_scope,
            "project_key": project_key,
            "metric_name": metric_name,
            "metric_value": metric_value,
            "aggregation": aggregation,
            "source_table": source_table,
            "sample_size": sample_size,
            "notes": notes,
        }
    )


def _build_summary_rows(pack: dict[str, Any]) -> list[dict[str, Any]]:
    tables = pack.get("tables") or {}
    out: list[dict[str, Any]] = []

    src_205b = tables.get("src_205B_timeseries") or []
    src_205c = tables.get("src_205C_timeseries") or []
    src_205d = tables.get("src_205D_timeseries") or []
    src_205e = tables.get("src_205E_daily") or []

    # 1) KPI per project for 205B
    by_205b: dict[str, list[dict[str, Any]]] = {}
    for row in src_205b:
        by_205b.setdefault(str(row["project_key"]), []).append(row)
    for project_key in sorted(by_205b):
        rows = by_205b[project_key]
        _append_metric(
            out,
            table_name="summary_205B_project_kpi",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="issues_avg_q1",
            metric_value=round(
                _avg([float(r["issues"]) for r in rows if r["issues"] is not None])
                or 0.0,
                4,
            ),
            aggregation="avg",
            source_table="src_205B_timeseries",
            sample_size=len(rows),
        )
        _append_metric(
            out,
            table_name="summary_205B_project_kpi",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="technical_debt_days_avg_q1",
            metric_value=round(
                _avg(
                    [
                        float(r["technical_debt_days"])
                        for r in rows
                        if r["technical_debt_days"] is not None
                    ]
                )
                or 0.0,
                4,
            ),
            aggregation="avg",
            source_table="src_205B_timeseries",
            sample_size=len(rows),
        )
        _append_metric(
            out,
            table_name="summary_205B_project_kpi",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="lines_of_code_max_q1",
            metric_value=max(
                float(r["lines_of_code"])
                for r in rows
                if r["lines_of_code"] is not None
            ),
            aggregation="max",
            source_table="src_205B_timeseries",
            sample_size=len(rows),
        )
        _append_metric(
            out,
            table_name="summary_205B_project_kpi",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="line_coverage_pct_avg_q1",
            metric_value=round(
                _avg(
                    [
                        float(r["line_coverage_pct"])
                        for r in rows
                        if r["line_coverage_pct"] is not None
                    ]
                )
                or 0.0,
                4,
            ),
            aggregation="avg",
            source_table="src_205B_timeseries",
            sample_size=len(rows),
        )

    # 2) Velocity per project for 205C
    by_205c: dict[str, list[dict[str, Any]]] = {}
    for row in src_205c:
        by_205c.setdefault(str(row["project_key"]), []).append(row)
    for project_key in sorted(by_205c):
        rows = by_205c[project_key]
        _append_metric(
            out,
            table_name="summary_205C_project_velocity",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="commits_sum_q1",
            metric_value=sum(float(r["commits"]) for r in rows),
            aggregation="sum",
            source_table="src_205C_timeseries",
            sample_size=len(rows),
        )
        _append_metric(
            out,
            table_name="summary_205C_project_velocity",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="churn_sum_q1",
            metric_value=sum(float(r["churn"]) for r in rows),
            aggregation="sum",
            source_table="src_205C_timeseries",
            sample_size=len(rows),
        )
        _append_metric(
            out,
            table_name="summary_205C_project_velocity",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="authors_avg_daily_q1",
            metric_value=round(_avg([float(r["authors"]) for r in rows]) or 0.0, 4),
            aggregation="avg",
            source_table="src_205C_timeseries",
            sample_size=len(rows),
        )

    # 3) PR flow quality per project for 205D
    by_205d: dict[str, list[dict[str, Any]]] = {}
    for row in src_205d:
        by_205d.setdefault(str(row["project_key"]), []).append(row)
    for project_key in sorted(by_205d):
        rows = by_205d[project_key]
        median_daily = [
            float(v)
            for v in (_as_float(r["pr_daily_median_lead_time_hours"]) for r in rows)
            if v is not None
        ]
        avg_daily = [
            float(v)
            for v in (_as_float(r["pr_daily_avg_lead_time_hours"]) for r in rows)
            if v is not None
        ]
        _append_metric(
            out,
            table_name="summary_205D_project_pr_flow",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="pr_opened_sum_q1",
            metric_value=sum(float(r["pr_opened_count_daily"]) for r in rows),
            aggregation="sum",
            source_table="src_205D_timeseries",
            sample_size=len(rows),
        )
        _append_metric(
            out,
            table_name="summary_205D_project_pr_flow",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="pr_merged_sum_q1",
            metric_value=sum(float(r["pr_merged_count_daily"]) for r in rows),
            aggregation="sum",
            source_table="src_205D_timeseries",
            sample_size=len(rows),
        )
        _append_metric(
            out,
            table_name="summary_205D_project_pr_flow",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="pr_active_avg_daily_q1",
            metric_value=round(
                _avg([float(r["pr_active_daily"]) for r in rows]) or 0.0, 4
            ),
            aggregation="avg",
            source_table="src_205D_timeseries",
            sample_size=len(rows),
        )
        _append_metric(
            out,
            table_name="summary_205D_project_pr_flow",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="pr_median_lead_time_hours_q1",
            metric_value=round(_median(median_daily) or 0.0, 4),
            aggregation="median",
            source_table="src_205D_timeseries",
            sample_size=len(median_daily),
            notes="median z dziennych median lead time",
        )
        _append_metric(
            out,
            table_name="summary_205D_project_pr_flow",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="pr_avg_lead_time_hours_q1",
            metric_value=round(_avg(avg_daily) or 0.0, 4),
            aggregation="avg",
            source_table="src_205D_timeseries",
            sample_size=len(avg_daily),
            notes="avg z dziennych avg lead time",
        )

    # 4) Comments quality for 205E (Venom)
    by_205e: dict[str, list[dict[str, Any]]] = {}
    for row in src_205e:
        by_205e.setdefault(str(row["project_key"]), []).append(row)
    for project_key in sorted(by_205e):
        rows = by_205e[project_key]
        avg_closed = [
            float(v)
            for v in (_as_float(r["avg_comments_closed_daily"]) for r in rows)
            if v is not None
        ]
        avg_merged = [
            float(v)
            for v in (_as_float(r["avg_comments_merged_daily"]) for r in rows)
            if v is not None
        ]
        median_closed = [
            float(v)
            for v in (_as_float(r["median_comments_closed_daily"]) for r in rows)
            if v is not None
        ]
        _append_metric(
            out,
            table_name="summary_205E_project_comments",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="closed_pr_sum_q1",
            metric_value=sum(float(r["closed_pr_count_daily"]) for r in rows),
            aggregation="sum",
            source_table="src_205E_daily",
            sample_size=len(rows),
        )
        _append_metric(
            out,
            table_name="summary_205E_project_comments",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="merged_pr_sum_q1",
            metric_value=sum(float(r["merged_pr_count_daily"]) for r in rows),
            aggregation="sum",
            source_table="src_205E_daily",
            sample_size=len(rows),
        )
        _append_metric(
            out,
            table_name="summary_205E_project_comments",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="avg_comments_closed_daily_q1",
            metric_value=round(_avg(avg_closed) or 0.0, 4),
            aggregation="avg",
            source_table="src_205E_daily",
            sample_size=len(avg_closed),
        )
        _append_metric(
            out,
            table_name="summary_205E_project_comments",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="avg_comments_merged_daily_q1",
            metric_value=round(_avg(avg_merged) or 0.0, 4),
            aggregation="avg",
            source_table="src_205E_daily",
            sample_size=len(avg_merged),
        )
        _append_metric(
            out,
            table_name="summary_205E_project_comments",
            metric_scope="project_q1",
            project_key=project_key,
            metric_name="median_comments_closed_daily_q1",
            metric_value=round(_median(median_closed) or 0.0, 4),
            aggregation="median",
            source_table="src_205E_daily",
            sample_size=len(median_closed),
        )

    return out


def _chart_sources_check(
    pack: dict[str, Any], chart_spec: dict[str, Any]
) -> list[dict[str, Any]]:
    available_tables = set((pack.get("tables") or {}).keys())
    chart_rows: list[dict[str, Any]] = []
    for chart in chart_spec.get("charts", []):
        chart_id = str(chart.get("chart_id", ""))
        source_sheet = str(chart.get("source_sheet", ""))
        status = "ok" if source_sheet in available_tables else "missing_source_table"
        chart_rows.append(
            {
                "table_name": "summary_chart_sources_check",
                "metric_scope": "chart_source_check",
                "project_key": "",
                "metric_name": chart_id,
                "metric_value": "",
                "aggregation": status,
                "source_table": source_sheet,
                "sample_size": "",
                "notes": "",
            }
        )
    return chart_rows


def _series_nonnull_ratio(rows: list[dict[str, Any]], field_name: str) -> tuple[int, int, bool]:
    has_any_key = any(field_name in row for row in rows)
    nonnull = 0
    for row in rows:
        if field_name not in row:
            continue
        value = row.get(field_name)
        if value is None:
            continue
        if isinstance(value, str) and not value.strip():
            continue
        nonnull += 1
    if has_any_key:
        return nonnull, len(rows), True

    # Some source tables are kept in long form with metric_name/metric_value and
    # only transformed to wide during workbook build. In that case, series fields
    # from chart spec map to metric_name values.
    has_long_metric_shape = any(
        ("metric_name" in row) and ("metric_value" in row) for row in rows
    )
    if not has_long_metric_shape:
        return nonnull, len(rows), False

    matching_rows = [
        row for row in rows if str(row.get("metric_name") or "").strip() == field_name
    ]
    if not matching_rows:
        return 0, len(rows), False

    metric_nonnull = 0
    for row in matching_rows:
        value = row.get("metric_value")
        if value is None:
            continue
        if isinstance(value, str) and not value.strip():
            continue
        metric_nonnull += 1
    return metric_nonnull, len(matching_rows), True


def _series_health_rows(
    pack: dict[str, Any],
    chart_spec: dict[str, Any],
    *,
    warn_ratio: float = 0.9,
    sparse_ratio: float = 0.5,
) -> list[dict[str, Any]]:
    tables = pack.get("tables") or {}
    out: list[dict[str, Any]] = []

    for chart in chart_spec.get("charts", []):
        chart_id = str(chart.get("chart_id", ""))
        source_sheet = str(chart.get("source_sheet", ""))
        rows = list(tables.get(source_sheet) or [])
        series_fields = _chart_series_definitions(chart)

        if not rows:
            out.append(
                {
                    "table_name": "summary_chart_series_check",
                    "metric_scope": "chart_series_check",
                    "project_key": chart_id,
                    "metric_name": f"{chart_id}:source",
                    "metric_value": "",
                    "aggregation": "source_no_rows",
                    "source_table": source_sheet,
                    "sample_size": "",
                    "notes": "",
                }
            )
            continue

        for role, field_name, label in series_fields:
            nonnull, total_rows, has_any_key = _series_nonnull_ratio(rows, field_name)
            if not has_any_key:
                status = "source_metric_missing"
                severity = "fail"
                ratio = ""
            elif nonnull == 0:
                ratio = 0.0
                if field_name.startswith("phase_"):
                    status = "series_all_null_background"
                    severity = "warn"
                elif role.startswith("optional"):
                    status = "series_all_null_optional"
                    severity = "warn"
                else:
                    status = "series_all_null"
                    severity = "fail"
            else:
                ratio = round(nonnull / total_rows, 4) if total_rows else 0.0
                if ratio < sparse_ratio:
                    status = "series_too_sparse"
                    severity = "warn"
                elif ratio < 1.0:
                    if ratio >= warn_ratio:
                        status = "series_partial_missing"
                        severity = "warn"
                    else:
                        status = "series_too_sparse"
                        severity = "warn"
                else:
                    status = "ok"
                    severity = "ok"

            notes = f"role={role};nonnull={nonnull};total={total_rows};ratio={ratio}"
            if label:
                notes += f";label={label}"
            notes += f";severity={severity}"
            out.append(
                {
                    "table_name": "summary_chart_series_check",
                    "metric_scope": "chart_series_check",
                    "project_key": chart_id,
                    "metric_name": f"{role}:{field_name}",
                    "metric_value": ratio,
                    "aggregation": status,
                    "source_table": source_sheet,
                    "sample_size": total_rows,
                    "notes": notes,
                }
            )
    return out


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    headers = [
        "table_name",
        "metric_scope",
        "project_key",
        "metric_name",
        "metric_value",
        "aggregation",
        "source_table",
        "sample_size",
        "notes",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        for row in rows:
            writer.writerow({h: row.get(h, "") for h in headers})


def main() -> int:
    args = _parse_args()
    repo_root = repo_root_from_script(__file__)
    cfg = load_pipeline_config(args.config, __file__)
    script_cfg = cfg_get(cfg, "scripts", "build_summary_tables", default={}) or {}
    dataset_id = choose_dataset_value(
        cfg,
        "visualization_summary_tables",
        "dataset_id",
        args.dataset_id,
        script_cfg,
        "visualization_summary_tables",
    )

    args.in_pack_json = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "in_pack_json",
        args.in_pack_json,
        script_cfg,
        "artifacts/processing/visualization/sources_pack_v01.json",
        for_input=True,
    )
    args.chart_spec_json = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "chart_spec_json",
        args.chart_spec_json,
        script_cfg,
        "artifacts/inputs/visualization/chart_spec_v04.json",
        for_input=True,
    )
    args.style_profile_json = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "chart_style_profile_json",
        args.style_profile_json,
        script_cfg,
        "artifacts/inputs/visualization/chart_style_profile_v04.json",
        for_input=True,
    )
    control_profile_key = "chart_control_profile_json"
    ds_control_profile = choose_dataset_value(
        cfg=cfg,
        dataset_id=dataset_id,
        key=control_profile_key,
        cli_value=args.control_profile_json,
        script_cfg=script_cfg,
        fallback="",
    )
    # Backward-compatible key used by older pipeline configs.
    if not ds_control_profile:
        control_profile_key = "control_profile_json"
    args.control_profile_json = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        control_profile_key,
        args.control_profile_json,
        script_cfg,
        "",
        for_input=True,
    )
    args.out_summary_csv = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "out_summary_csv",
        args.out_summary_csv,
        script_cfg,
        "artifacts/processing/visualization/summary_tables_v01.csv",
    )

    pack = _read_json(Path(args.in_pack_json))
    chart_spec = _read_json(Path(args.chart_spec_json))
    style_profile = _read_json(Path(args.style_profile_json)) if Path(args.style_profile_json).exists() else {}
    control_profile = _read_json(Path(args.control_profile_json)) if getattr(args, "control_profile_json", "") and Path(args.control_profile_json).exists() else {}
    validation = (control_profile.get("validation") or style_profile.get("validation") or {})
    warn_ratio = float(validation.get("series_nonnull_ratio_warn", 0.9))
    sparse_ratio = float(validation.get("series_nonnull_ratio_sparse", 0.5))

    summary_rows = _build_summary_rows(pack)
    chart_rows = _chart_sources_check(pack, chart_spec)
    series_rows = _series_health_rows(
        pack,
        chart_spec,
        warn_ratio=warn_ratio,
        sparse_ratio=sparse_ratio,
    )

    provenance_row = {
        "table_name": "summary_meta",
        "metric_scope": "provenance",
        "project_key": "",
        "metric_name": "generated_at_utc",
        "metric_value": dt.datetime.now(dt.UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "aggregation": "value",
        "source_table": Path(args.in_pack_json).name,
        "sample_size": "",
        "notes": Path(args.chart_spec_json).name,
    }

    all_rows = summary_rows + chart_rows + series_rows + [provenance_row]
    _write_csv(Path(args.out_summary_csv), all_rows)

    missing = [r["metric_name"] for r in chart_rows if r["aggregation"] != "ok"]
    series_failures = [r["metric_name"] for r in series_rows if r["aggregation"] in {"source_metric_missing", "series_all_null", "source_no_rows"}]
    series_warnings = [r["metric_name"] for r in series_rows if r["aggregation"] in {"series_partial_missing", "series_too_sparse", "series_all_null_background", "series_all_null_optional"}]
    print(f"[S02] CSV: {args.out_summary_csv}")
    print(f"[S02] Summary rows: {len(summary_rows)}")
    print(f"[S02] Chart source checks: {len(chart_rows)}, missing: {len(missing)}")
    print(f"[S02] Chart series checks: {len(series_rows)}, fail: {len(series_failures)}, warn: {len(series_warnings)}")
    if missing:
        print(f"[S02] Missing source tables for chart_id: {missing}")
    if series_failures:
        print(f"[S02] Series failures: {series_failures[:10]}")
    if series_warnings:
        print(f"[S02] Series warnings: {series_warnings[:10]}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
