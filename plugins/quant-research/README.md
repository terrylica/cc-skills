# quant-research

Quantitative research skills for financial data analysis and ML model evaluation: SOTA metrics for range bars, Sharpe ratios, ML prediction quality, and WFO epoch selection.

## Skills

| Skill                                                            | Description                                                     |
| ---------------------------------------------------------------- | --------------------------------------------------------------- |
| [rangebar-eval-metrics](./skills/rangebar-eval-metrics/SKILL.md) | SOTA metrics for range bar evaluation: Sharpe, risk, ML quality |
| [adaptive-wfo-epoch](./skills/adaptive-wfo-epoch/SKILL.md)       | Adaptive epoch selection for Walk-Forward Optimization (WFO)    |

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

## License

MIT
