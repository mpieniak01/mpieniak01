from __future__ import annotations

from pathlib import Path

import path_config


def test_load_pipeline_config_empty_path_uses_default_config() -> None:
    cfg = path_config.load_pipeline_config("", __file__)

    assert cfg["project"]["name"] == "research-venom"


def test_load_pipeline_config_missing_or_directory_path_returns_empty() -> None:
    assert path_config.load_pipeline_config("missing-config.json", __file__) == {}
    assert path_config.load_pipeline_config(".", __file__) == {}
