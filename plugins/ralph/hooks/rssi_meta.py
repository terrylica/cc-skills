"""
RSSI Level 5: Meta-RSSI

ADR: 2025-12-20-ralph-rssi-eternal-loop

Meta-improvement: Improve how improvement happens.
Analyzes discovery effectiveness and evolves the discovery mechanism itself.
"""

from __future__ import annotations

from pathlib import Path

from core.constants import (
    CAPABILITY_EXPANSION_THRESHOLD,
    DEFAULT_COVERAGE_THRESHOLD,
    DISCOVERY_LOW_EFFECTIVENESS,
    HIGH_EFFECTIVENESS_THRESHOLD,
    LOW_EFFECTIVENESS_THRESHOLD,
    MIN_SAMPLES_FOR_DISABLING,
    MIN_SAMPLES_FOR_EVALUATION,
    VERY_LOW_EFFECTIVENESS_THRESHOLD,
)
from rssi_evolution import (
    disable_underperforming_check,
    get_learned_patterns,
    learn_project_pattern,
    load_evolution_state,
    propose_new_check,
    save_evolution_state,
)


def analyze_discovery_effectiveness() -> dict:
    """
    Meta-analysis: How effective is the discovery mechanism itself?

    Returns:
        Dict with overall effectiveness metrics and recommendations.
    """
    state = load_evolution_state()
    effectiveness = state.get("tool_effectiveness", {})

    if not effectiveness:
        return {
            "status": "insufficient_data",
            "overall_effectiveness": 0.0,
            "total_checks_run": 0,
            "recommendations": ["Run more RSSI sessions to gather effectiveness data"],
        }

    # Calculate overall hit rate
    total_hits = sum(e["hits"] for e in effectiveness.values())
    total_misses = sum(e["misses"] for e in effectiveness.values())
    total = total_hits + total_misses

    if total == 0:
        return {
            "status": "no_data",
            "overall_effectiveness": 0.0,
            "total_checks_run": 0,
            "recommendations": [],
        }

    overall_rate = total_hits / total
    recommendations: list[str] = []

    if overall_rate < DISCOVERY_LOW_EFFECTIVENESS:
        recommendations.append(
            "Discovery is finding issues but not leading to commits. "
            "Consider more targeted checks."
        )
    elif overall_rate > HIGH_EFFECTIVENESS_THRESHOLD:
        recommendations.append(
            "Discovery is highly effective. Consider adding more ambitious checks."
        )

    # Find underperforming checks
    for check, stats in effectiveness.items():
        check_total = stats["hits"] + stats["misses"]
        if check_total >= MIN_SAMPLES_FOR_EVALUATION:
            rate = stats["hits"] / check_total
            if rate < LOW_EFFECTIVENESS_THRESHOLD:
                recommendations.append(
                    f"Consider disabling '{check}' - only {rate:.0%} effectiveness"
                )

    return {
        "status": "analyzed",
        "overall_effectiveness": overall_rate,
        "total_checks_run": total,
        "recommendations": recommendations,
    }


def improve_discovery_mechanism(project_dir: Path) -> list[str]:
    """
    The core of meta-RSSI: improve the discovery mechanism itself.

    Strategies:
    1. Disable ineffective checks
    2. Propose new checks based on patterns
    3. Learn project-specific conventions

    Args:
        project_dir: Project directory to analyze.

    Returns:
        List of improvements made or proposed.
    """
    improvements: list[str] = []
    state = load_evolution_state()

    # Strategy 1: Disable underperforming checks
    for check, stats in state.get("tool_effectiveness", {}).items():
        total = stats["hits"] + stats["misses"]
        if total >= MIN_SAMPLES_FOR_DISABLING and stats["hits"] / total < VERY_LOW_EFFECTIVENESS_THRESHOLD:
            if check not in state.get("disabled_checks", []):
                disable_underperforming_check(check)
                improvements.append(f"Disabled underperforming check: {check}")

    # Strategy 2: Learn from project structure
    patterns = get_learned_patterns()

    if (project_dir / "Makefile").exists() and "has_makefile" not in patterns:
        learn_project_pattern("has_makefile", True)
        improvements.append("Learned: Project uses Makefile - can run make targets")

    if (project_dir / "justfile").exists() and "has_justfile" not in patterns:
        learn_project_pattern("has_justfile", True)
        improvements.append("Learned: Project uses just - can run just recipes")

    if (project_dir / "mise.toml").exists() and "has_mise" not in patterns:
        learn_project_pattern("has_mise", True)
        improvements.append("Learned: Project uses mise - can run mise tasks")

    # Strategy 3: Evolve based on repo type
    pyproject = project_dir / "pyproject.toml"
    if pyproject.exists() and "pytest_coverage" not in patterns:
        try:
            toml_content = pyproject.read_text()
            if "pytest" in toml_content:
                learn_project_pattern("pytest_coverage", True)
                proposal = propose_new_check(
                    "pytest_coverage",
                    f"pytest --cov --cov-fail-under={DEFAULT_COVERAGE_THRESHOLD}",
                    "Project uses pytest - coverage check valuable",
                )
                state = load_evolution_state()
                state.setdefault("added_checks", []).append(proposal)
                save_evolution_state(state)
                improvements.append("Proposed: Add pytest coverage check")
        except OSError:
            pass

    # Strategy 4: Detect CI/CD patterns
    if (project_dir / ".github/workflows").exists() and "has_github_actions" not in patterns:
        learn_project_pattern("has_github_actions", True)
        improvements.append("Learned: Project uses GitHub Actions")

    if (project_dir / ".releaserc.yml").exists() and "has_semantic_release" not in patterns:
        learn_project_pattern("has_semantic_release", True)
        improvements.append("Learned: Project uses semantic-release")

    return improvements


def get_meta_suggestions() -> list[str]:
    """
    Generate meta-level improvement suggestions.

    Returns:
        List of high-level suggestions for improving RSSI behavior.
    """
    analysis = analyze_discovery_effectiveness()
    suggestions: list[str] = []

    if analysis["status"] == "insufficient_data":
        suggestions.append("Gather more data by running RSSI discovery sessions")
        return suggestions

    effectiveness = analysis["overall_effectiveness"]

    if effectiveness < DISCOVERY_LOW_EFFECTIVENESS:
        suggestions.append("Focus on high-impact checks: lint errors, type errors, security issues")
        suggestions.append("Consider reducing scope to most impactful improvements")

    if effectiveness > HIGH_EFFECTIVENESS_THRESHOLD:
        suggestions.append("Discovery is effective - consider expanding check coverage")
        suggestions.append("Try more ambitious improvements: refactoring, architecture changes")

    # Add specific recommendations from analysis
    suggestions.extend(analysis.get("recommendations", []))

    return suggestions


def should_expand_capabilities() -> bool:
    """
    Determine if RSSI should suggest installing new tools.

    Returns:
        True if discovery effectiveness is high enough to warrant expansion.
    """
    analysis = analyze_discovery_effectiveness()

    # Don't expand if we don't have enough data
    if analysis["status"] in ("insufficient_data", "no_data"):
        return False

    # Expand if effectiveness is moderate to high
    return analysis["overall_effectiveness"] >= CAPABILITY_EXPANSION_THRESHOLD
