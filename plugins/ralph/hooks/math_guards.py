"""Runtime guards for mathematical correctness.

Part of Ralph's 5-Round Validation System (Round 4: Adversarial Probing).
Validates that computed metrics fall within mathematically valid bounds.
"""

import math
from dataclasses import dataclass, field
from typing import Any

from core.constants import (
    RETURNS_EXTREME_THRESHOLD,
    SHARPE_STRATEGY_FLAW,
    SHARPE_SUSPICIOUS_HIGH,
    WFE_SEVERE_OVERFITTING,
    WFE_UNUSUALLY_HIGH,
)


@dataclass
class MathValidationResult:
    """Result of mathematical validation check."""

    is_valid: bool
    value: float
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def validate_sharpe(value: float) -> MathValidationResult:
    """Validate Sharpe ratio is mathematically plausible.

    MATH VALIDATION:
    Source: https://www.investopedia.com/terms/s/sharperatio.asp
    Formula: SR = (Rp - Rf) / σp
    Edge cases:
      - σp = 0: Return NaN (undefined)
      - |SR| > 5: Suspicious (possible overfitting)
      - SR < -3: Fundamental strategy flaw

    Args:
        value: Computed Sharpe ratio

    Returns:
        MathValidationResult with validity status and any warnings/errors
    """
    warnings_list: list[str] = []
    errors_list: list[str] = []

    if math.isnan(value):
        return MathValidationResult(
            True, value, ["Sharpe is NaN (std dev likely 0)"], []
        )
    if math.isinf(value):
        errors_list.append("Sharpe is Inf (impossible - check calculation)")
        return MathValidationResult(False, value, [], errors_list)
    if abs(value) > SHARPE_SUSPICIOUS_HIGH:
        warnings_list.append(f"Sharpe {value:.2f} > {SHARPE_SUSPICIOUS_HIGH} is suspicious (overfitting?)")
    if value < SHARPE_STRATEGY_FLAW:
        warnings_list.append(
            f"Sharpe {value:.2f} < {SHARPE_STRATEGY_FLAW} suggests fundamental strategy flaw"
        )

    return MathValidationResult(True, value, warnings_list, errors_list)


def validate_wfe(value: float) -> MathValidationResult:
    """Validate Walk-Forward Efficiency is mathematically valid.

    MATH VALIDATION:
    Source: Internal definition (out-sample performance / in-sample performance)
    Formula: WFE = Sharpe_out / Sharpe_in
    Edge cases:
      - WFE > 1.0: Mathematically impossible (out cannot exceed in)
      - WFE < 0.0: Mathematically impossible
      - WFE < 0.1: Severe overfitting indicator
      - WFE > 0.95: Unusually high (verify calculation)

    Args:
        value: Computed Walk-Forward Efficiency

    Returns:
        MathValidationResult with validity status and any warnings/errors
    """
    warnings_list: list[str] = []
    errors_list: list[str] = []

    if math.isnan(value):
        return MathValidationResult(
            True, value, ["WFE is NaN (division by zero in Sharpe?)"], []
        )

    if value > 1.0:
        errors_list.append(f"WFE {value:.2f} > 1.0 is mathematically impossible")
        return MathValidationResult(False, value, [], errors_list)
    if value < 0.0:
        errors_list.append(f"WFE {value:.2f} < 0 is mathematically impossible")
        return MathValidationResult(False, value, [], errors_list)
    if value < WFE_SEVERE_OVERFITTING:
        warnings_list.append(f"WFE {value:.2f} < {WFE_SEVERE_OVERFITTING} indicates severe overfitting")
    if value > WFE_UNUSUALLY_HIGH:
        warnings_list.append(
            f"WFE {value:.2f} > {WFE_UNUSUALLY_HIGH} is unusually high (verify calculation)"
        )

    return MathValidationResult(True, value, warnings_list, errors_list)


def validate_drawdown(value: float) -> MathValidationResult:
    """Validate drawdown is mathematically valid.

    MATH VALIDATION:
    Source: https://www.investopedia.com/terms/d/drawdown.asp
    Formula: DD = (Peak - Trough) / Peak (expressed as negative percentage)
    Edge cases:
      - DD > 0: Impossible (drawdown is always negative or zero)
      - DD < -1.0: Impossible (cannot lose more than 100%)

    Args:
        value: Computed drawdown (should be <= 0)

    Returns:
        MathValidationResult with validity status and any warnings/errors
    """
    if math.isnan(value):
        return MathValidationResult(
            True, value, ["Drawdown is NaN (no data?)"], []
        )

    if value > 0:
        return MathValidationResult(
            False, value, [], [f"Drawdown {value:.2f} > 0 is impossible (must be <= 0)"]
        )
    if value < -1.0:
        return MathValidationResult(
            False,
            value,
            [],
            [f"Drawdown {value:.2f} < -100% is impossible"],
        )

    return MathValidationResult(True, value, [], [])


def validate_returns(value: float) -> MathValidationResult:
    """Validate returns percentage is plausible.

    MATH VALIDATION:
    Source: Standard financial definition
    Formula: Returns = (End - Start) / Start
    Edge cases:
      - Returns < -1.0: Cannot lose more than 100%
      - |Returns| > 10.0: Extreme (1000%+ gain/loss), verify

    Args:
        value: Computed returns as decimal (0.1 = 10%)

    Returns:
        MathValidationResult with validity status and any warnings/errors
    """
    warnings_list: list[str] = []

    if math.isnan(value):
        return MathValidationResult(True, value, ["Returns is NaN"], [])
    if math.isinf(value):
        return MathValidationResult(
            False, value, [], ["Returns is Inf (division by zero?)"]
        )

    if value < -1.0:
        return MathValidationResult(
            False, value, [], [f"Returns {value:.2%} < -100% is impossible"]
        )
    if abs(value) > RETURNS_EXTREME_THRESHOLD:
        warnings_list.append(
            f"Returns {value:.2%} is extreme (verify calculation)"
        )

    return MathValidationResult(True, value, warnings_list, [])


# Registry of validators by metric name
MATH_VALIDATORS: dict[str, Any] = {
    "sharpe": validate_sharpe,
    "sortino": validate_sharpe,  # Same bounds apply
    "calmar": validate_sharpe,
    "wfe": validate_wfe,
    "walk_forward_efficiency": validate_wfe,
    "maxdd": validate_drawdown,
    "max_drawdown": validate_drawdown,
    "drawdown": validate_drawdown,
    "returns": validate_returns,
    "cagr": validate_returns,
}


def validate_metric(metric_name: str, value: Any) -> MathValidationResult:
    """Validate a named metric using the appropriate validator.

    Args:
        metric_name: Name of the metric (case-insensitive)
        value: Computed value to validate

    Returns:
        MathValidationResult with validity status
    """
    validator = MATH_VALIDATORS.get(metric_name.lower())
    if not validator:
        # Unknown metric, pass through without validation
        try:
            float_value = float(value)
        except (TypeError, ValueError):
            return MathValidationResult(True, 0.0, [], [])
        return MathValidationResult(True, float_value, [], [])

    try:
        float_value = float(value)
    except (TypeError, ValueError):
        return MathValidationResult(
            False, 0.0, [], [f"Cannot convert {metric_name}={value} to float"]
        )

    return validator(float_value)


def validate_metrics_batch(
    metrics: dict[str, Any]
) -> dict[str, MathValidationResult]:
    """Validate multiple metrics at once.

    Args:
        metrics: Dict of metric_name -> value

    Returns:
        Dict of metric_name -> MathValidationResult
    """
    results: dict[str, MathValidationResult] = {}
    for name, value in metrics.items():
        results[name] = validate_metric(name, value)
    return results
