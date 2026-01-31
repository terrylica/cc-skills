# quant-research

Quantitative research skills for financial data analysis and ML model evaluation.

## Skills

| Skill                                                            | Description                                                     |
| ---------------------------------------------------------------- | --------------------------------------------------------------- |
| [rangebar-eval-metrics](./skills/rangebar-eval-metrics/SKILL.md) | SOTA metrics for range bar evaluation: Sharpe, risk, ML quality |
| [adaptive-wfo-epoch](./skills/adaptive-wfo-epoch/SKILL.md)       | Adaptive epoch selection for Walk-Forward Optimization (WFO)    |

### rangebar-eval-metrics

Metrics for evaluating price-based sampling (range bars) including:

- Sharpe ratio calculations with proper annualization
- Risk metrics (drawdown, Calmar, Sortino)
- ML prediction quality metrics
- Crypto-specific considerations (sqrt(7) annualization, 24/7 markets)

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

## Installation

```bash
claude plugin marketplace add terrylica/cc-skills
```

## Related Plugins

- `devops-tools`: MLflow integration for experiment tracking
- `itp`: Workflow automation for research experiments
- `alpha-forge-worktree`: Git worktree management for parallel experiments
