from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "tools" / "prepare_sources.py"


def _write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def _minimal_inputs(tmp_path: Path, *, include_venom_205c: bool = True) -> Path:
    data = tmp_path / "data"
    rows_205b = [
        {
            "project_key": "mpieniak01_Venom",
            "date": date,
            "issues": issues,
            "technical_debt_days": debt,
            "lines_of_code": loc,
            "line_coverage_pct": coverage,
            "unit_tests": tests,
        }
        for date, issues, debt, loc, coverage, tests in [
            ("2026-01-01", 10, 4.5, 1000, 80.0, 20),
            ("2026-01-02", 11, 4.0, 1100, 81.0, 22),
        ]
    ]
    rows_205c = [
        {
            "project_key": "other/repo",
            "date": "2026-01-01",
            "commits": 1,
            "authors": 1,
            "additions": 7,
            "deletions": 3,
            "churn": 10,
            "truncated": "false",
        },
        {
            "project_key": "other/repo",
            "date": "2026-01-02",
            "commits": 0,
            "authors": 0,
            "additions": 0,
            "deletions": 0,
            "churn": 0,
            "truncated": "false",
        },
    ]
    if include_venom_205c:
        rows_205c.extend(
            [
                {
                    "project_key": "mpieniak01/Venom",
                    "date": "2026-01-01",
                    "commits": 2,
                    "authors": 1,
                    "additions": 100,
                    "deletions": 30,
                    "churn": 130,
                    "truncated": "false",
                },
                {
                    "project_key": "mpieniak01/Venom",
                    "date": "2026-01-02",
                    "commits": 1,
                    "authors": 1,
                    "additions": 50,
                    "deletions": 20,
                    "churn": 70,
                    "truncated": "false",
                },
            ]
        )
    rows_205d = [
        {
            "project_key": "mpieniak01/Venom",
            "date": "2026-01-01",
            "pr_opened_count_daily": 2,
            "pr_merged_count_daily": 1,
            "pr_closed_not_merged_daily": 0,
            "pr_active_daily": 3,
            "pr_daily_avg_lead_time_hours": 12.0,
            "pr_daily_median_lead_time_hours": 10.0,
            "pr_daily_avg_review_latency_hours": 2.0,
            "lead_time_sample_size": 1,
        },
        {
            "project_key": "mpieniak01/Venom",
            "date": "2026-01-02",
            "pr_opened_count_daily": 0,
            "pr_merged_count_daily": 0,
            "pr_closed_not_merged_daily": 0,
            "pr_active_daily": 2,
            "pr_daily_avg_lead_time_hours": "",
            "pr_daily_median_lead_time_hours": "",
            "pr_daily_avg_review_latency_hours": "",
            "lead_time_sample_size": 0,
        },
    ]
    rows_205e = [
        {
            "project_key": "mpieniak01/Venom",
            "date": "2026-01-01",
            "closed_pr_count_daily": 1,
            "merged_pr_count_daily": 1,
            "avg_comments_closed_daily": 3,
            "median_comments_closed_daily": 3,
            "avg_comments_merged_daily": 3,
            "median_comments_merged_daily": 3,
        },
        {
            "project_key": "mpieniak01/Venom",
            "date": "2026-01-02",
            "closed_pr_count_daily": 0,
            "merged_pr_count_daily": 0,
            "avg_comments_closed_daily": "",
            "median_comments_closed_daily": "",
            "avg_comments_merged_daily": "",
            "median_comments_merged_daily": "",
        },
    ]
    rows_layout = [
        {
            "order": 1,
            "sheet_name": "src_github_repos_ts_raw",
            "input_table": "src_205C_timeseries",
            "role": "raw",
            "source_type": "github_api",
            "notes": "minimal",
        }
    ]

    _write_csv(data / "205b.csv", rows_205b)
    _write_csv(data / "205c.csv", rows_205c)
    _write_csv(data / "205d.csv", rows_205d)
    _write_csv(data / "205e.csv", rows_205e)
    _write_csv(data / "layout.csv", rows_layout)

    config = tmp_path / "config.json"
    out_json = tmp_path / "sources_pack.json"
    out_csv = tmp_path / "sources_pack.csv"
    config.write_text(
        json.dumps(
            {
                "process": {
                    "steps": {
                        "visualization_sources_pack": {
                            "venom_205b_key": "mpieniak01_Venom",
                            "venom_205c_key": "mpieniak01/Venom",
                            "venom_205d_key": "mpieniak01/Venom",
                            "paths": {
                                "in_205b": str(data / "205b.csv"),
                                "in_205c": str(data / "205c.csv"),
                                "in_205d": str(data / "205d.csv"),
                                "in_205e_daily": str(data / "205e.csv"),
                                "layout_csv": str(data / "layout.csv"),
                                "out_json": str(out_json),
                                "out_csv": str(out_csv),
                            },
                        }
                    }
                }
            }
        ),
        encoding="utf-8",
    )
    return config


def _run_prepare_sources(config: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--config",
            str(config),
            "--dataset-id",
            "visualization_sources_pack",
            "--date-from",
            "2026-01-01",
            "--date-to",
            "2026-01-02",
        ],
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def test_w33_uses_github_205c_for_venom_code_flow(tmp_path: Path) -> None:
    config = _minimal_inputs(tmp_path, include_venom_205c=True)

    result = _run_prepare_sources(config)

    assert result.returncode == 0, result.stderr
    pack = json.loads((tmp_path / "sources_pack.json").read_text(encoding="utf-8"))
    assert pack["validation"]["source_keys"]["w33_code_flow_source"] == "src_205C_timeseries"
    assert "src_local_git_venom_timeseries" not in pack["tables"]

    w33 = pack["tables"]["tpl_W33_code_flow"]
    assert [row["additions"] for row in w33] == [100, 50]
    assert [row["deletions_negative"] for row in w33] == [-30, -20]
    assert [row["phase_i"] for row in w33] == [100, 100]


def test_missing_venom_in_205c_is_hard_error_not_local_git_fallback(tmp_path: Path) -> None:
    config = _minimal_inputs(tmp_path, include_venom_205c=False)

    result = _run_prepare_sources(config)

    assert result.returncode != 0
    assert "Missing mpieniak01/Venom in 205C GitHub API timeseries" in result.stderr
    assert "github_market_benchmark.py" in result.stderr
