#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Lychee Subprocess Runner

Wrapper for running lychee link checker as a subprocess.

ADR: /docs/adr/2025-12-11-link-checker-plugin-extraction.md
"""

from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class LycheeResult:
    """Result from lychee execution."""

    ran: bool
    error_count: int
    errors: list[str] = field(default_factory=list)
    skipped_reason: str | None = None


def find_config(workspace: Path, plugin_root: Path | None = None) -> Path | None:
    """
    Find lychee config using cascade resolution.

    Resolution order:
    1. {workspace}/.lycheerc.toml
    2. {workspace}/lychee.toml
    3. ~/.claude/.lycheerc.toml
    4. ${CLAUDE_PLUGIN_ROOT}/config/lychee.toml (if plugin_root provided)

    Args:
        workspace: Workspace directory to search
        plugin_root: Optional plugin root for fallback config

    Returns:
        Path to config file, or None if not found
    """
    candidates = [
        workspace / ".lycheerc.toml",
        workspace / "lychee.toml",
        Path.home() / ".claude" / ".lycheerc.toml",
    ]

    if plugin_root:
        candidates.append(plugin_root / "config" / "lychee.toml")

    for config in candidates:
        if config.exists():
            return config

    return None


def is_lychee_installed() -> bool:
    """Check if lychee is available in PATH."""
    try:
        result = subprocess.run(
            ["which", "lychee"],
            capture_output=True,
            timeout=5,
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def run_lychee(
    files: list[Path],
    workspace: Path,
    config_path: Path | None = None,
    timeout: int = 60,
) -> LycheeResult:
    """
    Run lychee on markdown files.

    Args:
        files: List of markdown files to check
        workspace: Workspace root for --root-dir
        config_path: Optional path to lychee config
        timeout: Timeout in seconds (default 60)

    Returns:
        LycheeResult with execution details
    """
    if not is_lychee_installed():
        return LycheeResult(
            ran=False,
            error_count=0,
            skipped_reason="lychee not installed",
        )

    if not files:
        return LycheeResult(
            ran=True,
            error_count=0,
            skipped_reason="no files to check",
        )

    # Build command
    cmd = ["lychee", "--format", "json"]

    if config_path:
        cmd.extend(["--config", str(config_path)])

    # Add root directory for repo-relative link resolution
    cmd.extend(["--root-dir", str(workspace)])

    # Limit files to avoid argument length issues
    cmd.extend(str(f) for f in files[:100])

    try:
        result = subprocess.run(
            cmd,
            cwd=workspace,
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**os.environ, "NO_COLOR": "1"},
        )

        return parse_lychee_output(result.stdout, result.stderr, result.returncode)

    except subprocess.TimeoutExpired:
        return LycheeResult(
            ran=True,
            error_count=0,
            errors=[f"lychee timed out after {timeout}s"],
            skipped_reason="timeout",
        )
    except Exception as e:
        return LycheeResult(
            ran=False,
            error_count=0,
            errors=[str(e)],
            skipped_reason=f"error: {e}",
        )


def parse_lychee_output(
    stdout: str,
    stderr: str,
    returncode: int,
) -> LycheeResult:
    """
    Parse lychee JSON output.

    Lychee JSON format:
    {
        "fail_map": {
            "file.md": [{"url": "...", "status": {...}}]
        }
    }
    """
    errors: list[str] = []
    error_count = 0

    if stdout.strip():
        try:
            output: dict[str, Any] = json.loads(stdout)
            fail_map = output.get("fail_map", {})

            for file_path, failures in fail_map.items():
                for failure in failures:
                    url = failure.get("url", "unknown")
                    status = failure.get("status", {})
                    error_count += 1
                    errors.append(f"{file_path}: {url} - {status}")

        except json.JSONDecodeError:
            # Fallback: non-zero exit means errors
            if returncode != 0:
                error_count = 1
                errors.append(stderr or "lychee returned non-zero")

    return LycheeResult(
        ran=True,
        error_count=error_count,
        errors=errors,
    )


if __name__ == "__main__":
    # Simple CLI for testing
    import sys

    if len(sys.argv) < 2:
        print("Usage: lychee_runner.py <workspace>")
        sys.exit(1)

    workspace = Path(sys.argv[1])
    files = list(workspace.rglob("*.md"))[:10]

    result = run_lychee(files, workspace)
    print(f"Ran: {result.ran}")
    print(f"Errors: {result.error_count}")
    if result.skipped_reason:
        print(f"Skipped: {result.skipped_reason}")
    for error in result.errors[:5]:
        print(f"  - {error}")
