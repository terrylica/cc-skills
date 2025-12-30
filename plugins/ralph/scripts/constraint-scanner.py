#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
# ADR: /docs/adr/2025-12-29-ralph-constraint-scanning.md
"""Ralph Constraint Scanner - Detect environment constraints before loop start.

Scans current alpha-forge worktree for hardcoded paths, rigid structure assumptions,
and other constraints that limit Ralph's freedom to refactor and explore.

4-Tier Severity System:
- CRITICAL: Block loop start, must be resolved
- HIGH: Escalate to user via AUQ, recommend prohibiting
- MEDIUM: Show in deep-dive, optional action
- LOW: Log only, informational

Usage:
    uv run constraint-scanner.py --project /path/to/project
    uv run constraint-scanner.py --project /path/to/project --output results.json
    uv run constraint-scanner.py --project /path/to/project --severity high
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any


class Severity(str, Enum):
    """4-tier severity classification for constraints."""
    CRITICAL = "critical"  # Block loop start
    HIGH = "high"          # Escalate to user, recommend prohibit
    MEDIUM = "medium"      # Show in deep-dive
    LOW = "low"            # Log only


@dataclass
class Constraint:
    """A detected constraint that limits Ralph's freedom."""
    id: str
    severity: str
    category: str
    description: str
    file: str = ""
    line: int = 0
    value: str = ""
    recommendation: str = ""


@dataclass
class BuiltinBusywork:
    """Busywork pattern from alpha_forge_filter.py."""
    id: str
    name: str
    description: str
    enabled: bool = True


@dataclass
class ScanResult:
    """Complete scan result."""
    scan_timestamp: str
    project_dir: str
    worktree_type: str  # "main" | "linked"
    main_repo_root: str
    constraints: list[Constraint] = field(default_factory=list)
    builtin_busywork: list[BuiltinBusywork] = field(default_factory=list)
    error: str | None = None


def get_worktree_info(project_dir: str) -> tuple[str, str, str]:
    """Detect worktree type using git rev-parse --git-common-dir.

    Returns:
        (worktree_type, main_repo_root, current_worktree)
        - worktree_type: "main" | "linked" | "not_git"
        - main_repo_root: Path to main repository
        - current_worktree: Path to current worktree
    """
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"],
            capture_output=True,
            text=True,
            cwd=project_dir,
            timeout=10,
        )
        if result.returncode != 0:
            return "not_git", "", project_dir

        git_common_dir = result.stdout.strip()

        if git_common_dir == ".git":
            # Main worktree
            return "main", project_dir, project_dir
        else:
            # Linked worktree - git-common-dir points to main's .git
            main_root = str(Path(git_common_dir).parent)
            return "linked", main_root, project_dir

    except subprocess.TimeoutExpired:
        print("[constraint-scanner] Warning: git command timed out", file=sys.stderr)
        return "timeout", "", project_dir
    except FileNotFoundError:
        print("[constraint-scanner] Warning: git not found", file=sys.stderr)
        return "no_git", "", project_dir


def is_alpha_forge(main_repo_root: str) -> bool:
    """Check if this is an alpha-forge repository."""
    if not main_repo_root:
        return False
    return Path(main_repo_root).name == "alpha-forge"


def scan_hardcoded_paths(project_dir: str) -> list[Constraint]:
    """Scan for hardcoded absolute paths in config files."""
    constraints = []
    home_dir = os.path.expanduser("~")
    constraint_id = 0

    # Patterns to scan for
    patterns = [
        (r"/Users/[^/]+/", Severity.HIGH, "Absolute user path"),
        (r"/home/[^/]+/", Severity.HIGH, "Absolute home path"),
        (rf"{re.escape(home_dir)}", Severity.CRITICAL, "Current user home path"),
    ]

    # Files to scan
    scan_files = [
        ".claude/settings.json",
        ".claude/settings.local.json",
        ".claude/ralph-config.json",
        "pyproject.toml",
    ]

    for rel_path in scan_files:
        file_path = Path(project_dir) / rel_path
        if not file_path.exists():
            continue

        try:
            content = file_path.read_text()
            lines = content.split("\n")

            for line_num, line in enumerate(lines, 1):
                for pattern, severity, desc in patterns:
                    matches = re.findall(pattern, line)
                    for match in matches:
                        constraint_id += 1
                        constraints.append(Constraint(
                            id=f"hardcoded-{constraint_id:03d}",
                            severity=severity.value,
                            category="hardcoded_path",
                            description=f"{desc} in {rel_path}:{line_num}",
                            file=rel_path,
                            line=line_num,
                            value=match,
                            recommendation="Use relative paths or environment variables",
                        ))
        except (OSError, UnicodeDecodeError) as e:
            print(f"[constraint-scanner] Warning: Could not read {file_path}: {e}", file=sys.stderr)

    return constraints


def scan_rigid_structure(project_dir: str) -> list[Constraint]:
    """Scan for rigid file structure assumptions."""
    constraints = []
    constraint_id = 0

    # Rigid structure patterns
    rigid_patterns = [
        ("packages/alpha-forge-core/", Severity.HIGH, "Rigid package structure assumption"),
        ("outputs/runs/", Severity.MEDIUM, "Output directory dependency"),
        ("data/raw/", Severity.LOW, "Data directory assumption"),
        ("models/trained/", Severity.LOW, "Model directory assumption"),
    ]

    # Check pyproject.toml and setup files
    config_files = ["pyproject.toml", ".claude/settings.json"]

    for config_file in config_files:
        file_path = Path(project_dir) / config_file
        if not file_path.exists():
            continue

        try:
            content = file_path.read_text()
            lines = content.split("\n")

            for line_num, line in enumerate(lines, 1):
                for pattern, severity, desc in rigid_patterns:
                    if pattern in line:
                        constraint_id += 1
                        constraints.append(Constraint(
                            id=f"structure-{constraint_id:03d}",
                            severity=severity.value,
                            category="rigid_structure",
                            description=f"{desc} in {config_file}:{line_num}",
                            file=config_file,
                            line=line_num,
                            value=pattern,
                            recommendation="Consider making paths configurable",
                        ))
        except (OSError, UnicodeDecodeError) as e:
            print(f"[constraint-scanner] Warning: Could not read {file_path}: {e}", file=sys.stderr)

    return constraints


def scan_global_claude_config() -> list[Constraint]:
    """Scan ~/.claude/ for Ralph-affecting configurations."""
    constraints = []
    constraint_id = 0
    claude_dir = Path.home() / ".claude"

    if not claude_dir.exists():
        return constraints

    # Check for hook configurations that might conflict
    settings_file = claude_dir / "settings.json"
    if settings_file.exists():
        try:
            data = json.loads(settings_file.read_text())
            hooks = data.get("hooks", {})

            # Check for conflicting hooks
            for hook_type, hook_list in hooks.items():
                if isinstance(hook_list, list):
                    for hook in hook_list:
                        if "ralph" not in str(hook).lower():
                            # Non-Ralph hook that might interfere
                            constraint_id += 1
                            constraints.append(Constraint(
                                id=f"hook-{constraint_id:03d}",
                                severity=Severity.LOW.value,
                                category="global_hook",
                                description=f"Non-Ralph {hook_type} hook may interfere",
                                file="~/.claude/settings.json",
                                value=str(hook)[:100],
                                recommendation="Review for Ralph compatibility",
                            ))
        except (OSError, json.JSONDecodeError) as e:
            print(f"[constraint-scanner] Warning: Could not parse settings.json: {e}", file=sys.stderr)

    return constraints


def get_builtin_busywork() -> list[BuiltinBusywork]:
    """Get built-in busywork patterns from alpha_forge_filter.py categories.

    These are toggleable options that Ralph can filter out.
    """
    return [
        BuiltinBusywork(
            id="busywork-lint",
            name="Linting/style rules",
            description="Ruff, Black, isort formatting suggestions",
        ),
        BuiltinBusywork(
            id="busywork-docs",
            name="Documentation gaps",
            description="Missing docstrings, README updates",
        ),
        BuiltinBusywork(
            id="busywork-types",
            name="Type hint additions",
            description="Adding type annotations to untyped code",
        ),
        BuiltinBusywork(
            id="busywork-todo",
            name="TODO/FIXME cleanup",
            description="Addressing inline TODO comments",
        ),
        BuiltinBusywork(
            id="busywork-security",
            name="Security warnings",
            description="Non-critical security scanner findings",
        ),
        BuiltinBusywork(
            id="busywork-tests",
            name="Test coverage gaps",
            description="Adding tests for existing code",
        ),
        BuiltinBusywork(
            id="busywork-git",
            name="Git hygiene",
            description="Commit message style, branch cleanup",
        ),
        BuiltinBusywork(
            id="busywork-refactor",
            name="Code smell refactoring",
            description="Optional refactoring suggestions",
        ),
        BuiltinBusywork(
            id="busywork-deps",
            name="Dependency updates",
            description="Non-breaking dependency version bumps",
        ),
        BuiltinBusywork(
            id="busywork-cicd",
            name="CI/CD improvements",
            description="GitHub Actions, pre-commit hook tweaks",
        ),
    ]


def run_scan(project_dir: str, min_severity: str | None = None) -> ScanResult:
    """Run full constraint scan on project directory.

    Args:
        project_dir: Path to project directory
        min_severity: Minimum severity to include (critical/high/medium/low)

    Returns:
        ScanResult with all detected constraints
    """
    worktree_type, main_repo_root, current_worktree = get_worktree_info(project_dir)

    # Check if alpha-forge
    if worktree_type == "not_git":
        return ScanResult(
            scan_timestamp=datetime.now(timezone.utc).isoformat(),
            project_dir=project_dir,
            worktree_type="not_git",
            main_repo_root="",
            error="Not a git repository",
        )

    if worktree_type == "timeout":
        return ScanResult(
            scan_timestamp=datetime.now(timezone.utc).isoformat(),
            project_dir=project_dir,
            worktree_type="timeout",
            main_repo_root="",
            error="Git command timed out",
        )

    if not is_alpha_forge(main_repo_root):
        return ScanResult(
            scan_timestamp=datetime.now(timezone.utc).isoformat(),
            project_dir=project_dir,
            worktree_type=worktree_type,
            main_repo_root=main_repo_root,
            constraints=[],
            builtin_busywork=[],
            error=None,  # Not an error, just not alpha-forge
        )

    # Run all scanners
    all_constraints: list[Constraint] = []
    all_constraints.extend(scan_hardcoded_paths(project_dir))
    all_constraints.extend(scan_rigid_structure(project_dir))
    all_constraints.extend(scan_global_claude_config())

    # Filter by severity if requested
    if min_severity:
        severity_order = ["critical", "high", "medium", "low"]
        try:
            min_idx = severity_order.index(min_severity.lower())
            all_constraints = [
                c for c in all_constraints
                if severity_order.index(c.severity) <= min_idx
            ]
        except ValueError:
            print(f"[constraint-scanner] Warning: Unknown severity '{min_severity}'", file=sys.stderr)

    # Sort by severity (critical first)
    severity_priority = {"critical": 0, "high": 1, "medium": 2, "low": 3}
    all_constraints.sort(key=lambda c: severity_priority.get(c.severity, 99))

    return ScanResult(
        scan_timestamp=datetime.now(timezone.utc).isoformat(),
        project_dir=project_dir,
        worktree_type=worktree_type,
        main_repo_root=main_repo_root,
        constraints=all_constraints,
        builtin_busywork=get_builtin_busywork(),
    )


def result_to_dict(result: ScanResult) -> dict[str, Any]:
    """Convert ScanResult to JSON-serializable dict."""
    return {
        "scan_timestamp": result.scan_timestamp,
        "project_dir": result.project_dir,
        "worktree_type": result.worktree_type,
        "main_repo_root": result.main_repo_root,
        "constraints": [asdict(c) for c in result.constraints],
        "builtin_busywork": [asdict(b) for b in result.builtin_busywork],
        "error": result.error,
    }


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Scan for constraints before Ralph loop start",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    uv run constraint-scanner.py --project .
    uv run constraint-scanner.py --project ~/eon/alpha-forge --severity high
    uv run constraint-scanner.py --project . --output ~/.claude/scan-results.json
        """,
    )
    parser.add_argument(
        "--project",
        required=True,
        help="Project directory to scan",
    )
    parser.add_argument(
        "--output",
        help="Output file path (default: stdout)",
    )
    parser.add_argument(
        "--severity",
        choices=["critical", "high", "medium", "low"],
        help="Minimum severity to include",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress stderr warnings",
    )

    args = parser.parse_args()

    # Expand path
    project_dir = os.path.expanduser(args.project)
    if not os.path.isdir(project_dir):
        print(f"Error: Project directory does not exist: {project_dir}", file=sys.stderr)
        return 1

    # Run scan
    result = run_scan(project_dir, args.severity)
    output = json.dumps(result_to_dict(result), indent=2)

    # Write output
    if args.output:
        output_path = Path(os.path.expanduser(args.output))
        try:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(output)
            if not args.quiet:
                print(f"[constraint-scanner] Results written to {output_path}", file=sys.stderr)
        except OSError as e:
            print(f"[constraint-scanner] Warning: Could not write output: {e}", file=sys.stderr)
            print(output)  # Fall back to stdout
    else:
        print(output)

    # Exit code based on critical constraints
    critical_count = sum(1 for c in result.constraints if c.severity == "critical")
    if critical_count > 0:
        if not args.quiet:
            print(f"[constraint-scanner] Found {critical_count} CRITICAL constraint(s)", file=sys.stderr)
        return 2  # Critical constraints found

    return 0


if __name__ == "__main__":
    sys.exit(main())
