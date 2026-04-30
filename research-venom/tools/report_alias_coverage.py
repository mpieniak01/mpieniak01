#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path
from typing import Any

from path_config import cfg_get, load_pipeline_config, repo_root_from_script, resolve_path

LEGACY_PATTERN = re.compile(r"(^|[\/_])205[BCDEF]?([\/_]|$)|205F", re.IGNORECASE)


def _collect_strings(node: Any, out: list[str]) -> None:
    if isinstance(node, dict):
        for value in node.values():
            _collect_strings(value, out)
    elif isinstance(node, list):
        for value in node:
            _collect_strings(value, out)
    elif isinstance(node, str):
        out.append(node)


def parse_args() -> argparse.Namespace:
    repo_root = repo_root_from_script(__file__)
    config_default = repo_root / "config" / "process_pipeline_v01.json"
    p = argparse.ArgumentParser(
        description="Generate legacy reference audit report for the process-first artifact contract."
    )
    p.add_argument("--config", default=str(config_default))
    p.add_argument(
        "--out-json",
        default="artifacts/meta/legacy_reference_audit_v01.json",
    )
    p.add_argument(
        "--out-md",
        default="artifacts/meta/legacy_reference_audit_v01.md",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = repo_root_from_script(__file__)
    cfg = load_pipeline_config(args.config, __file__)
    if not cfg:
        raise SystemExit(f"missing or empty pipeline config: {args.config}")

    datasets = cfg_get(cfg, "process", "steps", default={}) or {}
    scripts = cfg_get(cfg, "scripts", default={}) or {}
    paths = cfg_get(cfg, "paths", default={}) or {}

    script_values: list[str] = []
    _collect_strings(scripts, script_values)
    path_values: list[str] = []
    _collect_strings(paths, path_values)
    dataset_values: list[str] = []
    _collect_strings(datasets, dataset_values)

    scanned = list(dict.fromkeys(script_values + path_values + dataset_values))
    legacy_refs = sorted(
        {
            value
            for value in scanned
            if isinstance(value, str)
            and ("artifacts/" in value or value.startswith("_external/"))
            and LEGACY_PATTERN.search(value)
        }
    )

    report = {
        "generated_at": dt.datetime.now(dt.UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "config": str(Path(args.config).resolve()),
        "summary": {
            "legacy_refs_in_active_config": len(legacy_refs),
            "legacy_refs_expected": 0,
            "legacy_refs_ok": len(legacy_refs) == 0,
        },
        "legacy_refs": legacy_refs,
    }

    out_json = Path(resolve_path(repo_root, args.out_json))
    out_md = Path(resolve_path(repo_root, args.out_md))
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_md.parent.mkdir(parents=True, exist_ok=True)

    out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Legacy Reference Audit",
        "",
        f"- generated_at: `{report['generated_at']}`",
        f"- config: `{report['config']}`",
        f"- legacy_refs_in_active_config: `{report['summary']['legacy_refs_in_active_config']}`",
        f"- legacy_refs_expected: `{report['summary']['legacy_refs_expected']}`",
        f"- legacy_refs_ok: `{report['summary']['legacy_refs_ok']}`",
        "",
        "## Legacy References",
    ]
    if legacy_refs:
        for item in legacy_refs:
            lines.append(f"- `{item}`")
    else:
        lines.append("- none")

    out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"[AUDIT] json: {out_json}")
    print(f"[AUDIT] md:   {out_md}")
    print(f"[AUDIT] legacy refs: {len(legacy_refs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
