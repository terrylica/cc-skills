# Metric Design Guide

How to design metrics that work well with evolutionary percentile ranking. A metric that is good for single-config evaluation may be poor for cross-config ranking.

---

## Metric Quality Criteria for Ranking

### Criterion 1 - Discrimination Power

A metric must spread configs across a meaningful range. If 95% of configs cluster at the same value, the metric provides almost no ranking information.

**Test**: Compute the interquartile range (IQR) as a fraction of the full range. If IQR/range < 0.1, the metric has weak discrimination.

**Example**: DSR in the rangebar case study had max=0.500 across 961 configs. Zero configs exceeded 0.50. The metric was inert (zero discrimination power). This wasted one dimension of the optimization search space.

### Criterion 2 - Independence from Other Metrics

Highly correlated metrics (Spearman r > 0.95) provide redundant information. Including both inflates the dimensionality without adding discriminatory value.

**Test**: Compute Spearman rank correlation between all metric pairs. Flag pairs with |r| > 0.95 as redundant. Keep the one with better discrimination power.

**Example**: Sharpe, PSR, GROW, and CF-ES were dropped from the rangebar metric set because they had r > 0.95 with Omega ratio.

### Criterion 3 - Monotonic in Quality

The metric should have a clear direction. "Higher is better" or "lower is better" must be unambiguous. Metrics with non-monotonic quality (e.g., "closer to 1.0 is better") need transformation before ranking.

**Transformation**: For target-value metrics, use `abs(value - target)` and set `higher_is_better=False`.

### Criterion 4 - Defined for All Configs

None/NaN values get percentile 0 (worst). If many configs produce None for a metric, that metric effectively creates a binary gate (defined vs undefined) rather than a continuous ranking.

**Guideline**: If >30% of configs have None, the metric is better suited as a pre-filter (gate) than a ranking dimension.

### Criterion 5 - Robust to Outliers

A single extreme value can distort percentile ranks for neighboring configs. Use `rankdata(method='average')` (ties get the mean rank) and consider winsorizing extreme values before ranking.

---

## MetricSpec Design Patterns

### Pattern - Direct Metric

The simplest case. The JSONL file contains the raw metric value.

```python
MetricSpec("omega", "Omega", True, 100, "omega_rankings.jsonl", "omega_L0")
```

### Pattern - Inverse Metric (Lower is Better)

Set `higher_is_better=False`. The ranking module will negate values before ranking, so the config with the lowest raw value gets percentile 100.

```python
MetricSpec("regularity_cv", "Regularity CV", False, 100,
           "signal_regularity_rankings.jsonl", "kde_peak_cv")
```

### Pattern - Composite Metric

The source field is itself a composite (e.g., TAMRS = Rachev _SL/CDaR_ OU ratio). Include the composite AND its components as separate metrics. This lets the optimizer tighten on the composite or its components independently.

```python
# Composite
MetricSpec("tamrs", "TAMRS", True, 100, "tamrs_rankings.jsonl", "tamrs"),
# Components (also available for independent filtering)
MetricSpec("rachev", "Rachev", True, 100, "tamrs_rankings.jsonl", "rachev_ratio"),
MetricSpec("sl_cdar", "SL/CDaR", True, 100, "tamrs_rankings.jsonl", "sl_cdar_ratio"),
MetricSpec("ou_ratio", "OU Ratio", True, 100, "tamrs_rankings.jsonl", "ou_barrier_ratio"),
```

### Pattern - Count Metric

Integer counts (e.g., trade count) have many ties. `rankdata(method='average')` handles this correctly, but consider whether the count is better as a gate than a ranking dimension.

```python
MetricSpec("n_trades", "Trade Count", True, 100, "moments.jsonl", "n_trades")
```

### Pattern - Multi-Source Metric

When a metric requires data from multiple JSONL files, pre-compute it into a single JSONL file. The ranking module reads exactly one file per metric.

---

## Metric Count Guidelines

| Metric Count | Search Space   | Trials Needed | Recommended       |
| ------------ | -------------- | ------------- | ----------------- |
| 5-8          | 20^5 to 20^8   | 200-1000      | Good              |
| 9-12         | 20^9 to 20^12  | 1000-5000     | Typical           |
| 13-16        | 20^13 to 20^16 | 5000-10000    | Max practical     |
| 17+          | 20^17+         | >50000        | Split into stages |

**Why 12 is near-optimal**: With step=5 (20 values per metric), 12 metrics create a 20^12 search space. TPE converges reliably within 5000-10000 trials at this dimensionality. Beyond 16 metrics, consider hierarchical optimization (optimize subgroups, then combine).

---

## Adding a New Metric

1. **Compute the metric** in its own module, writing results to JSONL with `config_id` and metric value
2. **Add a MetricSpec** entry to the registry
3. **Add an env var** (`RANK_CUT_{NAME}`) to config.py with default=100
4. **Add to resolve_cutoffs()** mapping
5. **Run inertness check**: If the new metric has IQR/range < 0.1, reconsider including it
6. **Run correlation check**: If Spearman r > 0.95 with an existing metric, keep the more discriminating one
7. **Re-run optimization**: New metric changes the search space

---

## Removing a Metric

Removing a metric (setting its cutoff permanently to 100 or removing from the registry) is often more valuable than adding one. Signs a metric should be removed:

1. **Inert**: Max value == min value (or IQR/range < 0.05)
2. **Redundant**: Spearman r > 0.95 with a more discriminating metric
3. **Binary gate**: >30% None values (better as pre-filter)
4. **Non-binding**: In all 5 optimization objectives, the metric's cutoff stays at 100%

Do NOT remove a metric just because it is "hard to improve" - binding metrics are the most valuable ranking dimensions.
