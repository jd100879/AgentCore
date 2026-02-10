#!/usr/bin/env python3
"""Smoke-test the shareable report pipeline."""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
UBS_BIN = REPO_ROOT / "ubs"
TARGET = REPO_ROOT / "test-suite" / "python" / "buggy"


def run(cmd: list[str], allow_failure: bool = False) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 and not allow_failure:
        raise SystemExit(
            f"Command failed ({' '.join(cmd)}):\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )


def assert_json(path: Path, expect_comparison: bool) -> None:
    data = json.loads(path.read_text())
    assert "project" in data and "totals" in data, "missing required summary keys"
    git_meta = data.get("git", {})
    assert git_meta.get("repository"), "git metadata missing repository url"
    assert git_meta.get("commit"), "git metadata missing commit sha"
    if expect_comparison:
        comp = data.get("comparison")
        assert comp, "comparison block missing"
        delta = comp.get("delta") or {}
        for key in ("critical", "warning", "info"):
            assert key in delta, f"comparison delta missing {key}"
    else:
        assert "comparison" not in data, "baseline should not have comparison block"


def assert_html(path: Path) -> None:
    html = path.read_text()
    for snippet in ("UBS Report", "Per-language totals", "Critical"):
        assert snippet in html, f"HTML report missing snippet: {snippet}"


def main() -> None:
    tmpdir = Path(tempfile.mkdtemp(prefix="ubs-shareable-"))
    try:
        baseline = tmpdir / "baseline.json"
        current = tmpdir / "current.json"
        html_report = tmpdir / "report.html"

        base_cmd = [
            str(UBS_BIN),
            "--ci",
            "--only=python",
            "--category=resource-lifecycle",
            f"--report-json={baseline}",
            str(TARGET),
        ]
        run(base_cmd, allow_failure=True)
        assert baseline.exists(), "baseline JSON was not created"
        assert_json(baseline, expect_comparison=False)

        compare_cmd = [
            str(UBS_BIN),
            "--ci",
            "--only=python",
            "--category=resource-lifecycle",
            f"--comparison={baseline}",
            f"--report-json={current}",
            f"--html-report={html_report}",
            str(TARGET),
        ]
        run(compare_cmd, allow_failure=True)
        assert current.exists() and html_report.exists(), "shareable outputs missing"
        assert_json(current, expect_comparison=True)
        assert_html(html_report)

    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    main()
