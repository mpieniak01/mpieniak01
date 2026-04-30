from __future__ import annotations

from pathlib import Path
import subprocess
import sys

import path_config

REPO_ROOT = Path(__file__).resolve().parents[1]


def test_load_pipeline_config_empty_path_uses_default_config() -> None:
    cfg = path_config.load_pipeline_config("", __file__)

    assert cfg["project"]["name"] == "research-venom"


def test_load_pipeline_config_missing_or_directory_path_returns_empty() -> None:
    assert path_config.load_pipeline_config("missing-config.json", __file__) == {}
    assert path_config.load_pipeline_config(".", __file__) == {}


def test_report_alias_coverage_fails_for_missing_config() -> None:
    result = subprocess.run(
        [
            sys.executable,
            "tools/report_alias_coverage.py",
            "--config",
            "missing-config.json",
        ],
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    assert result.returncode != 0
    assert "missing or empty pipeline config" in result.stderr
