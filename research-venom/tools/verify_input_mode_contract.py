#!/usr/bin/env python3
"""Validate public-sample vs local-real input key contract for v04 configs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _step_paths(cfg: dict, step: str) -> dict:
    return cfg["process"]["steps"][step]["paths"]


def _assert(cond: bool, msg: str) -> None:
    if not cond:
        raise SystemExit(msg)


def _validate_ci_mode(repo_root: Path) -> None:
    # Public contract: "*_selected_v01.txt" are CI sample lists in the public repo.
    # Real/private keys are stored only under _external/not_tracked/*_real_v01.txt.
    v04 = _read_json(repo_root / "config/process_pipeline_v04.json")
    v04_test = _read_json(repo_root / "config/process_pipeline_v04_test.json")

    sonar_public = _step_paths(v04, "sonar_market")["project_key_file"]
    github_public = _step_paths(v04, "github_market")["repo_file"]
    github_public_sel = _step_paths(v04, "github_market")["selection_keys"]

    sonar_test = _step_paths(v04_test, "sonar_market")["project_key_file"]
    github_test = _step_paths(v04_test, "github_market")["repo_file"]
    github_test_sel = _step_paths(v04_test, "github_market")["selection_keys"]

    _assert(
        sonar_public.endswith("project_keys_selected_v01.txt"),
        f"v04 sonar path must point to public sample list, got: {sonar_public}",
    )
    _assert(
        github_public.endswith("repo_keys_selected_v01.txt"),
        f"v04 github repo path must point to public sample list, got: {github_public}",
    )
    _assert(
        github_public_sel.endswith("repo_keys_selected_v01.txt"),
        f"v04 github selection path must point to public sample list, got: {github_public_sel}",
    )

    _assert(
        sonar_test.endswith("project_keys_selected_v01.txt"),
        f"v04_test sonar path must point to public sample list, got: {sonar_test}",
    )
    _assert(
        github_test.endswith("repo_keys_selected_v01.txt"),
        f"v04_test github repo path must point to public sample list, got: {github_test}",
    )
    _assert(
        github_test_sel.endswith("repo_keys_selected_v01.txt"),
        f"v04_test github selection path must point to public sample list, got: {github_test_sel}",
    )

    _assert(
        (repo_root / sonar_test).exists(),
        f"missing sample sonar key file: {sonar_test}",
    )
    _assert(
        (repo_root / github_test).exists(),
        f"missing sample github key file: {github_test}",
    )
    _assert(
        not (repo_root / "artifacts/inputs/github_market/repo_keys_selected_sample_v01.txt").exists(),
        "legacy sample file naming detected: repo_keys_selected_sample_v01.txt should not exist in public contract",
    )
    _assert(
        not (repo_root / "artifacts/inputs/sonar_market/project_keys_selected_sample_v01.txt").exists(),
        "legacy sample file naming detected: project_keys_selected_sample_v01.txt should not exist in public contract",
    )


def _validate_local_real_mode(repo_root: Path) -> None:
    local_cfg = repo_root / "config/process_pipeline_v04_local_real.json"
    _assert(local_cfg.exists(), f"missing local real config: {local_cfg}")
    v04 = _read_json(local_cfg)

    sonar_real = _step_paths(v04, "sonar_market")["project_key_file"]
    github_real = _step_paths(v04, "github_market")["repo_file"]
    github_real_sel = _step_paths(v04, "github_market")["selection_keys"]

    _assert(
        sonar_real.endswith("_external/not_tracked/inputs/sonar_market/project_keys_selected_real_v01.txt"),
        f"local real mode requires private sonar path under _external/not_tracked, got: {sonar_real}",
    )
    _assert(
        github_real.endswith("_external/not_tracked/inputs/github_market/repo_keys_selected_real_v01.txt"),
        f"local real mode requires private github path under _external/not_tracked, got: {github_real}",
    )
    _assert(
        github_real_sel.endswith("_external/not_tracked/inputs/github_market/repo_keys_selected_real_v01.txt"),
        f"local real mode requires private github selection path under _external/not_tracked, got: {github_real_sel}",
    )
    _assert("_external/not_tracked/" in sonar_real, f"local real mode must use _external/not_tracked path: {sonar_real}")
    _assert("_external/not_tracked/" in github_real, f"local real mode must use _external/not_tracked path: {github_real}")
    _assert("_external/not_tracked/" in github_real_sel, f"local real mode must use _external/not_tracked path: {github_real_sel}")

    _assert((repo_root / sonar_real).exists(), f"missing real sonar key file: {sonar_real}")
    _assert((repo_root / github_real).exists(), f"missing real github key file: {github_real}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode",
        choices=("ci", "local-real"),
        required=True,
        help="ci: enforce public sample contract for v04/v04_test; local-real: enforce private config under _external/not_tracked",
    )
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Repository root path (default: current directory).",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    if args.mode == "ci":
        _validate_ci_mode(repo_root)
    else:
        _validate_local_real_mode(repo_root)
    print(f"input mode contract check passed: mode={args.mode}")


if __name__ == "__main__":
    main()
