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

| Metric Source         | Used For                                 | Reference                                                                                |
| --------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------------- |
| `weekly_sharpe`       | WFE numerator (OOS) and denominator (IS) | [sharpe-formulas.md](../rangebar-eval-metrics/references/sharpe-formulas.md)             |
| `n_bars`              | Sample size for aggregation weights      | [metrics-schema.md](../rangebar-eval-metrics/references/metrics-schema.md)               |
| `psr`, `dsr`          | Final acceptance criteria                | [sharpe-formulas.md](../rangebar-eval-metrics/references/sharpe-formulas.md)             |
| `prediction_autocorr` | Validate model isn't collapsed           | [ml-prediction-quality.md](../rangebar-eval-metrics/references/ml-prediction-quality.md) |
| `is_collapsed`        | Model health check                       | [ml-prediction-quality.md](../rangebar-eval-metrics/references/ml-prediction-quality.md) |
| Extended risk metrics | Deep risk analysis (optional)            | [risk-metrics.md](../rangebar-eval-metrics/references/risk-metrics.md)                   |

### Recommended Workflow

1. **Compute base metrics** using `rangebar-eval-metrics:compute_metrics.py`
2. **Feed to AWFES** for epoch selection with `weekly_sharpe` as primary signal
3. **Validate** with `psr > 0.85` and `dsr > 0.50` before deployment
4. **Monitor** `is_collapsed` and `prediction_autocorr` for model health

---

## OOS Application Phase

### Overview

After epoch selection via efficient frontier, apply the selected epochs to held-out test data for final OOS performance metrics. This phase produces "live trading" results that simulate deployment.

### Nested WFO Structure

AWFES uses **Nested WFO** with three data splits per fold:

```
                    AWFES: Nested WFO Data Split (per fold)

#############     +----------+     +---------+     +----------+     #==========#
# Train 60% # --> | Gap 6% A | --> | Val 20% | --> | Gap 6% B | --> H Test 20% H
#############     +----------+     +---------+     +----------+     #==========#
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "AWFES: Nested WFO Data Split (per fold)"; flow: east; }

[ Train 60% ] { border: bold; }
[ Gap 6% A ]
[ Val 20% ]
[ Gap 6% B ]
[ Test 20% ] { border: double; }

[ Train 60% ] -> [ Gap 6% A ]
[ Gap 6% A ] -> [ Val 20% ]
[ Val 20% ] -> [ Gap 6% B ]
[ Gap 6% B ] -> [ Test 20% ]
```

</details>

### Per-Fold Workflow

```
                  AWFES: Per-Fold Workflow

                   -----------------------
                  |      Fold i Data      |
                   -----------------------
                    |
                    v
                  +-----------------------+
                  | Split: Train/Val/Test |
                  +-----------------------+
                    |
                    v
                  +-----------------------+
                  | Epoch Sweep on Train  |
                  +-----------------------+
                    |
                    v
                  +-----------------------+
                  |  Compute WFE on Val   |
                  +-----------------------+
                    |
                    | val optimal
                    v
                  #=======================#
                  H    Bayesian Update    H
                  #=======================#
                    |
                    | smoothed epoch
                    v
                  +-----------------------+
                  |   Train Final Model   |
                  +-----------------------+
                    |
                    v
                  #=======================#
                  H   Evaluate on Test    H
                  #=======================#
                    |
                    v
                   -----------------------
                  |    Fold i Metrics     |
                   -----------------------
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "AWFES: Per-Fold Workflow"; flow: south; }

[ Fold i Data ] { shape: rounded; }
[ Split: Train/Val/Test ]
[ Epoch Sweep on Train ]
[ Compute WFE on Val ]
[ Bayesian Update ] { border: double; }
[ Train Final Model ]
[ Evaluate on Test ] { border: double; }
[ Fold i Metrics ] { shape: rounded; }

[ Fold i Data ] -> [ Split: Train/Val/Test ]
[ Split: Train/Val/Test ] -> [ Epoch Sweep on Train ]
[ Epoch Sweep on Train ] -> [ Compute WFE on Val ]
[ Compute WFE on Val ] -- val optimal --> [ Bayesian Update ]
[ Bayesian Update ] -- smoothed epoch --> [ Train Final Model ]
[ Train Final Model ] -> [ Evaluate on Test ]
[ Evaluate on Test ] -> [ Fold i Metrics ]
```

</details>

### Bayesian Carry-Forward Across Folds

```
                                 AWFES: Bayesian Carry-Forward Across Folds

 -------   init   +--------+  posterior   +--------+  posterior   +--------+     +--------+      -----------
| Prior | ------> | Fold 1 | -----------> | Fold 2 | -----------> | Fold 3 | ..> | Fold N | --> | Aggregate |
 -------          +--------+              +--------+              +--------+     +--------+      -----------
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "AWFES: Bayesian Carry-Forward Across Folds"; flow: east; }

[ Prior ] { shape: rounded; }
[ Fold 1 ]
[ Fold 2 ]
[ Fold 3 ]
[ Fold N ]
[ Aggregate ] { shape: rounded; }

[ Prior ] -- init --> [ Fold 1 ]
[ Fold 1 ] -- posterior --> [ Fold 2 ]
[ Fold 2 ] -- posterior --> [ Fold 3 ]
[ Fold 3 ] ..> [ Fold N ]
[ Fold N ] -> [ Aggregate ]
```

</details>

### Bayesian Epoch Selection for OOS

Instead of using the current fold's optimal epoch (look-ahead bias), use **Bayesian-smoothed epoch** from prior folds:

```python
class BayesianEpochSelector:
    """Bayesian updating of epoch selection across folds."""

    def __init__(
        self,
        epoch_configs: list[int],
        prior_mean: float | None = None,
        prior_variance: float = 100.0,
    ):
        self.epoch_configs = epoch_configs
        # Initialize prior: mean of epoch range if not specified
        self.posterior_mean = prior_mean or np.mean(epoch_configs)
        self.posterior_variance = prior_variance
        self.observation_variance = 50.0  # Assumed noise in optimal epoch
        self.history: list[dict] = []

    def update(self, observed_optimal_epoch: int, wfe: float) -> int:
        """Update posterior with new fold's optimal epoch.

        Uses precision-weighted Bayesian update:
        posterior_mean = (prior_precision * prior_mean + obs_precision * obs) /
                        (prior_precision + obs_precision)

        Args:
            observed_optimal_epoch: Optimal epoch from current fold's validation
            wfe: Walk-Forward Efficiency (used to weight observation)

        Returns:
            Smoothed epoch selection for TEST evaluation
        """
        # Weight observation by WFE (higher WFE = more reliable signal)
        effective_variance = self.observation_variance / max(wfe, 0.1)

        prior_precision = 1.0 / self.posterior_variance
        obs_precision = 1.0 / effective_variance

        # Bayesian update
        new_precision = prior_precision + obs_precision
        new_mean = (
            prior_precision * self.posterior_mean +
            obs_precision * observed_optimal_epoch
        ) / new_precision

        # Record before updating
        self.history.append({
            "observed_epoch": observed_optimal_epoch,
            "wfe": wfe,
            "prior_mean": self.posterior_mean,
            "posterior_mean": new_mean,
            "selected_epoch": self._snap_to_config(new_mean),
        })

        self.posterior_mean = new_mean
        self.posterior_variance = 1.0 / new_precision

        return self._snap_to_config(new_mean)

    def _snap_to_config(self, continuous_epoch: float) -> int:
        """Snap continuous estimate to nearest valid epoch config."""
        return min(self.epoch_configs, key=lambda e: abs(e - continuous_epoch))

    def get_current_epoch(self) -> int:
        """Get current smoothed epoch without updating."""
        return self._snap_to_config(self.posterior_mean)
```

### Application Workflow

```python
def apply_awfes_to_test(
    folds: list[Fold],
    model_factory: Callable,
    bayesian_selector: BayesianEpochSelector,
) -> list[dict]:
    """Apply AWFES with Bayesian smoothing to test data.

    Workflow per fold:
    1. Split into train/validation/test (60/20/20)
    2. Sweep epochs on train, compute WFE on validation
    3. Update Bayesian posterior with validation-optimal epoch
    4. Train final model at Bayesian-selected epoch on train+validation
    5. Evaluate on TEST (untouched data)
    """
    results = []

    for fold_idx, fold in enumerate(folds):
        # Step 1: Split data
        train, validation, test = fold.split_nested(
            train_pct=0.60,
            validation_pct=0.20,
            test_pct=0.20,
            embargo_pct=0.06,  # 6% gap at each boundary
        )

        # Step 2: Epoch sweep on train → validate on validation
        epoch_metrics = []
        for epoch in bayesian_selector.epoch_configs:
            model = model_factory()
            model.fit(train.X, train.y, epochs=epoch)

            is_sharpe = compute_sharpe(model.predict(train.X), train.y)
            val_sharpe = compute_sharpe(model.predict(validation.X), validation.y)
            wfe = val_sharpe / is_sharpe if is_sharpe > 0.1 else None

            epoch_metrics.append({
                "epoch": epoch,
                "is_sharpe": is_sharpe,
                "val_sharpe": val_sharpe,
                "wfe": wfe,
            })

        # Step 3: Find validation-optimal and update Bayesian
        val_optimal = max(
            [m for m in epoch_metrics if m["wfe"] is not None],
            key=lambda m: m["wfe"],
            default={"epoch": bayesian_selector.epoch_configs[0], "wfe": 0.3}
        )
        selected_epoch = bayesian_selector.update(
            val_optimal["epoch"],
            val_optimal["wfe"],
        )

        # Step 4: Train final model on train+validation at selected epoch
        combined_X = np.vstack([train.X, validation.X])
        combined_y = np.hstack([train.y, validation.y])
        final_model = model_factory()
        final_model.fit(combined_X, combined_y, epochs=selected_epoch)

        # Step 5: Evaluate on TEST (untouched)
        test_predictions = final_model.predict(test.X)
        test_metrics = compute_oos_metrics(test_predictions, test.y, test.timestamps)

        results.append({
            "fold_idx": fold_idx,
            "validation_optimal_epoch": val_optimal["epoch"],
            "bayesian_selected_epoch": selected_epoch,
            "test_metrics": test_metrics,
            "epoch_metrics": epoch_metrics,
        })

    return results
```

See [references/oos-application.md](./references/oos-application.md) for complete implementation.

---

## Epoch Smoothing Methods

### Why Smooth Epoch Selections?

Raw per-fold epoch selections are noisy due to:

- Limited validation data per fold
- Regime changes between folds
- Stochastic training dynamics

Smoothing reduces variance while preserving signal.

### Method Comparison

| Method                     | Formula                   | Pros                            | Cons                          |
| -------------------------- | ------------------------- | ------------------------------- | ----------------------------- |
| **Bayesian (Recommended)** | Precision-weighted update | Principled, handles uncertainty | More complex                  |
| EMA                        | `α × new + (1-α) × old`   | Simple, responsive              | No uncertainty quantification |
| SMA                        | Mean of last N            | Most stable                     | Slow to adapt                 |
| Median                     | Median of last N          | Robust to outliers              | Loses magnitude info          |

### Bayesian Updating (Primary Method)

```python
def bayesian_epoch_update(
    prior_mean: float,
    prior_variance: float,
    observed_epoch: int,
    observation_variance: float,
    wfe_weight: float = 1.0,
) -> tuple[float, float]:
    """Single Bayesian update step.

    Mathematical formulation:
    - Prior: N(μ₀, σ₀²)
    - Observation: N(x, σ_obs²/wfe)  # WFE-weighted
    - Posterior: N(μ₁, σ₁²)

    Where:
    μ₁ = (μ₀/σ₀² + x·wfe/σ_obs²) / (1/σ₀² + wfe/σ_obs²)
    σ₁² = 1 / (1/σ₀² + wfe/σ_obs²)
    """
    # Effective observation variance (lower WFE = less reliable)
    eff_obs_var = observation_variance / max(wfe_weight, 0.1)

    prior_precision = 1.0 / prior_variance
    obs_precision = 1.0 / eff_obs_var

    posterior_precision = prior_precision + obs_precision
    posterior_mean = (
        prior_precision * prior_mean + obs_precision * observed_epoch
    ) / posterior_precision
    posterior_variance = 1.0 / posterior_precision

    return posterior_mean, posterior_variance
```

### Exponential Moving Average (Alternative)

```python
def ema_epoch_update(
    current_ema: float,
    observed_epoch: int,
    alpha: float = 0.3,
) -> float:
    """EMA update: more weight on recent observations.

    α = 0.3 means ~90% of signal from last 7 folds.
    α = 0.5 means ~90% of signal from last 4 folds.
    """
    return alpha * observed_epoch + (1 - alpha) * current_ema
```

### Initialization Strategies

| Strategy             | When to Use              | Implementation                       |
| -------------------- | ------------------------ | ------------------------------------ |
| **Midpoint prior**   | No domain knowledge      | `mean(epoch_configs)`                |
| **Literature prior** | Published optimal exists | Known optimal ± uncertainty          |
| **Burn-in**          | Sufficient data          | Use first N folds for initialization |

```python
# Initialization example
EPOCH_CONFIGS = [80, 100, 150, 200, 400]

# Strategy 1: Midpoint (default)
prior_mean = np.mean(EPOCH_CONFIGS)  # 186
prior_variance = np.var(EPOCH_CONFIGS)  # High uncertainty

# Strategy 2: Literature (e.g., known 100-200 optimal for BiLSTM)
prior_mean = 150
prior_variance = 2500  # ±50 epochs

# Strategy 3: Burn-in (use first 5 folds)
burn_in_optima = [run_fold_sweep(fold) for fold in folds[:5]]
prior_mean = np.mean(burn_in_optima)
prior_variance = np.var(burn_in_optima) + 100  # Add base uncertainty
```

See [references/epoch-smoothing.md](./references/epoch-smoothing.md) for extended analysis.

---

## OOS Metrics Specification

### Metric Tiers for Test Evaluation

Following [rangebar-eval-metrics](../rangebar-eval-metrics/SKILL.md), compute these metrics on TEST data:

#### Tier 1: Primary Metrics (Mandatory)

| Metric                 | Formula                                 | Threshold | Purpose              |
| ---------------------- | --------------------------------------- | --------- | -------------------- |
| `weekly_sharpe`        | `mean(daily_pnl) / std(daily_pnl) × √7` | > 0       | Core performance     |
| `hit_rate`             | `n_correct_sign / n_total`              | > 0.50    | Directional accuracy |
| `cumulative_pnl`       | `Σ(pred × actual)`                      | > 0       | Total return         |
| `positive_sharpe_rate` | `n_folds(sharpe > 0) / n_folds`         | > 0.55    | Consistency          |
| `wfe_test`             | `test_sharpe / validation_sharpe`       | > 0.30    | Final transfer       |

#### Tier 2: Risk Metrics

| Metric          | Formula                        | Threshold | Purpose        |
| --------------- | ------------------------------ | --------- | -------------- |
| `max_drawdown`  | `max(peak - trough) / peak`    | < 0.30    | Worst loss     |
| `calmar_ratio`  | `annual_return / max_drawdown` | > 0.5     | Risk-adjusted  |
| `profit_factor` | `gross_profit / gross_loss`    | > 1.0     | Win/loss ratio |
| `cvar_10pct`    | `mean(worst 10% returns)`      | > -0.05   | Tail risk      |

#### Tier 3: Statistical Validation

| Metric             | Formula                           | Threshold | Purpose                   |
| ------------------ | --------------------------------- | --------- | ------------------------- |
| `psr`              | `P(true_sharpe > 0)`              | > 0.85    | Statistical significance  |
| `dsr`              | `sharpe - E[max_sharpe_null]`     | > 0.50    | Multiple testing adjusted |
| `binomial_pvalue`  | `binom.test(n_positive, n_total)` | < 0.05    | Sign test                 |
| `hac_ttest_pvalue` | HAC-adjusted t-test               | < 0.05    | Autocorrelation robust    |

### Metric Computation Code

```python
def compute_oos_metrics(
    predictions: np.ndarray,
    actuals: np.ndarray,
    timestamps: np.ndarray,
) -> dict[str, float]:
    """Compute full OOS metrics suite for test data.

    Args:
        predictions: Model predictions (signed magnitude)
        actuals: Actual returns
        timestamps: Bar timestamps for daily aggregation

    Returns:
        Dictionary with all tier metrics
    """
    pnl = predictions * actuals

    # Tier 1: Primary
    daily_pnl = group_by_day(pnl, timestamps)
    weekly_sharpe = (
        np.mean(daily_pnl) / np.std(daily_pnl) * np.sqrt(7)
        if np.std(daily_pnl) > 1e-10 else 0.0
    )
    hit_rate = np.mean(np.sign(predictions) == np.sign(actuals))
    cumulative_pnl = np.sum(pnl)

    # Tier 2: Risk
    equity_curve = np.cumsum(pnl)
    running_max = np.maximum.accumulate(equity_curve)
    drawdowns = (running_max - equity_curve) / np.maximum(running_max, 1e-10)
    max_drawdown = np.max(drawdowns)

    gross_profit = np.sum(pnl[pnl > 0])
    gross_loss = abs(np.sum(pnl[pnl < 0]))
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else float("inf")

    # CVaR (10%)
    sorted_pnl = np.sort(pnl)
    cvar_cutoff = max(1, int(len(sorted_pnl) * 0.10))
    cvar_10pct = np.mean(sorted_pnl[:cvar_cutoff])

    # Tier 3: Statistical
    sharpe_se = 1.0 / np.sqrt(len(daily_pnl)) if len(daily_pnl) > 0 else 1.0
    psr = norm.cdf(weekly_sharpe / sharpe_se) if sharpe_se > 0 else 0.5

    n_positive = np.sum(pnl > 0)
    n_total = len(pnl)
    binomial_pvalue = binom_test(n_positive, n_total, 0.5, alternative="greater")

    return {
        # Tier 1
        "weekly_sharpe": weekly_sharpe,
        "hit_rate": hit_rate,
        "cumulative_pnl": cumulative_pnl,
        "n_bars": len(pnl),
        # Tier 2
        "max_drawdown": max_drawdown,
        "profit_factor": profit_factor,
        "cvar_10pct": cvar_10pct,
        # Tier 3
        "psr": psr,
        "binomial_pvalue": binomial_pvalue,
    }
```

### Aggregation Across Folds

```python
def aggregate_test_metrics(fold_results: list[dict]) -> dict[str, float]:
    """Aggregate test metrics across all folds."""
    metrics = [r["test_metrics"] for r in fold_results]

    # Positive Sharpe Rate
    sharpes = [m["weekly_sharpe"] for m in metrics]
    positive_sharpe_rate = np.mean([s > 0 for s in sharpes])

    # Median for robustness
    median_sharpe = np.median(sharpes)
    median_hit_rate = np.median([m["hit_rate"] for m in metrics])

    # DSR for multiple testing
    n_trials = len(metrics)
    dsr = compute_dsr(median_sharpe, n_trials)

    return {
        "n_folds": len(metrics),
        "positive_sharpe_rate": positive_sharpe_rate,
        "median_sharpe": median_sharpe,
        "mean_sharpe": np.mean(sharpes),
        "std_sharpe": np.std(sharpes),
        "median_hit_rate": median_hit_rate,
        "dsr": dsr,
        "total_pnl": sum(m["cumulative_pnl"] for m in metrics),
    }
```

See [references/oos-metrics.md](./references/oos-metrics.md) for threshold justifications.

---

## Look-Ahead Bias Prevention

### The Problem

Using the same data for epoch selection AND final evaluation creates look-ahead bias:

```
❌ WRONG: Use fold's own optimal epoch for fold's OOS evaluation
   - Epoch selection "sees" validation returns
   - Then apply same epoch to OOS from same period
   - Result: Overly optimistic performance
```

### The Solution: Nested WFO + Bayesian Lag

```
✅ CORRECT: Bayesian-smoothed epoch from PRIOR folds for current TEST
   - Epoch selection on train/validation (inner loop)
   - Update Bayesian posterior with validation-optimal
   - Apply Bayesian-selected epoch to TEST (outer loop)
   - TEST data completely untouched during selection
```

### Embargo Requirements

| Boundary           | Embargo           | Rationale                 |
| ------------------ | ----------------- | ------------------------- |
| Train → Validation | 6% of fold        | Prevent feature leakage   |
| Validation → Test  | 6% of fold        | Prevent selection leakage |
| Fold → Fold        | 1 hour (calendar) | Range bar duration        |

```python
def compute_embargo_indices(
    n_total: int,
    train_pct: float = 0.60,
    val_pct: float = 0.20,
    test_pct: float = 0.20,
    embargo_pct: float = 0.06,
) -> dict[str, tuple[int, int]]:
    """Compute indices for nested split with embargoes.

    Returns dict with (start, end) tuples for each segment.
    """
    embargo_size = int(n_total * embargo_pct)

    train_end = int(n_total * train_pct)
    val_start = train_end + embargo_size
    val_end = val_start + int(n_total * val_pct)
    test_start = val_end + embargo_size
    test_end = n_total

    return {
        "train": (0, train_end),
        "embargo_1": (train_end, val_start),
        "validation": (val_start, val_end),
        "embargo_2": (val_end, test_start),
        "test": (test_start, test_end),
    }
```

### Validation Checklist

Before running AWFES with OOS application:

- [ ] **Three-way split**: Train/Validation/Test clearly separated
- [ ] **Embargoes**: 6% gap at each boundary
- [ ] **Bayesian lag**: Current fold uses posterior from prior folds
- [ ] **No peeking**: Test data untouched until final evaluation
- [ ] **Temporal order**: No shuffling, strict time sequence
- [ ] **Feature computation**: Features computed BEFORE split, no recalculation

### Anti-Patterns

| Anti-Pattern                                     | Detection                              | Fix                    |
| ------------------------------------------------ | -------------------------------------- | ---------------------- |
| Using current fold's epoch on current fold's OOS | `selected_epoch == fold_optimal_epoch` | Use Bayesian posterior |
| Validation overlaps test                         | Date ranges overlap                    | Add embargo            |
| Features computed on full dataset                | Scaler fit includes test               | Per-split scaling      |
| Fold shuffling                                   | Folds not time-ordered                 | Enforce temporal order |

See [references/look-ahead-bias.md](./references/look-ahead-bias.md) for detailed examples.

---

## References

| Topic                    | Reference File                                                                    |
| ------------------------ | --------------------------------------------------------------------------------- |
| Academic Literature      | [academic-foundations.md](./references/academic-foundations.md)                   |
| Mathematical Formulation | [mathematical-formulation.md](./references/mathematical-formulation.md)           |
| Decision Tree            | [epoch-selection-decision-tree.md](./references/epoch-selection-decision-tree.md) |
| Anti-Patterns            | [anti-patterns.md](./references/anti-patterns.md)                                 |
| OOS Application          | [oos-application.md](./references/oos-application.md)                             |
| Epoch Smoothing          | [epoch-smoothing.md](./references/epoch-smoothing.md)                             |
| OOS Metrics              | [oos-metrics.md](./references/oos-metrics.md)                                     |
| Look-Ahead Bias          | [look-ahead-bias.md](./references/look-ahead-bias.md)                             |

## Full Citations

- Bailey, D. H., & López de Prado, M. (2014). The deflated Sharpe ratio: Correcting for selection bias, backtest overfitting and non-normality. _The Journal of Portfolio Management_, 40(5), 94-107.
- Bischl, B., et al. (2023). Multi-Objective Hyperparameter Optimization in Machine Learning. _ACM Transactions on Evolutionary Learning and Optimization_.
- López de Prado, M. (2018). _Advances in Financial Machine Learning_. Wiley. Chapter 7.
- Nomura, M., & Ono, I. (2021). Warm Starting CMA-ES for Hyperparameter Optimization. _AAAI Conference on Artificial Intelligence_.
- Pardo, R. E. (2008). _The Evaluation and Optimization of Trading Strategies, 2nd Edition_. John Wiley & Sons.
