# quant-research

Quantitative research skills for financial data analysis and ML model evaluation.

## Skills

| Skill                                                            | Description                                                                                                                                                          |
| ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [rangebar-eval-metrics](./skills/rangebar-eval-metrics/SKILL.md) | SOTA metrics for range bar (price-based sampling) evaluation. Includes Sharpe calculations, risk metrics, ML prediction quality, and crypto-specific considerations. |

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
