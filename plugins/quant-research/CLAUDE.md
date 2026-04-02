# quant-research Plugin

> Quantitative research metrics: SOTA evaluation for range bars, Sharpe ratios, ML prediction quality, WFO epoch selection.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [mql5 CLAUDE.md](../mql5/CLAUDE.md)

## Skills

| Skill                              | Purpose                                                                |
| ---------------------------------- | ---------------------------------------------------------------------- |
| `opendeviation-eval-metrics`       | SOTA metrics: Sharpe, PSR, DSR, risk, ML quality (IC)                  |
| `sharpe-ratio-non-iid-corrections` | Generalized ρ-corrected Sharpe inference (PSR, DSR, pFDR, oFDR)        |
| `adaptive-wfo-epoch`               | Adaptive epoch selection for WFO                                       |
| `backtesting-py-oracle`            | backtesting.py config for SQL oracle validation                        |
| `evolutionary-metric-ranking`      | Multi-objective evolutionary optimization for per-metric cutoffs       |
| `exchange-session-detector`        | DST-aware exchange session detection via exchange_calendars            |
| `odb-microstructure-forensics`     | Investigate ODB bar anomalies via Parquet trade + ClickHouse forensics |

## Conventions

- **Crypto-specific**: sqrt(7) annualization for 24/7 markets
- **Statistical validation**: PSR, DSR, MinTRL for trading strategies
- **Polars-first**: Use lazy frames (scan_csv) for large datasets
- **Related plugins**: `devops-tools` (MLflow), `itp` (workflow automation)
