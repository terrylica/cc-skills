"""
RSSI Level 2: Dynamic Capability Discovery

ADR: 2025-12-20-ralph-rssi-eternal-loop

Dynamically discovers what tools are installed and uses them to find
improvement opportunities. Never returns empty - always finds something.

SLO Enhancement: For Alpha Forge projects, filters busywork opportunities
and applies ruff --ignore for excluded rules.
"""

from __future__ import annotations

import json
import logging
import shutil
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)

# Subprocess timeout constants (seconds)
RUFF_TIMEOUT_SECONDS = 30
MYPY_TIMEOUT_SECONDS = 60
GIT_TIMEOUT_SECONDS = 10
GREP_TIMEOUT_SECONDS = 30


def discover_available_tools(project_dir: Path) -> dict[str, bool | list[str]]:
    """
    Dynamically discover what tools are installed.

    Returns:
        Dict mapping tool name to availability (bool) or list of tasks/scripts.
    """
    tools: dict[str, bool | list[str]] = {}

    # Python linters/formatters
    for tool in ["ruff", "mypy", "pylint", "bandit", "pyright"]:
        tools[tool] = shutil.which(tool) is not None

    # Security scanners
    for tool in ["gitleaks", "trufflehog", "semgrep"]:
        tools[tool] = shutil.which(tool) is not None

    # Link validators
    tools["lychee"] = shutil.which("lychee") is not None

    # Detect mise tasks
    mise_toml = project_dir / "mise.toml"
    if mise_toml.exists():
        tools["mise_tasks"] = _discover_mise_tasks(mise_toml)
    else:
        tools["mise_tasks"] = []

    # Detect npm scripts
    package_json = project_dir / "package.json"
    if package_json.exists():
        tools["npm_scripts"] = _discover_npm_scripts(package_json)
    else:
        tools["npm_scripts"] = []

    return tools


def _discover_mise_tasks(mise_toml: Path) -> list[str]:
    """Parse mise.toml for available tasks."""
    tasks = []
    try:
        content = mise_toml.read_text()
        # Simple parsing - look for [tasks.X] sections
        for line in content.split("\n"):
            if line.startswith("[tasks."):
                task_name = line.split("[tasks.")[1].rstrip("]").strip()
                if task_name:
                    tasks.append(task_name)
    except OSError:
        pass
    return tasks


def _discover_npm_scripts(package_json: Path) -> list[str]:
    """Parse package.json for available scripts."""
    try:
        data = json.loads(package_json.read_text())
        return list(data.get("scripts", {}).keys())
    except (json.JSONDecodeError, OSError):
        return []


def _is_alpha_forge_project(project_dir: Path) -> bool:
    """Check if this is an Alpha Forge project.

    Detection based on pyproject.toml containing 'alpha-forge' or 'alpha_forge'.
    """
    pyproject = project_dir / "pyproject.toml"
    if not pyproject.exists():
        return False

    try:
        content = pyproject.read_text()
        return "alpha-forge" in content or "alpha_forge" in content
    except OSError:
        return False


def _get_ruff_ignore_args(project_dir: Path) -> list[str]:
    """Get ruff --ignore args for Alpha Forge projects.

    Returns empty list for non-Alpha Forge projects.
    """
    if not _is_alpha_forge_project(project_dir):
        return []

    try:
        from alpha_forge_filter import EXCLUDED_RUFF_RULES

        return ["--ignore", ",".join(EXCLUDED_RUFF_RULES)]
    except ImportError:
        # Fallback if module not available
        return ["--ignore", "E501,SIM,RUF,I,ANN,DTZ,PERF"]


def _filter_opportunities_for_alpha_forge(
    opportunities: list[str], project_dir: Path
) -> list[str]:
    """Filter busywork opportunities for Alpha Forge projects.

    Returns original list for non-Alpha Forge projects.
    """
    if not _is_alpha_forge_project(project_dir):
        return opportunities

    try:
        from alpha_forge_filter import get_allowed_opportunities

        filtered = get_allowed_opportunities(opportunities)
        skipped_count = len(opportunities) - len(filtered)
        if skipped_count > 0:
            logger.debug(f"SLO filter: skipped {skipped_count} busywork opportunities")
        return filtered
    except ImportError:
        logger.warning("alpha_forge_filter not available, skipping SLO filtering")
        return opportunities


def rssi_scan_opportunities(
    project_dir: Path,
    disabled_checks: list[str] | None = None,
    prioritized_checks: list[str] | None = None,
) -> list[str]:
    """
    RSSI-grade opportunity scanning.

    Never returns empty - always finds something to improve.
    Uses dynamic capability discovery.

    SLO Enhancement: For Alpha Forge projects, filters busywork opportunities
    and applies ruff --ignore for excluded rules (E501, SIM, RUF, I, ANN, DTZ, PERF).

    Args:
        project_dir: Project directory to scan.
        disabled_checks: Checks to skip (from evolution state).
        prioritized_checks: Checks to run first (ordered by effectiveness).

    Returns:
        List of improvement opportunities. NEVER empty.
    """
    disabled = set(disabled_checks or [])
    opportunities: list[str] = []
    tools = discover_available_tools(project_dir)

    # Get Alpha Forge-specific ruff ignore args
    ruff_ignore_args = _get_ruff_ignore_args(project_dir)

    # TIER 1: Use available linters
    if tools.get("ruff") and "ruff" not in disabled:
        try:
            ruff_cmd = [
                "ruff",
                "check",
                ".",
                "--select=F,E,W",
                "--statistics",
                "--quiet",
            ] + ruff_ignore_args
            result = subprocess.run(
                ruff_cmd,
                cwd=project_dir,
                capture_output=True,
                text=True,
                timeout=RUFF_TIMEOUT_SECONDS,
            )
            if result.stdout.strip():
                first_line = result.stdout.split("\n")[0]
                opportunities.append(f"Fix ruff issues: {first_line}")
        except (subprocess.TimeoutExpired, OSError):
            pass

    if tools.get("mypy") and "mypy" not in disabled:
        try:
            result = subprocess.run(
                ["mypy", ".", "--ignore-missing-imports", "--no-error-summary"],
                cwd=project_dir,
                capture_output=True,
                text=True,
                timeout=MYPY_TIMEOUT_SECONDS,
            )
            if "error" in result.stdout:
                count = result.stdout.count("error:")
                opportunities.append(f"Fix {count} mypy type errors")
        except (subprocess.TimeoutExpired, OSError):
            pass

    # TIER 2: Git-based discovery
    if "git_status" not in disabled:
        try:
            result = subprocess.run(
                ["git", "status", "--porcelain"],
                cwd=project_dir,
                capture_output=True,
                text=True,
                timeout=GIT_TIMEOUT_SECONDS,
            )
            if result.stdout.strip():
                lines = [ln for ln in result.stdout.strip().split("\n") if ln]
                opportunities.append(f"Review {len(lines)} uncommitted changes")
        except (subprocess.TimeoutExpired, OSError):
            pass

    # TIER 3: Code pattern analysis (TODO/FIXME)
    if "todo_scan" not in disabled:
        try:
            result = subprocess.run(
                ["grep", "-r", "-l", "-E", "TODO|FIXME|XXX|HACK", "--include=*.py", "."],
                cwd=project_dir,
                capture_output=True,
                text=True,
                timeout=GREP_TIMEOUT_SECONDS,
            )
            if result.stdout.strip():
                files = [f for f in result.stdout.strip().split("\n") if f]
                opportunities.append(f"Address TODO/FIXME in {len(files)} files")
        except (subprocess.TimeoutExpired, OSError):
            pass

    # TIER 4: Use project-specific tasks
    mise_tasks = tools.get("mise_tasks", [])
    if isinstance(mise_tasks, list):
        for task in mise_tasks:
            if task in ["lint", "check", "test", "validate"] and f"mise_{task}" not in disabled:
                opportunities.append(f"Run mise task: {task}")

    npm_scripts = tools.get("npm_scripts", [])
    if isinstance(npm_scripts, list):
        for script in npm_scripts:
            if script in ["lint", "test", "check", "typecheck"] and f"npm_{script}" not in disabled:
                opportunities.append(f"Run npm script: {script}")

    # TIER 5: Security scanning
    if tools.get("gitleaks") and "gitleaks" not in disabled:
        opportunities.append("Run gitleaks scan for secrets")
    if tools.get("bandit") and "bandit" not in disabled:
        opportunities.append("Run bandit security scan")

    # TIER 6: Structural analysis (always available)
    structural = _analyze_codebase_structure(project_dir)
    opportunities.extend(structural)

    # TIER 7: RSSI meta-improvement (ALWAYS available - guarantees non-empty)
    opportunities.append("Review recent git commits for documentation gaps")
    opportunities.append("Analyze test coverage for recently changed files")

    # SLO FILTER: For Alpha Forge projects, filter busywork opportunities
    opportunities = _filter_opportunities_for_alpha_forge(opportunities, project_dir)

    # Ensure we still have opportunities after filtering (fallback to meta-improvement)
    if not opportunities:
        opportunities.append("Analyze test coverage for recently changed files")

    return opportunities  # NEVER returns empty due to Tier 7 + fallback


def _analyze_codebase_structure(project_dir: Path) -> list[str]:
    """Analyze codebase for structural improvements."""
    findings: list[str] = []

    try:
        # Files without docstrings (sample first 5)
        py_files = list(project_dir.rglob("*.py"))
        for py_file in py_files[:5]:
            try:
                content = py_file.read_text()
                # Skip empty files and __init__.py
                if (
                    content.strip()
                    and not py_file.name == "__init__.py"
                    and not content.strip().startswith('"""')
                ):
                    rel_path = py_file.relative_to(project_dir)
                    findings.append(f"Add module docstring: {rel_path}")
                    break  # One at a time
            except OSError:
                continue

        # Directories without README
        for subdir in project_dir.iterdir():
            if subdir.is_dir() and not subdir.name.startswith("."):
                try:
                    py_count = len(list(subdir.glob("*.py")))
                    if py_count >= 3 and not (subdir / "README.md").exists():
                        findings.append(f"Add README to {subdir.name}/ ({py_count} Python files)")
                        break  # One at a time
                except OSError:
                    continue
    except OSError:
        pass

    return findings
