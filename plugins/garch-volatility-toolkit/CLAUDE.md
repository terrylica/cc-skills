# garch-volatility-toolkit Plugin

> Walk-forward GARCH(1,1) / GJR(1,1) volatility forecasting for portfolio construction — fitting recipes, leakage traps, and honest campaign results.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [quant-research CLAUDE.md](../quant-research/CLAUDE.md)

## Overview

Univariate GARCH(1,1) and GJR(1,1) volatility forecasts, DCC correlation, and
position-sizing overlays, applied walk-forward with no-lookahead discipline.
Tested on 20 seeds across BTC/ETH/SOL/AVAX futures (2025–26 test window).

## Critical framing — methodology, not an alpha claim

The value here is the **method** (walk-forward fitting recipes + leakage traps),
**not** a deployable edge. The campaign result set is negative-to-marginal and is
documented honestly:

- **GJR vol-scaling**: real at 2 bps (ensemble Sharpe +0.49 → +1.00, PSR 0.86) but
  **cost-fragile — dies at 7 bps** (+0.02, p=0.54). A low-cost / maker-venue lever only.
- **DCC de-weighting**: economically immaterial (+0.49 → +0.56 at 2 bps; negative at 7 bps).

Per-seed p<0.0001 figures were inflated (a deterministic overlay on correlated
seeds) and are **not** used. Independently re-verified ensemble net-Sharpe uses
equal-weight 20 seeds with non-IID PSR. Do not represent this toolkit as an edge.
SSoT verdict: [`skills/garch-vol-recipes/references/CAMPAIGN_VERDICT.md`](./skills/garch-vol-recipes/references/CAMPAIGN_VERDICT.md).

## Skills

- [garch-vol-recipes](./skills/garch-vol-recipes/SKILL.md) — univariate fits, DCC
  correlation, position-sizing overlays; no-lookahead walk-forward discipline.

## References

- [README.md](./README.md) — full campaign results + honest verdict table
