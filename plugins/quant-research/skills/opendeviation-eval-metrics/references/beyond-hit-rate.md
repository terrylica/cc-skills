# Beyond Hit Rate: Outcome Predictability Framework

Hit rate is among the worst evaluation metrics. A strategy with 80% historical win rate but all wins concentrated in 2022 and losses in 2025 is worthless. The right question is not "how often does it win?" but **"can we predict WHEN it wins?"**

Empirically validated on 866K ODB bars (BTCUSDT 250dbps, 2018-2026): **hit-rate ranking was inversely correlated with signal robustness**. The highest hit-rate signal (64% mean-reversion) was dead by 2025. The lowest (38% raw displacement) was the most robust and strengthening.

## The Three Failure Modes of Hit Rate

| Failure Mode            | Example                                                 | What Hit Rate Misses            |
| ----------------------- | ------------------------------------------------------- | ------------------------------- |
| **Temporal clustering** | 80% hit rate but all wins in Q1 2023                    | Wins concentrated in one regime |
| **Regime decay**        | 65% overall but 40% in last 6 months                    | Edge has evaporated             |
| **Random wins**         | 60% but W/L sequence indistinguishable from biased coin | No exploitable structure        |

## Metric Stack (Replaces Hit Rate)

### Tier 1: CRITICAL — sequence structure tests

| Metric                             | Formula                                      | Detects                          | Library                   |
| ---------------------------------- | -------------------------------------------- | -------------------------------- | ------------------------- |
| **Shannon Entropy of W/L bigrams** | `H = -Σ p_i·log₂(p_i)` on (WW, WL, LW, LL)   | Random wins (biased coin)        | `scipy.stats.entropy`     |
| **Lempel-Ziv Complexity**          | `LZC = c(n) / (n/log₂n)`, normalized         | Sequential pattern in W/L        | `antropy.lziv_complexity` |
| **Runs Test (Wald-Wolfowitz)**     | `Z = (R - E[R]) / σ_R`                       | Non-random streak structure      | Manual (`scipy`)          |
| **CV of inter-win intervals**      | `σ(gaps) / μ(gaps)` between consecutive wins | Bursty/clustered vs regular wins | `numpy`                   |

**CRITICAL**: Always compare entropy/LZC against a **shuffle test** (permute the W/L sequence 1000 times, compute z-score). Without base-rate correction, low-frequency events (11% hit rate) falsely appear structured because they mechanically produce low entropy.

### Tier 2: HIGH — temporal decay detection

| Metric                               | Formula                                            | Detects                                        | Library                          |
| ------------------------------------ | -------------------------------------------------- | ---------------------------------------------- | -------------------------------- | ------------------------ | ------------- |
| **CUSUM on equity curve**            | `S_t = max(0, S_{t-1} + (x_t - μ₀ - k))`           | Exact changepoint where strategy stops working | `ruptures` (PELT)                |
| **HHI across time buckets**          | `Σ(w_i/W_total)²` per quarter/year                 | Temporal concentration of edge                 | `numpy`                          |
| **KL Divergence period-over-period** | `D_KL(P‖Q)` between quarterly return distributions | Distributional shift / regime change           | `scipy.stats.entropy`            |
| **Alpha half-life**                  | `t_half = ln(2)/                                   | φ                                              | ` from AR(1) on rolling hit rate | How fast the edge erodes | `statsmodels` |

### Tier 3: META-LABELING — outcome prediction

| Metric                              | What It Does                                        | Library    |
| ----------------------------------- | --------------------------------------------------- | ---------- |
| **HMM regime-conditional hit rate** | `Var([HR_r0, ..., HR_rN])` across detected regimes  | `hmmlearn` |
| **Meta-labeling** (Lopez de Prado)  | Secondary classifier: P(primary_correct \| context) | `sklearn`  |
| **SHAP on meta-model**              | Which features predict WHEN the strategy wins       | `shap`     |
| **Brier score decomposition**       | REL (calibration) + RES (resolution) + UNC          | `sklearn`  |

## Composite: Outcome Predictability Index (OPI)

```
OPI = 0.25 * (1 - LZC_norm)           # Sequence compressibility
    + 0.25 * |z_runs|                   # Departure from randomness
    + 0.25 * Var(HR_per_regime)         # Regime-conditional spread
    + 0.25 * AUC_meta                   # Meta-model discriminative power
```

OPI = 0 means outcomes are completely random. Higher = more predictable timing = more valuable even at lower hit rate.

## Anti-Pattern: Hit Rate as Primary Metric

**NEVER use hit rate alone.** Always pair with at least:

1. One **sequence structure** metric (entropy, LZC, or runs test)
2. One **temporal decay** metric (CUSUM, HHI, or half-life)
3. One **regime awareness** metric (per-session HR, HMM, or KL divergence)

## Empirical Validation (ODB 866K bars)

| Signal               | Hit Rate | LZC Z (shuffle)          | CUSUM                 | Half-Life  | BHR Verdict |
| -------------------- | -------- | ------------------------ | --------------------- | ---------- | ----------- |
| Raw displacement     | 46.1%    | **-19.3\***              | ALIVE (strengthening) | 564 trades | **BEST**    |
| Slow bar + displaced | 47.8%    | -2.9\*\*                 | ALIVE                 | 410 trades | ALIVE       |
| Streak ≥ 10          | 56.2%    | —                        | DECAYING              | 101 trades | FRAGILE     |
| Mean-rev (p95)       | 63.9%    | -4.72\* (decay artifact) | DEAD                  | —          | **DEAD**    |

The highest hit-rate signal is dead. The lowest is strongest. This is the canonical example of why hit rate fails.

## Key References

| Paper                                                 | Year | Contribution                           |
| ----------------------------------------------------- | ---- | -------------------------------------- |
| Shannon, "Mathematical Theory of Communication"       | 1948 | Entropy framework                      |
| Page, "Continuous Inspection Schemes" (CUSUM)         | 1954 | Change detection                       |
| Wald & Wolfowitz, "Runs Test"                         | 1940 | Sequence randomness                    |
| Lempel & Ziv, "Complexity of Finite Sequences"        | 1976 | Compressibility                        |
| Lopez de Prado, AFML Ch.3+10 (Meta-labeling)          | 2018 | Outcome prediction                     |
| Lopez de Prado, "Sharpe Ratio Inference" SSRN 5520741 | 2025 | SR under non-normal correlated returns |
| arXiv:2511.16339, "Financial Information Theory"      | 2025 | NMI for signal quality                 |
