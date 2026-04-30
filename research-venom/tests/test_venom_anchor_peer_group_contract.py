from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "tools" / "prepare_sources.py"
TOOLS_DIR = REPO_ROOT / "tools"


def _load_prepare_sources_module():
    tools_dir_str = str(TOOLS_DIR)
    if tools_dir_str not in sys.path:
        sys.path.insert(0, tools_dir_str)
    spec = importlib.util.spec_from_file_location("prepare_sources", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load prepare_sources.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_select_anchor_peer_group_orders_venom_first_and_limits_size() -> None:
    mod = _load_prepare_sources_module()
    rows = [
        {"project_key": "alpha/one", "metric": 10},
        {"project_key": "mpieniak01/Venom", "metric": 2},
        {"project_key": "beta/two", "metric": 4},
        {"project_key": "gamma/three", "metric": 50},
        {"project_key": "delta/four", "metric": 3},
        {"project_key": "epsilon/five", "metric": 7},
    ]

    selected = mod._select_anchor_peer_group(
        rows,
        anchor_project_key="mpieniak01/Venom",
        max_projects=4,
        metric_field="metric",
    )

    assert [row["project_key"] for row in selected] == [
        "mpieniak01/Venom",
        "delta/four",
        "beta/two",
        "epsilon/five",
    ]


def test_select_anchor_peer_group_fails_when_anchor_missing() -> None:
    mod = _load_prepare_sources_module()
    rows = [{"project_key": "alpha/one", "metric": 10}]

    try:
        mod._select_anchor_peer_group(
            rows,
            anchor_project_key="mpieniak01/Venom",
            max_projects=4,
            metric_field="metric",
        )
    except RuntimeError as exc:
        assert "Missing anchor project" in str(exc)
    else:
        raise AssertionError("Expected RuntimeError for missing anchor project")
