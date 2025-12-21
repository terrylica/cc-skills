"""Alpha Forge SLO Filter: Filters busywork opportunities.

ADR: /docs/adr/2025-12-20-ralph-rssi-eternal-loop.md

Soft-skips opportunities that match busywork patterns (cosmetic linter fixes,
annotations, micro-optimizations) to focus on ROADMAP-aligned value delivery.

This filter only applies to Alpha Forge projects (detected via AdapterRegistry).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum

# Busywork patterns to soft-skip (filter from discovery)
# These are micro-optimizations that don't align with ROADMAP goals
BUSYWORK_PATTERNS: list[str] = [
    # ALL ruff/linting issues are busywork for Alpha Forge
    r"Fix ruff issues:",  # Any ruff issue
    r"Fix .* issues:",  # Any linting issues
    r"unused.*import",  # F401 style
    r"import.*unused",  # F401 style
    # Documentation busywork
    r"Add module docstring:",
    r"Add README to",
    r"Add docstring",
    r"missing docstring",
    r"Verify docs for:",
    r"documentation gaps",
    # TODO/FIXME scanning (not actionable without context)
    r"Address TODO",
    r"Address FIXME",
    r"TODO/FIXME",
    # Security scans (run manually, not in loop)
    r"Run gitleaks",
    r"Run bandit",
    r"security scan",
    # Generic busywork
    r"uncommitted changes",  # Git hygiene
    r"Review \d+ uncommitted",
    r"test coverage",  # Coverage hunting
    r"Analyze test coverage",
    r"sort imports",
    r"format.*code",
    r"Gather more data",  # Meta-busywork
    r"running RSSI discovery",
]

# Ruff rules to exclude from scanning (passed to ruff --ignore)
# For Alpha Forge, we ignore ALL style rules - only real bugs matter
EXCLUDED_RUFF_RULES: list[str] = [
    "E",  # All pycodestyle errors (style)
    "W",  # All pycodestyle warnings (style)
    "F401",  # Unused imports
    "F841",  # Unused variables
    "SIM",  # Simplifications
    "RUF",  # Ruff-specific
    "I",  # Import sorting
    "ANN",  # Type annotations
    "DTZ",  # Datetime timezone
    "PERF",  # Micro-optimizations
    "D",  # Docstrings
    "ERA",  # Commented code
    "T20",  # Print statements
    "PLR",  # Pylint refactor
    "C90",  # Complexity
]


class FilterResult(Enum):
    """Result of filtering an opportunity."""

    ALLOW = "allow"  # Opportunity is value-aligned, proceed
    SKIP = "skip"  # Opportunity is busywork, soft-skip
    ESCALATE = "escalate"  # Opportunity needs expert review


@dataclass
class FilteredOpportunity:
    """An opportunity with its filter result and metadata."""

    opportunity: str
    result: FilterResult
    reason: str
    matched_pattern: str | None = None


def is_busywork(opportunity: str) -> tuple[bool, str | None]:
    """Check if an opportunity matches busywork patterns.

    Args:
        opportunity: Opportunity description string

    Returns:
        Tuple of (is_busywork, matched_pattern)
    """
    for pattern in BUSYWORK_PATTERNS:
        if re.search(pattern, opportunity, re.IGNORECASE):
            return True, pattern
    return False, None


def filter_opportunities(
    opportunities: list[str],
    *,
    allow_busywork: bool = False,
) -> list[FilteredOpportunity]:
    """Filter opportunities to remove busywork.

    Args:
        opportunities: Raw list of opportunity descriptions
        allow_busywork: If True, allow busywork (for debugging)

    Returns:
        List of FilteredOpportunity with results
    """
    results: list[FilteredOpportunity] = []

    for opp in opportunities:
        is_bw, pattern = is_busywork(opp)

        if is_bw and not allow_busywork:
            results.append(
                FilteredOpportunity(
                    opportunity=opp,
                    result=FilterResult.SKIP,
                    reason="Matches busywork pattern",
                    matched_pattern=pattern,
                )
            )
        else:
            results.append(
                FilteredOpportunity(
                    opportunity=opp,
                    result=FilterResult.ALLOW,
                    reason="Value-aligned opportunity",
                )
            )

    return results


def get_allowed_opportunities(opportunities: list[str]) -> list[str]:
    """Get only the allowed (non-busywork) opportunities.

    Convenience function for simple filtering.

    Args:
        opportunities: Raw list of opportunity descriptions

    Returns:
        Filtered list with busywork removed
    """
    filtered = filter_opportunities(opportunities)
    return [f.opportunity for f in filtered if f.result == FilterResult.ALLOW]


def get_ruff_ignore_args() -> list[str]:
    """Get ruff command arguments to ignore excluded rules.

    Returns:
        List of arguments like ['--ignore', 'E501,SIM,RUF,I,ANN,DTZ,PERF']
    """
    return ["--ignore", ",".join(EXCLUDED_RUFF_RULES)]


def summarize_filter_results(filtered: list[FilteredOpportunity]) -> dict[str, int]:
    """Summarize filter results for metrics tracking.

    Args:
        filtered: List of filtered opportunities

    Returns:
        Dict with counts by result type
    """
    counts: dict[str, int] = {
        "total": len(filtered),
        "allowed": 0,
        "skipped": 0,
        "escalated": 0,
    }

    for f in filtered:
        if f.result == FilterResult.ALLOW:
            counts["allowed"] += 1
        elif f.result == FilterResult.SKIP:
            counts["skipped"] += 1
        elif f.result == FilterResult.ESCALATE:
            counts["escalated"] += 1

    return counts
