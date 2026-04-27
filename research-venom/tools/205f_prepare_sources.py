#!/usr/bin/env python3
"""S01: Prepare standardized 205F source pack from 205B/205C/205D/205E inputs.

Outputs:
- JSON pack with source/work tables and validation report
- Flat CSV export (table_name + row payload) for easy audit/import
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import sys
from pathlib import Path
from typing import Any

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
    root = Path(__file__).resolve().parents[4]
    artifacts_root = root / "docs_dev" / "_to_do" / "205_artifacts"
    parser = argparse.ArgumentParser(description="Build 205F standardized source pack.")
    parser.add_argument(
        "--in-205b",
        default=str(
            artifacts_root / "205B" / "timeseries" / "205B_timeseries_q1_2026.csv"
        ),
    )
    parser.add_argument(
        "--in-205c",
        default=str(
            artifacts_root / "205C" / "timeseries" / "205C_github_benchmark_q1_2026.csv"
        ),
    )
    parser.add_argument(
        "--in-205d",
        default=str(
            artifacts_root / "205D" / "timeseries" / "205D_pr_flow_q1_2026.csv"
        ),
    )
    parser.add_argument(
        "--in-205e-daily",
        default=str(
            artifacts_root
            / "205E"
            / "timeseries"
            / "csv"
            / "205E_pr_comments_q1_2026_daily.csv"
        ),
    )
    parser.add_argument(
        "--layout-csv",
        default=str(
            artifacts_root / "205F" / "inputs" / "205F_excel_sheet_layout_v01.csv"
        ),
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
        default="mpieniak01_Venom",
    )
    parser.add_argument(
        "--venom-205d-key",
        default="mpieniak01/Venom",
    )
    parser.add_argument(
        "--out-json",
        default=str(
            artifacts_root / "produkty" / "meta" / "205F_sources_pack_v01.json"
        ),
    )
    parser.add_argument(
        "--out-csv",
        default=str(artifacts_root / "produkty" / "meta" / "205F_sources_pack_v01.csv"),
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
                    "source_series": "205B",
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
                    "source_series": "205C",
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

    wrk_205b_venom = [
        row for row in src_205b if row["project_key"] == args.venom_205b_key
    ]
    wrk_205d_venom = [
        row for row in src_205d if row["project_key"] == args.venom_205d_key
    ]
    wrk_205d_repo_summary = _mk_wrk_205d_repo_summary(src_205d)
    wrk_205e_comments_daily = list(src_205e_daily)
    wrk_summary_benchmark = _mk_wrk_summary_benchmark(src_205b, src_205c)

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
