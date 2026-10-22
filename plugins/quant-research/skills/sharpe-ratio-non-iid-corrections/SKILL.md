---
name: sharpe-ratio-non-iid-corrections
description: >-
  Sharpe ratio inference for ONE strategy under non-Normal, serially correlated returns.
  Implements the ρ-corrected (AR(1), skew, kurtosis) Sharpe variance of López de Prado,
  Lipton & Zoonekynd (2026, Eq 2-3) and the single-test tools built on it: PSR, MinTRL,
  critical Sharpe ratio and test power. Numba JIT. Use when computing Sharpe significance,
  a Sharpe confidence band, minimum track record length or power with autocorrelation and
  fat tails. TRIGGERS - PSR, probabilistic sharpe ratio, MinTRL, minimum track record length,
  sharpe variance, non-iid sharpe, autocorrelated sharpe, sharpe significance, sharpe power.
allowed-tools: Read, Grep, Glob, Bash
---

# Sharpe Ratio Non-IID Corrections

Sharpe ratio inference for a single strategy whose returns are non-Normal and serially correlated. Reference implementation of the generalized sampling variance in López de Prado, Lipton & Zoonekynd (2026), and of the single-test statistics that use it.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Out of scope — do not re-add (operator rule, 2026-10-15)

Never compute, report, rank by or cite the Deflated Sharpe Ratio or any other trial-count correction: FWER and FDR procedures (Holm, Bonferroni/Šidák, Benjamini-Yekutieli, the paper's pFDR/oFDR/SFDR), e-LOND and other online multiple testing, expected-maximum-Sharpe deflation, effective-number-of-trials estimates, and the minimum backtest length (MinBTL), which is a function of the number of trials. MinTRL is a different quantity (one rule's own track record) and stays. They were removed from this skill on purpose. Instead:

- **Judge parsimony on the model itself** (how many free parameters, how much was tuned), not by deflating a Sharpe for the number of trials.
- **Guard selection with registration before runs and with unused data**: fix the hypothesis, rule and evaluation window before running, and confirm on data no run has touched.
- **Report each rule's own statistics**: its Sharpe, ρ-corrected σ[SR̂], PSR, MinTRL and power.

PSR, MinTRL, the ρ-corrected variance and power are single-test statistics and stay. PBO/CSCV describes a selection procedure and is not covered by the rule.

## Quick Start

```bash
# Run the 9 validation tests (paper Exhibit 1 numerical examples)
uv run --no-project --with numpy --with numba \
  python plugins/quant-research/skills/sharpe-ratio-non-iid-corrections/references/sharpe_numba.py
```

## Paper Metadata

| Field           | Value                                                                         |
| --------------- | ----------------------------------------------------------------------------- |
| **Title**       | How to Use the Sharpe Ratio                                                   |
| **Authors**     | Marcos López de Prado, Alexander Lipton, Vincent Zoonekynd                    |
| **Series**      | ADIA Lab Research Paper Series, No. 19                                        |
| **Date**        | March 7, 2026                                                                 |
| **SSRN**        | 5520741                                                                       |
| **Replication** | <https://github.com/zoonek/2025-sharpe-ratio>                                 |
| **Source PDF**  | [lopez-de-prado-sharpe-2026.pdf](./references/lopez-de-prado-sharpe-2026.pdf) |

The PDF is kept because the variance derivation (Section 2, Appendix A.1–A.2) and the PSR/MinTRL/power equations this skill implements are cited by equation number from it. Only those sections are used; the transcription omits the rest.

## References

| Topic                                     | Reference File                                                                          |
| ----------------------------------------- | --------------------------------------------------------------------------------------- |
| Paper transcription (implemented excerpt) | [how-to-use-the-sharpe-ratio-2026.md](./references/how-to-use-the-sharpe-ratio-2026.md) |
| Equation → Implementation Tracker         | [sharpe-paper-tracker.md](./references/sharpe-paper-tracker.md)                         |
| Numba JIT Implementation                  | [sharpe_numba.py](./references/sharpe_numba.py)                                         |
| Source PDF                                | [lopez-de-prado-sharpe-2026.pdf](./references/lopez-de-prado-sharpe-2026.pdf)           |
| Paper Figures                             | [media/](./references/media/) (Exhibit 2, variance vs autocorrelation, pp. 12-13)       |

## Preflight: what to compute

Inputs are all objective, computed from the return series under evaluation:

| Parameter  | Meaning                                       | Source               |
| ---------- | --------------------------------------------- | -------------------- |
| **SR̂**     | Observed (non-annualized) Sharpe ratio        | Return series        |
| **T**      | Number of return observations                 | Return series        |
| **γ₃, γ₄** | Skewness, Pearson kurtosis (γ₄=3 is Gaussian) | Return series        |
| **ρ**      | Lag-1 autocorrelation                         | Return series        |
| **SR₀**    | Benchmark Sharpe under the null (often 0)     | Fixed before the run |
| **SR₁, α** | Alternative Sharpe and test size, for power   | Fixed before the run |

Fix SR₀, SR₁ and α in the registration, before looking at results. Report SR̂, σ[SR̂], PSR, MinTRL against T, and power together.

## Key Formulas

All equations use the paper's non-IID variance (Eq 2-3) with Pearson kurtosis convention (γ₄=3 for Gaussian).

| Eq    | Name        | Formula                                                            | Function                |
| ----- | ----------- | ------------------------------------------------------------------ | ----------------------- |
| 2-3   | SR Variance | V[SR̂] = (1/T)·(a − b·γ₃·SR + c·(γ₄−1)/4·SR²)                       | `sr_variance()`         |
| 9     | PSR         | Φ((SR̂ − SR₀) / σ[SR₀])                                             | `psr()`                 |
| 11    | MinTRL      | (a − b·γ₃·SR₀ + c·(γ₄−1)/4·SR₀²) · (z\_{1−α}/(SR̂−SR₀))²            | `min_trl()`             |
| 8, 14 | Critical SR | SR₀ + σ[SR₀]·z\_{1−α}                                              | `critical_sr()`         |
| 13-15 | Power       | 1 − Φ((SR_c − SR₁) / σ[SR₁])                                       | `power()`               |
| 17    | β (Type II) | Φ((z\_{1−α}·√(a(ρ)) − SR₁·√T) / √(a − b·γ₃·SR₁ + c·(γ₄−1)/4·SR₁²)) | `power()` → `1 - power` |

Where a = (1+ρ)/(1−ρ), b = (1+ρ+ρ²)/(1−ρ²), c = (1+ρ²)/(1−ρ²) are AR(1) variance coefficients (`ar1_variance_coeffs()`).

## Numerical Example (Paper Exhibit 1)

Hedge fund: T=24 months, γ₃=−2.448, γ₄=10.164 (Pearson), SR=0.036/0.079≈0.456, ρ=0.2.

| Quantity             | Equation | Value             | Notes                                  |
| -------------------- | -------- | ----------------- | -------------------------------------- |
| σ[SR̂] (non-Gaussian) | Eq 3     | **0.379**         | vs 0.214 Gaussian — 77% wider          |
| PSR (SR₀=0)          | Eq 9     | **0.966**         | Still significant despite wider CI     |
| PSR (SR₀=0.1)        | Eq 9+5   | **0.900**         | Harder benchmark reduces confidence    |
| MinTRL (SR₀=0)       | Eq 11    | **19.543** months | T=24 > 19.5 → sufficient               |
| MinTRL (SR₀=0.1)     | Eq 11    | **39.369** months | More than doubles for SR₀ closer to SR̂ |
| β (power, SR₁=0.5)   | Eq 17    | **0.411**         | vs 0.224 IID Normal — 84% higher       |
| Power (1−β)          | Eq 15    | **0.589**         | Low for 24-month track record          |

## Implementation Architecture

4-tier dependency hierarchy (Numba JIT, Rust-ready):

```
Tier 0: erfinv, norm_cdf, norm_ppf
Tier 1: sr_variance (Eqs 3/58), ar1_variance_coeffs
Tier 2: psr (Eq 9), min_trl (Eq 11), critical_sr (Eq 8)
Tier 3: power (Eqs 12-17)
```

## Related Skills

| Skill                                                                | Relationship                                                     |
| -------------------------------------------------------------------- | ---------------------------------------------------------------- |
| [opendeviation-eval-metrics](../opendeviation-eval-metrics/SKILL.md) | Consumes PSR and MinTRL for range bar evaluation (ρ=0 quick-ref) |
| [adaptive-wfo-epoch](../adaptive-wfo-epoch/SKILL.md)                 | Reports PSR per walk-forward fold                                |

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
