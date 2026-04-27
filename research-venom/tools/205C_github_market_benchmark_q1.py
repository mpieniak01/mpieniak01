#!/usr/bin/env python3
"""Build GitHub API benchmark dataset for Q1 2026.

Modes:
- discover: find candidate repositories with GitHub Search API
- analyze: analyze explicit repository list (owner/repo)
- full: discover then analyze selected repositories

Outputs:
- repo selection JSON + Markdown + plain key list
- per-repo raw JSON and daily CSV
- aggregated daily CSV for all repositories
- benchmark manifest JSON + Markdown summary
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

GITHUB_API = "https://api.github.com"
DEFAULT_STAR_SHARDS = [
    "stars:>=5000",
    "stars:2000..4999",
    "stars:1000..1999",
    "stars:500..999",
    "stars:200..499",
    "stars:100..199",
    "stars:50..99",
    "stars:20..49",
    "stars:10..19",
]


class GitHubApiError(RuntimeError):
    """Raised when GitHub API call fails after retries."""


@dataclass
class ApiConfig:
    token: str
    timeout: float
    max_retries: int
    search_sleep_s: float
    api_sleep_s: float


@dataclass
class RateState:
    remaining: int | None = None
    reset_epoch: int | None = None


@dataclass
class RepoCandidate:
    full_name: str
    html_url: str
    description: str | None
    language: str | None
    size_kb: int
    stargazers_count: int
    forks_count: int
    pushed_at: str | None
    commits_q1: int = 0


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
    if token:
        return token

    # Fallback to gh CLI auth token if available.
    try:
        token = subprocess.check_output(["gh", "auth", "token"], text=True).strip()
    except Exception:
        token = ""
    if token:
        return token

    raise GitHubApiError(
        f"Missing GitHub token. Set {args.token_env} or authenticate gh CLI."
    )


def _parse_link_header(header: str) -> dict[str, str]:
    links: dict[str, str] = {}
    for part in header.split(","):
        chunk = part.strip()
        if not chunk:
            continue
        if ";" not in chunk:
            continue
        url_part, meta = chunk.split(";", 1)
        url = url_part.strip().lstrip("<").rstrip(">")
        meta = meta.strip()
        if "rel=" not in meta:
            continue
        rel = meta.split("rel=", 1)[1].strip().strip('"')
        links[rel] = url
    return links


def _github_get(
    url: str,
    cfg: ApiConfig,
    *,
    rate: RateState,
    is_search: bool,
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
                body = json.loads(resp.read().decode("utf-8"))
                hdrs = {k.lower(): v for k, v in resp.headers.items()}
                rem = hdrs.get("x-ratelimit-remaining")
                reset = hdrs.get("x-ratelimit-reset")
                rate.remaining = int(rem) if rem and rem.isdigit() else None
                rate.reset_epoch = int(reset) if reset and reset.isdigit() else None
                return body, hdrs
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
            payload = exc.read().decode("utf-8", errors="ignore")
            raise GitHubApiError(f"HTTP {exc.code} for {url}: {payload[:300]}") from exc
        except urllib.error.URLError as exc:
            if attempt < cfg.max_retries - 1:
                time.sleep(2 * (attempt + 1))
                continue
            raise GitHubApiError(f"Network error for {url}: {exc.reason}") from exc

    raise GitHubApiError(f"Failed request after retries: {url}")


def _normalize_full_name(value: str) -> str | None:
    value = value.strip()
    if not value or value.startswith("#"):
        return None
    if "/" in value:
        owner, repo = value.split("/", 1)
        owner = owner.strip()
        repo = repo.strip()
        if owner and repo:
            return f"{owner}/{repo}"
        return None
    if "_" in value:
        owner, repo = value.split("_", 1)
        owner = owner.strip()
        repo = repo.strip()
        if owner and repo:
            return f"{owner}/{repo}"
    return None


def _read_explicit_repos(args: argparse.Namespace) -> list[str]:
    repos: list[str] = []
    for item in args.repo:
        normalized = _normalize_full_name(item)
        if normalized:
            repos.append(normalized)

    if args.repo_file:
        path = Path(args.repo_file)
        if path.exists():
            for line in path.read_text("utf-8").splitlines():
                normalized = _normalize_full_name(line)
                if normalized:
                    repos.append(normalized)

    # Keep order, drop duplicates.
    return list(dict.fromkeys(repos))


def _build_search_query(args: argparse.Namespace, star_shard: str) -> str:
    terms: list[str] = [
        "is:public",
        "archived:false",
        "fork:false" if not args.include_forks else "fork:true",
        f"pushed:{args.from_date}..{args.to_date}",
        star_shard,
    ]
    if args.language:
        terms.append(f"language:{args.language}")
    if args.size_min_kb > 0:
        terms.append(f"size:>={args.size_min_kb}")
    if args.size_max_kb > 0:
        terms.append(f"size:<={args.size_max_kb}")
    if args.query_text:
        terms.append(args.query_text)
    return " ".join(terms)


def _discover_candidates(
    args: argparse.Namespace, cfg: ApiConfig
) -> list[RepoCandidate]:
    star_shards = [s.strip() for s in args.star_shard if s.strip()]
    if not star_shards:
        star_shards = DEFAULT_STAR_SHARDS

    rate = RateState()
    out: list[RepoCandidate] = []
    seen: set[str] = set()

    for shard in star_shards:
        query = _build_search_query(args, shard)
        for page in range(1, max(1, args.max_pages_per_shard) + 1):
            params = {
                "q": query,
                "sort": args.search_sort,
                "order": args.search_order,
                "per_page": min(100, max(1, args.per_page)),
                "page": page,
            }
            url = f"{GITHUB_API}/search/repositories?{urllib.parse.urlencode(params)}"
            payload, _ = _github_get(url, cfg, rate=rate, is_search=True)
            items = payload.get("items", [])
            if not items:
                break

            for item in items:
                full_name = item.get("full_name")
                if not full_name or full_name in seen:
                    continue
                seen.add(full_name)
                out.append(
                    RepoCandidate(
                        full_name=full_name,
                        html_url=item.get("html_url")
                        or f"https://github.com/{full_name}",
                        description=item.get("description"),
                        language=item.get("language"),
                        size_kb=int(item.get("size") or 0),
                        stargazers_count=int(item.get("stargazers_count") or 0),
                        forks_count=int(item.get("forks_count") or 0),
                        pushed_at=item.get("pushed_at"),
                    )
                )
                if len(out) >= args.candidate_limit:
                    return out

            # Search API returns max 1,000 items per query.
            total_count = int(payload.get("total_count") or 0)
            if page * min(100, max(1, args.per_page)) >= min(total_count, 1000):
                break

            if cfg.search_sleep_s > 0:
                time.sleep(cfg.search_sleep_s)

    return out


def _count_commits_in_window(
    full_name: str,
    cfg: ApiConfig,
    *,
    since_iso: str,
    until_iso: str,
) -> int:
    rate = RateState()
    params = {
        "since": since_iso,
        "until": until_iso,
        "per_page": 1,
        "page": 1,
    }
    url = f"{GITHUB_API}/repos/{full_name}/commits?{urllib.parse.urlencode(params)}"
    payload, headers = _github_get(url, cfg, rate=rate, is_search=False)
    if not isinstance(payload, list) or not payload:
        return 0
    link_header = headers.get("link", "")
    if link_header:
        links = _parse_link_header(link_header)
        last = links.get("last")
        if last:
            parsed = urllib.parse.urlparse(last)
            page = urllib.parse.parse_qs(parsed.query).get("page", ["1"])[0]
            if str(page).isdigit():
                return int(page)
    return len(payload)


def _select_repositories(
    candidates: list[RepoCandidate],
    args: argparse.Namespace,
    cfg: ApiConfig,
) -> list[RepoCandidate]:
    selected: list[RepoCandidate] = []

    for idx, cand in enumerate(candidates, start=1):
        cand.commits_q1 = _count_commits_in_window(
            cand.full_name,
            cfg,
            since_iso=f"{args.from_date}T00:00:00Z",
            until_iso=f"{args.to_date}T23:59:59Z",
        )
        if cand.commits_q1 >= args.min_commits_q1:
            selected.append(cand)
        if cfg.api_sleep_s > 0 and idx < len(candidates):
            time.sleep(cfg.api_sleep_s)

    selected.sort(
        key=lambda x: (x.commits_q1, x.stargazers_count, x.size_kb),
        reverse=True,
    )
    return selected[: args.project_limit]


def _fetch_commit_list(
    full_name: str,
    cfg: ApiConfig,
    *,
    since_iso: str,
    until_iso: str,
    per_page: int,
    max_commits: int,
) -> tuple[list[dict[str, Any]], bool]:
    rate = RateState()
    page = 1
    out: list[dict[str, Any]] = []
    truncated = False

    while True:
        params = {
            "since": since_iso,
            "until": until_iso,
            "per_page": min(100, max(1, per_page)),
            "page": page,
        }
        url = f"{GITHUB_API}/repos/{full_name}/commits?{urllib.parse.urlencode(params)}"
        payload, _ = _github_get(url, cfg, rate=rate, is_search=False)
        if not isinstance(payload, list) or not payload:
            break

        out.extend(payload)
        if max_commits > 0 and len(out) > max_commits:
            out = out[:max_commits]
            truncated = True
            break

        if len(payload) < min(100, max(1, per_page)):
            break

        page += 1
        if cfg.api_sleep_s > 0:
            time.sleep(cfg.api_sleep_s)

    return out, truncated


def _fetch_commit_stats(
    full_name: str,
    sha: str,
    cfg: ApiConfig,
    *,
    rate: RateState,
) -> tuple[int, int]:
    url = f"{GITHUB_API}/repos/{full_name}/commits/{sha}"
    payload, _ = _github_get(url, cfg, rate=rate, is_search=False)
    stats = payload.get("stats") or {}
    return int(stats.get("additions") or 0), int(stats.get("deletions") or 0)


def _date_range(start: dt.date, end: dt.date) -> list[str]:
    out: list[str] = []
    current = start
    one = dt.timedelta(days=1)
    while current <= end:
        out.append(current.isoformat())
        current += one
    return out


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", "utf-8")


def _write_csv(path: Path, rows: list[dict[str, Any]], headers: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=headers)
        writer.writeheader()
        for row in rows:
            writer.writerow({h: row.get(h, "") for h in headers})


def _write_selection_artifacts(
    selected: list[RepoCandidate],
    *,
    args: argparse.Namespace,
) -> None:
    payload = {
        "generated_at": _now_iso(),
        "source": {
            "from_date": args.from_date,
            "to_date": args.to_date,
            "language": args.language or None,
            "size_min_kb": args.size_min_kb,
            "size_max_kb": args.size_max_kb,
            "project_limit": args.project_limit,
            "candidate_limit": args.candidate_limit,
            "min_commits_q1": args.min_commits_q1,
            "search_sort": args.search_sort,
            "search_order": args.search_order,
        },
        "selected": [
            {
                "full_name": c.full_name,
                "html_url": c.html_url,
                "description": c.description,
                "language": c.language,
                "size_kb": c.size_kb,
                "stargazers_count": c.stargazers_count,
                "forks_count": c.forks_count,
                "pushed_at": c.pushed_at,
                "commits_q1": c.commits_q1,
            }
            for c in selected
        ],
    }
    _write_json(Path(args.selection_json), payload)

    lines = [
        "# 205C_repo_selection_github",
        "",
        f"Data generacji: `{payload['generated_at']}`",
        "",
        "## Parametry",
        "",
        f"- `Q1`: `{args.from_date}` -> `{args.to_date}`",
        f"- `language`: `{args.language or '-'} `",
        f"- `size_min_kb`: `{args.size_min_kb}`",
        f"- `size_max_kb`: `{args.size_max_kb if args.size_max_kb > 0 else '-'} `",
        f"- `project_limit`: `{args.project_limit}`",
        f"- `min_commits_q1`: `{args.min_commits_q1}`",
        "",
        "## Wybrane repo",
        "",
        "| Repo | Commits Q1 | Size (KB) | Stars | Language | Bio projektu |",
        "|---|---:|---:|---:|---|---|",
    ]
    for c in selected:
        bio = (c.description or "-").replace("|", "\\|").replace("\n", " ").strip()
        lines.append(
            f"| `{c.full_name}` | {c.commits_q1} | {c.size_kb} | {c.stargazers_count} | {c.language or '-'} | {bio} |"
        )

    md_path = Path(args.selection_md)
    md_path.parent.mkdir(parents=True, exist_ok=True)
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    keys_path = Path(args.selection_keys)
    keys_path.parent.mkdir(parents=True, exist_ok=True)
    keys_path.write_text(
        "\n".join([c.full_name for c in selected]) + "\n",
        encoding="utf-8",
    )


def _analyze_repositories(
    repo_names: list[str],
    args: argparse.Namespace,
    cfg: ApiConfig,
) -> int:
    start_date = dt.date.fromisoformat(args.from_date)
    end_date = dt.date.fromisoformat(args.to_date)
    if end_date < start_date:
        raise GitHubApiError("--to-date must be >= --from-date")

    since_iso = f"{args.from_date}T00:00:00Z"
    until_iso = f"{args.to_date}T23:59:59Z"

    per_repo_root = Path(args.per_repo_dir)
    raw_dir = per_repo_root / "raw"
    csv_dir = per_repo_root / "csv"

    aggregate_rows: list[dict[str, Any]] = []
    projects_summary: list[dict[str, Any]] = []

    for repo_idx, full_name in enumerate(repo_names, start=1):
        commits, truncated = _fetch_commit_list(
            full_name,
            cfg,
            since_iso=since_iso,
            until_iso=until_iso,
            per_page=args.per_page,
            max_commits=args.max_commits_per_repo,
        )

        daily_map: dict[str, dict[str, Any]] = {
            d: {
                "project_key": full_name,
                "date": d,
                "commits": 0,
                "authors": 0,
                "additions": 0,
                "deletions": 0,
                "churn": 0,
                "truncated": "true" if truncated else "false",
            }
            for d in _date_range(start_date, end_date)
        }
        authors_by_day: dict[str, set[str]] = {d: set() for d in daily_map}

        commit_records: list[dict[str, Any]] = []
        rate = RateState()
        for i, c in enumerate(commits, start=1):
            sha = c.get("sha")
            if not sha:
                continue
            commit_obj = c.get("commit") or {}
            author_obj = commit_obj.get("author") or {}
            date_raw = author_obj.get("date")
            if not date_raw:
                continue
            date = date_raw[:10]
            if date not in daily_map:
                continue

            author_login = (
                (c.get("author") or {}).get("login")
                or author_obj.get("name")
                or "unknown"
            )
            additions, deletions = _fetch_commit_stats(
                full_name,
                sha,
                cfg,
                rate=rate,
            )

            daily = daily_map[date]
            daily["commits"] += 1
            daily["additions"] += additions
            daily["deletions"] += deletions
            daily["churn"] += additions + deletions
            authors_by_day[date].add(str(author_login))

            commit_records.append(
                {
                    "sha": sha,
                    "date": date_raw,
                    "author": author_login,
                    "additions": additions,
                    "deletions": deletions,
                    "churn": additions + deletions,
                    "html_url": c.get("html_url"),
                }
            )
            if cfg.api_sleep_s > 0 and i < len(commits):
                time.sleep(cfg.api_sleep_s)

        daily_rows: list[dict[str, Any]] = []
        for d in sorted(daily_map):
            row = daily_map[d]
            row["authors"] = len(authors_by_day[d])
            daily_rows.append(row)

        total_commits = sum(r["commits"] for r in daily_rows)
        total_additions = sum(r["additions"] for r in daily_rows)
        total_deletions = sum(r["deletions"] for r in daily_rows)
        active_days = sum(1 for r in daily_rows if r["commits"] > 0)
        unique_authors = len({rec["author"] for rec in commit_records})

        safe_name = full_name.replace("/", "__")
        repo_payload = {
            "generated_at": _now_iso(),
            "project_key": full_name,
            "source": {
                "from": since_iso,
                "to": until_iso,
                "max_commits_per_repo": args.max_commits_per_repo,
            },
            "summary": {
                "commits_q1": total_commits,
                "active_days_q1": active_days,
                "authors_q1": unique_authors,
                "additions_q1": total_additions,
                "deletions_q1": total_deletions,
                "churn_q1": total_additions + total_deletions,
                "truncated": truncated,
                "fetched_commits": len(commits),
            },
            "daily_rows": daily_rows,
            "commits": commit_records,
        }
        _write_json(raw_dir / f"{safe_name}.json", repo_payload)
        _write_csv(
            csv_dir / f"{safe_name}.csv",
            daily_rows,
            headers=[
                "project_key",
                "date",
                "commits",
                "authors",
                "additions",
                "deletions",
                "churn",
                "truncated",
            ],
        )

        aggregate_rows.extend(daily_rows)
        projects_summary.append(
            {
                "project_key": full_name,
                "commits_q1": total_commits,
                "active_days_q1": active_days,
                "authors_q1": unique_authors,
                "additions_q1": total_additions,
                "deletions_q1": total_deletions,
                "churn_q1": total_additions + total_deletions,
                "truncated": truncated,
                "raw_json": str(raw_dir / f"{safe_name}.json"),
                "csv": str(csv_dir / f"{safe_name}.csv"),
            }
        )

        if cfg.api_sleep_s > 0 and repo_idx < len(repo_names):
            time.sleep(cfg.api_sleep_s)

    _write_csv(
        Path(args.aggregate_csv),
        aggregate_rows,
        headers=[
            "project_key",
            "date",
            "commits",
            "authors",
            "additions",
            "deletions",
            "churn",
            "truncated",
        ],
    )

    manifest = {
        "generated_at": _now_iso(),
        "mode": args.mode,
        "source": {
            "from": since_iso,
            "to": until_iso,
            "repo_count": len(repo_names),
            "repo_keys": repo_names,
            "aggregate_csv": args.aggregate_csv,
            "per_repo_dir": args.per_repo_dir,
        },
        "projects": projects_summary,
    }
    _write_json(Path(args.output_json), manifest)

    lines = [
        "# 205C_analiza_github_benchmark_q1_2026",
        "",
        f"Data generacji: `{manifest['generated_at']}`",
        "",
        "## Konfiguracja",
        "",
        f"- `from`: `{since_iso}`",
        f"- `to`: `{until_iso}`",
        f"- `repo_count`: `{len(repo_names)}`",
        f"- `aggregate_csv`: `{args.aggregate_csv}`",
        f"- `per_repo_dir`: `{args.per_repo_dir}`",
        "",
        "## Podsumowanie repo",
        "",
        "| Repo | Commits Q1 | Active Days | Authors | Additions | Deletions | Churn | Truncated |",
        "|---|---:|---:|---:|---:|---:|---:|---|",
    ]
    for p in sorted(projects_summary, key=lambda x: x["commits_q1"], reverse=True):
        lines.append(
            f"| `{p['project_key']}` | {p['commits_q1']} | {p['active_days_q1']} | "
            f"{p['authors_q1']} | {p['additions_q1']} | {p['deletions_q1']} | "
            f"{p['churn_q1']} | {str(p['truncated']).lower()} |"
        )

    md_path = Path(args.output_md)
    md_path.parent.mkdir(parents=True, exist_ok=True)
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Saved JSON manifest: {args.output_json}")
    print(f"Saved Markdown summary: {args.output_md}")
    print(f"Saved aggregate CSV: {args.aggregate_csv}")
    print(f"Saved per-repo artifacts: {args.per_repo_dir}")
    return 0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="GitHub benchmark Q1 2026: repo selection + per-day metrics export."
    )
    p.add_argument("--mode", choices=["discover", "analyze", "full"], default="full")
    p.add_argument("--env-file", default=".env.dev")
    p.add_argument("--token-env", default="GITHUB_TOKEN")

    p.add_argument("--from-date", default="2026-01-01")
    p.add_argument("--to-date", default="2026-03-31")

    # Search / selection
    p.add_argument("--language", default="Python")
    p.add_argument("--query-text", default="")
    p.add_argument("--include-forks", action="store_true")
    p.add_argument("--size-min-kb", type=int, default=50000)
    p.add_argument("--size-max-kb", type=int, default=0)
    p.add_argument("--project-limit", type=int, default=10)
    p.add_argument("--candidate-limit", type=int, default=300)
    p.add_argument("--min-commits-q1", type=int, default=1)
    p.add_argument("--star-shard", action="append", default=[])
    p.add_argument(
        "--search-sort",
        default="updated",
        choices=["updated", "stars", "forks", "help-wanted-issues"],
    )
    p.add_argument("--search-order", default="desc", choices=["asc", "desc"])
    p.add_argument("--max-pages-per-shard", type=int, default=10)

    # Repo input override
    p.add_argument(
        "--repo",
        action="append",
        default=[],
        help="Explicit repo full name owner/repo.",
    )
    p.add_argument(
        "--repo-file",
        default="docs_dev/_to_do/205_artifacts/205C/inputs/205C_repo_keys_selected.txt",
    )

    # API behavior
    p.add_argument("--per-page", type=int, default=100)
    p.add_argument("--timeout", type=float, default=30.0)
    p.add_argument("--max-retries", type=int, default=4)
    p.add_argument("--search-sleep-s", type=float, default=2.2)
    p.add_argument("--api-sleep-s", type=float, default=0.05)
    p.add_argument("--max-commits-per-repo", type=int, default=0)

    # Artifacts
    p.add_argument(
        "--selection-json",
        default="docs_dev/_to_do/205_artifacts/205C/selection/205C_repo_selection_github.json",
    )
    p.add_argument(
        "--selection-md",
        default="docs_dev/_to_do/205_artifacts/205C/selection/205C_repo_selection_github.md",
    )
    p.add_argument(
        "--selection-keys",
        default="docs_dev/_to_do/205_artifacts/205C/inputs/205C_repo_keys_selected.txt",
    )

    p.add_argument(
        "--output-json",
        default="docs_dev/_to_do/205_artifacts/205C/analysis/205C_analiza_github_benchmark_q1_2026.json",
    )
    p.add_argument(
        "--output-md",
        default="docs_dev/_to_do/205_artifacts/205C/analysis/205C_analiza_github_benchmark_q1_2026.md",
    )
    p.add_argument(
        "--aggregate-csv",
        default="docs_dev/_to_do/205_artifacts/205C/timeseries/205C_github_benchmark_q1_2026.csv",
    )
    p.add_argument(
        "--per-repo-dir", default="docs_dev/_to_do/205_artifacts/205C/timeseries"
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    env_values = _load_env_file(Path(args.env_file)) if args.env_file else {}
    token = _resolve_token(args, env_values)

    cfg = ApiConfig(
        token=token,
        timeout=args.timeout,
        max_retries=max(1, args.max_retries),
        search_sleep_s=max(0.0, args.search_sleep_s),
        api_sleep_s=max(0.0, args.api_sleep_s),
    )

    explicit_repos = _read_explicit_repos(args)

    if args.mode == "discover":
        candidates = _discover_candidates(args, cfg)
        selected = _select_repositories(candidates, args, cfg)
        _write_selection_artifacts(selected, args=args)
        print(f"Discovered candidates: {len(candidates)}")
        print(f"Selected repositories: {len(selected)}")
        print(f"Selection keys file: {args.selection_keys}")
        return 0

    if args.mode == "analyze":
        if not explicit_repos:
            raise GitHubApiError(
                "Analyze mode requires repos via --repo or --repo-file (owner/repo)."
            )
        return _analyze_repositories(explicit_repos, args, cfg)

    # full mode
    if explicit_repos:
        selected_names = explicit_repos[: args.project_limit]
    else:
        candidates = _discover_candidates(args, cfg)
        selected = _select_repositories(candidates, args, cfg)
        _write_selection_artifacts(selected, args=args)
        selected_names = [c.full_name for c in selected]

    if not selected_names:
        raise GitHubApiError("No repositories selected for analysis.")

    return _analyze_repositories(selected_names, args, cfg)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GitHubApiError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(2)
