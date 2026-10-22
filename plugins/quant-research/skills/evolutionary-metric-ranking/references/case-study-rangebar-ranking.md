# Case Study - Range Bar Pattern Ranking (Issue `#17`)

Production application of evolutionary metric ranking to 1,008 two-feature trading configurations. Executed in `terrylica/rangebar-patterns` (2026-02-14).

**Repository**: [terrylica/rangebar-patterns](https://github.com/terrylica/rangebar-patterns)
**Issue**: [#17 - Per-Metric Percentile Cutoffs](https://github.com/terrylica/rangebar-patterns/issues/17)

> **About this write-up.** The original run ranked on 12 metrics. Two of them were trial-count-based statistics, which the operator rule of 2026-10-15 (no trial-count corrections) removed, so this study describes only the 10 metrics that remain. Every cutoff set, survivor count and binding sequence below was produced by the original 12-metric run, and none of them can be reproduced exactly from this rewritten study, because two of its metrics were removed. They are kept as the record of that run, each flagged where it depended on a removed metric; no replacement figures have been computed.

---

## Problem

1,008 trading configurations (two-feature filter combinations applied to a 2-consecutive-DOWN-bar pattern on SOLUSDT @500dbps range bars) needed to be ranked across heterogeneous quality metrics. Raw values were on incompatible scales:

| Metric         | Range          | Scale                |
| -------------- | -------------- | -------------------- |
| Kelly fraction | [-0.15, +0.08] | Return per unit risk |
| Trade count    | [50, 3500]     | Integer count        |
| Omega ratio    | [0.85, 1.25]   | Ratio (>1 = profit)  |
| TAMRS          | [0.009, 0.379] | Composite score      |
| Rachev ratio   | [0.0, 2.0]     | Tail asymmetry       |
| E-value        | [1.0, 1.02]    | Sequential test      |
| Regularity CV  | [0.0, 2.5]     | Lower = better       |

No weighted-sum scoring could meaningfully combine these. Traditional screening gates (pass/fail thresholds) were too coarse - a config just below a threshold is essentially identical to one just above.

---

## Implementation

### Metric Registry (10 metrics)

```python
DEFAULT_METRICS = (
    MetricSpec("tamrs",         "TAMRS",            True,  100, "tamrs_rankings.jsonl",             "tamrs"),
    MetricSpec("rachev",        "Rachev",           True,  100, "tamrs_rankings.jsonl",             "rachev_ratio"),
    MetricSpec("ou_ratio",      "OU Ratio",         True,  100, "tamrs_rankings.jsonl",             "ou_barrier_ratio"),
    MetricSpec("sl_cdar",       "SL/CDaR",          True,  100, "tamrs_rankings.jsonl",             "sl_cdar_ratio"),
    MetricSpec("omega",         "Omega",            True,  100, "omega_rankings.jsonl",             "omega_L0"),
    MetricSpec("evalue",        "E-value",          True,  100, "evalues.jsonl",                    "final_evalue"),
    MetricSpec("regularity_cv", "Regularity CV",    False, 100, "signal_regularity_rankings.jsonl", "kde_peak_cv"),
    MetricSpec("coverage",      "Coverage",         True,  100, "signal_regularity_rankings.jsonl", "temporal_coverage"),
    MetricSpec("n_trades",      "Trade Count",      True,  100, "moments.jsonl",                    "n_trades"),
    MetricSpec("kelly",         "Kelly",            True,  100, "moments.jsonl",                    "kelly_fraction"),
)
```

Note: `regularity_cv` has `higher_is_better=False` - lower CV means more regular signal timing, which is desirable.

### Env Var Configuration

```bash
# Default: all cutoffs at 100% (no filter)
uv run python -m rangebar_patterns.eval.ranking

# Custom cutoffs (one RBP_RANK_CUT_<METRIC>=<percentile> per metric to tighten)
RBP_RANK_CUT_TAMRS=<pct> RBP_RANK_CUT_RACHEV=<pct> RBP_RANK_CUT_OMEGA=<pct> \
  uv run python -m rangebar_patterns.eval.ranking
```

### Files Created

| File                                    | Lines | Purpose                                                     |
| --------------------------------------- | ----- | ----------------------------------------------------------- |
| `src/rangebar_patterns/eval/ranking.py` | 453   | MetricSpec, percentile ranks, cutoffs, intersection, report |
| `scripts/rank_optimize.py`              | 241   | Optuna optimizer with 5 objectives                          |
| `tests/test_eval/test_ranking.py`       | ~130  | 14 unit tests for all pure functions                        |

---

## Optimization Results (5 Objectives x 10,000 Trials)

These are the original run's results. Each objective's cutoffs were found by a search over all 12 cutoff dimensions, and the cutoff sets of max_survivors_min_cutoff, quality_at_target_n and tightest_nonempty tightened at least one removed metric (diversity_reward's did not). An optimizer run over the 10 remaining metrics searches a different space, so these figures are a record, not a reproducible result.

### Summary Table

| Objective                | Survivors | Mean Cutoff | Active Filters | Key Insight                                                                      |
| ------------------------ | --------- | ----------- | -------------- | -------------------------------------------------------------------------------- |
| max_survivors_min_cutoff | 835       | 94.6%       | 4/12           | Barely filters - four cutoffs slightly tightened, two of them on removed metrics |
| **quality_at_target_n**  | **11**    | **66.7%**   | **11/12**      | **Best balance: 11 high-quality configs, 72.3% avg percentile**                  |
| tightest_nonempty        | 1         | 31.3%       | 12/12          | Maximum tightening - sole universal champion                                     |
| diversity_reward         | 747       | 97.5%       | 4/12           | Rewards independent metrics - evalue, n_trades, omega, ou_ratio                  |
| pareto_efficiency        | 348       | 85.8%       | 10/12          | 353-point Pareto front from NSGA-II                                              |

### Optimal Cutoffs (quality_at_target_n)

The original run's cutoffs for the 10 remaining metrics:

```
RBP_RANK_CUT_TAMRS=30 RBP_RANK_CUT_RACHEV=90 RBP_RANK_CUT_OU_RATIO=60
RBP_RANK_CUT_SL_CDAR=50 RBP_RANK_CUT_OMEGA=70 RBP_RANK_CUT_EVALUE=95
RBP_RANK_CUT_REGULARITY_CV=65 RBP_RANK_CUT_COVERAGE=85 RBP_RANK_CUT_N_TRADES=100
RBP_RANK_CUT_KELLY=35
```

Together with cutoffs on the two removed metrics, that run produced 11 survivors with average percentile rank 72.35%. Applying only the 10 cutoffs above gives a different survivor set, which has not been computed.

---

## Universal Champion

**`turnover_imbalance_lt_p25__price_impact_lt_p25`** - the ONLY config appearing in all 5 objective survivor sets of the original 12-metric run. Its raw metric values below do not depend on the registry; its champion status does, and it has not been re-checked without the removed metrics.

| Metric      | Value                     |
| ----------- | ------------------------- |
| Kelly       | +0.051                    |
| Omega       | 1.236                     |
| TAMRS       | 0.078                     |
| Rachev      | 2.000 (saturated)         |
| OU ratio    | 0.392                     |
| N trades    | 131                       |
| KDE peak CV | 0.000 (perfectly regular) |
| E-value     | 1.006                     |

**Interpretation**: This config selects moments where both turnover imbalance and price impact are in the bottom quartile of signal-specific rolling distributions. Low turnover imbalance + low price impact = informed flow absorbing liquidity before a move.

---

## Key Forensic Findings

### Finding 1 - Binding Constraint Hierarchy

Uniform cutoff tightening reveals the binding sequence. In the original run, Rachev ratio was the tightest killer at the first step (90%) and trade count at the 70% step. The other two steps were led by the removed metrics, and every survivor count in the sequence was an intersection over all 12 metrics, so the sequence is not reproduced here.

**Binding constraints (original 12-metric run)**: Rachev ratio (tail asymmetry) led the first step and trade count the 70% step. Which metric binds first in a 10-metric registry has not been computed.

### Finding 2 - Feature Themes in Quality Survivors

The 11 quality survivors of the original run (quality_at_target_n objective) show dominant features:

| Feature                    | Count (out of 11) | Interpretation          |
| -------------------------- | ----------------- | ----------------------- |
| OFI (order flow imbalance) | 5                 | Directional pressure    |
| turnover_imbalance         | 4                 | Liquidity asymmetry     |
| price_impact               | 4                 | Market impact costs     |
| vwap_close_deviation       | 4                 | Institutional execution |

**Theme**: Order flow imbalance + price impact asymmetry. These configs detect moments where order flow is extreme AND price impact is low - consistent with informed flow absorbing liquidity before a move.

### Finding 3 - Performance Characteristics

- **Single-core optimal**: Each evaluation takes ~6.3ms (pure NumPy/set operations). Data fits in L2 cache. TPE sampler is inherently sequential.
- **10K trials per objective**: ~60 seconds each, 5 objectives = 5 minutes total.
- **Apple Silicon**: M-series chips handle this workload trivially. No GPU or parallelism needed.
- **Memory**: <100MB total (the original run's 12 metric files, ~1000 configs each).

---

## Lessons Learned

### L1 - Pre-compute All Metrics Before Ranking

The ranking system reads pre-computed JSONL files. Each metric module (TAMRS, Rachev, Omega, etc.) runs independently and writes its own JSONL. The ranking module never computes metrics - it only reads and ranks.

**Why**: Decoupling computation from ranking means the optimizer can run 10K+ trials at ~6ms each without touching the database.

### L2 - Optuna TPE is Sufficient for This Scale

With the original run's 12 integer dimensions (step=5, 20 values each), TPE finds good solutions in 200-500 trials and plateaus by 2,000. Running 10,000 trials is overkill but confirms convergence. Grid search over 20^12 = 4 x 10^15 would be infeasible; random search would need ~50K trials.

### L3 - Cross-Objective Consistency is the Strongest Filter

The universal champion (`turnover_imbalance_lt_p25__price_impact_lt_p25`) would not have been identified by any single objective alone. It ranks 1st under tightest_nonempty but only ~8th under quality_at_target_n. Cross-objective intersection reveals robustness that single-objective optimization misses.

### L4 - Inert Dimensions Waste Budget

A metric that cannot discriminate between configs still consumes a cutoff dimension. In the original run one of the 12 dimensions was inert; it was one of the two metrics since removed. Run a quick inertness check (SKILL.md P7) before any optimization.

### L5 - The Ranking System Coexists with Screening

The per-metric percentile ranking system was built **parallel to** the existing multi-tier screening system (screening.py). Neither replaces the other:

- **Screening** (pass/fail gates): "Does this config meet minimum standards?"
- **Ranking** (percentile cutoffs): "Among all configs, which are consistently excellent?"

Both provide valid but different perspectives on the same data.

---

## Reproduction

The repository has since renamed its package to `opendeviationbar_patterns` and its env prefix to `OPENDEVIATIONBAR_`, and dropped the Kelly cutoff; check its current task definitions before re-running.

```bash
# In terrylica/rangebar-patterns (names as of the 2026-02-14 study):

# 1. Run the full eval pipeline first (requires ClickHouse): the repo's
#    eval:full task chain — extract, OU, compute, synthesize, screen, rank.

# 2. Run ranking with default cutoffs
uv run python -m rangebar_patterns.eval.ranking

# 3. Run evolutionary optimizer (all 5 objectives)
for OBJ in max_survivors_min_cutoff quality_at_target_n tightest_nonempty diversity_reward pareto_efficiency; do
    RBP_RANK_OBJECTIVE=$OBJ RBP_RANK_N_TRIALS=10000 uv run python scripts/rank_optimize.py
done

# 4. Apply the optimizer's best cutoffs (RBP_RANK_CUT_<METRIC>=<pct>) and inspect.
#    A re-run over the 10-metric registry finds its own cutoffs; it will not
#    reproduce the 2026-02-14 figures above.
```

---

## Output Artifacts

| File                                   | Format               | Content                                 |
| -------------------------------------- | -------------------- | --------------------------------------- |
| `results/eval/rankings.jsonl`          | 1 line per config    | Percentile ranks across all metrics     |
| `results/eval/ranking_report.md`       | Markdown             | Human-readable report with top configs  |
| `results/eval/rank_optimization.jsonl` | 1 line per objective | Best cutoffs, survivor counts, env vars |
