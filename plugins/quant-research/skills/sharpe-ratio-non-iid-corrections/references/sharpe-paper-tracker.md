---
paper: "How to Use the Sharpe Ratio"
authors: López de Prado, Lipton, Zoonekynd
year: 2026
ssrn: "5520741"
source_pdf: ./lopez-de-prado-sharpe-2026.pdf
full_transcription: ./how-to-use-the-sharpe-ratio-2026.md
numba_implementation: ./sharpe_numba.py
replication_code: https://github.com/zoonek/2025-sharpe-ratio
equations_total: 82
equations_verified: 82
validation_tests: 18
validation_status: all_pass
---

# Sharpe Paper Equation → Implementation Tracker

Compact map from paper equations to Numba JIT functions and validation tests.

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
| 7   | Critical z   | z\_{1−α} = Φ⁻¹(1−α)            | 8    | `norm_ppf`                | 13   | ✓   |
| 8   | Critical SR  | SR*c = SR₀ + σ[SR₀]·z*{1−α}    | 8    | `critical_sr`             | —    | ✓   |
| 9   | PSR          | Φ((SR̂ − SR₀)/σ[SR₀])           | 8    | `psr`                     | 3,14 | ✓   |

## Section 4: Minimum Track Record Length

| Eq  | Name                 | Compact Formula                                   | Page    | Function  | Test      | ✓    |
| --- | -------------------- | ------------------------------------------------- | ------- | --------- | --------- | ---- | --- |
| 10  | MinTRL (definition)  | min T s.t. P[SR̂≥SR̂\*                              | H₀] ≤ α | 9         | `min_trl` | 4,15 | ✓   |
| 11  | MinTRL (closed form) | (a−b·γ₃·SR₀+c·(γ₄−1)/4·SR₀²)·(z\_{1−α}/(SR̂−SR₀))² | 9       | `min_trl` | 4,15      | ✓    |

## Section 5: Statistical Power

| Eq  | Name               | Compact Formula                                       | Page | Function      | Test | ✓   |
| --- | ------------------ | ----------------------------------------------------- | ---- | ------------- | ---- | --- |
| 12  | Type II error β    | Φ((SR_c − SR₁)/σ[SR₁])                                | 10   | `power`       | 16   | ✓   |
| 13  | Power (1−β)        | 1 − Φ((SR_c − SR₁)/σ[SR₁])                            | 10   | `power`       | 16   | ✓   |
| 14  | SR_c (restated)    | SR₀ + σ[SR₀]·z\_{1−α}                                 | 10   | `critical_sr` | —    | ✓   |
| 15  | Power (expanded)   | 1 − Φ((SR₀+σ[SR₀]z\_{1−α}−SR₁)/σ[SR₁])                | 10   | `power`       | 16   | ✓   |
| 16  | σ[SR₁]             | √(V[SR̂] evaluated at SR₁)                             | 11   | `sr_variance` | —    | ✓   |
| 17  | β (fully expanded) | Φ((z\_{1−α}√a − SR₁√T)/√(a−b·γ₃·SR₁+c·(γ₄−1)/4·SR₁²)) | 11   | `power`       | 16   | ✓   |

## Section 6: False Discovery Rates

| Eq  | Name                     | Compact Formula                          | Page               | Function           | Test   | ✓    |
| --- | ------------------------ | ---------------------------------------- | ------------------ | ------------------ | ------ | ---- | --- |
| 18  | pFDR definition          | P[H₀                                     | SR̂≥SR_c]           | 13                 | `pfdr` | 5,17 | ✓   |
| 19  | Bayes theorem            | P[H₀                                     | SR̂≥SR_c] via Bayes | 13                 | `pfdr` | 5,17 | ✓   |
| 20  | Total probability        | α·P[H₀] + (1−β)·P[H₁]                    | 13                 | (inline)           | —      | ✓    |
| 21  | pFDR (closed)            | (1 + (1−β)P[H₁]/(αP[H₀]))⁻¹              | 14                 | `pfdr`             | 5,17   | ✓    |
| 22  | oFDR definition          | P[H₀                                     | SR̂≥SR̂\*]           | 15                 | `ofdr` | 18   | ✓   |
| 23  | Total probability (oFDR) | p·P[H₀] + (1−Φ[z*(SR₁)])·P[H₁]           | 15                 | (inline in `ofdr`) | —      | ✓    |
| 24  | oFDR (closed)            | p·P[H₀] / (p·P[H₀]+(1−Φ[z*(SR₁)])·P[H₁]) | 15                 | `ofdr`             | 18     | ✓    |
| 25  | FWER                     | 1 − (1−α)^K                              | 16                 | `fwer`             | 8      | ✓    |

## Section 7: Deflated Sharpe Ratio

| Eq  | Name                    | Compact Formula                               | Page | Function                 | Test | ✓   |
| --- | ----------------------- | --------------------------------------------- | ---- | ------------------------ | ---- | --- |
| 26  | CDF of max              | F[m] = Φ[m]^K                                 | 17   | (inline in `moments_mk`) | —    | ✓   |
| 27  | SR_c (multiple testing) | SR₀ + Φ⁻¹((1−α_K)^{1/K})·√V                   | 17   | (inline in `dsr`)        | —    | ✓   |
| 28  | E[max SR]               | SR₀ + √V·((1−γ)Φ⁻¹[1−1/K]+γΦ⁻¹[1−1/(Ke)])     | 18   | `expected_max_sr`        | 6    | ✓   |
| 29  | DSR null                | SR₀,K = E[max{SR̂_k}]                          | 19   | `dsr`                    | 10   | ✓   |
| 30  | DSR variance            | √V[max] = √V[SR̂]·√V[max{X_k}]                 | 19   | `dsr`                    | 10   | ✓   |
| 31  | √V[max{X_k}]            | ≈ √(π²/6−γ²/(1+γ))·(Φ⁻¹[1−1/(Ke)]−Φ⁻¹[1−1/K]) | 20   | `var_max_sr_evt`         | 7    | ✓   |

## Section 8: Strategic False Discovery Rate

| Eq  | Name            | Compact Formula                  | Page | Function         | Test | ✓   |
| --- | --------------- | -------------------------------- | ---- | ---------------- | ---- | --- |
| 32  | SFDR definition | Find SR_c: pFDR(SR_c)=q          | 21   | `sfdr_threshold` | 9    | ✓   |
| 33  | SFDR (expanded) | Brent root of q − pFDR(SR_c) = 0 | 21   | `sfdr_threshold` | 9    | ✓   |

## Appendix A: Asymptotic Variance (Mathematical Derivation)

| Eq    | Name               | Compact Formula                     | Page  | Function              | Test | ✓   |
| ----- | ------------------ | ----------------------------------- | ----- | --------------------- | ---- | --- |
| 34    | Moment definitions | γ₃=v₃/σ³, γ₄=v₄/σ⁴, ρ=Cor[xₜ,xₜ₊₁]  | 27    | —                     | —    | ✓   |
| 35-43 | GMM derivation     | CLT → sandwich estimator → Σ matrix | 27-30 | —                     | —    | ✓   |
| 44-56 | AR(1) autocov      | xₜ=ρxₜ₋₁+εₜ → cross-moment formulas | 30-33 | `ar1_variance_coeffs` | 12   | ✓   |
| 57-58 | Joint asymptotic   | Σ with non-IID corrections          | 33-34 | `sr_variance`         | 1,2  | ✓   |
| 59-60 | Gaussian special   | Σ with γ₃=0, γ₄=3 → simpler formula | 34    | `sr_variance`         | 2    | ✓   |
| 61    | Effective N        | T_eff = (1−ρ)/(1+ρ)·T               | 35    | —                     | —    | ✓   |

## Appendix B: Expected Maximum and Variance of Maximum

| Eq    | Name              | Compact Formula                         | Page  | Function                             | Test | ✓   |
| ----- | ----------------- | --------------------------------------- | ----- | ------------------------------------ | ---- | --- |
| 62-65 | Order statistics  | F[m], f[m], E[M^r], V[M]                | 36-37 | `moments_mk`, `var_max_sr_numerical` | 7    | ✓   |
| 66-75 | EVT approximation | Gumbel a_K, b_K, V[M]≈Δ²(π²/6−γ²/(1+γ)) | 37-39 | `var_max_sr_evt`                     | 7    | ✓   |

## Appendix C: General FDR Framework

| Eq    | Name        | Compact Formula | Page                            | Function | Test                             | ✓         |
| ----- | ----------- | --------------- | ------------------------------- | -------- | -------------------------------- | --------- | --- |
| 76-82 | General FDR | q=P[H₀          | X≥c], α, β, Bayes → closed form | 40-42    | `pfdr`, `ofdr`, `sfdr_threshold` | 5,9,17,18 | ✓   |

## Summary

- **82/82** equations verified against source PDF
- **18 validation tests** covering all numerical examples from the paper
- **20+ @njit functions** across 6 dependency tiers
- All pure functions (no global state), ready for Rust translation
