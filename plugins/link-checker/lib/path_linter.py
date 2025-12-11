#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Path Policy Linter

Validates markdown link paths against project policies.

ADR: /docs/adr/2025-12-11-link-checker-plugin-extraction.md

Policy Rules:
- NO_ABSOLUTE_PATHS: Links should not use filesystem absolute paths
- NO_PARENT_ESCAPES: Excessive ../ traversal may escape repository
- MARKETPLACE_RELATIVE: Plugin files should use relative paths
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Literal


@dataclass
class PathViolation:
    """A path policy violation."""

    file: str
    rule: str
    severity: Literal["error", "warning"]
    link: str
    message: str


# Regex pattern for markdown links: [text](url)
LINK_PATTERN = re.compile(r'\[([^\]]*)\]\(([^)]+)\)')


def check_absolute_paths(content: str) -> list[str]:
    """
    Detect absolute filesystem paths in markdown links.

    Args:
        content: Markdown file content

    Returns:
        List of absolute path links found
    """
    absolute_paths: list[str] = []

    for match in LINK_PATTERN.finditer(content):
        _, link_url = match.groups()

        # Skip external URLs and anchors
        if link_url.startswith(("http://", "https://", "mailto:", "#")):
            continue

        # Check for absolute filesystem paths
        if link_url.startswith("/Users/") or link_url.startswith("/home/"):
            absolute_paths.append(link_url)

    return absolute_paths


def check_relative_escapes(content: str, max_levels: int = 5) -> list[str]:
    """
    Detect excessive parent directory traversal in links.

    Args:
        content: Markdown file content
        max_levels: Maximum allowed ../ levels (default 5)

    Returns:
        List of links with excessive parent traversal
    """
    escapes: list[str] = []

    for match in LINK_PATTERN.finditer(content):
        _, link_url = match.groups()

        # Skip external URLs and anchors
        if link_url.startswith(("http://", "https://", "mailto:", "#")):
            continue

        # Count parent traversals
        if link_url.count("../") >= max_levels:
            escapes.append(link_url)

    return escapes


def check_marketplace_relative(
    content: str,
    file_path: Path,
    workspace: Path,
) -> list[str]:
    """
    Check if plugin files use relative paths correctly.

    Plugin files (in plugins/ directories) should use ./ or ../ relative paths,
    not repo-root absolute paths starting with /.

    Args:
        content: Markdown file content
        file_path: Path to the file being checked
        workspace: Workspace root

    Returns:
        List of violating links (repo-absolute in plugin context)
    """
    violations: list[str] = []

    # Check if file is in a plugins directory
    try:
        rel_path = file_path.relative_to(workspace)
        parts = rel_path.parts
    except ValueError:
        return violations

    # Only check files under plugins/
    if "plugins" not in parts:
        return violations

    for match in LINK_PATTERN.finditer(content):
        _, link_url = match.groups()

        # Skip external URLs and anchors
        if link_url.startswith(("http://", "https://", "mailto:", "#")):
            continue

        # In plugin context, links starting with / are repo-absolute
        # They should be ./ or ../ relative instead
        if link_url.startswith("/") and not link_url.startswith("/Users"):
            violations.append(link_url)

    return violations


def lint_paths(
    files: list[Path],
    workspace: Path,
    check_marketplace: bool = True,
) -> list[PathViolation]:
    """
    Lint markdown files for path policy violations.

    Args:
        files: List of markdown files to check
        workspace: Workspace root directory
        check_marketplace: Whether to check marketplace relative path rules

    Returns:
        List of PathViolation objects
    """
    violations: list[PathViolation] = []

    for file_path in files:
        try:
            content = file_path.read_text(encoding="utf-8")
        except Exception:
            continue

        try:
            rel_file = str(file_path.relative_to(workspace))
        except ValueError:
            rel_file = str(file_path)

        # Check absolute paths
        for link in check_absolute_paths(content):
            violations.append(PathViolation(
                file=rel_file,
                rule="NO_ABSOLUTE_PATHS",
                severity="error",
                link=link,
                message=f"Absolute filesystem path detected: {link}",
            ))

        # Check parent escapes
        for link in check_relative_escapes(content):
            violations.append(PathViolation(
                file=rel_file,
                rule="NO_PARENT_ESCAPES",
                severity="warning",
                link=link,
                message=f"Excessive parent traversal (5+ levels): {link}",
            ))

        # Check marketplace relative paths
        if check_marketplace:
            for link in check_marketplace_relative(content, file_path, workspace):
                violations.append(PathViolation(
                    file=rel_file,
                    rule="MARKETPLACE_RELATIVE",
                    severity="warning",
                    link=link,
                    message=f"Plugin file uses repo-absolute path (should be relative): {link}",
                ))

    return violations


if __name__ == "__main__":
    # Simple CLI for testing
    import sys

    if len(sys.argv) < 2:
        print("Usage: path_linter.py <workspace>")
        sys.exit(1)

    workspace = Path(sys.argv[1])
    files = list(workspace.rglob("*.md"))[:20]

    violations = lint_paths(files, workspace)

    if not violations:
        print("No path violations found.")
        sys.exit(0)

    print(f"Found {len(violations)} violation(s):\n")
    for v in violations:
        print(f"[{v.severity.upper()}] {v.rule}")
        print(f"  File: {v.file}")
        print(f"  Link: {v.link}")
        print(f"  {v.message}\n")

    sys.exit(1 if any(v.severity == "error" for v in violations) else 0)
