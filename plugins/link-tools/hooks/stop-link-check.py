#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "python-ulid>=2.7.0",
#     "typing-extensions>=4.0.0",
# ]
# ///
"""
Link Checker Stop Hook

Universal link validation for Claude Code sessions using lychee.
Runs at session end (Stop hook event).

ADR: /docs/adr/2025-12-11-link-checker-plugin-extraction.md

Features:
- Lychee link validation (broken links, redirects)
- Path policy validation (relative paths in plugins)
- JSON output for programmatic consumption
- ULID correlation IDs for tracing

Exit codes:
- 0: Success (pass, skipped, or graceful error)
- 1: Hard error (invalid input)
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from ulid import ULID

try:
    import tomllib  # Python 3.11+
except ImportError:
    import tomli as tomllib  # Fallback for older Python


def generate_ulid() -> str:
    """Generate a ULID for correlation."""
    return str(ULID())


def find_lychee_config(workspace: Path, plugin_root: Path) -> Path | None:
    """
    Find lychee config using cascade resolution.

    Resolution order:
    1. {workspace}/.lycheerc.toml
    2. {workspace}/lychee.toml
    3. ~/.claude/.lycheerc.toml
    4. ${CLAUDE_PLUGIN_ROOT}/config/lychee.toml
    """
    candidates = [
        workspace / ".lycheerc.toml",
        workspace / "lychee.toml",
        Path.home() / ".claude" / ".lycheerc.toml",
        plugin_root / "config" / "lychee.toml",
    ]

    for config in candidates:
        if config.exists():
            return config

    return None


def load_exclude_paths(config_path: Path | None) -> list[str]:
    """
    Load exclude_path patterns from lychee config.

    Returns list of path patterns to exclude from path policy linting.
    These patterns are regex strings that match against relative file paths.
    """
    if not config_path or not config_path.exists():
        return []

    try:
        with open(config_path, "rb") as f:
            config = tomllib.load(f)
        return config.get("exclude_path", [])
    except (OSError, tomllib.TOMLDecodeError):
        return []


def find_git_root(workspace: Path) -> Path | None:
    """Find git repository root from workspace."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=workspace,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return Path(result.stdout.strip())
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return None


def discover_markdown_files(
    workspace: Path,
    exclude_patterns: list[str] | None = None,
) -> list[Path]:
    """
    Discover markdown files in workspace.

    Args:
        workspace: Root directory to search
        exclude_patterns: Regex patterns from lychee config's exclude_path
    """
    import re

    md_files: list[Path] = []

    # Default exclusion directories (always excluded)
    exclude_dirs = {
        "node_modules",
        ".git",
        "file-history",
        "plugins/marketplaces",
        ".venv",
        "backups",
        "__pycache__",
    }

    # Compile exclude_path patterns from config
    compiled_patterns: list[re.Pattern[str]] = []
    if exclude_patterns:
        for pattern in exclude_patterns:
            try:
                compiled_patterns.append(re.compile(pattern))
            except re.error:
                # Skip invalid regex patterns
                pass

    for md_file in workspace.rglob("*.md"):
        rel_path = md_file.relative_to(workspace)
        rel_path_str = str(rel_path)

        # Check if file is in excluded directory
        parts = set(rel_path.parts[:-1])
        if parts.intersection(exclude_dirs):
            continue

        # Check against exclude_path patterns from config
        if any(p.search(rel_path_str) for p in compiled_patterns):
            continue

        md_files.append(md_file)

    return md_files


def run_lychee(
    files: list[Path],
    workspace: Path,
    config_path: Path | None,
) -> dict[str, Any]:
    """
    Run lychee on markdown files.

    Returns dict with:
    - ran: bool (whether lychee executed)
    - error_count: int (number of broken links)
    - errors: list[str] (error messages)
    """
    # Check if lychee is installed
    if subprocess.run(["which", "lychee"], capture_output=True).returncode != 0:
        return {
            "ran": False,
            "error_count": 0,
            "errors": [],
            "skipped_reason": "lychee not installed",
        }

    if not files:
        return {
            "ran": True,
            "error_count": 0,
            "errors": [],
            "skipped_reason": "no markdown files found",
        }

    # Build lychee command
    cmd = ["lychee", "--format", "json"]

    if config_path:
        cmd.extend(["--config", str(config_path)])

    # Add root directory for repo-relative link resolution
    cmd.extend(["--root-dir", str(workspace)])

    # Add files
    cmd.extend(str(f) for f in files[:100])  # Limit to avoid arg length issues

    try:
        result = subprocess.run(
            cmd,
            cwd=workspace,
            capture_output=True,
            text=True,
            timeout=60,
            env={**os.environ, "NO_COLOR": "1"},
        )

        # Parse JSON output
        errors: list[str] = []
        error_count = 0

        if result.stdout.strip():
            try:
                lychee_output = json.loads(result.stdout)
                # Lychee JSON format: {"fail_map": {"file.md": [{"url": ..., "status": ...}]}}
                fail_map = lychee_output.get("fail_map", {})
                for file_path, failures in fail_map.items():
                    for failure in failures:
                        url = failure.get("url", "unknown")
                        status = failure.get("status", {})
                        error_count += 1
                        errors.append(f"{file_path}: {url} - {status}")
            except json.JSONDecodeError:
                # Fallback: count non-zero exit as error
                if result.returncode != 0:
                    error_count = 1
                    errors.append(result.stderr or "lychee returned non-zero")

        return {
            "ran": True,
            "error_count": error_count,
            "errors": errors,
        }

    except subprocess.TimeoutExpired:
        return {
            "ran": True,
            "error_count": 0,
            "errors": ["lychee timed out after 60s"],
            "skipped_reason": "timeout",
        }
    except (OSError, subprocess.SubprocessError) as e:
        return {
            "ran": False,
            "error_count": 0,
            "errors": [str(e)],
            "skipped_reason": f"error: {e}",
        }


def lint_paths(files: list[Path], workspace: Path) -> list[dict[str, Any]]:
    """
    Lint markdown files for path policy violations.

    Checks:
    - Absolute paths (/Users/...) in links
    - Parent escapes (../../..) that leave the repository

    Returns list of violations.
    """
    import re

    violations: list[dict[str, Any]] = []

    # Regex patterns for markdown links
    link_pattern = re.compile(r'\[([^\]]*)\]\(([^)]+)\)')

    for file_path in files:
        try:
            content = file_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            # Skip files that can't be read (permissions, encoding issues)
            continue

        for match in link_pattern.finditer(content):
            _link_text, link_url = match.groups()

            # Skip external URLs and anchors
            if link_url.startswith(("http://", "https://", "mailto:", "#")):
                continue

            # Check for absolute filesystem paths
            if link_url.startswith("/Users/") or link_url.startswith("/home/"):
                violations.append({
                    "file": str(file_path.relative_to(workspace)),
                    "rule": "NO_ABSOLUTE_PATHS",
                    "severity": "error",
                    "link": link_url,
                    "message": f"Absolute filesystem path detected: {link_url}",
                })

            # Check for excessive parent traversal
            if link_url.count("../") >= 5:
                violations.append({
                    "file": str(file_path.relative_to(workspace)),
                    "rule": "NO_PARENT_ESCAPES",
                    "severity": "warning",
                    "link": link_url,
                    "message": f"Excessive parent traversal (5+ levels): {link_url}",
                })

    return violations


def write_results_file(
    workspace: Path,
    lychee_result: dict[str, Any],
    path_violations: list[dict[str, Any]],
    correlation_id: str,
) -> Path | None:
    """Write detailed results to workspace file."""
    results_file = workspace / ".link-check-results.md"

    try:
        lines = [
            "# Link Check Results",
            "",
            f"**Correlation ID**: `{correlation_id}`",
            f"**Timestamp**: {__import__('datetime').datetime.now().isoformat()}",
            "",
        ]

        # Lychee results
        lines.append("## Lychee Link Validation")
        lines.append("")

        if not lychee_result.get("ran"):
            reason = lychee_result.get("skipped_reason", "unknown")
            lines.append(f"*Skipped*: {reason}")
        elif lychee_result.get("error_count", 0) == 0:
            lines.append("No broken links found.")
        else:
            lines.append(f"Found **{lychee_result['error_count']}** broken link(s):")
            lines.append("")
            for error in lychee_result.get("errors", [])[:20]:
                lines.append(f"- {error}")

        lines.append("")

        # Path violations
        lines.append("## Path Policy Violations")
        lines.append("")

        if not path_violations:
            lines.append("No path violations found.")
        else:
            lines.append(f"Found **{len(path_violations)}** violation(s):")
            lines.append("")
            for v in path_violations[:20]:
                lines.append(f"- **{v['rule']}** ({v['severity']}): {v['file']}")
                lines.append(f"  - {v['message']}")

        results_file.write_text("\n".join(lines), encoding="utf-8")
        return results_file

    except OSError:
        # File write failed (permissions, disk full, etc.)
        return None


def main() -> int:
    """Main entry point for Stop hook."""
    # Read hook input from stdin
    try:
        hook_input = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        # Invalid JSON - hard error
        print(json.dumps({
            "status": "error",
            "error_count": 0,
            "message": "Invalid JSON input",
        }))
        return 1

    # Check loop prevention flag
    if hook_input.get("stop_hook_active", False):
        print(json.dumps({
            "status": "skipped",
            "error_count": 0,
            "message": "Stop hook already active (loop prevention)",
        }))
        return 0

    # Determine workspace
    workspace_str = hook_input.get("cwd") or os.environ.get("CLAUDE_WORKSPACE_DIR", "")
    if not workspace_str:
        workspace_str = str(Path.home() / ".claude")

    workspace = Path(workspace_str)
    if not workspace.exists():
        print(json.dumps({
            "status": "error",
            "error_count": 0,
            "message": f"Workspace does not exist: {workspace}",
        }))
        return 0  # Graceful exit

    # Find git root (for repo-relative link resolution)
    git_root = find_git_root(workspace)
    effective_root = git_root or workspace

    # Determine plugin root
    plugin_root_str = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
    if plugin_root_str:
        plugin_root = Path(plugin_root_str)
    else:
        # Fallback: derive from this script's location
        plugin_root = Path(__file__).parent.parent

    # Generate correlation ID
    correlation_id = generate_ulid()

    # Find lychee config
    config_path = find_lychee_config(effective_root, plugin_root)

    # Load exclude_path patterns from config (used by both lychee and path linter)
    exclude_patterns = load_exclude_paths(config_path)

    # Discover markdown files (respects exclude_path from config)
    md_files = discover_markdown_files(effective_root, exclude_patterns)

    # Run lychee
    lychee_result = run_lychee(md_files, effective_root, config_path)

    # Run path linter
    path_violations = lint_paths(md_files, effective_root)

    # Write results file
    results_file = write_results_file(
        effective_root,
        lychee_result,
        path_violations,
        correlation_id,
    )

    # Calculate totals
    lychee_errors = lychee_result.get("error_count", 0)
    path_errors = len([v for v in path_violations if v["severity"] == "error"])
    total_errors = lychee_errors + path_errors

    # Determine status
    if not lychee_result.get("ran") and not md_files:
        status = "skipped"
    elif total_errors > 0:
        status = "fail"
    else:
        status = "pass"

    # Output JSON result
    result = {
        "status": status,
        "error_count": total_errors,
        "lychee_errors": lychee_errors,
        "path_violations": len(path_violations),
        "correlation_id": correlation_id,
    }

    if results_file:
        result["results_file"] = str(results_file)

    if lychee_result.get("skipped_reason"):
        result["lychee_skipped"] = lychee_result["skipped_reason"]

    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
