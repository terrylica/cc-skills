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
# Alpha Forge goal: OOS robustness + time series forecasting excellence
BUSYWORK_PATTERNS: list[str] = [
    # === LINTING/STYLE (zero functional value) ===
    r"Fix ruff issues:",
    r"Fix .* issues:",
    r"Fix pylint",
    r"Fix mypy",
    r"Fix flake8",
    r"unused.*import",
    r"import.*unused",
    r"sort imports",
    r"format.*code",
    r"line too long",
    r"trailing whitespace",
    r"missing.*blank line",
    r"E501|E302|E303|W291|W293",  # Specific style codes
    # === DOCUMENTATION (not the goal) ===
    r"Add module docstring",
    r"Add README",
    r"Add docstring",
    r"missing docstring",
    r"Verify docs for:",
    r"documentation gaps",
    r"update.*README",
    r"update.*CHANGELOG",
    r"add.*comment",
    r"improve.*comment",
    # === TYPE HINTS (cosmetic for working code) ===
    r"Add type hint",
    r"missing.*annotation",
    r"type annotation",
    r"ANN\d+",
    # === TODO/FIXME (not actionable without context) ===
    r"Address TODO",
    r"Address FIXME",
    r"TODO/FIXME",
    r"\d+ files.*TODO",
    # === SECURITY SCANS (run manually, not in loop) ===
    r"Run gitleaks",
    r"Run bandit",
    r"security scan",
    r"secret.*scan",
    # === TEST COVERAGE HUNTING (not the goal) ===
    r"test coverage",
    r"Analyze test coverage",
    r"increase coverage",
    r"add.*test.*for",
    r"missing.*test",
    r"0%.*coverage",
    # === GIT HYGIENE (not functional) ===
    r"uncommitted changes",
    r"Review \d+ uncommitted",
    r"commit message",
    r"git.*clean",
    # === REFACTORING WITHOUT PURPOSE ===
    r"rename.*variable",
    r"extract.*function",
    r"simplify.*code",
    r"reduce.*complexity",
    r"DRY.*violation",
    r"code.*smell",
    r"refactor.*for.*readability",
    # === META-BUSYWORK ===
    r"Gather more data",
    r"running Ralph discovery",
    r"discover.*opportunities",
    # === DEPENDENCY CHURN (unless security) ===
    r"update.*dependency",
    r"bump.*version",
    r"upgrade.*package",
    # === CI/CD TWEAKS ===
    r"update.*workflow",
    r"fix.*CI",
    r"update.*pre-commit",
    r"update.*config",
]

# High-value patterns that SHOULD be worked on (for reference/logging)
# These align with Alpha Forge ROADMAP: OOS robustness + time series forecasting
VALUE_ALIGNED_PATTERNS: list[str] = [
    # === ROADMAP ITEMS ===
    r"ROADMAP",
    r"Phase \d",
    r"milestone",
    # === OOS ROBUSTNESS (core goal) ===
    r"out.of.sample",
    r"OOS",
    r"walk.forward",
    r"WFE",  # Walk-Forward Efficiency
    r"overfitting",
    r"generalization",
    r"robustness",
    r"regime.*detection",
    r"regime.*change",
    # === TIME SERIES FORECASTING (core goal) ===
    r"time.series",
    r"forecast",
    r"prediction",
    r"LSTM|GRU|Transformer",
    r"attention.*mechanism",
    r"temporal",
    r"sequence.*model",
    # === FEATURE ENGINEERING ===
    r"feature.*engineer",
    r"technical.*indicator",
    r"alpha.*factor",
    r"signal.*generat",
    # === MODEL ARCHITECTURE ===
    r"model.*architect",
    r"hyperparameter",
    r"neural.*network",
    r"ensemble",
    r"stacking",
    # === DATA PIPELINE ===
    r"data.*pipeline",
    r"data.*quality",
    r"data.*validation",
    r"missing.*data.*handl",
    # === RISK MANAGEMENT ===
    r"risk.*manag",
    r"position.*sizing",
    r"drawdown",
    r"Sharpe|Sortino|Calmar",
    # === BACKTESTING ===
    r"backtest",
    r"simulation",
    r"historical.*test",
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
    SKIP = "skip"  # Opportunity is busywork, soft-skip (can still be chosen as fallback)
    BLOCK = "block"  # Opportunity is busywork AND research CONVERGED, hard-block (cannot be chosen)
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


def _matches_natural_language(
    opportunity: str,
    phrases: list[str],
) -> str | None:
    """Case-insensitive substring matching for natural language phrases.

    Used for user-provided guidance (forbidden/encouraged lists).

    Args:
        opportunity: The opportunity description to check
        phrases: List of natural language phrases to match

    Returns:
        First matching phrase, or None if no match
    """
    opp_lower = opportunity.lower()
    for phrase in phrases:
        if phrase.lower() in opp_lower:
            return phrase
    return None


def filter_opportunities(
    opportunities: list[str],
    *,
    allow_busywork: bool = False,
    research_converged: bool = False,
    custom_forbidden: list[str] | None = None,
    custom_encouraged: list[str] | None = None,
) -> list[FilteredOpportunity]:
    """Filter opportunities with user guidance support.

    Priority order (encouraged-wins):
    1. Check encouraged phrases FIRST (if match → ALLOW, override any forbidden)
    2. Check built-in BUSYWORK_PATTERNS (regex)
    3. Check custom_forbidden phrases (natural language substring)
    4. Default to ALLOW

    Args:
        opportunities: Raw list of opportunity descriptions
        allow_busywork: If True, allow busywork (for debugging)
        research_converged: If True, HARD-BLOCK busywork (cannot be chosen at all).
            When research is CONVERGED, only /research invocations are allowed.
        custom_forbidden: User-provided forbidden phrases (natural language)
        custom_encouraged: User-provided encouraged phrases (natural language, overrides forbidden)

    Returns:
        List of FilteredOpportunity with results
    """
    results: list[FilteredOpportunity] = []

    for opp in opportunities:
        # Priority 1: Check ENCOURAGED FIRST (natural language, overrides all)
        if custom_encouraged:
            enc_match = _matches_natural_language(opp, custom_encouraged)
            if enc_match:
                results.append(
                    FilteredOpportunity(
                        opportunity=opp,
                        result=FilterResult.ALLOW,
                        reason=f"Encouraged: matches '{enc_match}'",
                        matched_pattern=enc_match,
                    )
                )
                continue  # Skip forbidden checks

        # Priority 2: Check built-in BUSYWORK_PATTERNS (regex)
        is_builtin_bw, builtin_pattern = is_busywork(opp)

        # Priority 3: Check custom_forbidden (natural language) - HARD BLOCK
        is_user_forbidden = False
        user_forbidden_pattern = None
        if custom_forbidden:
            custom_match = _matches_natural_language(opp, custom_forbidden)
            if custom_match:
                is_user_forbidden = True
                user_forbidden_pattern = custom_match

        # Apply filter result with priority:
        # 1. User-forbidden → BLOCK (user explicitly said no)
        # 2. Built-in busywork + CONVERGED → BLOCK
        # 3. Built-in busywork → SKIP (soft, can be fallback)
        # 4. Otherwise → ALLOW
        if is_user_forbidden and not allow_busywork:
            # User explicitly forbade this - HARD BLOCK always
            results.append(
                FilteredOpportunity(
                    opportunity=opp,
                    result=FilterResult.BLOCK,
                    reason=f"User-forbidden: '{user_forbidden_pattern}'",
                    matched_pattern=user_forbidden_pattern,
                )
            )
        elif is_builtin_bw and not allow_busywork:
            if research_converged:
                # Hard-block busywork when research is CONVERGED
                results.append(
                    FilteredOpportunity(
                        opportunity=opp,
                        result=FilterResult.BLOCK,
                        reason="CONVERGED: Only /research allowed, busywork hard-blocked",
                        matched_pattern=builtin_pattern,
                    )
                )
            else:
                # Soft-skip built-in busywork (can still be chosen as fallback)
                results.append(
                    FilteredOpportunity(
                        opportunity=opp,
                        result=FilterResult.SKIP,
                        reason=f"Built-in busywork: '{builtin_pattern}'",
                        matched_pattern=builtin_pattern,
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


def get_allowed_opportunities(
    opportunities: list[str],
    *,
    research_converged: bool = False,
    custom_forbidden: list[str] | None = None,
    custom_encouraged: list[str] | None = None,
) -> list[str]:
    """Get only the allowed (non-busywork) opportunities.

    Convenience function for simple filtering with user guidance support.

    Args:
        opportunities: Raw list of opportunity descriptions
        research_converged: If True, HARD-BLOCK busywork
        custom_forbidden: User-provided forbidden phrases (natural language)
        custom_encouraged: User-provided encouraged phrases (overrides forbidden)

    Returns:
        Filtered list with busywork removed
    """
    filtered = filter_opportunities(
        opportunities,
        research_converged=research_converged,
        custom_forbidden=custom_forbidden,
        custom_encouraged=custom_encouraged,
    )
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
        "blocked": 0,
        "escalated": 0,
    }

    for f in filtered:
        if f.result == FilterResult.ALLOW:
            counts["allowed"] += 1
        elif f.result == FilterResult.SKIP:
            counts["skipped"] += 1
        elif f.result == FilterResult.BLOCK:
            counts["blocked"] += 1
        elif f.result == FilterResult.ESCALATE:
            counts["escalated"] += 1

    return counts
