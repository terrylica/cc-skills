# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Unit tests for mathematical validation guards.

Tests use two strategies:
1. Golden value tests - Compare against authoritative pre-computed values
2. Edge case tests - Critical scenarios (division by zero, impossible values, etc.)
"""

import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from math_guards import (
    validate_drawdown,
    validate_metric,
    validate_metrics_batch,
    validate_returns,
    validate_sharpe,
    validate_wfe,
)


def test_sharpe_typical_value():
    """Sharpe of 1.5 is a good strategy (authoritative: typical institutional target)."""
    result = validate_sharpe(1.5)
    assert result.is_valid is True, f"Expected valid, got {result}"
    assert len(result.warnings) == 0, f"Unexpected warnings: {result.warnings}"
    assert len(result.errors) == 0, f"Unexpected errors: {result.errors}"


def test_sharpe_zero():
    """Sharpe of 0 is valid (no excess returns)."""
    result = validate_sharpe(0.0)
    assert result.is_valid is True
    assert len(result.warnings) == 0


def test_sharpe_negative_typical():
    """Sharpe of -1 is valid but indicates poor performance."""
    result = validate_sharpe(-1.0)
    assert result.is_valid is True
    assert len(result.warnings) == 0


def test_sharpe_nan():
    """NaN Sharpe is valid (std dev = 0 case)."""
    result = validate_sharpe(float("nan"))
    assert result.is_valid is True
    assert any("NaN" in w for w in result.warnings), f"Expected NaN warning: {result.warnings}"


def test_sharpe_inf_is_invalid():
    """Infinite Sharpe is mathematically impossible."""
    result = validate_sharpe(float("inf"))
    assert result.is_valid is False
    assert any("Inf" in e for e in result.errors), f"Expected Inf error: {result.errors}"


def test_sharpe_negative_inf_is_invalid():
    """Negative infinite Sharpe is mathematically impossible."""
    result = validate_sharpe(float("-inf"))
    assert result.is_valid is False


def test_sharpe_extreme_positive_warning():
    """Sharpe > 5 triggers warning (possible overfitting)."""
    result = validate_sharpe(6.0)
    assert result.is_valid is True
    assert any("suspicious" in w.lower() for w in result.warnings)


def test_sharpe_extreme_negative_warning():
    """Sharpe < -3 triggers warning (fundamental strategy flaw)."""
    result = validate_sharpe(-4.0)
    assert result.is_valid is True
    assert any("flaw" in w.lower() for w in result.warnings)


def test_sharpe_boundary_no_warning():
    """Sharpe exactly at 5 should not trigger warning."""
    result = validate_sharpe(5.0)
    assert result.is_valid is True
    assert len(result.warnings) == 0


def test_wfe_typical_good():
    """WFE of 0.6 indicates acceptable generalization."""
    result = validate_wfe(0.6)
    assert result.is_valid is True
    assert len(result.warnings) == 0


def test_wfe_zero():
    """WFE of 0 is valid but indicates complete overfitting."""
    result = validate_wfe(0.0)
    assert result.is_valid is True
    assert any("overfitting" in w.lower() for w in result.warnings)


def test_wfe_perfect():
    """WFE of 1.0 is the mathematical upper bound."""
    result = validate_wfe(1.0)
    assert result.is_valid is True


def test_wfe_above_one_is_invalid():
    """WFE > 1.0 is mathematically impossible."""
    result = validate_wfe(1.5)
    assert result.is_valid is False
    assert any("impossible" in e.lower() for e in result.errors)


def test_wfe_negative_is_invalid():
    """WFE < 0 is mathematically impossible."""
    result = validate_wfe(-0.1)
    assert result.is_valid is False
    assert any("impossible" in e.lower() for e in result.errors)


def test_wfe_nan_is_valid():
    """NaN WFE is valid (division issues in Sharpe)."""
    result = validate_wfe(float("nan"))
    assert result.is_valid is True


def test_wfe_low_warning():
    """WFE < 0.1 indicates severe overfitting."""
    result = validate_wfe(0.05)
    assert result.is_valid is True
    assert any("overfitting" in w.lower() for w in result.warnings)


def test_wfe_unusually_high_warning():
    """WFE > 0.95 triggers verification warning."""
    result = validate_wfe(0.98)
    assert result.is_valid is True
    assert any("unusually high" in w.lower() for w in result.warnings)


def test_drawdown_typical():
    """Drawdown of -15% is typical for strategies."""
    result = validate_drawdown(-0.15)
    assert result.is_valid is True
    assert len(result.errors) == 0


def test_drawdown_zero():
    """Drawdown of 0 is valid (no losses)."""
    result = validate_drawdown(0.0)
    assert result.is_valid is True


def test_drawdown_max_loss():
    """Drawdown of -100% is valid (total loss)."""
    result = validate_drawdown(-1.0)
    assert result.is_valid is True


def test_drawdown_positive_is_invalid():
    """Positive drawdown is mathematically impossible."""
    result = validate_drawdown(0.05)
    assert result.is_valid is False
    assert any("impossible" in e.lower() for e in result.errors)


def test_drawdown_below_minus_one_is_invalid():
    """Drawdown < -100% is mathematically impossible."""
    result = validate_drawdown(-1.5)
    assert result.is_valid is False
    assert any("impossible" in e.lower() for e in result.errors)


def test_drawdown_nan_is_valid():
    """NaN drawdown is valid (no data case)."""
    result = validate_drawdown(float("nan"))
    assert result.is_valid is True


def test_returns_positive():
    """Positive returns are valid."""
    result = validate_returns(0.25)
    assert result.is_valid is True
    assert len(result.warnings) == 0


def test_returns_negative():
    """Negative returns are valid (up to -100%)."""
    result = validate_returns(-0.50)
    assert result.is_valid is True


def test_returns_below_minus_one_is_invalid():
    """Returns < -100% is mathematically impossible."""
    result = validate_returns(-1.5)
    assert result.is_valid is False
    assert any("impossible" in e.lower() for e in result.errors)


def test_returns_extreme_warning():
    """Extreme returns (>1000%) trigger warning."""
    result = validate_returns(15.0)
    assert result.is_valid is True
    assert any("extreme" in w.lower() for w in result.warnings)


def test_returns_inf_is_invalid():
    """Infinite returns is invalid."""
    result = validate_returns(float("inf"))
    assert result.is_valid is False


def test_validate_known_metric():
    """Known metrics use their specific validator."""
    result = validate_metric("sharpe", 1.5)
    assert result.is_valid is True


def test_validate_unknown_metric():
    """Unknown metrics pass through without validation."""
    result = validate_metric("unknown_metric", 999.0)
    assert result.is_valid is True
    assert result.value == 999.0


def test_validate_case_insensitive():
    """Metric names are case-insensitive."""
    result = validate_metric("SHARPE", 1.5)
    assert result.is_valid is True


def test_validate_invalid_type():
    """Non-numeric values return error."""
    result = validate_metric("sharpe", "not_a_number")
    assert result.is_valid is False
    assert any("convert" in e.lower() for e in result.errors)


def test_validate_aliases():
    """Metric aliases work correctly."""
    # maxdd is alias for drawdown
    result = validate_metric("maxdd", -0.2)
    assert result.is_valid is True

    # walk_forward_efficiency is alias for wfe
    result = validate_metric("walk_forward_efficiency", 0.7)
    assert result.is_valid is True


def test_batch_all_valid():
    """Batch validation with all valid metrics."""
    metrics = {
        "sharpe": 1.5,
        "wfe": 0.6,
        "maxdd": -0.15,
    }
    results = validate_metrics_batch(metrics)
    assert all(r.is_valid for r in results.values())


def test_batch_mixed_validity():
    """Batch validation with mix of valid/invalid."""
    metrics = {
        "sharpe": 1.5,
        "wfe": 1.5,  # Invalid: > 1.0
    }
    results = validate_metrics_batch(metrics)
    assert results["sharpe"].is_valid is True
    assert results["wfe"].is_valid is False


if __name__ == "__main__":
    # Simple test runner
    import traceback

    test_functions = [
        name for name in dir() if name.startswith("test_") and callable(eval(name))
    ]

    passed = 0
    failed = 0

    for test_name in test_functions:
        try:
            eval(f"{test_name}()")
            print(f"  ✓ {test_name}")
            passed += 1
        except AssertionError as e:
            print(f"  ✗ {test_name}: {e}")
            failed += 1
        except Exception as e:
            print(f"  ✗ {test_name}: {type(e).__name__}: {e}")
            traceback.print_exc()
            failed += 1

    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
