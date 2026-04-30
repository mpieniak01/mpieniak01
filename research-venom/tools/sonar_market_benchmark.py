#!/usr/bin/env python3
"""Build SonarQube Cloud market benchmark dataset and report.

Required env secret:
- SONAR_TOKEN (Bearer token)
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import re
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from path_config import (
    choose_dataset_value,
    cfg_get,
    load_pipeline_config,
    repo_root_from_script,
    resolve_dataset_path,
)

DEFAULT_BASE_URL = "https://sonarcloud.io"
CORE_METRICS = ["violations", "sqale_index", "ncloc", "coverage", "tests"]
EXTENDED_METRICS = [
    "bugs",
    "vulnerabilities",
    "code_smells",
    "duplicated_lines_density",
    "sqale_rating",
    "reliability_rating",
    "security_rating",
    "complexity",
    "open_issues",
]
ALL_METRICS = ",".join(list(dict.fromkeys(CORE_METRICS + EXTENDED_METRICS)))
HISTORY_METRICS = "violations,open_issues,sqale_index,ncloc,coverage,tests"


class SonarApiError(RuntimeError):
    """Raised when Sonar API call fails after retries."""


@dataclass
class FetchConfig:
    base_url: str
    token: str
    timeout: float
    max_retries: int
    sleep_s: float


def _now_iso() -> str:
    return (
        dt.datetime.now(dt.UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def _safe_number(raw: str | None) -> float | None:
    if raw is None or raw == "":
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def _q1_median_q3(values: list[float]) -> dict[str, float]:
    if len(values) == 1:
        value = values[0]
        return {"q1": value, "median": value, "q3": value}
    qs = statistics.quantiles(values, n=4, method="inclusive")
    return {"q1": qs[0], "median": statistics.median(values), "q3": qs[2]}


def _percentile_position(
    values: list[float],
    value: float,
    higher_better: bool,
) -> float:
    if not values:
        return 0.0
    if higher_better:
        rank = sum(v <= value for v in values)
    else:
        rank = sum(v >= value for v in values)
    return (rank / len(values)) * 100.0


def _sanitize_md(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ").strip()


def _fmt(value: float | None, digits: int = 2) -> str:
    if value is None:
        return "-"
    return f"{float(value):.{digits}f}"


def _load_env_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    for raw_line in path.read_text("utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        values[key] = value
    return values


def _api_get(path: str, params: dict[str, Any], cfg: FetchConfig) -> dict[str, Any]:
    query = urllib.parse.urlencode(params, doseq=True)
    url = f"{cfg.base_url}{path}?{query}" if query else f"{cfg.base_url}{path}"
    headers = {
        "Accept": "application/json",
        "Authorization": f"Bearer {cfg.token}",
    }

    for attempt in range(cfg.max_retries):
        req = urllib.request.Request(url=url, headers=headers, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=cfg.timeout) as response:  # nosec B310
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            payload = ""
            try:
                payload = exc.read().decode("utf-8")
            except Exception:
                payload = ""
            retryable = exc.code in {408, 429, 500, 502, 503, 504}
            if retryable and attempt < cfg.max_retries - 1:
                time.sleep(2 * (attempt + 1))
                continue
            msg = payload[:300] if payload else exc.reason
            raise SonarApiError(f"HTTP {exc.code} for {url}: {msg}") from exc
        except urllib.error.URLError as exc:
            if attempt < cfg.max_retries - 1:
                time.sleep(2 * (attempt + 1))
                continue
            raise SonarApiError(f"Network error for {url}: {exc.reason}") from exc

    raise SonarApiError(f"Request failed after retries: {url}")


def _fetch_candidates(
    cfg: FetchConfig,
    *,
    organization: str | None,
    query: str | None,
    candidate_limit: int,
    page_size: int,
) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    page = 1

    while len(candidates) < candidate_limit:
        if organization:
            payload = _api_get(
                "/api/projects/search",
                {
                    "organization": organization,
                    "p": page,
                    "ps": page_size,
                },
                cfg,
            )
            items = payload.get("components", [])
        else:
            params: dict[str, Any] = {"p": page, "ps": page_size}
            if query:
                params["q"] = query
            payload = _api_get("/api/components/search_projects", params, cfg)
            items = payload.get("components", [])

        if not items:
            break

        for item in items:
            candidates.append(
                {
                    "key": item.get("key"),
                    "name": item.get("name") or item.get("key"),
                    "organization": item.get("organization"),
                }
            )
            if len(candidates) >= candidate_limit:
                break

        if len(items) < page_size:
            break
        page += 1
        if cfg.sleep_s > 0:
            time.sleep(cfg.sleep_s)

    return [c for c in candidates if c.get("key")]


def _fetch_measures(project_key: str, cfg: FetchConfig) -> dict[str, str]:
    payload = _api_get(
        "/api/measures/component",
        {"component": project_key, "metricKeys": ALL_METRICS},
        cfg,
    )
    component = payload.get("component", {})
    measures = component.get("measures", [])
    out: dict[str, str] = {}
    for measure in measures:
        key = measure.get("metric")
        value = measure.get("value")
        if key and isinstance(value, str):
            out[key] = value
    return out


def _to_record(candidate: dict[str, Any], raw: dict[str, str]) -> dict[str, Any]:
    issues_raw = _safe_number(raw.get("violations"))
    open_issues_raw = _safe_number(raw.get("open_issues"))
    sqale_index_minutes = _safe_number(raw.get("sqale_index"))
    ncloc = _safe_number(raw.get("ncloc"))
    coverage = _safe_number(raw.get("coverage"))
    tests = _safe_number(raw.get("tests"))

    issues = issues_raw if issues_raw is not None else open_issues_raw
    debt_days = (
        round(sqale_index_minutes / 480.0, 4)
        if sqale_index_minutes is not None
        else None
    )

    normalized = {
        "issues": issues,
        "technical_debt_days": debt_days,
        "lines_of_code": ncloc,
        "line_coverage_pct": coverage,
        "unit_tests": tests,
    }
    required_count = sum(1 for v in normalized.values() if v is not None)

    return {
        "project_key": candidate["key"],
        "project_name": candidate.get("name") or candidate["key"],
        "organization": candidate.get("organization"),
        "raw_metrics": raw,
        "normalized": normalized,
        "core_completeness": f"{required_count}/5",
        "core_complete": required_count == 5,
    }


def _safe_filename(text: str) -> str:
    return re.sub(r"[^a-zA-Z0-9._-]+", "_", text).strip("._-") or "project"


def _parse_sonar_datetime(value: str) -> dt.datetime:
    return dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%S%z")


def _fetch_metric_history(
    project_key: str,
    cfg: FetchConfig,
    *,
    from_ts: str,
    to_ts: str,
    page_size: int,
) -> dict[str, list[dict[str, Any]]]:
    page = 1
    history_by_metric: dict[str, list[dict[str, Any]]] = {}
    while True:
        payload = _api_get(
            "/api/measures/search_history",
            {
                "component": project_key,
                "metrics": HISTORY_METRICS,
                "from": from_ts,
                "to": to_ts,
                "p": page,
                "ps": page_size,
            },
            cfg,
        )
        for measure in payload.get("measures", []):
            metric = measure.get("metric")
            if not metric:
                continue
            history = measure.get("history", [])
            bucket = history_by_metric.setdefault(metric, [])
            bucket.extend(history if isinstance(history, list) else [])

        paging = payload.get("paging", {})
        total = int(paging.get("total", 0) or 0)
        page_index = int(paging.get("pageIndex", page) or page)
        ps = int(paging.get("pageSize", page_size) or page_size)
        if total == 0 or page_index * ps >= total:
            break
        page += 1
        if cfg.sleep_s > 0:
            time.sleep(cfg.sleep_s)

    for metric, points in history_by_metric.items():
        points.sort(key=lambda p: p.get("date", ""))
        deduped: dict[str, dict[str, Any]] = {}
        for point in points:
            date = point.get("date")
            if date:
                deduped[date] = point
        history_by_metric[metric] = [deduped[d] for d in sorted(deduped)]
    return history_by_metric


def _build_daily_rows(
    metric_history: dict[str, list[dict[str, Any]]],
    *,
    start_date: dt.date,
    end_date: dt.date,
) -> list[dict[str, Any]]:
    points_by_metric: dict[str, list[tuple[dt.date, float]]] = {}
    for metric, history in metric_history.items():
        entries: list[tuple[dt.date, float]] = []
        for point in history:
            value = _safe_number(point.get("value"))
            date_raw = point.get("date")
            if value is None or not date_raw:
                continue
            date = _parse_sonar_datetime(date_raw).date()
            entries.append((date, value))
        entries.sort(key=lambda x: x[0])
        collapsed: dict[dt.date, float] = {}
        for date, value in entries:
            collapsed[date] = value
        points_by_metric[metric] = [(d, collapsed[d]) for d in sorted(collapsed)]

    cursors = {m: 0 for m in points_by_metric}
    last_values: dict[str, float | None] = {m: None for m in points_by_metric}

    out: list[dict[str, Any]] = []
    current = start_date
    one_day = dt.timedelta(days=1)
    while current <= end_date:
        for metric, points in points_by_metric.items():
            i = cursors[metric]
            while i < len(points) and points[i][0] <= current:
                last_values[metric] = points[i][1]
                i += 1
            cursors[metric] = i

        issues = last_values.get("violations")
        if issues is None:
            issues = last_values.get("open_issues")
        sqale_index = last_values.get("sqale_index")
        technical_debt_days = (
            round(float(sqale_index) / 480.0, 4) if sqale_index is not None else None
        )
        row = {
            "date": current.isoformat(),
            "issues": issues,
            "technical_debt_days": technical_debt_days,
            "lines_of_code": last_values.get("ncloc"),
            "line_coverage_pct": last_values.get("coverage"),
            "unit_tests": last_values.get("tests"),
        }
        out.append(row)
        current += one_day
    return out


def _write_csv_rows(path: Path, rows: list[dict[str, Any]], headers: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=headers)
        writer.writeheader()
        for row in rows:
            formatted = {
                k: (
                    ""
                    if row.get(k) is None
                    else f"{row[k]:.4f}".rstrip("0").rstrip(".")
                    if isinstance(row.get(k), float)
                    else row.get(k)
                )
                for k in headers
            }
            writer.writerow(formatted)


def _run_timeseries_mode(
    args: argparse.Namespace,
    cfg: FetchConfig,
    *,
    explicit_keys: list[str],
    resolved_org: str,
    resolved_query: str,
) -> int:
    if not explicit_keys:
        raise SonarApiError(
            "Timeseries mode requires explicit project keys (--project-key or --project-key-file)."
        )

    start_date = dt.date.fromisoformat(args.from_date)
    end_date = dt.date.fromisoformat(args.to_date)
    if end_date < start_date:
        raise SonarApiError("--to-date must be >= --from-date")

    from_ts = f"{start_date.isoformat()}T00:00:00+0000"
    to_ts = f"{end_date.isoformat()}T23:59:59+0000"
    ts_root = Path(args.timeseries_dir)
    raw_dir = ts_root / "raw"
    csv_dir = ts_root / "csv"
    agg_csv_path = Path(args.aggregate_csv)
    output_json = Path(args.output_json)
    output_md = Path(args.output_md)

    project_summaries: list[dict[str, Any]] = []
    all_rows: list[dict[str, Any]] = []
    for idx, key in enumerate(explicit_keys, start=1):
        history = _fetch_metric_history(
            key,
            cfg,
            from_ts=from_ts,
            to_ts=to_ts,
            page_size=max(1, args.timeseries_page_size),
        )
        daily_rows = _build_daily_rows(
            history,
            start_date=start_date,
            end_date=end_date,
        )
        safe_name = _safe_filename(key)
        project_payload = {
            "project_key": key,
            "generated_at": _now_iso(),
            "source": {
                "base_url": cfg.base_url,
                "organization": resolved_org or None,
                "query": resolved_query or None,
                "from": from_ts,
                "to": to_ts,
                "metrics": HISTORY_METRICS.split(","),
            },
            "raw_history": history,
            "daily_rows": daily_rows,
        }
        _write_json(raw_dir / f"{safe_name}.json", project_payload)
        _write_csv_rows(
            csv_dir / f"{safe_name}.csv",
            daily_rows,
            headers=[
                "date",
                "issues",
                "technical_debt_days",
                "lines_of_code",
                "line_coverage_pct",
                "unit_tests",
            ],
        )

        non_empty_days = sum(
            1
            for row in daily_rows
            if any(
                row.get(col) is not None
                for col in [
                    "issues",
                    "technical_debt_days",
                    "lines_of_code",
                    "line_coverage_pct",
                    "unit_tests",
                ]
            )
        )
        project_summaries.append(
            {
                "project_key": key,
                "daily_rows": len(daily_rows),
                "non_empty_days": non_empty_days,
                "raw_json": str(raw_dir / f"{safe_name}.json"),
                "csv": str(csv_dir / f"{safe_name}.csv"),
            }
        )

        for row in daily_rows:
            all_rows.append({"project_key": key, **row})

        if cfg.sleep_s > 0 and idx < len(explicit_keys):
            time.sleep(cfg.sleep_s)

    _write_csv_rows(
        agg_csv_path,
        all_rows,
        headers=[
            "project_key",
            "date",
            "issues",
            "technical_debt_days",
            "lines_of_code",
            "line_coverage_pct",
            "unit_tests",
        ],
    )

    payload = {
        "generated_at": _now_iso(),
        "mode": "timeseries",
        "source": {
            "base_url": cfg.base_url,
            "organization": resolved_org or None,
            "query": resolved_query or None,
            "from": from_ts,
            "to": to_ts,
            "timeseries_dir": str(ts_root),
            "project_keys_explicit": explicit_keys,
        },
        "metrics": {
            "Issues": "violations (fallback: open_issues)",
            "Technical Debt (days)": "sqale_index / 480",
            "Lines of Code": "ncloc",
            "Line Coverage (%)": "coverage",
            "Unit Tests": "tests",
        },
        "projects": project_summaries,
        "aggregated_csv": str(agg_csv_path),
    }
    _write_json(output_json, payload)

    lines: list[str] = []
    lines.append("# sonar_market_benchmark_2026")
    lines.append("")
    lines.append(f"Data generacji: `{payload['generated_at']}`")
    lines.append("")
    lines.append("## Konfiguracja")
    lines.append("")
    lines.append(f"- `from`: `{from_ts}`")
    lines.append(f"- `to`: `{to_ts}`")
    lines.append(f"- `timeseries_dir`: `{ts_root}`")
    lines.append(f"- `projekty`: `{len(project_summaries)}`")
    lines.append("")
    lines.append("## Artefakty")
    lines.append("")
    lines.append(f"- `manifest json`: `{output_json}`")
    lines.append(f"- `aggregated csv`: `{agg_csv_path}`")
    lines.append(f"- `project raw json dir`: `{raw_dir}`")
    lines.append(f"- `project csv dir`: `{csv_dir}`")
    lines.append("")
    lines.append("## Projekty")
    lines.append("")
    lines.append("| Project Key | Daily Rows | Non-empty Days | CSV |")
    lines.append("|---|---:|---:|---|")
    for project in project_summaries:
        lines.append(
            f"| `{project['project_key']}` | {project['daily_rows']} | "
            f"{project['non_empty_days']} | `{project['csv']}` |"
        )
    output_md.parent.mkdir(parents=True, exist_ok=True)
    output_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Saved JSON manifest: {output_json}")
    print(f"Saved Markdown summary: {output_md}")
    print(f"Saved aggregated CSV: {agg_csv_path}")
    print(f"Saved per-project raw JSON dir: {raw_dir}")
    print(f"Saved per-project CSV dir: {csv_dir}")
    return 0


def _build_summary(
    records: list[dict[str, Any]],
    venom_project_key: str | None,
) -> dict[str, Any]:
    complete = [r for r in records if r["core_complete"]]
    summary: dict[str, Any] = {
        "total_projects": len(records),
        "core_complete_projects": len(complete),
        "core_coverage_ratio": f"{len(complete)}/{len(records)}" if records else "0/0",
        "core_metric_stats": {},
        "venom_position": None,
    }

    metric_cfg = {
        "issues": False,
        "technical_debt_days": False,
        "lines_of_code": True,
        "line_coverage_pct": True,
        "unit_tests": True,
    }
    for metric in metric_cfg:
        values = [
            float(r["normalized"][metric])
            for r in complete
            if r["normalized"].get(metric) is not None
        ]
        if values:
            summary["core_metric_stats"][metric] = _q1_median_q3(values)

    if not venom_project_key:
        return summary

    venom = next((r for r in records if r["project_key"] == venom_project_key), None)
    if not venom or not venom["core_complete"]:
        summary["venom_position"] = {
            "project_key": venom_project_key,
            "status": "missing_or_incomplete",
        }
        return summary

    venom_metrics = venom["normalized"]
    percentiles: dict[str, float] = {}
    for metric, higher_better in metric_cfg.items():
        value = venom_metrics.get(metric)
        if value is None:
            continue
        values = [
            float(r["normalized"][metric])
            for r in complete
            if r["normalized"].get(metric) is not None
        ]
        if values:
            percentiles[metric] = round(
                _percentile_position(values, float(value), higher_better),
                2,
            )

    summary["venom_position"] = {
        "project_key": venom_project_key,
        "status": "ok",
        "normalized": venom_metrics,
        "percentile_position": percentiles,
    }
    return summary


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", "utf-8")


def _write_markdown(
    path: Path,
    *,
    payload: dict[str, Any],
    top_rows: int,
) -> None:
    rows = payload["projects"]
    summary = payload["summary"]
    generated_at = payload["generated_at"]
    source = payload["source"]

    ranked = sorted(
        rows,
        key=lambda r: (
            0 if r["core_complete"] else 1,
            -(r["normalized"].get("line_coverage_pct") or -1),
        ),
    )
    ranked = ranked[:top_rows]

    lines: list[str] = []
    lines.append("# sonar_market_benchmark")
    lines.append("")
    lines.append(f"Data generacji: `{generated_at}`")
    lines.append("")
    lines.append("## Konfiguracja")
    lines.append("")
    lines.append(f"- `base_url`: `{source['base_url']}`")
    lines.append(f"- `organization`: `{source.get('organization') or '-'}`")
    lines.append(f"- `query`: `{source.get('query') or '-'}`")
    lines.append(f"- `project_limit`: `{source['project_limit']}`")
    lines.append(f"- `candidate_limit`: `{source.get('candidate_limit', '-')}`")
    lines.append(
        f"- `loc_range`: `{source.get('min_loc', '-')}` - `{source.get('max_loc', '-')}`"
    )
    lines.append(
        f"- `allow_incomplete_core`: `{source.get('allow_incomplete_core', False)}`"
    )
    lines.append("")
    lines.append("## Mapa metryk rdzeniowych")
    lines.append("")
    lines.append("| Kolumna raportu | Sonar metric key |")
    lines.append("|---|---|")
    lines.append("| Issues | `violations` (fallback: `open_issues`) |")
    lines.append("| Technical Debt (days) | `sqale_index` / 480 |")
    lines.append("| Lines of Code | `ncloc` |")
    lines.append("| Line Coverage (%) | `coverage` |")
    lines.append("| Unit Tests | `tests` |")
    lines.append("")
    lines.append("## Podsumowanie")
    lines.append("")
    lines.append("| Metryka | Wartość |")
    lines.append("|---|---:|")
    lines.append(f"| Projekty w benchmarku | {summary['total_projects']} |")
    lines.append(
        f"| Projekty z kompletem rdzenia | {summary['core_complete_projects']} |"
    )
    lines.append(f"| Pokrycie rdzenia | {summary['core_coverage_ratio']} |")
    lines.append("")

    selection = payload.get("selection_stats") or {}
    rejected = selection.get("rejected") or {}
    if selection:
        lines.append("### Statystyki selekcji")
        lines.append("")
        lines.append("| Metryka | Wartość |")
        lines.append("|---|---:|")
        lines.append(
            f"| Przeskanowani kandydaci | {selection.get('scanned_candidates', 0)} |"
        )
        lines.append(f"| Wybrane projekty | {selection.get('selected_projects', 0)} |")
        lines.append(
            f"| Odrzucone LOC poza zakresem | {rejected.get('loc_out_of_range', 0)} |"
        )
        lines.append(
            f"| Odrzucone przez niekompletne metryki | {rejected.get('core_incomplete', 0)} |"
        )
        lines.append(f"| Odrzucone przez błędy API | {rejected.get('api_error', 0)} |")
        lines.append("")

    stats = summary.get("core_metric_stats", {})
    if stats:
        lines.append("### Rozkład metryk rdzeniowych (Q1 / Mediana / Q3)")
        lines.append("")
        lines.append("| Metryka | Q1 | Mediana | Q3 |")
        lines.append("|---|---:|---:|---:|")
        for metric, s in stats.items():
            lines.append(
                f"| `{metric}` | {s['q1']:.2f} | {s['median']:.2f} | {s['q3']:.2f} |"
            )
        lines.append("")

    venom = summary.get("venom_position")
    if venom:
        lines.append("### Pozycja Venom")
        lines.append("")
        lines.append(f"- `project_key`: `{venom.get('project_key')}`")
        lines.append(f"- `status`: `{venom.get('status')}`")
        if venom.get("status") == "ok":
            lines.append("")
            lines.append("| Metryka | Wartość Venom | Percentyl |")
            lines.append("|---|---:|---:|")
            normalized = venom.get("normalized", {})
            percentiles = venom.get("percentile_position", {})
            for metric in [
                "issues",
                "technical_debt_days",
                "lines_of_code",
                "line_coverage_pct",
                "unit_tests",
            ]:
                value = normalized.get(metric)
                percentile = percentiles.get(metric)
                value_text = "-" if value is None else f"{float(value):.2f}"
                percentile_text = "-" if percentile is None else f"{percentile:.2f}"
                lines.append(f"| `{metric}` | {value_text} | {percentile_text} |")
        lines.append("")

    lines.append(f"## Top {len(ranked)} projektów (podgląd)")
    lines.append("")
    lines.append(
        "| Project Key | Name | Issues | Debt (days) | LOC | Coverage (%) | Tests | Core |"
    )
    lines.append("|---|---|---:|---:|---:|---:|---:|---:|")
    for row in ranked:
        n = row["normalized"]
        lines.append(
            "| "
            f"`{row['project_key']}` | "
            f"{_sanitize_md(str(row['project_name']))} | "
            f"{_fmt(n['issues'], 0)} | "
            f"{_fmt(n['technical_debt_days'], 2)} | "
            f"{_fmt(n['lines_of_code'], 0)} | "
            f"{_fmt(n['line_coverage_pct'], 2)} | "
            f"{_fmt(n['unit_tests'], 0)} | "
            f"{row['core_completeness']} |"
        )

    lines.append("")
    lines.append("## Uwagi")
    lines.append("")
    lines.append(
        "- W SonarQube Cloud metryka `Issues` jest mapowana przez `violations` "
        "(z fallbackiem do `open_issues`)."
    )
    lines.append("- `Technical Debt (days)` liczony z `sqale_index` (minuty / 480).")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build Sonar market benchmark dataset (Issues, Technical Debt, LOC, "
            "Coverage, Unit Tests) for public projects."
        )
    )
    parser.add_argument(
        "--config",
        default="config/process_pipeline_v01.json",
        help="Central pipeline config path (relative to repo root or absolute).",
    )
    parser.add_argument(
        "--dataset-id",
        default="",
        help="Dataset identifier from config.process.steps (default: sonar_market).",
    )
    parser.add_argument(
        "--base-url",
        default=None,
        help="SonarQube Cloud base URL (e.g. https://sonarcloud.io).",
    )
    parser.add_argument(
        "--env-file",
        default="",
        help="Optional dotenv-like file (parsed safely, no shell execution).",
    )
    parser.add_argument(
        "--token-env",
        default="",
        help="Environment variable name with Sonar API token.",
    )
    parser.add_argument(
        "--mode",
        choices=["snapshot", "timeseries"],
        default="snapshot",
        help="Run mode: snapshot benchmark or per-day timeseries export.",
    )
    parser.add_argument(
        "--organization",
        default=None,
        help="Organization key for /api/projects/search (optional).",
    )
    parser.add_argument(
        "--query",
        default=None,
        help="Optional query for /api/components/search_projects.",
    )
    parser.add_argument(
        "--project-key",
        action="append",
        default=[],
        help="Explicit project key to include (repeatable).",
    )
    parser.add_argument(
        "--project-key-file",
        default="",
        help="Optional file with project keys (one key per line).",
    )
    parser.add_argument(
        "--exclude-project-key",
        action="append",
        default=[],
        help="Project key to exclude from fetched list (repeatable).",
    )
    parser.add_argument(
        "--venom-project-key",
        default=None,
        help="Project key for Venom row to compute percentile position.",
    )
    parser.add_argument(
        "--project-limit",
        type=int,
        default=10,
        help="Target number of selected benchmark projects.",
    )
    parser.add_argument(
        "--candidate-limit",
        type=int,
        default=120,
        help="Max number of candidate projects scanned to find matching sample.",
    )
    parser.add_argument(
        "--min-loc",
        type=int,
        default=80000,
        help="Minimum LOC (`ncloc`) for selected projects.",
    )
    parser.add_argument(
        "--max-loc",
        type=int,
        default=160000,
        help="Maximum LOC (`ncloc`) for selected projects.",
    )
    parser.add_argument(
        "--allow-incomplete-core",
        action="store_true",
        help="Allow projects missing part of core metrics (default: reject).",
    )
    parser.add_argument(
        "--page-size",
        type=int,
        default=25,
        help="Pagination size for project listing endpoints.",
    )
    parser.add_argument(
        "--sleep-s",
        type=float,
        default=1.0,
        help="Sleep between API calls in seconds.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=30.0,
        help="Request timeout in seconds.",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=2,
        help="Max retries for transient HTTP/network failures.",
    )
    parser.add_argument(
        "--output-json",
        default="",
        help="Output JSON path.",
    )
    parser.add_argument(
        "--output-md",
        default="",
        help="Output Markdown path.",
    )
    parser.add_argument(
        "--markdown-top",
        type=int,
        default=25,
        help="How many rows to include in Markdown preview table.",
    )
    parser.add_argument(
        "--from-date",
        default="2026-01-01",
        help="Start date for timeseries mode (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--to-date",
        default="2026-03-31",
        help="End date for timeseries mode (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--timeseries-dir",
        default="",
        help="Output directory for timeseries artifacts.",
    )
    parser.add_argument(
        "--aggregate-csv",
        default="",
        help="Aggregated daily CSV output path.",
    )
    parser.add_argument(
        "--timeseries-page-size",
        type=int,
        default=500,
        help="Page size for /api/measures/search_history in timeseries mode.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = repo_root_from_script(__file__)
    cfg = load_pipeline_config(args.config, __file__)
    script_cfg = cfg_get(cfg, "scripts", "sonar_market_benchmark", default={}) or {}
    dataset_id = choose_dataset_value(
        cfg,
        "sonar_market",
        "dataset_id",
        args.dataset_id,
        script_cfg,
        "sonar_market",
    )

    args.env_file = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "env_file",
        args.env_file,
        script_cfg,
        ".env.dev",
        for_input=True,
    )
    args.token_env = choose_dataset_value(
        cfg, dataset_id, "token_env", args.token_env, script_cfg, "SONAR_TOKEN"
    )
    args.project_key_file = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "project_key_file",
        args.project_key_file,
        script_cfg,
        "artifacts/inputs/sonar_market/project_keys_selected_v01.txt",
        for_input=True,
    )
    args.output_json = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "output_json",
        args.output_json,
        script_cfg,
        "artifacts/products_light/sonar_market/benchmark_analysis_2026_v01.json",
    )
    args.output_md = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "output_md",
        args.output_md,
        script_cfg,
        "artifacts/products_light/sonar_market/benchmark_analysis_2026_v01.md",
    )
    args.timeseries_dir = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "timeseries_dir",
        args.timeseries_dir,
        script_cfg,
        "artifacts/sources/sonar_market/timeseries",
    )
    args.aggregate_csv = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "aggregate_csv",
        args.aggregate_csv,
        script_cfg,
        "artifacts/products_light/sonar_market/timeseries_agg_2026_v01.csv",
    )
    env_values = _load_env_file(Path(args.env_file)) if args.env_file else {}
    token = (
        os.environ.get(args.token_env, "") or env_values.get(args.token_env, "")
    ).strip()
    if not token:
        print(
            f"Missing Sonar token. Set environment variable: {args.token_env}",
            file=sys.stderr,
        )
        return 2

    resolved_base_url = (
        args.base_url
        or os.environ.get("SONAR_BASE_URL")
        or env_values.get("SONAR_BASE_URL")
        or DEFAULT_BASE_URL
    ).strip()
    resolved_org = (
        args.organization
        or os.environ.get("SONAR_ORGANIZATION")
        or env_values.get("SONAR_ORGANIZATION")
        or ""
    ).strip()
    resolved_query = (
        args.query
        or os.environ.get("SONAR_PROJECT_QUERY")
        or env_values.get("SONAR_PROJECT_QUERY")
        or ""
    ).strip()
    resolved_venom_key = (
        args.venom_project_key
        or os.environ.get("SONAR_VENOM_PROJECT_KEY")
        or env_values.get("SONAR_VENOM_PROJECT_KEY")
        or ""
    ).strip()

    cfg = FetchConfig(
        base_url=resolved_base_url.rstrip("/"),
        token=token,
        timeout=args.timeout,
        max_retries=max(1, args.max_retries),
        sleep_s=max(0.0, args.sleep_s),
    )
    explicit_keys = [k.strip() for k in args.project_key if k and k.strip()]
    if args.project_key_file:
        path = Path(args.project_key_file)
        if path.exists():
            for line in path.read_text("utf-8").splitlines():
                key = line.strip()
                if not key or key.startswith("#"):
                    continue
                explicit_keys.append(key)
    # Keep input order but drop duplicates.
    explicit_keys = list(dict.fromkeys(explicit_keys))
    exclude_keys = {k.strip() for k in args.exclude_project_key if k.strip()}

    if exclude_keys and explicit_keys:
        explicit_keys = [k for k in explicit_keys if k not in exclude_keys]

    if args.mode == "timeseries":
        return _run_timeseries_mode(
            args,
            cfg,
            explicit_keys=explicit_keys,
            resolved_org=resolved_org,
            resolved_query=resolved_query,
        )

    desired_projects = max(1, args.project_limit)
    candidate_limit = max(desired_projects, args.candidate_limit)
    min_loc = max(0, args.min_loc)
    max_loc = max(min_loc, args.max_loc)

    if explicit_keys:
        candidates = [
            {"key": k, "name": k, "organization": None} for k in explicit_keys
        ]
    else:
        candidates = _fetch_candidates(
            cfg,
            organization=(resolved_org or None),
            query=(resolved_query or None),
            candidate_limit=candidate_limit,
            page_size=max(1, args.page_size),
        )

    if exclude_keys:
        candidates = [c for c in candidates if c["key"] not in exclude_keys]

    candidates = candidates[:candidate_limit]
    if not candidates:
        raise SonarApiError("No project candidates found for the configured filters.")

    records: list[dict[str, Any]] = []
    rejected_stats = {
        "loc_out_of_range": 0,
        "core_incomplete": 0,
        "api_error": 0,
    }
    scanned_candidates = 0
    for idx, candidate in enumerate(candidates, start=1):
        scanned_candidates = idx
        key = candidate["key"]
        try:
            raw = _fetch_measures(key, cfg)
        except SonarApiError:
            rejected_stats["api_error"] += 1
        else:
            record = _to_record(candidate, raw)
            loc = record["normalized"].get("lines_of_code")
            if loc is None or float(loc) < min_loc or float(loc) > max_loc:
                rejected_stats["loc_out_of_range"] += 1
            elif not args.allow_incomplete_core and not record["core_complete"]:
                rejected_stats["core_incomplete"] += 1
            else:
                records.append(record)
                if len(records) >= desired_projects:
                    break

        if cfg.sleep_s > 0 and idx < len(candidates):
            time.sleep(cfg.sleep_s)

    payload = {
        "generated_at": _now_iso(),
        "source": {
            "base_url": cfg.base_url,
            "env_file": args.env_file or None,
            "organization": resolved_org or None,
            "query": resolved_query or None,
            "project_limit": desired_projects,
            "candidate_limit": candidate_limit,
            "min_loc": min_loc,
            "max_loc": max_loc,
            "allow_incomplete_core": bool(args.allow_incomplete_core),
            "project_keys_explicit": explicit_keys,
        },
        "core_metric_mapping": {
            "Issues": "violations (fallback: open_issues)",
            "Technical Debt (days)": "sqale_index / 480",
            "Lines of Code": "ncloc",
            "Line Coverage (%)": "coverage",
            "Unit Tests": "tests",
        },
        "selection_stats": {
            "selected_projects": len(records),
            "scanned_candidates": scanned_candidates,
            "rejected": rejected_stats,
        },
        "projects": records,
        "summary": _build_summary(records, resolved_venom_key or None),
    }

    output_json = Path(args.output_json)
    output_md = Path(args.output_md)
    _write_json(output_json, payload)
    _write_markdown(output_md, payload=payload, top_rows=max(1, args.markdown_top))

    print(f"Saved JSON: {output_json}")
    print(f"Saved Markdown: {output_md}")
    print(
        "Core-complete projects: "
        f"{payload['summary']['core_complete_projects']}/{payload['summary']['total_projects']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
