# Academic Foundations: Adaptive Walk-Forward Epoch Selection

## Literature Review

This methodology synthesizes concepts from four distinct academic traditions:

1. **Walk-Forward Analysis** (Trading Systems Research)
2. **Probabilistic Sharpe Ratio** (Statistical Finance)
3. **Multi-Objective Hyperparameter Optimization** (Machine Learning)
4. **Warm-Starting Sequential Optimization** (AutoML)

## 1. Walk-Forward Efficiency (WFE)

### Origin

Walk-Forward Efficiency was introduced by **Robert E. Pardo** in his seminal work on trading system validation:

- **Pardo, R. E. (1992).** _Design, Testing, and Optimization of Trading Systems._ John Wiley & Sons.
- **Pardo, R. E. (2008).** _The Evaluation and Optimization of Trading Strategies, 2nd Edition._ John Wiley & Sons.

### Definition

```
WFE = OOS_Performance / IS_Performance
```

Typically expressed as return ratio or Sharpe ratio.

### Interpretation Guidelines (Pardo)

| WFE Value | Interpretation                         |
| --------- | -------------------------------------- |
| > 0.60    | Robust strategy, low overfitting risk  |
| 0.50-0.60 | Acceptable, reasonable generalization  |
| < 0.50    | Likely overfit, requires revision      |
| ~1.00     | Encouraging but warrants investigation |
| Variable  | Signals fragility across regimes       |

### Key Quote

> "Walk-Forward Efficiency measures the degree to which a strategy's in-sample performance translates to out-of-sample results. A strategy that cannot maintain at least 50% of its in-sample performance is likely overfit to historical data."
> — Pardo (2008), Chapter 8

## 2. Probabilistic Sharpe Ratio (PSR)

### Origin

**Bailey, D. H., & López de Prado, M. (2012).** "The Sharpe Ratio Efficient Frontier." _Journal of Risk_, 15(2), 3-44. The non-IID (autocorrelated, non-Normal) variance used here is López de Prado, Lipton & Zoonekynd (2026); see the [sharpe-ratio-non-iid-corrections](../../sharpe-ratio-non-iid-corrections/SKILL.md) skill.

### Problem Addressed

A point estimate of the Sharpe ratio says nothing about its significance. PSR is the probability that the true Sharpe of this one rule exceeds a benchmark SR₀, given its sample length, skewness, kurtosis and autocorrelation.

### Formula

```
PSR = Φ[(SR - SR₀) × √T / √(1 + 0.5×SR² - γ₃×SR + (γ₄-3)/4×SR²)]
```

Where SR is the observed Sharpe ratio, SR₀ the benchmark fixed before the run (usually 0), T the number of observations, γ₃ skewness, γ₄ Pearson kurtosis and Φ the standard normal CDF.

### Epoch selection without trial-count corrections

Operator rule (2026-10-15): never compute, report, rank by or cite the Deflated Sharpe Ratio or any other trial-count correction. Selection across epochs and folds is guarded instead by keeping the epoch candidate set small and declared before the sweep (parsimony judged on the model itself), by registering thresholds before runs, and by judging the selected rule on test data no selection step has touched. Each rule reports its own Sharpe, PSR and MinTRL.

## 3. Multi-Objective Hyperparameter Optimization (MOHPO)

### Key References

- **Bischl, B., Binder, M., Lang, M., et al. (2023).** "Multi-Objective Hyperparameter Optimization in Machine Learning—An Overview." _ACM Transactions on Evolutionary Learning and Optimization._
- **Deb, K., Pratap, A., Agarwal, S., & Meyarivan, T. (2002).** "A Fast and Elitist Multiobjective Genetic Algorithm: NSGA-II." _IEEE Transactions on Evolutionary Computation_, 6(2), 182-197.

### Pareto Optimality

A solution is **Pareto-optimal** if no other solution improves one objective without worsening another.

For epoch selection with objectives:

1. **Maximize WFE** (generalization quality)
2. **Minimize training time** (computational cost)

An epoch is on the efficient frontier if no other epoch dominates it.

### Algorithms

- **NSGA-II**: Non-dominated Sorting Genetic Algorithm (Deb et al., 2002)
- **SPEA-II**: Strength Pareto Evolutionary Algorithm
- **SMS-EMOA**: S-Metric Selection Evolutionary Multi-Objective Algorithm

For discrete epoch selection (4 candidates), exhaustive evaluation is tractable; these algorithms are relevant for continuous or large search spaces.

## 4. Warm-Starting Sequential Optimization

### Key References

- **Nomura, M., & Ono, I. (2021).** "Warm Starting CMA-ES for Hyperparameter Optimization." _Proceedings of the AAAI Conference on Artificial Intelligence._
- **Perrone, V., et al. (2017).** "Learning to Transfer Initializations for Bayesian Hyperparameter Optimization." _BayesOpt Workshop at NeurIPS._

### Concept

Transfer knowledge from previous optimization runs to accelerate future searches. In the context of AWFES:

```
epoch_prior(fold_n) = optimal_epoch(fold_{n-1})
```

### Benefits

1. **Reduced search cost**: Prior narrows exploration
2. **Temporal adaptation**: Captures regime-specific patterns
3. **Stability**: Prevents erratic epoch switching

### Risk: Path Dependency

Warm-starting creates serial correlation in epoch selection. Mitigation:

- Use stability penalty for changes
- Periodically reset to prior-free search
- Monitor epoch selection variance across folds

## 5. Related Work in Finance

### Combinatorial Purged Cross-Validation (CPCV)

**López de Prado, M. (2018).** _Advances in Financial Machine Learning._ Wiley. Chapter 7.

CPCV addresses look-ahead bias in time series cross-validation by:

1. Testing all possible train/test combinations
2. Purging overlapping samples (embargo)
3. Providing distribution of performance, not point estimate

AWFES is compatible with CPCV: use CPCV for outer loop model evaluation, AWFES for inner loop epoch selection.

### Evidence-Based Technical Analysis

**Aronson, D. R. (2006).** _Evidence-Based Technical Analysis: Applying the Scientific Method and Statistical Inference to Trading Signals._ John Wiley & Sons.

Key contributions:

- Data-mining bias corrections for trading strategies
- Hypothesis testing framework for technical analysis
- Evaluated 6,400+ signaling rules with proper statistical controls

## 6. Comparison: AWFES vs Related Methods

| Method                    | Selection Criterion  | Temporal Structure      | Adaptation            |
| ------------------------- | -------------------- | ----------------------- | --------------------- |
| Early Stopping            | Validation loss      | Continuous monitoring   | None                  |
| Nested CV                 | Validation accuracy  | Shuffled splits         | None                  |
| Bayesian Optimization     | Acquisition function | Independent evaluations | Surrogate model       |
| Population-Based Training | Validation metric    | Within-training         | Weight transfer       |
| **AWFES**                 | WFE (IS/OOS ratio)   | Temporal WFO            | Epoch prior carryover |

### Key Distinctions

1. **WFE vs validation loss**: WFE directly measures generalization; validation loss measures prediction accuracy
2. **Temporal ordering**: AWFES respects time series structure; standard CV does not
3. **Discrete candidates**: AWFES evaluates all candidates; Bayesian optimization uses surrogate to reduce evaluations
4. **Carry-forward**: AWFES transfers epoch selection, not model weights

## 7. Empirical Guidelines

### From Pardo (2008)

| Guideline           | Value         | Rationale                              |
| ------------------- | ------------- | -------------------------------------- |
| Minimum WFE         | 0.50          | Below this, strategy likely overfit    |
| IS/OOS ratio        | 80/20 typical | Balance signal detection vs validation |
| Fold count          | 10-30         | Statistical significance               |
| Walk-forward period | 3+ years      | Capture multiple market cycles         |

### From López de Prado (2018)

| Guideline            | Value          | Rationale                                  |
| -------------------- | -------------- | ------------------------------------------ |
| Minimum track record | MinTRL formula | Required days for statistical significance |
| Embargo period       | 6% of data     | Prevent look-ahead bias                    |
| CPCV paths           | 20-30          | Balance compute vs coverage                |

## Full Bibliography

```bibtex
@article{bailey2012efficient,
  title={The Sharpe Ratio Efficient Frontier},
  author={Bailey, David H and L{\'o}pez de Prado, Marcos},
  journal={Journal of Risk},
  volume={15},
  number={2},
  pages={3--44},
  year={2012}
}

@book{pardo2008evaluation,
  title={The Evaluation and Optimization of Trading Strategies},
  author={Pardo, Robert E},
  year={2008},
  publisher={John Wiley \& Sons},
  edition={2nd}
}

@book{lopezdeprado2018advances,
  title={Advances in Financial Machine Learning},
  author={L{\'o}pez de Prado, Marcos},
  year={2018},
  publisher={John Wiley \& Sons}
}

@article{bischl2023mohpo,
  title={Multi-Objective Hyperparameter Optimization in Machine Learning—An Overview},
  author={Bischl, Bernd and others},
  journal={ACM Transactions on Evolutionary Learning and Optimization},
  year={2023}
}

@inproceedings{nomura2021warm,
  title={Warm Starting CMA-ES for Hyperparameter Optimization},
  author={Nomura, Masahiro and Ono, Isao},
  booktitle={Proceedings of the AAAI Conference on Artificial Intelligence},
  year={2021}
}

@article{deb2002nsga2,
  title={A Fast and Elitist Multiobjective Genetic Algorithm: NSGA-II},
  author={Deb, Kalyanmoy and others},
  journal={IEEE Transactions on Evolutionary Computation},
  volume={6},
  number={2},
  pages={182--197},
  year={2002}
}

@book{aronson2006evidence,
  title={Evidence-Based Technical Analysis},
  author={Aronson, David R},
  year={2006},
  publisher={John Wiley \& Sons}
}
```
