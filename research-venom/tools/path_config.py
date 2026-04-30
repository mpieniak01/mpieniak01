#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def repo_root_from_script(script_file: str) -> Path:
    return Path(script_file).resolve().parent.parent


def load_pipeline_config(config_path: str | None, script_file: str) -> dict[str, Any]:
    repo_root = repo_root_from_script(script_file)
    config_text = (config_path or "").strip()
    if not config_text:
        candidate = repo_root / "config" / "process_pipeline_v01.json"
    else:
        candidate = Path(config_text)
        if not candidate.is_absolute():
            candidate = repo_root / candidate
    if not candidate.is_file():
        return {}
    return json.loads(candidate.read_text(encoding="utf-8"))


def cfg_get(cfg: dict[str, Any], *keys: str, default: Any = None) -> Any:
    node: Any = cfg
    for key in keys:
        if not isinstance(node, dict) or key not in node:
            return default
        node = node[key]
    return node


def resolve_path(repo_root: Path, value: str | None) -> str:
    text = (value or "").strip()
    if not text:
        return ""
    path = Path(text)
    if path.is_absolute():
        return str(path)
    return str((repo_root / path).resolve())


def choose(cli_value: str | None, cfg_value: str | None, fallback: str) -> str:
    cli = (cli_value or "").strip()
    if cli:
        return cli
    cfg = (cfg_value or "").strip()
    if cfg:
        return cfg
    return fallback


def dataset_get(cfg: dict[str, Any], dataset_id: str, key: str, default: Any = None) -> Any:
    ds = cfg_get(cfg, "process", "steps", dataset_id, default={}) or {}
    if not isinstance(ds, dict):
        return default
    paths = ds.get("paths") if isinstance(ds.get("paths"), dict) else {}
    if isinstance(paths, dict) and key in paths:
        return paths.get(key)
    if key in ds:
        return ds.get(key)
    return default


def choose_dataset_value(
    cfg: dict[str, Any],
    dataset_id: str,
    key: str,
    cli_value: str | None,
    script_cfg: dict[str, Any],
    fallback: str,
) -> str:
    ds_value = dataset_get(cfg, dataset_id, key, default=None)
    cfg_value = ds_value if isinstance(ds_value, str) and ds_value.strip() else script_cfg.get(key)
    return choose(cli_value, cfg_value, fallback)


def resolve_configured_path(
    repo_root: Path, cfg: dict[str, Any], value: str | None, *, for_input: bool = False
) -> str:
    selected = (value or "").strip()
    if not selected:
        return ""
    return resolve_path(repo_root, selected)


def resolve_dataset_path(
    repo_root: Path,
    cfg: dict[str, Any],
    dataset_id: str,
    key: str,
    cli_value: str | None,
    script_cfg: dict[str, Any],
    fallback: str,
    *,
    for_input: bool = False,
) -> str:
    selected = choose_dataset_value(
        cfg=cfg,
        dataset_id=dataset_id,
        key=key,
        cli_value=cli_value,
        script_cfg=script_cfg,
        fallback=fallback,
    )
    return resolve_configured_path(repo_root, cfg, selected, for_input=for_input)
