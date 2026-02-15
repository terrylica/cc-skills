# Objective Function Reference

Detailed guide for designing and selecting objective functions for evolutionary cutoff optimization. Each objective encodes a different definition of "quality" and reveals different aspects of the configuration landscape.

---

## Design Principles

### Principle 1 - Handle Empty Intersection

Every objective must return 0 (or equivalent worst value) when `n_intersection == 0`. This prevents the optimizer from exploring the empty-intersection region of the search space.

```python
if result["n_intersection"] == 0:
    return 0.0  # Worst possible value
```

### Principle 2 - Monotonic in Quality

The objective should increase monotonically with the quality being measured. Optuna maximizes by default; for minimization objectives, return the complement.

```python
# Minimize total budget -> maximize (max_budget - budget)
return max_budget - total_budget
```

### Principle 3 - Meaningful Gradients

The objective should change smoothly with cutoff changes. Discontinuous objectives (like "1 if survivors >= 10, else 0") provide no gradient for the optimizer to follow.

```python
# GOOD: Partial credit for n < target
if n < target_n:
    return avg_pct * (n / target_n)  # Smooth degradation

# BAD: Cliff function
if n < target_n:
    return 0.0  # No gradient
```

---

## Objective Catalog

### 1. max_survivors_min_cutoff (Efficiency Frontier)

**Question**: How many configs survive per unit of filtering looseness?

```python
def obj_max_survivors_min_cutoff(result, cutoffs):
    n = result["n_intersection"]
    if n == 0:
        return 0.0
    mean_cutoff = sum(cutoffs.values()) / len(cutoffs)
    if mean_cutoff < 1:
        return 0.0
    return n / mean_cutoff
```

**Behavior**: Favors loose cutoffs that keep many survivors. The optimizer finds cutoffs just tight enough to provide meaningful filtering while maximizing the survivor count.

**Typical result**: Large survivor sets (hundreds) with most cutoffs near 100%. Only the most discriminating metrics get slightly tightened.

**Use when**: Exploring the efficiency frontier, understanding which metrics provide the most bang-for-buck filtering.

### 2. quality_at_target_n (Constrained Portfolio)

**Question**: Given a target portfolio size N, what cutoffs maximize the average quality of survivors?

```python
def obj_quality_at_target_n(result, cutoffs, target_n=10):
    n = result["n_intersection"]
    avg_pct = result["avg_percentile"]
    if n < target_n:
        return avg_pct * (n / target_n)  # Partial credit
    return avg_pct
```

**Behavior**: Tightens cutoffs aggressively to select the highest-quality subset of exactly N configs. The partial credit term prevents the optimizer from converging on n=0 (which has undefined quality).

**Typical result**: Moderate survivor count (close to target_n) with high average percentile. Most metrics have meaningful cutoffs.

**Tuning**: Set `target_n` based on your deployment capacity. For a 10-strategy portfolio, use target_n=10. For initial screening, use target_n=50.

**Use when**: You know how many configs you want to deploy and want the best possible set.

### 3. tightest_nonempty (Universal Champion)

**Question**: What is the absolute tightest set of cutoffs that still yields at least one survivor?

```python
def obj_tightest_nonempty(result, cutoffs):
    n = result["n_intersection"]
    if n == 0:
        return 0.0
    total_budget = sum(cutoffs.values())
    max_budget = len(cutoffs) * 100
    return max_budget - total_budget
```

**Behavior**: Drives all cutoffs as low as possible while maintaining at least one survivor. This finds the single config (or small set) that is excellent across the most dimensions simultaneously.

**Typical result**: 1-3 survivors with very tight cutoffs (mean ~30%). The survivor is the closest thing to a "universal champion."

**Interpretation warning**: The sole survivor may not be the best on any single metric - it is the most consistently good across all metrics. Check its raw values to ensure they meet minimum requirements.

**Use when**: Finding the single most defensible config selection.

### 4. pareto_efficiency (Multi-Objective Trade-Off)

**Question**: What is the full trade-off landscape between survivor count and cutoff tightness?

```python
study = optuna.create_study(
    directions=["maximize", "minimize"],
    sampler=optuna.samplers.NSGAIISampler(seed=42),
)

def pareto_objective(trial):
    cutoffs = suggest_cutoffs(trial)
    result = run_ranking_with_cutoffs(cutoffs, metric_data=metric_data)
    return result["n_intersection"], sum(cutoffs.values()) / len(cutoffs)
```

**Behavior**: Returns the full Pareto frontier - the set of solutions where you cannot improve one objective without worsening the other. Each point on the frontier represents a different quality/quantity trade-off.

**Typical result**: 100-500 Pareto-optimal solutions spanning from "many survivors, loose cutoffs" to "few survivors, tight cutoffs."

**Reading the frontier**: Plot survivors (y-axis) vs mean cutoff (x-axis). Look for "knees" where the curve bends sharply - these are natural transition points.

**Use when**: You want to understand the full landscape before committing to a specific operating point.

### 5. diversity_reward (Redundancy Detector)

**Question**: Are all tightened cutoffs providing independent information, or are some redundant?

```python
def obj_diversity_reward(result, cutoffs):
    n = result["n_intersection"]
    if n == 0:
        return 0.0
    n_binding = result["n_binding_metrics"]
    n_active = sum(1 for v in cutoffs.values() if v < 100)
    if n_active == 0:
        return 0.0
    efficiency = n_binding / n_active
    return n * efficiency
```

**Behavior**: Penalizes cutoff combinations where some tightened metrics are redundant (not binding). A metric is "not binding" if relaxing it to 100% does not change the intersection.

**Typical result**: Fewer active filters than other objectives, but each active filter genuinely matters. Reveals which metrics are correlated (tightening one makes the other redundant).

**Use when**: Designing a metric dashboard, deciding which metrics to invest effort in improving, or identifying metric redundancy.

---

## Objective Selection Guide

| Goal                 | Recommended Objective      | Why                           |
| -------------------- | -------------------------- | ----------------------------- |
| Initial exploration  | max_survivors_min_cutoff   | See the landscape             |
| Deployment selection | quality_at_target_n        | Matches real-world constraint |
| Academic publication | tightest_nonempty + pareto | Defensible methodology        |
| Metric design        | diversity_reward           | Reveals redundancy            |
| Full analysis        | ALL FIVE + cross-objective | Most robust conclusions       |

---

## Custom Objective Design

When the 5 built-in objectives don't fit, design a custom one following these patterns:

### Pattern - Weighted Quality

```python
def obj_weighted_quality(result, cutoffs, weights=None):
    """Weight some metrics more than others in quality assessment."""
    n = result["n_intersection"]
    if n == 0:
        return 0.0

    weighted_sum = 0.0
    for metric_name, pct_ranks in result["all_pct_ranks"].items():
        w = weights.get(metric_name, 1.0) if weights else 1.0
        for cid in result["survivors"]:
            weighted_sum += w * pct_ranks.get(cid, 0.0)

    return weighted_sum / (n * sum(weights.values()))
```

### Pattern - Stability Reward

```python
def obj_stability_reward(result, cutoffs, reference_cutoffs=None):
    """Prefer cutoffs close to a reference point (prior knowledge)."""
    n = result["n_intersection"]
    if n == 0:
        return 0.0

    distance = sum(
        abs(cutoffs[k] - reference_cutoffs.get(k, 50))
        for k in cutoffs
    )
    return n / (1 + 0.01 * distance)
```

### Pattern - Minimum Per-Metric Quality

```python
def obj_min_percentile(result, cutoffs):
    """Maximize the WORST percentile across survivors (maximin)."""
    n = result["n_intersection"]
    if n == 0:
        return 0.0

    min_pct = float("inf")
    for cid in result["survivors"]:
        for pct_ranks in result["all_pct_ranks"].values():
            min_pct = min(min_pct, pct_ranks.get(cid, 0.0))

    return min_pct  # Higher = better worst-case
```
