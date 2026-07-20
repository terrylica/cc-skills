# GARCH Volatility Toolkit

Walk-forward GARCH(1,1) and GJR(1,1) volatility forecasting for portfolio construction. Includes recipes, leakage traps, and campaign results from testing on 20 seeds (BTC/ETH/SOL/AVAX futures, 2025-26 test window).

## Campaign Results (honest)

A negative-to-marginal result set — **not** a deployable edge. Independently re-verified ensemble
net-Sharpe (equal-weight 20 seeds, non-IID PSR); see
[CAMPAIGN_VERDICT.md](./skills/garch-vol-recipes/references/CAMPAIGN_VERDICT.md).

| Overlay (ensemble Sharpe) | 2 bps                      | 7 bps               | Verdict                                   |
| ------------------------- | -------------------------- | ------------------- | ----------------------------------------- |
| **GJR vol-scaling**       | +0.49→**+1.00** (PSR→0.86) | +0.02, p=0.54, 9/20 | Real @2bps, **cost-fragile — dies @7bps** |
| **DCC de-weighting**      | +0.49→+0.56 (PSR→0.73)     | −1.64→−1.58         | Economically immaterial                   |

GARCH information does not create a retail-cost-surviving edge here; GJR vol-sizing is a
low-cost/maker-venue lever only. Per-seed p<0.0001 figures were inflated (deterministic overlay on
correlated seeds) and are not used. This toolkit's value is the **methodology** (walk-forward fitting
recipes + leakage traps), not an alpha claim.

## Quick Links

- **[Main Skill](./skills/garch-vol-recipes/SKILL.md)** — Full recipes, code examples, leakage traps, exercises
- **Reference Data** — Campaign results, parameter tuning, model diagnostics

## Key Insights

1. **GJR forecast vol dominates realized vol** — Walk-forward GJR(1,1) captures leverage effect (negative shocks amplify volatility), producing better forecasts than simple rolling-window approaches

2. **Turnover trade-off** — GJR vol-scaling increases rebalancing ~27%. At 2bps costs easily absorbed; at 7bps still net-positive (+0.274 Sharpe after costs)

3. **Consistency matters** — All 20 seeds improve with GJR; no outlier failures. DCC has 1 regime-sensitive seed (6789), suggesting regime-conditional gating needed

4. **No lookahead required** — Walk-forward fitting with 2024 validation window and 2025-26 test-blind evaluation ensures durable signals

## Skills in This Plugin

### 1. garch-vol-recipes

Complete recipes for:

- Univariate GARCH(1,1) with walking window parameter estimation
- GJR(1,1) with leverage effect γ fitting
- DCC (Dynamic Conditional Correlation) initialization and recursion
- Inverse vol-scaling position sizing
- Campaign verdict + leakage traps + exercises

**Use when**: Building volatility forecasting models, testing position-sizing overlays, learning GARCH best practices

## Installation

```bash
# Clone or pull cc-skills
cd ~/eon/cc-skills

# The skill is available immediately
claude plugin marketplace list | grep garch-volatility-toolkit
```

## Files

```
garch-volatility-toolkit/
├── plugin.json                          # Plugin metadata
├── README.md                            # This file
└── skills/
    └── garch-vol-recipes/
        ├── SKILL.md                     # Full content (recipes, code, exercises)
        └── references/
            ├── angleB_gjr_dcc_results.json    # DCC de-weighting results (20 seeds)
            ├── angleC_vol_scaling_results.json # GJR vol-scaling results (20 seeds)
            └── campaign_verdict.md            # Full campaign analysis
```

## License

PolyForm Noncommercial 1.0.0. Free for personal, educational, research use. Commercial use requires separate license.

---

**Author**: Terry Li (terrylica)  
**Last Updated**: 2026-07-20
