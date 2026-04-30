from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = REPO_ROOT / "tools"
for path in (REPO_ROOT, TOOLS_DIR):
    text = str(path)
    if text not in sys.path:
        sys.path.insert(0, text)


def pytest_collection_modifyitems(config: pytest.Config, items: list[pytest.Item]) -> None:
    if os.environ.get("RUN_DATA_QUALITY_TESTS") == "1":
        return
    skip_data_quality = pytest.mark.skip(
        reason="data_quality tests require RUN_DATA_QUALITY_TESTS=1 and local artifacts"
    )
    for item in items:
        if "data_quality" in item.keywords:
            item.add_marker(skip_data_quality)
