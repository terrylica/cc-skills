# quant-research Plugin

> Quantitative research metrics: SOTA evaluation for range bars, Sharpe ratios, ML prediction quality, WFO epoch selection.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [mql5 CLAUDE.md](../mql5/CLAUDE.md)

## Skills

- [adaptive-wfo-epoch](./skills/adaptive-wfo-epoch/SKILL.md)
- [backtesting-py-oracle](./skills/backtesting-py-oracle/SKILL.md)
- [evolutionary-metric-ranking](./skills/evolutionary-metric-ranking/SKILL.md)
- [exchange-session-detector](./skills/exchange-session-detector/SKILL.md)
- [odb-microstructure-forensics](./skills/odb-microstructure-forensics/SKILL.md)
- [opendeviation-eval-metrics](./skills/opendeviation-eval-metrics/SKILL.md)
- [sharpe-ratio-non-iid-corrections](./skills/sharpe-ratio-non-iid-corrections/SKILL.md)
- [zigzag-pattern-classifier](./skills/zigzag-pattern-classifier/SKILL.md)

## Conventions

- **Crypto-specific**: sqrt(7) annualization for 24/7 markets
- **Statistical validation**: PSR, MinTRL and the non-IID Sharpe variance for trading strategies. Never compute, report, rank by or cite the Deflated Sharpe Ratio, the minimum backtest length (MinBTL) or any other trial-count correction (FWER/FDR, Holm, Benjamini-Yekutieli, e-LOND): judge parsimony on the model, guard selection with registration before runs and unused data, report each rule's own statistics (operator rule 2026-10-15). PBO/CSCV is not covered
- **Polars-first**: Use lazy frames (scan_csv) for large datasets
- **Related plugins**: `devops-tools` (MLflow), `itp` (workflow automation)
