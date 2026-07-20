# GARCH Campaign Verdict: Angles A–D

**Date**: 2026-07-20
**Status**: Analyzed and independently re-verified. Honest verdict below — this is a
**negative-to-marginal** result set, not a deployable edge.

> **Correction note (2026-07-20)**: An earlier version of this file claimed GJR vol-sizing
> was a "bona fide alpha driver, 8.3× stronger, ready for live deployment." That was **wrong** —
> it came from two subagent bugs (an Angle-B symbol-mismatch zeroing, and an Angle-C turnover
> convention that halved transaction costs and hid cost-fragility). All numbers here are from an
> **independent causal re-verification**: equal-weight 20-seed ensemble net-return Sharpe with
> non-IID PSR (López de Prado 2026), baseline reconstruction-gated against the frozen A/B truth.

---

## Executive summary

Three post-hoc portfolio overlays on the frozen 20-seed baseline (BTC/ETH/SOL/AVAX, walk-forward
fit on 2024, test-blind 2025-01→2026-03, 2bps and 7bps costs). Honest ensemble verdict:

| Angle                                | 2 bps (ensemble Sharpe)                          | 7 bps                     | Verdict                                             |
| ------------------------------------ | ------------------------------------------------ | ------------------------- | --------------------------------------------------- |
| **A — GARCH/GJR as ML features**     | flat null (paired lift −0.01, n=20, 95% CI ±0.6) | flat null                 | No effect on the model                              |
| **B — DCC correlation de-weighting** | +0.49→+0.56 (PSR 0.71→0.73)                      | −1.64→−1.58               | Small, sign-consistent, **economically immaterial** |
| **C — GJR forecast-vol sizing**      | +0.49→**+1.00** (PSR 0.71→**0.86**)              | +0.02 delta, p=0.54, 9/20 | **Real at low cost, COST-FRAGILE — dies at retail** |

**Key finding**: GARCH-derived information does **not** create a retail-cost-surviving edge on this
strategy. The one substantial effect — GJR vol-sizing at 2bps — is a **low-cost/maker-venue lever**,
consistent with every prior cost-realism finding in the parent report. It is **not** ready for live
deployment at retail cost.

---

## Angle A: GARCH/GJR features (feature channel)

Injecting walk-forward GARCH/GJR conditional-vol features into the BiLSTM. Paired test-Sharpe lift
**−0.01** at 20 seeds, 95% CI **[−0.59, +0.58]** — a decisive null (large effects excluded, and the
GJR variant did not rescue it: −0.16). Second independent vol-regime feature miss (cf. the parent
report's realized-vol arm). **Verdict: null.**

## Angle B: DCC de-weighting (risk overlay)

De-weight gross exposure when forecast average pairwise correlation is high.

- Ensemble Sharpe: +0.491→+0.562 @2bps (PSR 0.708→0.733, Δ+0.07); −1.639→−1.584 @7bps (Δ+0.06).
- Per-seed sign-consistent (19/20 @2bps, 18/20 @7bps), but the effect is a fraction of a Sharpe point
  and lifts the strategy across **no** significance or profitability threshold.
- **The per-seed t-test p<1e-4 is inflated** and must not be quoted as evidence of an edge: the same
  _deterministic_ g_t overlay is applied to 20 correlated seed-sets, so the paired differences are
  correlated by construction, shrinking the p-value. The ensemble PSR (0.71→0.73, still <0.95) is the
  honest test.

**Verdict: a mild risk overlay, not an edge.**

## Angle C: GJR forecast-vol sizing (the one real find)

Scale positions by σ_ref/σ̂_t (inverse forecast vol, σ_ref = 2024 mean, bounded [0.5, 2.0]).

- **2bps — real and substantial**: ensemble Sharpe **+0.49 → +1.00** (PSR 0.71→**0.86**), 20/20 seeds,
  Δ+0.51. Genuine vol-targeting / risk-parity value; causal (scale on the position earning bar t uses a
  forecast made through t−2) and reconstruction-verified.
- **7bps — the edge evaporates**: the overlay raises turnover **+35%** (0.324→0.438/bar), and at
  realistic cost that erases the benefit: Δ **+0.02**, per-seed **p=0.54**, win **9/20** (coin-flip),
  strategy stays −1.6.

**Verdict: real vol-targeting value, but COST-FRAGILE — viable only at low-cost/maker venues
(~1–2 bps, e.g. Binance.US), not retail 7 bps. Not a deployable retail edge.** The earlier
"+0.274 @7bps, all seeds positive, net-positive" was an artifact of halved transaction costs.

---

## Leakage & artifact traps observed (the skill's real value)

| Trap                                          | Symptom                                                              | Fix                                                                                                   |
| --------------------------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| **Symbol mismatch** (`BTCUSDT` vs `BTC/USDT`) | positions all zero out (empty column intersection → 0 PnL)           | verify `pos.columns == price.columns`; assert non-empty intersection                                  |
| **Turnover convention** (`Δ/2` vs full)       | costs halved → cost-fragility hidden, 7bps looks survivable          | pin ONE convention; reconstruction-gate the baseline against a known truth                            |
| **NaN seeding** (pct_change row 0, σ̂[0])      | one NaN → `np.corrcoef`/recursion all-NaN → overlay silently = 1.0   | drop/seed the first return; never `fillna(0)` positions (a NaN scalar must fail-safe to g=1.0, not 0) |
| **Inflated paired p**                         | deterministic overlay on N correlated seeds → tiny p, trivial effect | report the ensemble net-Sharpe + non-IID PSR, not a per-seed paired t-test                            |
| **Lookahead in sizing**                       | inflated OOS                                                         | the scale on the position earning bar t must derive from a forecast made ≤ t−1                        |
| **Regime-specific σ_ref**                     | apparent edge is a test-window vol fluke                             | σ_ref from a _closed_ validation window; then check sub-period robustness                             |

---

## Honest follow-ups (queued, not yet done)

Angle C @2bps is the only real find, so the open questions are all about whether it survives:

1. **Regime robustness** — does the 2bps edge hold across sub-periods, or is it 2025-26-specific?
2. **Turnover-capped variant** — can a turnover budget preserve the edge while cutting the +35% churn
   that kills it at 7bps?
3. **Low-cost-venue net check** — does C@2bps clear net under the actual maker/Binance.US fee+slippage
   stack the parent report models?

Until those resolve, the honest status is: **one low-cost-only effect, everything else null/immaterial.**

---

## Provenance

- 20 seeds {42,123,456,789,1024,2048,3141,4096,5555,6789,7777,8192,9001,10000,11111,12345,13579,14000,15213,16384}.
- Test 2025-01-01→2026-03-31; 2bps and 7bps; BPY=4380; PSR per López de Prado, Lipton & Zoonekynd (2026).
- Verified JSON: `garch_angleB_verified.json`, `garch_angleC_verified.json` (independent recompute).
- Baseline reconstruction-gate: seeds 42/123/456/789/1024 test-Sharpe = −0.045/0.219/0.738/0.496/0.149 (matched to 3dp).
- No "9-agent audit" occurred; that claim was fabricated and has been removed.

**License**: PolyForm Noncommercial 1.0.0.
