**Skill**: [Adaptive WFO Epoch Selection](../SKILL.md)

# Guardrails (Principled Guidelines)

## G1: WFE Thresholds

The traditional thresholds (0.30, 0.50, 0.70) are **guidelines based on practitioner consensus**, not derived from first principles. They represent:

| Threshold | Meaning     | Statistical Basis                                          |
| --------- | ----------- | ---------------------------------------------------------- |
| **0.30**  | Hard reject | Retaining <30% of IS performance is almost certainly noise |
| **0.50**  | Warning     | At 50%, half the signal is lost - investigate              |
| **0.70**  | Target      | Industry standard for "good" transfer                      |

```python
# These are GUIDELINES, not hard rules
# Adjust based on your domain and risk tolerance
WFE_THRESHOLDS = {
    "hard_reject": 0.30,  # Below this: almost certainly overfitting
    "warning": 0.50,      # Below this: significant signal loss
    "target": 0.70,       # Above this: good generalization
}

def classify_wfe(wfe: float | None) -> str:
    """Classify WFE with principled thresholds."""
    if wfe is None:
        return "INVALID"  # IS_Sharpe below noise floor
    if wfe < WFE_THRESHOLDS["hard_reject"]:
        return "REJECT"
    if wfe < WFE_THRESHOLDS["warning"]:
        return "INVESTIGATE"
    if wfe < WFE_THRESHOLDS["target"]:
        return "ACCEPTABLE"
    return "EXCELLENT"
```

## G2: IS_Sharpe Minimum (Data-Driven)

**OLD (magic number):**

```python
# WRONG: Fixed threshold regardless of sample size
if is_sharpe < 1.0:
    wfe = None
```

**NEW (principled):**

```python
# CORRECT: Threshold adapts to sample size
min_is_sharpe = compute_is_sharpe_threshold(n_samples)
if is_sharpe < min_is_sharpe:
    wfe = None  # Below noise floor for this sample size
```

The threshold derives from the standard error of Sharpe ratio: SE(SR) ~ 1/sqrt(n).

**Note on SE(Sharpe) approximation**: The formula `1/sqrt(n)` is a first-order approximation valid when SR is small (close to 0). The full Lo (2002) formula is:

```
SE(SR) = sqrt((1 + 0.5*SR^2) / n)
```

For high-Sharpe strategies (SR > 1.0), the simplified formula underestimates SE by ~25-50%. Use the full formula when evaluating strategies with SR > 1.0.

## G3: Stability Penalty for Epoch Changes (Adaptive)

The stability penalty prevents hyperparameter churn. Instead of fixed thresholds, use **relative improvement** based on WFE variance:

```python
def compute_stability_threshold(wfe_history: list[float]) -> float:
    """Compute stability threshold from observed WFE variance.

    Principle: Require improvement exceeding noise level.

    If WFE has std=0.15 across folds, random fluctuation could be +/-0.15.
    To distinguish signal from noise, require improvement > 1 sigma of WFE.

    Minimum: 5% (prevent switching on negligible improvements)
    Maximum: 20% (don't be overly conservative)
    """
    if len(wfe_history) < 3:
        return 0.10  # Default until enough history

    wfe_std = np.std(wfe_history)
    threshold = max(0.05, min(0.20, wfe_std))
    return threshold


class AdaptiveStabilityPenalty:
    """Stability penalty that adapts to observed WFE variance."""

    def __init__(self):
        self.wfe_history: list[float] = []
        self.epoch_changes: list[int] = []

    def should_change_epoch(
        self,
        current_wfe: float,
        candidate_wfe: float,
        current_epoch: int,
        candidate_epoch: int,
    ) -> bool:
        """Decide whether to change epochs based on adaptive threshold."""
        self.wfe_history.append(current_wfe)

        if current_epoch == candidate_epoch:
            return False  # Same epoch, no change needed

        threshold = compute_stability_threshold(self.wfe_history)
        improvement = (candidate_wfe - current_wfe) / max(abs(current_wfe), 0.01)

        if improvement > threshold:
            self.epoch_changes.append(len(self.wfe_history))
            return True

        return False  # Improvement not significant
```

## G4: Registration and Unused Data for Epoch Search (Principled)

Selecting the best of K epochs across F folds inflates the selected Sharpe. By operator rule (2026-10-15) this is **not** handled with a Deflated Sharpe Ratio or any other trial-count correction; do not compute, report, rank by or cite one. Guard the selection instead:

1. **Parsimony on the model itself**: keep the epoch candidate set small (3-5 options) and count it as part of the model's complexity.
2. **Registration before runs**: write the candidate set, WFE thresholds (G1), IS_Sharpe minimum (G2), stability penalty (G3) and acceptance criteria down before the sweep starts, and do not change them after seeing results.
3. **Unused data**: judge the selected configuration on the test split (and a final holdout) that no selection step has touched.
4. **Report the rule's own statistics**: its Sharpe, PSR and MinTRL on the untouched data.

```python
def accept_selected_epoch(
    test_sharpe: float,
    test_psr: float,
    n_test_obs: int,
    min_trl_obs: float,
    registered_psr_threshold: float,
) -> bool:
    """Accept the selected epoch on untouched test data only.

    registered_psr_threshold is fixed in the registration before the sweep.
    """
    return test_sharpe > 0 and test_psr > registered_psr_threshold and n_test_obs >= min_trl_obs
```
