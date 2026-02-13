# quant-research

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-3-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Quantitative research skills for financial data analysis and ML model evaluation: SOTA metrics for range bars, Sharpe ratios, ML prediction quality, and WFO epoch selection.

## Skills

| Skill                                                            | Description                                                     |
| ---------------------------------------------------------------- | --------------------------------------------------------------- |
| [rangebar-eval-metrics](./skills/rangebar-eval-metrics/SKILL.md) | SOTA metrics for range bar evaluation: Sharpe, risk, ML quality |
| [adaptive-wfo-epoch](./skills/adaptive-wfo-epoch/SKILL.md)       | Adaptive epoch selection for Walk-Forward Optimization (WFO)    |
| [backtesting-py-oracle](./skills/backtesting-py-oracle/SKILL.md) | backtesting.py config for SQL oracle validation (hedging, NaN)  |

## Installation

```bash
claude plugin marketplace add terrylica/cc-skills
claude plugin install quant-research@cc-skills
```

## Usage

Skills are model-invoked based on context.

**Trigger phrases:**

- "range bar metrics", "Sharpe ratio", "WFO metrics", "DSR", "PSR" → rangebar-eval-metrics
- "WFO epoch", "epoch selection", "adaptive epochs", "WFE" → adaptive-wfo-epoch
- "backtesting.py", "hedging", "exclusive_orders", "oracle validation", "SQL vs Python" → backtesting-py-oracle

## Features

### rangebar-eval-metrics

Metrics for evaluating price-based sampling (range bars):

- **Sharpe ratio** calculations with proper daily aggregation and annualization
- **Risk metrics**: Maximum drawdown, Calmar ratio, Sortino ratio
- **ML prediction quality**: Information Coefficient (IC), autocorrelation analysis
- **Statistical validation**: Probabilistic Sharpe Ratio (PSR), Deflated Sharpe Ratio (DSR), MinTRL
- **Crypto-specific**: sqrt(7) annualization for 24/7 markets

### adaptive-wfo-epoch

Per-fold adaptive epoch selection using Walk-Forward Efficiency (WFE):

- Generates log-spaced epoch candidates from search bounds
- Computes WFE = OOS_Sharpe / IS_Sharpe for each epoch
- Finds efficient frontier (max WFE vs training cost)
- Carries forward priors between folds

### backtesting-py-oracle

Configuration and anti-patterns for SQL oracle validation:

- **Multi-position mode**: `hedging=True, exclusive_orders=False` for overlapping trades
- **Trade sort alignment**: Sort `stats._trades` by EntryTime (default is ExitTime)
- **NaN poisoning prevention**: Skip NaN in rolling quantile windows
- **5-gate oracle framework**: Signal count, timestamp, price, exit type, Kelly comparison
- **Strategy templates**: Single-position vs multi-position with per-trade barrier tracking

## Use Cases

- Evaluating BiLSTM/transformer models on range bar data
- Walk-Forward Optimization (WFO) metrics calculation
- Statistical validation (PSR, DSR, MinTRL) for trading strategies
- Crypto market-specific metric adaptations (sqrt(7) annualization, 24/7 markets)

## Dependencies

| Component | Required | Installation            |
| --------- | -------- | ----------------------- |
| Python    | Yes      | `mise use python@3.13`  |
| Polars    | Yes      | `uv pip install polars` |
| NumPy     | Yes      | `uv pip install numpy`  |
| SciPy     | Optional | `uv pip install scipy`  |

## Related Plugins

- `devops-tools`: MLflow integration for experiment tracking
- `itp`: Workflow automation for research experiments
- `alpha-forge-worktree`: Git worktree management for parallel experiments

## Troubleshooting

| Issue                        | Cause                          | Solution                                          |
| ---------------------------- | ------------------------------ | ------------------------------------------------- |
| Sharpe ratio NaN             | Zero variance in returns       | Check for flat price data or insufficient samples |
| PSR calculation fails        | scipy not installed            | Run `uv pip install scipy` for statistical tests  |
| DSR too low                  | Many trials in backtest        | Expected with large search spaces; check MinTRL   |
| WFE negative                 | OOS underperforming IS         | Model may be overfitting; reduce complexity       |
| Epoch search bounds too wide | Long runtime                   | Narrow search bounds based on prior experiments   |
| Range bar aggregation wrong  | Incorrect timestamp handling   | Verify bars are price-based not time-based        |
| Memory error on large data   | Polars operations on full data | Use lazy frames (scan_csv) for large datasets     |
| Annualization factor wrong   | Using daily for crypto         | Use sqrt(7) for 24/7 crypto markets               |

## License

MIT
