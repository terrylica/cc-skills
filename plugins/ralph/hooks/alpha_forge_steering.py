"""Alpha Forge Active Steering: Injects value-alignment into all prompts.

ADR: /docs/adr/2025-12-20-ralph-rssi-eternal-loop.md

This module provides active steering for Alpha Forge agents, ensuring
every prompt includes reminders about:
1. OOS robustness as the primary goal
2. Time series forecasting excellence
3. SOTA technology adoption
4. ROADMAP alignment
5. Explicit busywork avoidance

Use get_steering_prompt() to inject into any agent/subagent prompt.
"""

# Core value reminder - inject at START of every prompt
ALPHA_FORGE_VALUES = """
## ALPHA FORGE MISSION (ALWAYS REMEMBER)

You are working on **Alpha Forge** - a quantitative trading research platform.

**PRIMARY GOALS** (in order of priority):
1. **OOS Robustness** - Out-of-sample performance is the ONLY metric that matters
2. **Time Series Forecasting** - State-of-the-art prediction capabilities
3. **ROADMAP Alignment** - Every action must advance ROADMAP.md items

**BEFORE ANY ACTION, ASK:**
- Does this improve OOS robustness? (WFE, Sharpe, generalization)
- Does this improve forecasting? (accuracy, uncertainty quantification)
- Is this in ROADMAP.md?
- Is this SOTA (2024-2025)?
- Is the library well-maintained (stars > 1000, commits < 3 months)?

If you can't answer YES to at least 3 of these, **find different work**.
"""

# Explicit forbidden list - inject after values
FORBIDDEN_WORK = """
## FORBIDDEN BUSYWORK (SKIP IMMEDIATELY)

**NEVER** spend time on:
- Linting (ruff, pylint, flake8, mypy)
- Import sorting, formatting, style fixes
- Docstrings, READMEs, comments, documentation
- Type hints, annotations
- TODO/FIXME scanning
- Test coverage hunting
- Security scans (gitleaks, bandit)
- Dependency updates, version bumps
- Git hygiene, commit message fixes
- Refactoring for "readability"
- CI/CD tweaks

**These have ZERO impact on OOS robustness or forecasting.**
"""

# SOTA technology guidance
SOTA_GUIDANCE = """
## SOTA TECHNOLOGY STANDARD

Before implementing ANY solution:

1. **Search first**: "{problem} SOTA implementation 2025"
2. **Verify maintenance**:
   - Last release < 6 months? YES required
   - Active issue responses? YES required
   - Growing star count? Preferred
3. **Prefer modern stack**:
   - PyTorch > TensorFlow for new models
   - Polars > Pandas for data processing
   - UV > pip for package management
   - Typer > argparse for CLI
   - Pydantic > dataclasses for validation
4. **Reject deprecated**:
   - No sklearn.externals
   - No keras without tensorflow
   - No Python 2 patterns
"""

# High-value work reminders
HIGH_VALUE_WORK = """
## HIGH-VALUE WORK (Focus Here)

### OOS Robustness
- Walk-forward optimization
- WFE (Walk-Forward Efficiency) improvements
- Overfitting detection/prevention
- Regime change detection
- Cross-validation strategies
- Generalization testing

### Time Series Forecasting
- Model architecture (LSTM, GRU, Transformer, attention)
- Feature engineering for temporal patterns
- Multi-horizon forecasting
- Uncertainty quantification
- Probabilistic predictions

### Alpha Generation
- Sharpe/Sortino/Calmar optimization
- Position sizing algorithms
- Risk management
- Data pipeline robustness
- Backtesting accuracy
"""

# Mathematical validation requirements (Round 4: Adversarial Probing)
MATHEMATICAL_VALIDATION = """
## MATHEMATICAL CORRECTNESS REQUIREMENTS (Mandatory for ALL Math Code)

When writing ANY code involving mathematical formulas:

### 1. Authoritative Source Citation (REQUIRED)
- MUST cite source: academic paper, official library docs, or standard textbook
- MUST verify implementation matches source formula exactly
- MUST document edge cases defined by the mathematical source

### 2. Edge Case Handling (REQUIRED)
MUST handle these scenarios with explicit code:
- **Division by zero** -> Return NaN or raise clear exception
- **Impossible values** -> Assert/raise immediately (WFE > 1.0, negative std)
- **Extreme values** -> Log warning for suspicious results (|Sharpe| > 5)
- **NaN/Inf input** -> Propagate or handle explicitly (document choice)

### 3. Test Requirements (REQUIRED)
For EACH mathematical formula, create:
- **Golden value test**: Compare against authoritative pre-computed value
- **Property-based test (Hypothesis)**: Test mathematical invariants
- **Edge case test**: All critical scenarios from #2

### 4. Documentation Format
Add this comment block above each math function:
```
# MATH VALIDATION:
# Source: [URL or citation]
# Formula: [mathematical notation]
# Edge cases: [list]
# Tested: [test file:function]
```

### Forbidden Patterns
- Writing math code WITHOUT tests
- Trusting formula "looks right" without authoritative source
- Ignoring edge cases "because they rarely happen"
- Testing only happy path (consistent output != correct math)
"""


def get_steering_prompt(include_forbidden: bool = True) -> str:
    """Get the full Alpha Forge steering prompt.

    Args:
        include_forbidden: Include explicit forbidden list

    Returns:
        Complete steering prompt to inject into agents
    """
    parts = [ALPHA_FORGE_VALUES]
    if include_forbidden:
        parts.append(FORBIDDEN_WORK)
    parts.extend([SOTA_GUIDANCE, HIGH_VALUE_WORK, MATHEMATICAL_VALIDATION])
    return "\n".join(parts)


def get_compact_reminder() -> str:
    """Get a compact reminder for space-constrained contexts.

    Returns:
        Short reminder string
    """
    return """
**ALPHA FORGE FOCUS**: OOS robustness + time series forecasting ONLY.
**SKIP**: All linting, docs, style, coverage, security scans.
**REQUIRE**: SOTA (2024-2025), well-maintained libs, ROADMAP alignment.
"""


def should_skip_opportunity(opportunity: str) -> tuple[bool, str]:
    """Check if an opportunity should be skipped based on steering.

    More aggressive than the filter - checks value alignment.

    Args:
        opportunity: Opportunity description

    Returns:
        (should_skip, reason)
    """
    import re

    # Import patterns from filter
    from alpha_forge_filter import BUSYWORK_PATTERNS, VALUE_ALIGNED_PATTERNS

    # Check if it matches any busywork pattern
    for pattern in BUSYWORK_PATTERNS:
        if re.search(pattern, opportunity, re.IGNORECASE):
            return True, f"Matches busywork pattern: {pattern}"

    # Check if it matches any value-aligned pattern (bonus points)
    for pattern in VALUE_ALIGNED_PATTERNS:
        if re.search(pattern, opportunity, re.IGNORECASE):
            return False, f"Value-aligned: {pattern}"

    # Default: not explicitly value-aligned, proceed with caution
    return False, "Unknown - verify ROADMAP alignment"
