from __future__ import annotations

import argparse
from pathlib import Path

import pytest

import github_market_benchmark as gmb


def test_explicit_repo_file_keeps_venom_even_when_it_is_11th(tmp_path: Path) -> None:
    repos = [f"owner/repo{i}" for i in range(10)] + ["mpieniak01/Venom"]
    repo_file = tmp_path / "repos.txt"
    repo_file.write_text("\n".join(repos) + "\n", encoding="utf-8")

    args = argparse.Namespace(repo=[], repo_file=str(repo_file))

    assert gmb._read_explicit_repos(args) == repos


def test_full_mode_with_explicit_repos_does_not_apply_project_limit(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    repos = [f"owner/repo{i}" for i in range(10)] + ["mpieniak01/Venom"]
    repo_file = tmp_path / "repos.txt"
    repo_file.write_text("\n".join(repos) + "\n", encoding="utf-8")

    config = tmp_path / "config.json"
    config.write_text(
        '{"process":{"steps":{"github_market":{"paths":{}}}}}',
        encoding="utf-8",
    )
    captured: dict[str, list[str]] = {}

    def fake_analyze(repo_names: list[str], args: argparse.Namespace, cfg: gmb.ApiConfig) -> int:
        captured["repo_names"] = repo_names
        return 0

    monkeypatch.setattr(gmb, "_resolve_token", lambda args, env_values: "token")
    monkeypatch.setattr(gmb, "_analyze_repositories", fake_analyze)
    monkeypatch.setattr(
        gmb,
        "parse_args",
        lambda: argparse.Namespace(
            config=str(config),
            dataset_id="github_market",
            mode="full",
            env_file="",
            token_env="GITHUB_TOKEN",
            from_date="2026-01-01",
            to_date="2026-03-31",
            language="Python",
            query_text="",
            include_forks=False,
            size_min_kb=0,
            size_max_kb=0,
            project_limit=10,
            candidate_limit=300,
            min_commits_q1=1,
            star_shard=[],
            search_sort="updated",
            search_order="desc",
            max_pages_per_shard=10,
            repo=[],
            repo_file=str(repo_file),
            per_page=100,
            timeout=30.0,
            max_retries=1,
            search_sleep_s=0.0,
            api_sleep_s=0.0,
            max_commits_per_repo=0,
            selection_json="",
            selection_md="",
            selection_keys="",
            output_json="",
            output_md="",
            aggregate_csv="",
            per_repo_dir="",
        ),
    )

    assert gmb.main() == 0
    assert captured["repo_names"] == repos


def test_placeholder_token_is_ignored_before_gh_cli_fallback(monkeypatch: pytest.MonkeyPatch) -> None:
    args = argparse.Namespace(token_env="GITHUB_TOKEN")

    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    monkeypatch.setattr(gmb.subprocess, "check_output", lambda *args, **kwargs: "gh-token\n")

    token = gmb._resolve_token(args, {"GITHUB_TOKEN": "PASTE_GITHUB_TOKEN_HERE"})

    assert token == "gh-token"
