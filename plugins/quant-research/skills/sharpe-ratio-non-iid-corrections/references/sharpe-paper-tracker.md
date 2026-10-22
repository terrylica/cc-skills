---
paper: "How to Use the Sharpe Ratio"
authors: López de Prado, Lipton, Zoonekynd
year: 2026
ssrn: "5520741"
source_pdf: ./lopez-de-prado-sharpe-2026.pdf
transcription_excerpt: ./how-to-use-the-sharpe-ratio-2026.md
numba_implementation: ./sharpe_numba.py
replication_code: https://github.com/zoonek/2025-sharpe-ratio
equations_in_scope: "1-17, 34-61"
validation_tests: 9
validation_status: all_pass
---

# Sharpe Paper Equation → Implementation Tracker

Compact map from paper equations to Numba JIT functions and validation tests.

**Scope**: Sections 2-5 (variance, PSR, MinTRL, power) and Appendix A.1-A.2 only. Sections 6-8 (Bayesian FDR, FWER, the Deflated Sharpe Ratio, SFDR) and Appendices A.3-A.6 / B / C are out of scope by operator rule (2026-10-15): no trial-count corrections. See SKILL.md § "Out of scope".

**Conventions**: γ₄ = Pearson kurtosis (=3 for Gaussian). All functions are `@njit(cache=True)`.

## Section 2: Sharpe Ratio Estimation

| Eq  | Name                     | Compact Formula                             | Page | Function          | Test | ✓   |
| --- | ------------------------ | ------------------------------------------- | ---- | ----------------- | ---- | --- |
| 1   | SR definition            | SR = μ/σ                                    | 5    | —                 | —    | ✓   |
| 2   | SR variance (population) | V[SR̂] = (1/T)(a − b·γ₃·SR + c·(γ₄−1)/4·SR²) | 6    | `sr_variance`     | 1,2  | ✓   |
| 3   | SR variance (sample)     | Same as Eq 2 with sample estimates          | 6    | `sr_variance`     | 1,2  | ✓   |
| 4   | Test statistic           | z\* = (SR̂ − SR₀)/σ[SR₀]                     | 7    | (inline in `psr`) | 3    | ✓   |
| 5   | σ[SR₀]                   | √(V[SR̂] evaluated at SR₀)                   | 7    | `sr_variance`     | 3    | ✓   |

## Section 3: Probabilistic Sharpe Ratio

| Eq  | Name         | Compact Formula                | Page | Function                  | Test | ✓   |
| --- | ------------ | ------------------------------ | ---- | ------------------------- | ---- | --- |
| 6   | Type I error | α = 1 − Φ((SR_c − SR₀)/σ[SR₀]) | 8    | (inline in `critical_sr`) | —    | ✓   |
| 7   | Critical z   | z\_{1−α} = Φ⁻¹(1−α)            | 8    | `norm_ppf`                | 6    | ✓   |
| 8   | Critical SR  | SR*c = SR₀ + σ[SR₀]·z*{1−α}    | 8    | `critical_sr`             | —    | ✓   |
| 9   | PSR          | Φ((SR̂ − SR₀)/σ[SR₀])           | 8    | `psr`                     | 3,7  | ✓   |

## Section 4: Minimum Track Record Length

| Eq  | Name                 | Compact Formula                                   | Page | Function  | Test | ✓   |
| --- | -------------------- | ------------------------------------------------- | ---- | --------- | ---- | --- |
| 10  | MinTRL (definition)  | min T s.t. P[SR̂≥SR̂\* \| H₀] ≤ α                   | 9    | `min_trl` | 4,8  | ✓   |
| 11  | MinTRL (closed form) | (a−b·γ₃·SR₀+c·(γ₄−1)/4·SR₀²)·(z\_{1−α}/(SR̂−SR₀))² | 9    | `min_trl` | 4,8  | ✓   |

## Section 5: Statistical Power

| Eq  | Name               | Compact Formula                                       | Page | Function      | Test | ✓   |
| --- | ------------------ | ----------------------------------------------------- | ---- | ------------- | ---- | --- |
| 12  | Type II error β    | Φ((SR_c − SR₁)/σ[SR₁])                                | 10   | `power`       | 9    | ✓   |
| 13  | Power (1−β)        | 1 − Φ((SR_c − SR₁)/σ[SR₁])                            | 10   | `power`       | 9    | ✓   |
| 14  | SR_c (restated)    | SR₀ + σ[SR₀]·z\_{1−α}                                 | 10   | `critical_sr` | —    | ✓   |
| 15  | Power (expanded)   | 1 − Φ((SR₀+σ[SR₀]z\_{1−α}−SR₁)/σ[SR₁])                | 10   | `power`       | 9    | ✓   |
| 16  | σ[SR₁]             | √(V[SR̂] evaluated at SR₁)                             | 11   | `sr_variance` | —    | ✓   |
| 17  | β (fully expanded) | Φ((z\_{1−α}√a − SR₁√T)/√(a−b·γ₃·SR₁+c·(γ₄−1)/4·SR₁²)) | 11   | `power`       | 9    | ✓   |

## Appendix A: Asymptotic Variance (Mathematical Derivation)

| Eq    | Name               | Compact Formula                     | Page  | Function              | Test | ✓   |
| ----- | ------------------ | ----------------------------------- | ----- | --------------------- | ---- | --- |
| 34    | Moment definitions | γ₃=v₃/σ³, γ₄=v₄/σ⁴, ρ=Cor[xₜ,xₜ₊₁]  | 27    | —                     | —    | ✓   |
| 35-43 | GMM derivation     | CLT → sandwich estimator → Σ matrix | 27-30 | —                     | —    | ✓   |
| 44-56 | AR(1) autocov      | xₜ=ρxₜ₋₁+εₜ → cross-moment formulas | 30-33 | `ar1_variance_coeffs` | 5    | ✓   |
| 57-58 | Joint asymptotic   | Σ with non-IID corrections          | 33-34 | `sr_variance`         | 1,2  | ✓   |
| 59-60 | Gaussian special   | Σ with γ₃=0, γ₄=3 → simpler formula | 34    | `sr_variance`         | 2    | ✓   |
| 61    | Effective N        | T_eff = (1−ρ)/(1+ρ)·T               | 35    | —                     | —    | ✓   |

## Summary

- Equations 1-17 and 34-61 (the in-scope sections) verified against the source PDF
- **9 validation tests** covering the paper's single-test numerical examples
- **9 @njit functions** across 4 dependency tiers
- All pure functions (no global state), ready for Rust translation
