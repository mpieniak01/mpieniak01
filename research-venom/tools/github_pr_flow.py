#!/usr/bin/env python3
"""Build PR flow dataset (daily) for a repository in a date window.

Outputs:
- per-repo raw JSON
- per-repo daily CSV
- aggregate CSV
- manifest JSON
- markdown summary
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import statistics
import subprocess
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

GITHUB_API = "https://api.github.com"


class GitHubApiError(RuntimeError):
    """Raised when GitHub API call fails."""


@dataclass
class ApiConfig:
    token: str
    timeout: float
    max_retries: int
    sleep_s: float


@dataclass
class RateState:
    remaining: int | None = None
    reset_epoch: int | None = None


def _now_iso() -> str:
    return (
        dt.datetime.now(dt.UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


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


def _resolve_token(args: argparse.Namespace, env_values: dict[str, str]) -> str:
    token = (
        os.environ.get(args.token_env) or env_values.get(args.token_env) or ""
    ).strip()
    if token and not token.upper().startswith("PASTE_"):
        return token
    try:
        token = subprocess.check_output(["gh", "auth", "token"], text=True).strip()
    except Exception:
        token = ""
    if token:
        return token
    raise GitHubApiError(f"Missing token. Set {args.token_env} or authenticate gh CLI.")


def _iso_to_datetime(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def _iso_to_date(value: str | None) -> dt.date | None:
    stamp = _iso_to_datetime(value)
    return stamp.date() if stamp else None


def _github_get(
    url: str, cfg: ApiConfig, *, rate: RateState
) -> tuple[Any, dict[str, str]]:
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {cfg.token}",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    for attempt in range(cfg.max_retries):
        req = urllib.request.Request(url, headers=headers, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=cfg.timeout) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
                hdrs = {k.lower(): v for k, v in resp.headers.items()}
                rem = hdrs.get("x-ratelimit-remaining")
                reset = hdrs.get("x-ratelimit-reset")
                rate.remaining = int(rem) if rem and rem.isdigit() else None
                rate.reset_epoch = int(reset) if reset and reset.isdigit() else None
                return payload, hdrs
        except urllib.error.HTTPError as exc:
            hdrs = {k.lower(): v for k, v in exc.headers.items()}
            rem = hdrs.get("x-ratelimit-remaining")
            reset = hdrs.get("x-ratelimit-reset")
            if rem == "0" and reset and reset.isdigit():
                wait_s = max(1, int(reset) - int(time.time()) + 1)
                time.sleep(wait_s)
                continue
            if (
                exc.code in {403, 429, 500, 502, 503, 504}
                and attempt < cfg.max_retries - 1
            ):
                time.sleep(2 * (attempt + 1))
                continue
            body = exc.read().decode("utf-8", errors="ignore")
            raise GitHubApiError(f"HTTP {exc.code} for {url}: {body[:300]}") from exc
        except urllib.error.URLError as exc:
            if attempt < cfg.max_retries - 1:
                time.sleep(2 * (attempt + 1))
                continue
            raise GitHubApiError(f"Network error for {url}: {exc.reason}") from exc
    raise GitHubApiError(f"Failed request after retries: {url}")


def _search_pr_numbers(
    query: str, cfg: ApiConfig, *, per_page: int = 100, max_items: int = 1000
) -> list[int]:
    out: list[int] = []
    page = 1
    rate = RateState()
    while len(out) < max_items:
        params = {
            "q": query,
            "per_page": min(100, max(1, per_page)),
            "page": page,
            "sort": "created",
            "order": "asc",
        }
        url = f"{GITHUB_API}/search/issues?{urllib.parse.urlencode(params)}"
        payload, _ = _github_get(url, cfg, rate=rate)
        items = payload.get("items", [])
        if not items:
            break
        for item in items:
            n = item.get("number")
            if isinstance(n, int):
                out.append(n)
            if len(out) >= max_items:
                break
        if len(items) < params["per_page"]:
            break
        page += 1
        if cfg.sleep_s > 0:
            time.sleep(cfg.sleep_s)
    return out


def _fetch_pr_detail(
    owner: str, repo: str, number: int, cfg: ApiConfig
) -> dict[str, Any]:
    rate = RateState()
    url = f"{GITHUB_API}/repos/{owner}/{repo}/pulls/{number}"
    payload, _ = _github_get(url, cfg, rate=rate)
    if not isinstance(payload, dict):
        raise GitHubApiError(f"Invalid PR detail payload for #{number}")
    return payload


def _fetch_first_review_at(
    owner: str, repo: str, number: int, cfg: ApiConfig
) -> str | None:
    page = 1
    per_page = 100
    rate = RateState()
    first_at: str | None = None
    while True:
        params = {"per_page": per_page, "page": page}
        url = f"{GITHUB_API}/repos/{owner}/{repo}/pulls/{number}/reviews?{urllib.parse.urlencode(params)}"
        payload, _ = _github_get(url, cfg, rate=rate)
        if not isinstance(payload, list) or not payload:
            break
        for review in payload:
            submitted_at = review.get("submitted_at")
            if not submitted_at:
                continue
            if first_at is None or submitted_at < first_at:
                first_at = submitted_at
        if len(payload) < per_page:
            break
        page += 1
        if cfg.sleep_s > 0:
            time.sleep(cfg.sleep_s)
    return first_at


def _date_range(start: dt.date, end: dt.date) -> list[str]:
    out: list[str] = []
    cur = start
    one = dt.timedelta(days=1)
    while cur <= end:
        out.append(cur.isoformat())
        cur += one
    return out


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def _write_csv(path: Path, rows: list[dict[str, Any]], headers: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=headers)
        writer.writeheader()
        for row in rows:
            writer.writerow({h: row.get(h, "") for h in headers})


def _hours_delta(start: str | None, end: str | None) -> float | None:
    s = _iso_to_datetime(start)
    e = _iso_to_datetime(end)
    if not s or not e:
        return None
    return (e - s).total_seconds() / 3600.0


def run(args: argparse.Namespace) -> int:
    start_date = dt.date.fromisoformat(args.from_date)
    end_date = dt.date.fromisoformat(args.to_date)
    if end_date < start_date:
        raise GitHubApiError("--to-date must be >= --from-date")

    env = _load_env_file(Path(args.env_file)) if args.env_file else {}
    token = _resolve_token(args, env)
    cfg = ApiConfig(
        token=token,
        timeout=args.timeout,
        max_retries=max(1, args.max_retries),
        sleep_s=max(0.0, args.sleep_s),
    )

    owner = args.owner
    repo = args.repo
    repo_full = f"{owner}/{repo}"
    from_s = args.from_date
    to_s = args.to_date

    # Three search slices: created in range, carry-over open, carry-over closed in range.
    q_created = f"repo:{owner}/{repo} is:pr created:{from_s}..{to_s}"
    q_open_carry = f"repo:{owner}/{repo} is:pr is:open created:<{from_s}"
    q_closed_carry = (
        f"repo:{owner}/{repo} is:pr is:closed created:<{from_s} closed:{from_s}..{to_s}"
    )

    nums = set(_search_pr_numbers(q_created, cfg))
    nums.update(_search_pr_numbers(q_open_carry, cfg))
    nums.update(_search_pr_numbers(q_closed_carry, cfg))
    numbers = sorted(nums)

    detailed: list[dict[str, Any]] = []
    for idx, number in enumerate(numbers, start=1):
        pr = _fetch_pr_detail(owner, repo, number, cfg)
        first_review_at = (
            _fetch_first_review_at(owner, repo, number, cfg)
            if args.include_reviews
            else None
        )
        created_at = pr.get("created_at")
        merged_at = pr.get("merged_at")
        closed_at = pr.get("closed_at")

        rec = {
            "number": pr.get("number"),
            "title": pr.get("title"),
            "html_url": pr.get("html_url"),
            "state": pr.get("state"),
            "draft": bool(pr.get("draft")),
            "author": (pr.get("user") or {}).get("login"),
            "created_at": created_at,
            "merged_at": merged_at,
            "closed_at": closed_at,
            "is_merged": bool(merged_at),
            "is_closed_without_merge": bool(closed_at and not merged_at),
            "additions": int(pr.get("additions") or 0),
            "deletions": int(pr.get("deletions") or 0),
            "changed_files": int(pr.get("changed_files") or 0),
            "commits": int(pr.get("commits") or 0),
            "first_review_at": first_review_at,
            "lead_time_hours": _hours_delta(created_at, merged_at),
            "review_latency_hours": _hours_delta(created_at, first_review_at),
        }
        detailed.append(rec)
        if cfg.sleep_s > 0 and idx < len(numbers):
            time.sleep(cfg.sleep_s)

    # Keep only PRs that overlap the analysis window.
    overlapping: list[dict[str, Any]] = []
    for pr in detailed:
        created_d = _iso_to_date(pr.get("created_at"))
        closed_d = _iso_to_date(pr.get("closed_at"))
        if not created_d:
            continue
        if created_d > end_date:
            continue
        if closed_d and closed_d < start_date:
            continue
        overlapping.append(pr)

    days = _date_range(start_date, end_date)
    daily_rows: list[dict[str, Any]] = []
    for day in days:
        d = dt.date.fromisoformat(day)
        opened = 0
        merged = 0
        closed_wo = 0
        active_eod = 0
        lead_times: list[float] = []
        review_latencies: list[float] = []

        for pr in overlapping:
            created_d = _iso_to_date(pr.get("created_at"))
            merged_d = _iso_to_date(pr.get("merged_at"))
            closed_d = _iso_to_date(pr.get("closed_at"))

            if created_d == d:
                opened += 1
            if merged_d == d:
                merged += 1
                lt = pr.get("lead_time_hours")
                if isinstance(lt, (int, float)):
                    lead_times.append(float(lt))
                rl = pr.get("review_latency_hours")
                if isinstance(rl, (int, float)):
                    review_latencies.append(float(rl))
            if closed_d == d and not merged_d:
                closed_wo += 1
            if created_d and created_d <= d and (not closed_d or closed_d > d):
                active_eod += 1

        daily_rows.append(
            {
                "project_key": repo_full,
                "date": day,
                "pr_opened_count_daily": opened,
                "pr_merged_count_daily": merged,
                "pr_closed_not_merged_daily": closed_wo,
                "pr_active_daily": active_eod,
                "pr_daily_avg_lead_time_hours": round(
                    sum(lead_times) / len(lead_times), 4
                )
                if lead_times
                else "",
                "pr_daily_median_lead_time_hours": round(
                    statistics.median(lead_times), 4
                )
                if lead_times
                else "",
                "pr_daily_avg_review_latency_hours": round(
                    sum(review_latencies) / len(review_latencies), 4
                )
                if review_latencies
                else "",
                "lead_time_sample_size": len(lead_times),
            }
        )

    merged_prs = [p for p in overlapping if p.get("merged_at")]
    opened_in_window = 0
    merged_in_window = 0
    closed_wo_in_window = 0
    for p in overlapping:
        created_d = _iso_to_date(p.get("created_at"))
        merged_d = _iso_to_date(p.get("merged_at"))
        closed_d = _iso_to_date(p.get("closed_at"))
        if created_d and start_date <= created_d <= end_date:
            opened_in_window += 1
        if merged_d and start_date <= merged_d <= end_date:
            merged_in_window += 1
        if closed_d and not merged_d and start_date <= closed_d <= end_date:
            closed_wo_in_window += 1
    lead_all = [
        float(p["lead_time_hours"])
        for p in merged_prs
        if isinstance(p.get("lead_time_hours"), (int, float))
    ]
    review_all = [
        float(p["review_latency_hours"])
        for p in merged_prs
        if isinstance(p.get("review_latency_hours"), (int, float))
    ]

    def pct(values: list[float], q: float) -> float | None:
        if not values:
            return None
        values_sorted = sorted(values)
        idx = int(round((len(values_sorted) - 1) * q))
        return values_sorted[idx]

    summary = {
        "project_key": repo_full,
        "window": {"from": f"{from_s}T00:00:00Z", "to": f"{to_s}T23:59:59Z"},
        "counts": {
            "prs_collected_by_search": len(numbers),
            "prs_overlapping_window": len(overlapping),
            "prs_opened_in_window": opened_in_window,
            "prs_merged_in_window": merged_in_window,
            "prs_closed_without_merge_in_window": closed_wo_in_window,
        },
        "kpis": {
            "merge_rate_q1": round((merged_in_window / opened_in_window), 6)
            if opened_in_window > 0
            else None,
            "backlog_pressure_q1": round(
                sum(int(r["pr_active_daily"]) for r in daily_rows) / len(daily_rows), 4
            )
            if daily_rows
            else None,
            "lead_time_avg_hours_q1": round(sum(lead_all) / len(lead_all), 4)
            if lead_all
            else None,
            "lead_time_median_hours_q1": round(statistics.median(lead_all), 4)
            if lead_all
            else None,
            "lead_time_p50_hours_q1": round(pct(lead_all, 0.50), 4)
            if lead_all
            else None,
            "lead_time_p75_hours_q1": round(pct(lead_all, 0.75), 4)
            if lead_all
            else None,
            "lead_time_p90_hours_q1": round(pct(lead_all, 0.90), 4)
            if lead_all
            else None,
            "review_latency_avg_hours_q1": round(sum(review_all) / len(review_all), 4)
            if review_all
            else None,
            "review_latency_median_hours_q1": round(statistics.median(review_all), 4)
            if review_all
            else None,
        },
    }

    root = Path(args.output_root)
    raw_path = root / "raw" / f"{owner}__{repo}_pr_flow.json"
    csv_path = root / "csv" / f"{owner}__{repo}_pr_flow.csv"
    agg_path = Path(args.aggregate_csv)
    manifest_json = Path(args.output_json)
    manifest_md = Path(args.output_md)

    _write_json(
        raw_path,
        {
            "generated_at": _now_iso(),
            "source": {
                "method": "github_api",
                "owner": owner,
                "repo": repo,
                "from": summary["window"]["from"],
                "to": summary["window"]["to"],
                "include_reviews": bool(args.include_reviews),
            },
            "summary": summary,
            "pull_requests": overlapping,
            "daily_rows": daily_rows,
        },
    )

    daily_headers = [
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
    ]
    _write_csv(csv_path, daily_rows, daily_headers)

    _write_csv(agg_path, daily_rows, daily_headers)

    manifest = {
        "generated_at": _now_iso(),
        "mode": "pr_flow_timeseries",
        "source": {
            "owner": owner,
            "repo": repo,
            "from": summary["window"]["from"],
            "to": summary["window"]["to"],
            "output_root": str(root),
            "include_reviews": bool(args.include_reviews),
        },
        "summary": summary,
        "artifacts": {
            "raw_json": str(raw_path),
            "daily_csv": str(csv_path),
            "aggregate_csv": str(agg_path),
        },
    }
    _write_json(manifest_json, manifest)

    lines = [
        "# github_pr_flow_2026",
        "",
        f"Data generacji: `{manifest['generated_at']}`",
        "",
        "## Konfiguracja",
        "",
        f"- `repo`: `{repo_full}`",
        f"- `from`: `{summary['window']['from']}`",
        f"- `to`: `{summary['window']['to']}`",
        f"- `include_reviews`: `{str(args.include_reviews).lower()}`",
        "",
        "## KPI Q1 2026",
        "",
        f"- `prs_opened_in_window`: `{summary['counts']['prs_opened_in_window']}`",
        f"- `prs_merged_in_window`: `{summary['counts']['prs_merged_in_window']}`",
        f"- `prs_closed_without_merge_in_window`: `{summary['counts']['prs_closed_without_merge_in_window']}`",
        f"- `merge_rate_q1`: `{summary['kpis']['merge_rate_q1']}`",
        f"- `backlog_pressure_q1`: `{summary['kpis']['backlog_pressure_q1']}`",
        f"- `lead_time_avg_hours_q1`: `{summary['kpis']['lead_time_avg_hours_q1']}`",
        f"- `lead_time_median_hours_q1`: `{summary['kpis']['lead_time_median_hours_q1']}`",
        f"- `lead_time_p90_hours_q1`: `{summary['kpis']['lead_time_p90_hours_q1']}`",
        f"- `review_latency_avg_hours_q1`: `{summary['kpis']['review_latency_avg_hours_q1']}`",
        "",
        "## Artefakty",
        "",
        f"- `manifest json`: `{manifest_json}`",
        f"- `raw json`: `{raw_path}`",
        f"- `daily csv`: `{csv_path}`",
        f"- `aggregate csv`: `{agg_path}`",
    ]
    manifest_md.parent.mkdir(parents=True, exist_ok=True)
    manifest_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Collected PR numbers: {len(numbers)}")
    print(f"Overlapping PRs: {len(overlapping)}")
    print(f"Saved manifest JSON: {manifest_json}")
    print(f"Saved manifest Markdown: {manifest_md}")
    print(f"Saved raw JSON: {raw_path}")
    print(f"Saved daily CSV: {csv_path}")
    print(f"Saved aggregate CSV: {agg_path}")
    return 0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Build daily PR flow dataset for repository and date window."
    )
    p.add_argument(
        "--config",
        default="config/process_pipeline_v01.json",
        help="Central pipeline config path (relative to repo root or absolute).",
    )
    p.add_argument(
        "--dataset-id",
        default="",
        help="Dataset identifier from config.process.steps (default: github_pr_flow).",
    )
    p.add_argument("--owner", default="")
    p.add_argument("--repo", default="")
    p.add_argument("--from-date", default="2026-01-01")
    p.add_argument("--to-date", default="2026-03-31")
    p.add_argument("--env-file", default="")
    p.add_argument("--token-env", default="")
    p.add_argument("--timeout", type=float, default=30.0)
    p.add_argument("--max-retries", type=int, default=4)
    p.add_argument("--sleep-s", type=float, default=0.05)
    p.add_argument(
        "--include-reviews", action=argparse.BooleanOptionalAction, default=True
    )
    p.add_argument(
        "--output-root", default=""
    )
    p.add_argument(
        "--output-json",
        default="",
    )
    p.add_argument(
        "--output-md",
        default="",
    )
    p.add_argument(
        "--aggregate-csv",
        default="",
    )
    return p.parse_args()


def main() -> int:
    try:
        args = parse_args()
        repo_root = repo_root_from_script(__file__)
        cfg = load_pipeline_config(args.config, __file__)
        script_cfg = cfg_get(cfg, "scripts", "github_pr_flow", default={}) or {}
        dataset_id = choose_dataset_value(
            cfg,
            "github_pr_flow",
            "dataset_id",
            args.dataset_id,
            script_cfg,
            "github_pr_flow",
        )

        args.owner = choose_dataset_value(
            cfg, dataset_id, "owner", args.owner, script_cfg, "mpieniak01"
        )
        args.repo = choose_dataset_value(
            cfg, dataset_id, "repo", args.repo, script_cfg, "Venom"
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
            cfg, dataset_id, "token_env", args.token_env, script_cfg, "GITHUB_TOKEN"
        )
        args.output_root = resolve_dataset_path(
            repo_root,
            cfg,
            dataset_id,
            "output_root",
            args.output_root,
            script_cfg,
            "artifacts/sources/pr_flow/per_repo",
        )
        args.output_json = resolve_dataset_path(
            repo_root,
            cfg,
            dataset_id,
            "output_json",
            args.output_json,
            script_cfg,
            "artifacts/products_light/pr_flow/analysis_2026_v01.json",
        )
        args.output_md = resolve_dataset_path(
            repo_root,
            cfg,
            dataset_id,
            "output_md",
            args.output_md,
            script_cfg,
            "artifacts/products_light/pr_flow/analysis_2026_v01.md",
        )
        args.aggregate_csv = resolve_dataset_path(
            repo_root,
            cfg,
            dataset_id,
            "aggregate_csv",
            args.aggregate_csv,
            script_cfg,
            "artifacts/products_light/pr_flow/timeseries_agg_2026_v01.csv",
        )
        return run(args)
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
