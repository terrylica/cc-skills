"""
Ralph Level 4: Self-Modification

ADR: 2025-12-20-ralph-rssi-eternal-loop

Ralph (Recursively Self-Improving Superintelligence) evolves discovery
mechanisms based on effectiveness tracking. Proposes new checks, disables
underperforming ones, learns project conventions.
"""

from __future__ import annotations

import json
import shutil
from datetime import datetime
from pathlib import Path

from core.constants import STATE_DIR

EVOLUTION_LOG = STATE_DIR / "ralph-evolution.json"


def load_evolution_state() -> dict:
    """
    Load the evolution state - what checks have been added/removed.

    Returns:
        Dict with evolution state including added_checks, disabled_checks,
        learned_patterns, tool_effectiveness, and last_evolution timestamp.
    """
    if EVOLUTION_LOG.exists():
        try:
            return json.loads(EVOLUTION_LOG.read_text())
        except (json.JSONDecodeError, OSError):
            pass

    return {
        "added_checks": [],
        "disabled_checks": [],
        "learned_patterns": {},
        "tool_effectiveness": {},
        "last_evolution": None,
    }


def save_evolution_state(state: dict) -> None:
    """
    Persist evolution state to JSON.

    Args:
        state: Evolution state dict to persist.
    """
    state["last_evolution"] = datetime.now().isoformat()
    EVOLUTION_LOG.parent.mkdir(parents=True, exist_ok=True)
    EVOLUTION_LOG.write_text(json.dumps(state, indent=2))


def propose_new_check(check_name: str, check_command: str, rationale: str) -> dict:
    """
    Propose a new check to add to Ralph (Recursively Self-Improving Superintelligence) discovery.

    Args:
        check_name: Unique identifier for the check.
        check_command: Shell command to run.
        rationale: Why this check is valuable.

    Returns:
        Proposal dict that can be written to evolution log
        for human review or auto-integration.
    """
    return {
        "type": "new_check",
        "name": check_name,
        "command": check_command,
        "rationale": rationale,
        "proposed_at": datetime.now().isoformat(),
        "status": "proposed",  # proposed -> approved -> integrated
    }


def track_check_effectiveness(check_name: str, led_to_improvement: bool) -> None:
    """
    Track whether a check led to actual improvements.

    Used to prioritize/deprioritize checks over time.

    Args:
        check_name: Name of the check that was run.
        led_to_improvement: Whether running this check led to a commit.
    """
    state = load_evolution_state()

    if check_name not in state["tool_effectiveness"]:
        state["tool_effectiveness"][check_name] = {"hits": 0, "misses": 0}

    if led_to_improvement:
        state["tool_effectiveness"][check_name]["hits"] += 1
    else:
        state["tool_effectiveness"][check_name]["misses"] += 1

    save_evolution_state(state)


def get_prioritized_checks() -> list[str]:
    """
    Return checks ordered by effectiveness.

    High-hit checks first, low-hit checks may be disabled.

    Returns:
        List of check names ordered by effectiveness (best first).
    """
    state = load_evolution_state()
    effectiveness = state.get("tool_effectiveness", {})

    # Calculate hit rate
    rated: list[tuple[str, float, int]] = []
    for check, stats in effectiveness.items():
        total = stats["hits"] + stats["misses"]
        if total > 0:
            rate = stats["hits"] / total
            rated.append((check, rate, total))

    # Sort by rate (high first), then by sample size
    rated.sort(key=lambda x: (-x[1], -x[2]))

    return [check for check, _, _ in rated]


def get_disabled_checks() -> list[str]:
    """
    Get list of checks that have been disabled due to low effectiveness.

    Returns:
        List of disabled check names.
    """
    state = load_evolution_state()
    return state.get("disabled_checks", [])


def suggest_capability_expansion(project_dir: Path) -> list[str]:
    """
    Suggest tools to install that would enable more discovery.

    Based on project type and what's missing.

    Args:
        project_dir: Project directory to analyze.

    Returns:
        List of installation suggestions.
    """
    suggestions: list[str] = []

    # Check for Python project without type checker
    has_python = (project_dir / "pyproject.toml").exists() or list(project_dir.glob("*.py"))
    if has_python:
        if not shutil.which("mypy") and not shutil.which("pyright"):
            suggestions.append("Install mypy or pyright for type checking: `uv tool install mypy`")

        # Check for security scanning
        if not shutil.which("bandit"):
            suggestions.append("Install bandit for security scanning: `uv tool install bandit`")

    # Check for link validation
    if not shutil.which("lychee"):
        suggestions.append("Install lychee for link validation: `brew install lychee`")

    # Check for secrets scanning
    if not shutil.which("gitleaks"):
        suggestions.append("Install gitleaks for secret detection: `brew install gitleaks`")

    # Check for Rust project tools
    if (project_dir / "Cargo.toml").exists():
        if not shutil.which("cargo-deny"):
            suggestions.append("Install cargo-deny for dependency auditing: `cargo install cargo-deny`")
        if not shutil.which("cargo-nextest"):
            suggestions.append("Install cargo-nextest for faster tests: `cargo install cargo-nextest`")

    return suggestions


def disable_underperforming_check(check_name: str) -> None:
    """
    Mark a check as disabled due to low effectiveness.

    Args:
        check_name: Name of the check to disable.
    """
    state = load_evolution_state()

    if check_name not in state["disabled_checks"]:
        state["disabled_checks"].append(check_name)

    save_evolution_state(state)


def learn_project_pattern(pattern_name: str, pattern_value: str | bool | dict) -> None:
    """
    Record a learned project-specific pattern.

    Args:
        pattern_name: Name/key for the pattern.
        pattern_value: Value or configuration for the pattern.
    """
    state = load_evolution_state()
    state["learned_patterns"][pattern_name] = pattern_value
    save_evolution_state(state)


def get_learned_patterns() -> dict:
    """
    Get all learned project patterns.

    Returns:
        Dict of pattern_name -> pattern_value.
    """
    state = load_evolution_state()
    return state.get("learned_patterns", {})
