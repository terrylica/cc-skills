---
name: adaptive-wfo-epoch
description: >
  Adaptive epoch selection for Walk-Forward Optimization using efficient frontier analysis.
  Per-fold epoch sweeps with WFE-based selection and carry-forward priors.
  TRIGGERS - epoch selection, WFO epoch, walk-forward epoch, training epochs WFO,
  efficient frontier epochs, overfitting epochs, epoch sweep, BiLSTM epochs,
  WFE optimization, adaptive hyperparameter, Pardo WFE, epoch carry-forward.
allowed-tools: Read, Grep, Glob, Bash
---

# Adaptive Walk-Forward Epoch Selection (AWFES)

Machine-readable reference for adaptive epoch selection within Walk-Forward Optimization (WFO). Optimizes training epochs per-fold using Walk-Forward Efficiency (WFE) as the objective.

## Quick Start

```python
from adaptive_wfo_epoch import EpochSweep, compute_efficient_frontier

# Define epoch candidates
EPOCH_CONFIGS = [400, 800, 1000, 2000]

# Per-fold epoch sweep
for fold in wfo_folds:
    epoch_metrics = []
    for epoch in EPOCH_CONFIGS:
        is_sharpe, oos_sharpe = train_and_evaluate(fold, epochs=epoch)
        wfe = oos_sharpe / is_sharpe if is_sharpe > 0.1 else None
        epoch_metrics.append({"epoch": epoch, "wfe": wfe, "is_sharpe": is_sharpe})

    # Select from efficient frontier
    selected_epoch = compute_efficient_frontier(epoch_metrics)

    # Carry forward to next fold as prior
    prior_epoch = selected_epoch
```

## Methodology Overview

### What This Is

Per-fold adaptive epoch selection where:

1. Train models across a range of epochs (e.g., 400, 800, 1000, 2000)
2. Compute WFE = OOS_Sharpe / IS_Sharpe for each epoch count
3. Find the "efficient frontier" - epochs maximizing WFE vs training cost
4. Select optimal epoch from frontier for OOS evaluation
5. Carry forward as prior for next fold

### What This Is NOT

- **NOT early stopping**: Early stopping monitors validation loss continuously; this evaluates discrete candidates post-hoc
- **NOT Bayesian optimization**: No surrogate model; direct evaluation of all candidates
- **NOT nested cross-validation**: Uses temporal WFO, not shuffled splits

## Academic Foundations

| Concept                     | Citation                       | Key Insight                                       |
| --------------------------- | ------------------------------ | ------------------------------------------------- |
| Walk-Forward Efficiency     | Pardo (1992, 2008)             | WFE = OOS_Return / IS_Return as robustness metric |
| Deflated Sharpe Ratio       | Bailey & López de Prado (2014) | Adjusts for multiple testing                      |
| Pareto-Optimal HP Selection | Bischl et al. (2023)           | Multi-objective hyperparameter optimization       |
| Warm-Starting               | Nomura & Ono (2021)            | Transfer knowledge between optimization runs      |

See [references/academic-foundations.md](./references/academic-foundations.md) for full literature review.

## Core Formula: Walk-Forward Efficiency

```python
def compute_wfe(is_sharpe: float, oos_sharpe: float) -> float | None:
    """Walk-Forward Efficiency - measures performance transfer.

    WFE = OOS_Sharpe / IS_Sharpe

    Interpretation:
    - WFE > 0.70: Excellent transfer (low overfitting)
    - WFE 0.50-0.70: Good transfer
    - WFE 0.30-0.50: Moderate transfer (investigate)
    - WFE < 0.30: REJECT (severe overfitting)

    Reference: Pardo (2008) "The Evaluation and Optimization of Trading Strategies"
    """
    if abs(is_sharpe) < 0.1:  # Near-zero denominator
        return None
    return oos_sharpe / is_sharpe
```

## Guardrails (MANDATORY)

### G1: WFE Minimum Threshold

```yaml
wfe_threshold:
  hard_reject: 0.30 # REJECT if WFE < 0.30
  warning: 0.50 # FLAG for review if WFE < 0.50
  target: 0.70 # Target for production deployment
```

**Rationale**: WFE < 0.30 means losing >70% of in-sample performance out-of-sample, indicating severe overfitting.

### G2: IS_Sharpe Minimum

```yaml
is_sharpe_minimum: 1.0
```

**Rationale**: WFE is only meaningful when IS_Sharpe > 1.0. With near-zero IS_Sharpe, the ratio becomes unstable and meaningless.

```python
# WRONG: Computing WFE with weak in-sample signal
is_sharpe = 0.1
oos_sharpe = 0.05
wfe = 0.5  # Looks acceptable but both Sharpes are noise!

# CORRECT: Require minimum IS_Sharpe
if is_sharpe < 1.0:
    wfe = None  # Mark as invalid, use fallback
```

### G3: Stability Penalty for Epoch Changes

```yaml
stability_penalty:
  enabled: true
  min_wfe_improvement: 0.10 # 10% improvement required to change
  min_consecutive_folds: 2 # Must be optimal for 2+ folds
  max_changes_per_quarter: 2 # Prevent hyperparameter churn
```

**Rationale**: Frequent epoch switching indicates instability or overfitting to the epoch search space itself.

### G4: DSR Adjustment for Epoch Search

```python
def adjusted_dsr_for_epoch_search(
    sharpe: float,
    n_folds: int,
    n_epochs: int,
) -> float:
    """Deflated Sharpe Ratio accounting for epoch selection multiplicity.

    When selecting from K epochs, the expected maximum Sharpe under null
    is inflated. This adjustment corrects for that selection bias.

    Reference: Bailey & López de Prado (2014)
    """
    from math import sqrt, log, pi

    n_trials = n_folds * n_epochs  # Total selection events

    # Expected maximum under null (order statistics)
    e_max = sqrt(2 * log(n_trials))
    e_max -= (log(log(n_trials)) + log(4 * pi)) / (2 * sqrt(2 * log(n_trials)))

    # Assume SE(Sharpe) ≈ 0.3 for typical strategies
    sharpe_se = 0.3
    e_max *= sharpe_se

    # Deflated Sharpe
    return max(0, sharpe - e_max)
```

For 4 epochs × 31 folds = 124 trials: **A Sharpe of 1.0 deflates to ~0.25 after adjustment.**

## WFE Aggregation Methods

### Method 1: Pooled WFE (Recommended for precision-weighted)

```python
def pooled_wfe(fold_results: list[dict]) -> float:
    """Weights each fold by its sample size (precision).

    Formula: Σ(T_OOS × SR_OOS) / Σ(T_IS × SR_IS)

    Advantage: More stable than arithmetic mean, handles varying fold sizes.
    Use when: Fold sizes vary significantly.
    """
    numerator = sum(r["n_oos"] * r["oos_sharpe"] for r in fold_results)
    denominator = sum(r["n_is"] * r["is_sharpe"] for r in fold_results)

    if denominator < 1e-10:
        return float("nan")
    return numerator / denominator
```

### Method 2: Median WFE (Recommended for robustness)

```python
def median_wfe(fold_results: list[dict]) -> float:
    """Robust to outliers, standard in robust statistics.

    Advantage: Single extreme fold doesn't dominate.
    Use when: Suspected outlier folds (regime changes, data issues).
    """
    wfes = [r["wfe"] for r in fold_results if r["wfe"] is not None]
    return float(np.median(wfes)) if wfes else float("nan")
```

### Method 3: Weighted Arithmetic Mean

```python
def weighted_mean_wfe(fold_results: list[dict]) -> float:
    """Weights by inverse variance (efficiency weighting).

    Formula: Σ(w_i × WFE_i) / Σ(w_i)
    where w_i = 1 / Var(WFE_i) ≈ n_oos × n_is / (n_oos + n_is)

    Advantage: Optimal when combining estimates of different precision.
    Use when: All folds have similar characteristics.
    """
    weighted_sum = 0.0
    weight_total = 0.0

    for r in fold_results:
        if r["wfe"] is None:
            continue
        weight = r["n_oos"] * r["n_is"] / (r["n_oos"] + r["n_is"] + 1e-10)
        weighted_sum += weight * r["wfe"]
        weight_total += weight

    return weighted_sum / weight_total if weight_total > 0 else float("nan")
```

### Aggregation Selection Guide

| Scenario            | Recommended Method | Rationale               |
| ------------------- | ------------------ | ----------------------- |
| Variable fold sizes | Pooled WFE         | Weights by precision    |
| Suspected outliers  | Median WFE         | Robust to extremes      |
| Homogeneous folds   | Weighted mean      | Optimal efficiency      |
| Reporting           | **All three**      | Cross-check consistency |

## Efficient Frontier Algorithm

```python
def compute_efficient_frontier(
    epoch_metrics: list[dict],
    wfe_weight: float = 1.0,
    time_weight: float = 0.1,
) -> tuple[list[int], int]:
    """
    Find Pareto-optimal epochs and select best.

    An epoch is on the frontier if no other epoch dominates it
    (better WFE AND lower training time).

    Args:
        epoch_metrics: List of {epoch, wfe, training_time_sec}
        wfe_weight: Weight for WFE in selection (higher = prefer generalization)
        time_weight: Weight for training time (higher = prefer speed)

    Returns:
        (frontier_epochs, selected_epoch)
    """
    import numpy as np

    # Filter valid metrics
    valid = [(m["epoch"], m["wfe"], m.get("training_time_sec", m["epoch"]))
             for m in epoch_metrics
             if m["wfe"] is not None and np.isfinite(m["wfe"])]

    if not valid:
        # Fallback: return epoch with best OOS Sharpe
        best_oos = max(epoch_metrics, key=lambda m: m.get("oos_sharpe", 0))
        return ([best_oos["epoch"]], best_oos["epoch"])

    # Pareto dominance check
    frontier = []
    for i, (epoch_i, wfe_i, time_i) in enumerate(valid):
        dominated = False
        for j, (epoch_j, wfe_j, time_j) in enumerate(valid):
            if i == j:
                continue
            # j dominates i if: better/equal WFE AND lower/equal time (strict in at least one)
            if (wfe_j >= wfe_i and time_j <= time_i and
                (wfe_j > wfe_i or time_j < time_i)):
                dominated = True
                break
        if not dominated:
            frontier.append((epoch_i, wfe_i, time_i))

    frontier_epochs = [e for e, _, _ in frontier]

    if len(frontier) == 1:
        return (frontier_epochs, frontier[0][0])

    # Weighted score selection
    wfes = np.array([w for _, w, _ in frontier])
    times = np.array([t for _, _, t in frontier])

    wfe_norm = (wfes - wfes.min()) / (wfes.max() - wfes.min() + 1e-10)
    time_norm = (times.max() - times) / (times.max() - times.min() + 1e-10)

    scores = wfe_weight * wfe_norm + time_weight * time_norm
    best_idx = np.argmax(scores)

    return (frontier_epochs, frontier[best_idx][0])
```

## Carry-Forward Mechanism

```python
class AdaptiveEpochSelector:
    """Maintains epoch selection state across WFO folds."""

    def __init__(self, epoch_configs: list[int], stability_penalty: float = 0.1):
        self.epoch_configs = epoch_configs
        self.stability_penalty = stability_penalty
        self.selection_history: list[dict] = []
        self.last_selected: int | None = None

    def select_epoch(self, epoch_metrics: list[dict]) -> int:
        """Select epoch with stability penalty for changes."""
        frontier_epochs, candidate = compute_efficient_frontier(epoch_metrics)

        # Apply stability penalty if changing epochs
        if self.last_selected is not None and candidate != self.last_selected:
            candidate_wfe = next(
                m["wfe"] for m in epoch_metrics if m["epoch"] == candidate
            )
            last_wfe = next(
                (m["wfe"] for m in epoch_metrics if m["epoch"] == self.last_selected),
                0.0
            )

            # Only change if improvement exceeds penalty threshold
            if candidate_wfe < last_wfe * (1 + self.stability_penalty):
                candidate = self.last_selected

        # Record and return
        self.selection_history.append({
            "epoch": candidate,
            "frontier": frontier_epochs,
            "changed": candidate != self.last_selected,
        })
        self.last_selected = candidate
        return candidate
```

## Anti-Patterns

| Anti-Pattern                   | Symptom                             | Fix                               |
| ------------------------------ | ----------------------------------- | --------------------------------- |
| **Peak picking**               | Best epoch always at sweep boundary | Expand range, check for plateau   |
| **Insufficient folds**         | effective_n < 30                    | Increase folds or data span       |
| **Ignoring temporal autocorr** | Folds correlated                    | Use purged CV, gap between folds  |
| **Overfitting to IS**          | IS >> OOS Sharpe                    | Reduce epochs, add regularization |
| **sqrt(252) for crypto**       | Inflated Sharpe                     | Use sqrt(365) or sqrt(7) weekly   |
| **Single epoch selection**     | No uncertainty quantification       | Report confidence interval        |
| **Meta-overfitting**           | Epoch selection itself overfits     | Limit to 3-4 candidates max       |

See [references/anti-patterns.md](./references/anti-patterns.md) for detailed examples.

## Decision Tree

See [references/epoch-selection-decision-tree.md](./references/epoch-selection-decision-tree.md) for the full practitioner decision tree.

```
Start
  │
  ├─ IS_Sharpe > 1.0? ──NO──> Mark WFE invalid, use fallback
  │         │
  │        YES
  │         │
  ├─ Compute WFE for each epoch
  │         │
  ├─ Any WFE > 0.30? ──NO──> REJECT all epochs (severe overfit)
  │         │
  │        YES
  │         │
  ├─ Compute efficient frontier
  │         │
  ├─ Apply stability penalty
  │         │
  └─> Return selected epoch
```

## Integration with rangebar-eval-metrics

This skill extends [rangebar-eval-metrics](../rangebar-eval-metrics/SKILL.md):

| Metric Source         | Used For                                 |
| --------------------- | ---------------------------------------- |
| `weekly_sharpe`       | WFE numerator (OOS) and denominator (IS) |
| `n_bars`              | Sample size for aggregation weights      |
| `psr`, `dsr`          | Final acceptance criteria                |
| `prediction_autocorr` | Validate model isn't collapsed           |

## References

| Topic                    | Reference File                                                                    |
| ------------------------ | --------------------------------------------------------------------------------- |
| Academic Literature      | [academic-foundations.md](./references/academic-foundations.md)                   |
| Mathematical Formulation | [mathematical-formulation.md](./references/mathematical-formulation.md)           |
| Decision Tree            | [epoch-selection-decision-tree.md](./references/epoch-selection-decision-tree.md) |
| Anti-Patterns            | [anti-patterns.md](./references/anti-patterns.md)                                 |

## Full Citations

- Bailey, D. H., & López de Prado, M. (2014). The deflated Sharpe ratio: Correcting for selection bias, backtest overfitting and non-normality. _The Journal of Portfolio Management_, 40(5), 94-107.
- Bischl, B., et al. (2023). Multi-Objective Hyperparameter Optimization in Machine Learning. _ACM Transactions on Evolutionary Learning and Optimization_.
- López de Prado, M. (2018). _Advances in Financial Machine Learning_. Wiley. Chapter 7.
- Nomura, M., & Ono, I. (2021). Warm Starting CMA-ES for Hyperparameter Optimization. _AAAI Conference on Artificial Intelligence_.
- Pardo, R. E. (2008). _The Evaluation and Optimization of Trading Strategies, 2nd Edition_. John Wiley & Sons.
