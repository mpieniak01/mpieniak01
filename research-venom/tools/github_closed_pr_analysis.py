#!/usr/bin/env python3
"""Analyze closed GitHub pull requests with rate-limit aware pagination.

Outputs:
- JSON dataset with per-PR details
- Markdown summary report
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import statistics
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
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

STOPWORDS = {
    "the",
    "and",
    "for",
    "with",
    "from",
    "that",
    "this",
    "into",
    "are",
    "was",
    "were",
    "have",
    "has",
    "had",
    "you",
    "your",
    "our",
    "not",
    "but",
    "fix",
    "feat",
    "task",
    "chore",
    "pr",
    "wip",
    "add",
    "update",
    "refactor",
    "venom",
    "oraz",
    "dla",
    "jest",
    "oraz",
    "który",
    "ktora",
    "ktory",
    "oraz",
    "z",
    "na",
    "do",
    "i",
    "w",
    "or",
    "to",
    "of",
    "in",
    "a",
}

TOPIC_RULES: list[tuple[str, re.Pattern[str]]] = [
    (
        "frontend_ui",
        re.compile(
            r"\b(next|react|ui|frontend|cockpit|dashboard|screen|view|ux|layout|i18n)\b",
            re.I,
        ),
    ),
    (
        "backend_api",
        re.compile(
            r"\b(api|backend|fastapi|route|endpoint|schema|contract|orchestrator)\b",
            re.I,
        ),
    ),
    (
        "tests_quality",
        re.compile(
            r"\b(test|pytest|coverage|quality|sonar|lint|flake|ruff|mypy)\b", re.I
        ),
    ),
    ("docs", re.compile(r"\b(doc|docs|documentation|readme|guide)\b", re.I)),
    (
        "infra_devops",
        re.compile(
            r"\b(ci|workflow|docker|compose|k8s|infra|deploy|release|wsl)\b", re.I
        ),
    ),
    (
        "security",
        re.compile(r"\b(security|auth|token|vuln|cve|hardening|policy)\b", re.I),
    ),
    (
        "models_ai",
        re.compile(
            r"\b(model|onnx|ollama|vllm|llm|academy|lora|embedding|inference)\b", re.I
        ),
    ),
]


@dataclass
class RateState:
    remaining: int | None = None
    reset_epoch: int | None = None


def iso_to_date(value: str | None) -> dt.date | None:
    if not value:
        return None
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).date()


def gh_token() -> str:
    env_token = os.environ.get("GITHUB_TOKEN", "").strip()
    if env_token:
        return env_token
    try:
        token = subprocess.check_output(
            ["gh", "auth", "token"],
            text=True,
            stderr=subprocess.STDOUT,
        ).strip()
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        raise RuntimeError(
            "Unable to obtain GitHub token. Set GITHUB_TOKEN or run `gh auth login`."
        ) from exc
    if not token:
        raise RuntimeError(
            "Empty token from `gh auth token`. Set GITHUB_TOKEN or re-authenticate gh."
        )
    return token


def api_get(
    url: str, token: str, rate: RateState, max_retries: int = 4
) -> tuple[Any, dict[str, str]]:
    for attempt in range(max_retries):
        req = urllib.request.Request(url)
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")

        try:
            with urllib.request.urlopen(req, timeout=60) as resp:  # nosec B310
                headers = {k.lower(): v for k, v in resp.headers.items()}
                rate.remaining = (
                    int(headers.get("x-ratelimit-remaining", "0"))
                    if headers.get("x-ratelimit-remaining")
                    else None
                )
                rate.reset_epoch = (
                    int(headers.get("x-ratelimit-reset", "0"))
                    if headers.get("x-ratelimit-reset")
                    else None
                )
                data = json.loads(resp.read().decode("utf-8"))
                return data, headers
        except urllib.error.HTTPError as exc:
            if exc.code in {403, 429}:
                headers = {k.lower(): v for k, v in exc.headers.items()}
                reset = headers.get("x-ratelimit-reset")
                if reset and reset.isdigit():
                    wait_s = max(1, int(reset) - int(time.time()) + 1)
                    time.sleep(wait_s)
                    continue
                time.sleep(2 * (attempt + 1))
                continue
            if exc.code >= 500 and attempt < max_retries - 1:
                time.sleep(2 * (attempt + 1))
                continue
            raise
    raise RuntimeError(f"Failed to GET {url} after retries")


def fetch_closed_prs(
    owner: str, repo: str, token: str, per_page: int, max_prs: int, sleep_s: float
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    page = 1
    rate = RateState()

    while len(out) < max_prs:
        params = urllib.parse.urlencode(
            {
                "state": "closed",
                "per_page": per_page,
                "page": page,
                "sort": "updated",
                "direction": "desc",
            }
        )
        url = f"{GITHUB_API}/repos/{owner}/{repo}/pulls?{params}"
        batch, _ = api_get(url, token, rate)

        if not batch:
            break

        out.extend(batch)
        if len(batch) < per_page:
            break
        page += 1

        if len(out) >= max_prs:
            out = out[:max_prs]
            break

        if sleep_s > 0:
            time.sleep(sleep_s)

    return out


def enrich_pr_details(
    owner: str, repo: str, prs: list[dict[str, Any]], token: str, sleep_s: float
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    rate = RateState()
    total = len(prs)
    for idx, pr in enumerate(prs, start=1):
        number = pr.get("number")
        if not number:
            out.append(pr)
            continue
        url = f"{GITHUB_API}/repos/{owner}/{repo}/pulls/{number}"
        detailed, _ = api_get(url, token, rate)
        out.append(detailed)
        if sleep_s > 0 and idx < total:
            time.sleep(sleep_s)
    return out


def tokenize(text: str) -> list[str]:
    words = re.findall(r"[a-zA-Z][a-zA-Z0-9_-]{2,}", text.lower())
    return [w for w in words if w not in STOPWORDS]


def summarize(prs: list[dict[str, Any]]) -> dict[str, Any]:
    records: list[dict[str, Any]] = []
    month_counter = Counter()
    topic_counter = Counter()
    keyword_counter = Counter()

    for pr in prs:
        title = pr.get("title") or ""
        body = pr.get("body") or ""
        additions = int(pr.get("additions") or 0)
        deletions = int(pr.get("deletions") or 0)
        changed_files = int(pr.get("changed_files") or 0)
        comments = int(pr.get("comments") or 0)
        review_comments = int(pr.get("review_comments") or 0)
        closed_at = pr.get("closed_at")
        merged_at = pr.get("merged_at")
        realized_date = merged_at or closed_at

        rec = {
            "number": pr.get("number"),
            "title": title,
            "body": body,
            "url": pr.get("html_url"),
            "author": (pr.get("user") or {}).get("login"),
            "state": pr.get("state"),
            "created_at": pr.get("created_at"),
            "closed_at": closed_at,
            "merged_at": merged_at,
            "realization_date": realized_date,
            "additions": additions,
            "deletions": deletions,
            "line_changes": additions + deletions,
            "changed_files": changed_files,
            "comments": comments,
            "review_comments": review_comments,
            "total_comments": comments + review_comments,
        }
        records.append(rec)

        d = iso_to_date(closed_at)
        if d:
            month_counter[f"{d.year}-{d.month:02d}"] += 1

        full_text = f"{title}\n{body}"
        keyword_counter.update(tokenize(full_text))
        for name, rule in TOPIC_RULES:
            if rule.search(full_text):
                topic_counter[name] += 1

    merged_count = sum(1 for r in records if r["merged_at"])
    closed_only_count = len(records) - merged_count

    line_changes = [r["line_changes"] for r in records]
    comments = [r["total_comments"] for r in records]
    changed_files = [r["changed_files"] for r in records]

    top_by_lines = sorted(records, key=lambda r: r["line_changes"], reverse=True)[:20]
    top_by_comments = sorted(records, key=lambda r: r["total_comments"], reverse=True)[
        :20
    ]

    closed_dates = [iso_to_date(r["closed_at"]) for r in records if r["closed_at"]]

    return {
        "generated_at": dt.datetime.now(dt.UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "stats": {
            "total_closed_prs": len(records),
            "merged_prs": merged_count,
            "closed_unmerged_prs": closed_only_count,
            "first_closed_date": str(min(closed_dates)) if closed_dates else None,
            "last_closed_date": str(max(closed_dates)) if closed_dates else None,
            "total_additions": sum(r["additions"] for r in records),
            "total_deletions": sum(r["deletions"] for r in records),
            "total_line_changes": sum(r["line_changes"] for r in records),
            "total_comments": sum(r["total_comments"] for r in records),
            "avg_line_changes_per_pr": round(statistics.mean(line_changes), 2)
            if line_changes
            else 0,
            "median_line_changes_per_pr": round(statistics.median(line_changes), 2)
            if line_changes
            else 0,
            "avg_comments_per_pr": round(statistics.mean(comments), 2)
            if comments
            else 0,
            "median_comments_per_pr": round(statistics.median(comments), 2)
            if comments
            else 0,
            "avg_changed_files_per_pr": round(statistics.mean(changed_files), 2)
            if changed_files
            else 0,
            "median_changed_files_per_pr": round(statistics.median(changed_files), 2)
            if changed_files
            else 0,
        },
        "monthly_distribution": dict(sorted(month_counter.items())),
        "topic_distribution": dict(topic_counter.most_common()),
        "top_keywords": keyword_counter.most_common(30),
        "top_prs_by_line_changes": [
            {
                "number": r["number"],
                "title": r["title"],
                "line_changes": r["line_changes"],
                "additions": r["additions"],
                "deletions": r["deletions"],
                "total_comments": r["total_comments"],
                "realization_date": r["realization_date"],
                "url": r["url"],
            }
            for r in top_by_lines
        ],
        "top_prs_by_comments": [
            {
                "number": r["number"],
                "title": r["title"],
                "line_changes": r["line_changes"],
                "total_comments": r["total_comments"],
                "realization_date": r["realization_date"],
                "url": r["url"],
            }
            for r in top_by_comments
        ],
        "records": records,
    }


def markdown_report(
    owner_repo: str, payload: dict[str, Any], json_rel_path: str
) -> str:
    s = payload["stats"]
    monthly = payload["monthly_distribution"]
    topics = payload["topic_distribution"]
    top_keywords = payload["top_keywords"][:15]
    top_lines = payload["top_prs_by_line_changes"][:15]

    lines: list[str] = []
    lines.append(f"# 205_analiza_pr - Analiza zamkniętych PR ({owner_repo})")
    lines.append("")
    lines.append(f"Data generacji: `{payload['generated_at']}`")
    lines.append("")
    lines.append("## Zakres i metodyka")
    lines.append("")
    lines.append(
        "1. Źródło: GitHub REST API (`/repos/{owner}/{repo}/pulls?state=closed`)."
    )
    lines.append(
        "2. Skrypt: `tools/github_closed_pr_analysis.py` z paginacją (`per_page=100`) i retry/rate-limit guard."
    )
    lines.append(
        "3. Dla każdego PR zebrano: `title`, `body`, `line_changes (add+del)`, `realization_date (merged_at/closed_at)`, `comments + review_comments`."
    )
    lines.append(f"4. Pełny dataset: `{json_rel_path}`.")
    lines.append("")
    lines.append("## Wyniki główne")
    lines.append("")
    lines.append("| Metryka | Wartość |")
    lines.append("|---|---:|")
    lines.append(f"| Zamknięte PR | {s['total_closed_prs']} |")
    lines.append(f"| Merged PR | {s['merged_prs']} |")
    lines.append(f"| Closed bez merge | {s['closed_unmerged_prs']} |")
    lines.append(
        f"| Zakres dat closed | {s['first_closed_date']} -> {s['last_closed_date']} |"
    )
    lines.append(f"| Suma linii dodanych | {s['total_additions']} |")
    lines.append(f"| Suma linii usuniętych | {s['total_deletions']} |")
    lines.append(f"| Suma zmian linii (churn) | {s['total_line_changes']} |")
    lines.append(f"| Suma komentarzy (issue + review) | {s['total_comments']} |")
    lines.append(f"| Śr. churn / PR | {s['avg_line_changes_per_pr']} |")
    lines.append(f"| Mediana churn / PR | {s['median_line_changes_per_pr']} |")
    lines.append(f"| Śr. komentarzy / PR | {s['avg_comments_per_pr']} |")
    lines.append(f"| Mediana komentarzy / PR | {s['median_comments_per_pr']} |")
    lines.append("")

    lines.append("## Rozkład miesięczny (closed PR)")
    lines.append("")
    lines.append("| Miesiąc | Zamknięte PR |")
    lines.append("|---|---:|")
    for m, c in monthly.items():
        lines.append(f"| `{m}` | {c} |")
    lines.append("")

    lines.append("## Tematy dominujące (heurystyka słów kluczowych)")
    lines.append("")
    lines.append("| Temat | Liczba PR |")
    lines.append("|---|---:|")
    for t, c in topics.items():
        lines.append(f"| `{t}` | {c} |")
    lines.append("")

    lines.append("## Najczęstsze słowa (title+body)")
    lines.append("")
    lines.append("| Słowo | Wystąpienia |")
    lines.append("|---|---:|")
    for kw, c in top_keywords:
        lines.append(f"| `{kw}` | {c} |")
    lines.append("")

    lines.append("## Top 15 PR wg skali zmian linii")
    lines.append("")
    lines.append("| PR | Tytuł | Linie zmian | Komentarze | Data realizacji |")
    lines.append("|---:|---|---:|---:|---|")
    for r in top_lines:
        title = (r["title"] or "").replace("|", "\\|")
        lines.append(
            f"| [#{r['number']}]({r['url']}) | {title} | {r['line_changes']} | {r['total_comments']} | `{(r['realization_date'] or '')[:10]}` |"
        )
    lines.append("")

    lines.append("## Podsumowanie")
    lines.append("")
    lines.append(
        "1. Repo ma dużą bazę zamkniętych PR; skala zmian jest wysoka, a mediana churn na PR istotnie niższa od średniej (rozkład z długim ogonem dużych PR)."
    )
    lines.append(
        "2. Dominują obszary: backend/API, frontend/UI, testy/jakość oraz modele/AI, co jest spójne z ewolucją produktu i stabilizacją jakości."
    )
    lines.append(
        "3. Dla pracy inżynierskiej można wykorzystać: trend miesięczny, top PR wg churn oraz relację `churn <-> komentarze` jako wskaźnik złożoności zmian."
    )
    lines.append("")

    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Analyze closed PRs from GitHub with rate-limit aware fetching."
    )
    p.add_argument(
        "--config",
        default="config/process_pipeline_v01.json",
        help="Central pipeline config path (relative to repo root or absolute).",
    )
    p.add_argument(
        "--dataset-id",
        default="",
        help="Dataset identifier from config.process.steps (default: github_pr_comments).",
    )
    p.add_argument("--owner", default="")
    p.add_argument("--repo", default="")
    p.add_argument("--max-prs", type=int, default=2000)
    p.add_argument("--per-page", type=int, default=100)
    p.add_argument(
        "--sleep",
        type=float,
        default=0.15,
        help="Sleep between page requests (seconds).",
    )
    p.add_argument(
        "--detail-sleep",
        type=float,
        default=0.05,
        help="Sleep between per-PR detail requests (seconds).",
    )
    p.add_argument(
        "--no-enrich-details",
        action="store_true",
        help="Skip per-PR detail calls (faster but may miss additions/deletions/changed_files).",
    )
    p.add_argument(
        "--output-json",
        default="",
    )
    p.add_argument(
        "--output-md",
        default="",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = repo_root_from_script(__file__)
    cfg = load_pipeline_config(args.config, __file__)
    script_cfg = cfg_get(cfg, "scripts", "github_closed_pr_analysis", default={}) or {}
    dataset_id = choose_dataset_value(
        cfg,
        "github_pr_comments",
        "dataset_id",
        args.dataset_id,
        script_cfg,
        "github_pr_comments",
    )

    args.owner = choose_dataset_value(
        cfg, dataset_id, "owner", args.owner, script_cfg, "mpieniak01"
    )
    args.repo = choose_dataset_value(
        cfg, dataset_id, "repo", args.repo, script_cfg, "Venom"
    )
    args.output_json = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "output_json",
        args.output_json,
        script_cfg,
        "artifacts/products_light/pr_comments/analysis_2026_v01.json",
    )
    args.output_md = resolve_dataset_path(
        repo_root,
        cfg,
        dataset_id,
        "output_md",
        args.output_md,
        script_cfg,
        "artifacts/products_light/pr_comments/analysis_2026_v01.md",
    )
    token = gh_token()

    prs = fetch_closed_prs(
        owner=args.owner,
        repo=args.repo,
        token=token,
        per_page=max(1, min(args.per_page, 100)),
        max_prs=max(1, args.max_prs),
        sleep_s=max(0.0, args.sleep),
    )

    if not args.no_enrich_details:
        prs = enrich_pr_details(
            owner=args.owner,
            repo=args.repo,
            prs=prs,
            token=token,
            sleep_s=max(0.0, args.detail_sleep),
        )

    payload = summarize(prs)

    out_json = Path(args.output_json)
    out_md = Path(args.output_md)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_md.parent.mkdir(parents=True, exist_ok=True)

    out_json.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    rel_json = os.path.relpath(out_json, out_md.parent)
    out_md.write_text(
        markdown_report(f"{args.owner}/{args.repo}", payload, rel_json),
        encoding="utf-8",
    )

    print(f"Fetched closed PRs: {payload['stats']['total_closed_prs']}")
    print(f"Output JSON: {out_json}")
    print(f"Output MD:   {out_md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
