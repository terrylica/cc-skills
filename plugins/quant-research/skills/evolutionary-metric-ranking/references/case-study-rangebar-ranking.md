# Case Study - Range Bar Pattern Ranking (Issue `#17`)

Production application of evolutionary metric ranking to 1,008 two-feature trading configurations evaluated across 12 quality metrics. Executed in `terrylica/rangebar-patterns` (2026-02-14).

**Repository**: [terrylica/rangebar-patterns](https://github.com/terrylica/rangebar-patterns)
**Issue**: [#17 - Per-Metric Percentile Cutoffs](https://github.com/terrylica/rangebar-patterns/issues/17)

---

## Problem

1,008 trading configurations (two-feature filter combinations applied to a 2-consecutive-DOWN-bar pattern on SOLUSDT @500dbps range bars) needed to be ranked across 12 heterogeneous quality metrics. Raw values were on incompatible scales:

| Metric         | Range          | Scale                |
| -------------- | -------------- | -------------------- |
| Kelly fraction | [-0.15, +0.08] | Return per unit risk |
| Trade count    | [50, 3500]     | Integer count        |
| Omega ratio    | [0.85, 1.25]   | Ratio (>1 = profit)  |
| TAMRS          | [0.009, 0.379] | Composite score      |
| Rachev ratio   | [0.0, 2.0]     | Tail asymmetry       |
| DSR            | [0.0, 0.5]     | Deflated Sharpe      |
| E-value        | [1.0, 1.02]    | Sequential test      |
| Regularity CV  | [0.0, 2.5]     | Lower = better       |

No weighted-sum scoring could meaningfully combine these. Traditional screening gates (pass/fail thresholds) were too coarse - a config just below a threshold is essentially identical to one just above.

---

## Implementation

### Metric Registry (12 metrics)

```python
DEFAULT_METRICS = (
    MetricSpec("tamrs",         "TAMRS",            True,  100, "tamrs_rankings.jsonl",             "tamrs"),
    MetricSpec("rachev",        "Rachev",           True,  100, "tamrs_rankings.jsonl",             "rachev_ratio"),
    MetricSpec("ou_ratio",      "OU Ratio",         True,  100, "tamrs_rankings.jsonl",             "ou_barrier_ratio"),
    MetricSpec("sl_cdar",       "SL/CDaR",          True,  100, "tamrs_rankings.jsonl",             "sl_cdar_ratio"),
    MetricSpec("omega",         "Omega",            True,  100, "omega_rankings.jsonl",             "omega_L0"),
    MetricSpec("dsr",           "DSR",              True,  100, "dsr_rankings.jsonl",               "dsr"),
    MetricSpec("headroom",      "MinBTL Headroom",  True,  100, "minbtl_gate.jsonl",                "headroom_ratio"),
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
mise run eval:rank

# Custom cutoffs from optimizer output
RBP_RANK_CUT_TAMRS=30 RBP_RANK_CUT_RACHEV=90 RBP_RANK_CUT_OMEGA=70 \
  RBP_RANK_CUT_HEADROOM=25 RBP_RANK_CUT_KELLY=35 mise run eval:rank
```

### Files Created

| File                                    | Lines | Purpose                                                     |
| --------------------------------------- | ----- | ----------------------------------------------------------- |
| `src/rangebar_patterns/eval/ranking.py` | 453   | MetricSpec, percentile ranks, cutoffs, intersection, report |
| `scripts/rank_optimize.py`              | 241   | Optuna optimizer with 5 objectives                          |
| `tests/test_eval/test_ranking.py`       | ~130  | 14 unit tests for all pure functions                        |

---

## Optimization Results (5 Objectives x 10,000 Trials)

### Summary Table

| Objective                | Survivors | Mean Cutoff | Active Filters | Key Insight                                                        |
| ------------------------ | --------- | ----------- | -------------- | ------------------------------------------------------------------ |
| max_survivors_min_cutoff | 835       | 94.6%       | 4/12           | Barely filters - DSR, headroom, kelly, ou_ratio slightly tightened |
| **quality_at_target_n**  | **11**    | **66.7%**   | **11/12**      | **Best balance: 11 high-quality configs, 72.3% avg percentile**    |
| tightest_nonempty        | 1         | 31.3%       | 12/12          | Maximum tightening - sole universal champion                       |
| diversity_reward         | 747       | 97.5%       | 4/12           | Rewards independent metrics - evalue, n_trades, omega, ou_ratio    |
| pareto_efficiency        | 348       | 85.8%       | 10/12          | 353-point Pareto front from NSGA-II                                |

### Optimal Cutoffs (quality_at_target_n)

```
RBP_RANK_CUT_TAMRS=30 RBP_RANK_CUT_RACHEV=90 RBP_RANK_CUT_OU_RATIO=60
RBP_RANK_CUT_SL_CDAR=50 RBP_RANK_CUT_OMEGA=70 RBP_RANK_CUT_DSR=95
RBP_RANK_CUT_HEADROOM=25 RBP_RANK_CUT_EVALUE=95 RBP_RANK_CUT_REGULARITY_CV=65
RBP_RANK_CUT_COVERAGE=85 RBP_RANK_CUT_N_TRADES=100 RBP_RANK_CUT_KELLY=35
```

This produces 11 survivors with average percentile rank 72.35% across all metrics.

---

## Universal Champion

**`turnover_imbalance_lt_p25__price_impact_lt_p25`** - the ONLY config appearing in all 5 objective survivor sets.

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

### Finding 1 - DSR is an Inert Dimension

DSR max across ALL 961 configs: **0.500**. Zero configs above 0.50. Zero configs above 0.95.

DSR is a flat-zero field that cannot discriminate between configs. The effective ranking space is **11-dimensional**, not 12. DSR should be removed or permanently set to cutoff=100.

**Root cause**: None of the 1,008 configs produce statistically significant results under Deflated Sharpe Ratio with the null inflation from 1,008 trials. This is a feature (correct multiple testing), not a bug.

### Finding 2 - Binding Constraint Hierarchy

Uniform cutoff tightening reveals the binding sequence:

```
@90%: 410 survivors | tightest killer: rachev (-57)
@80%: 132 survivors | tightest killer: headroom (-27)
@70%:  29 survivors | tightest killer: n_trades (-12)
@60%:   6 survivors | tightest killer: dsr (-6) [artifact - kills 6 because of zero-mass tail]
@50%:   0 survivors
```

**Binding constraints**: Rachev ratio and MinBTL headroom are the primary quality gates. Configs with strong Rachev (tail asymmetry) and sufficient data (headroom above MinBTL) are the rarest combinations.

### Finding 3 - Feature Themes in Quality Survivors

The 11 quality survivors (quality_at_target_n objective) show dominant features:

| Feature                    | Count (out of 11) | Interpretation          |
| -------------------------- | ----------------- | ----------------------- |
| OFI (order flow imbalance) | 5                 | Directional pressure    |
| turnover_imbalance         | 4                 | Liquidity asymmetry     |
| price_impact               | 4                 | Market impact costs     |
| vwap_close_deviation       | 4                 | Institutional execution |

**Theme**: Order flow imbalance + price impact asymmetry. These configs detect moments where order flow is extreme AND price impact is low - consistent with informed flow absorbing liquidity before a move.

### Finding 4 - Performance Characteristics

- **Single-core optimal**: Each evaluation takes ~6.3ms (pure NumPy/set operations). Data fits in L2 cache. TPE sampler is inherently sequential.
- **10K trials per objective**: ~60 seconds each, 5 objectives = 5 minutes total.
- **Apple Silicon**: M-series chips handle this workload trivially. No GPU or parallelism needed.
- **Memory**: <100MB total (12 metric files, ~1000 configs each).

---

## Lessons Learned

### L1 - Pre-compute All Metrics Before Ranking

The ranking system reads pre-computed JSONL files. Each metric module (TAMRS, Rachev, Omega, etc.) runs independently and writes its own JSONL. The ranking module never computes metrics - it only reads and ranks.

**Why**: Decoupling computation from ranking means the optimizer can run 10K+ trials at ~6ms each without touching the database.

### L2 - Optuna TPE is Sufficient for This Scale

With 12 integer dimensions (step=5, 20 values each), TPE finds good solutions in 200-500 trials and plateaus by 2,000. Running 10,000 trials is overkill but confirms convergence. Grid search over 20^12 = 4 x 10^15 would be infeasible; random search would need ~50K trials.

### L3 - Cross-Objective Consistency is the Strongest Filter

The universal champion (`turnover_imbalance_lt_p25__price_impact_lt_p25`) would not have been identified by any single objective alone. It ranks 1st under tightest_nonempty but only ~8th under quality_at_target_n. Cross-objective intersection reveals robustness that single-objective optimization misses.

### L4 - Inert Dimensions Waste Budget

DSR contributed zero discrimination but consumed one of 12 cutoff dimensions. Detecting and removing it before optimization would have made the search more efficient. In general, run a quick inertness check before any optimization.

### L5 - The Ranking System Coexists with Screening

The per-metric percentile ranking system was built **parallel to** the existing multi-tier screening system (screening.py). Neither replaces the other:

- **Screening** (pass/fail gates): "Does this config meet minimum standards?"
- **Ranking** (percentile cutoffs): "Among all configs, which are consistently excellent?"

Both provide valid but different perspectives on the same data.

---

## Reproduction

```bash
# In terrylica/rangebar-patterns:

# 1. Run the full eval pipeline (requires ClickHouse)
mise run eval:full

# 2. Run ranking with default cutoffs
mise run eval:rank

# 3. Run evolutionary optimizer (all 5 objectives)
for OBJ in max_survivors_min_cutoff quality_at_target_n tightest_nonempty diversity_reward pareto_efficiency; do
    RBP_RANK_OBJECTIVE=$OBJ RBP_RANK_N_TRIALS=10000 mise run eval:rank-optimize
done

# 4. Apply best cutoffs and inspect
RBP_RANK_CUT_TAMRS=30 RBP_RANK_CUT_RACHEV=90 RBP_RANK_CUT_OMEGA=70 \
  RBP_RANK_CUT_HEADROOM=25 RBP_RANK_CUT_KELLY=35 mise run eval:rank
```

---

## Output Artifacts

| File                                   | Format               | Content                                 |
| -------------------------------------- | -------------------- | --------------------------------------- |
| `results/eval/rankings.jsonl`          | 1 line per config    | Percentile ranks across all 12 metrics  |
| `results/eval/ranking_report.md`       | Markdown             | Human-readable report with top configs  |
| `results/eval/rank_optimization.jsonl` | 1 line per objective | Best cutoffs, survivor counts, env vars |
