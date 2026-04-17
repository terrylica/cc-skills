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
- **Statistical validation**: PSR, DSR, MinTRL for trading strategies
- **Polars-first**: Use lazy frames (scan_csv) for large datasets
- **Related plugins**: `devops-tools` (MLflow), `itp` (workflow automation)
