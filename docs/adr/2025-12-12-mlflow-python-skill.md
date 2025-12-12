---
status: accepted
date: 2025-12-12
decision-maker: Terry Li
consulted:
  [
    MLflow-Query-Explorer,
    Python-API-Researcher,
    QuantStats-Comparator,
    MLflow-Auth-Prober,
  ]
research-method: single-agent
clarification-iterations: 5
perspectives: [EcosystemArtifact, UpstreamIntegration]
---

# ADR: Unified MLflow Python Skill with QuantStats Integration

**Design Spec**: [Implementation Spec](/docs/design/2025-12-12-mlflow-python-skill/spec.md)

## Context and Problem Statement

The existing `devops-tools:mlflow-query` skill provides CLI-based read-only access to MLflow experiments. However, users need to:

1. **Write** backtest metrics (Sharpe, max_drawdown, total_return) after strategy runs
2. **Log** hyperparameters used in each experiment
3. **Create** experiment groups for systematic research
4. **Query** experiments with more powerful filtering than CLI allows

The MLflow CLI has a critical limitation: it cannot log metrics or parameters (`mlflow runs log-metric` and `mlflow runs log-param` do not exist). These operations require the Python API.

Additionally, the existing skill uses a non-idiomatic authentication pattern (credentials embedded in URI), which MLflow does not officially support.

### Before/After

```
⏮️ Before: CLI-Based Read-Only

┌──────┐     ┌──────────────┐     ┌──────────────┐     ┌───────────────┐
│ User │     │ mlflow-query │     │  MLflow CLI  │     │ MLflow Server │
│      │ ──> │ (CLI Skill)  │ ──> │ (uvx mlflow) │ ──> │               │
└──────┘     └──────────────┘     └──────────────┘     └───────────────┘
```

```
                   ⏭️ After: Python API Unified Read+Write

┌──────┐     ┌────────────────┐     ┌───────────────────┐     ┌───────────────┐
│ User │     │ mlflow-python  │     │ MLflow Python API │     │ MLflow Server │
│      │ ──> │ (Python Skill) │ ──> │   + QuantStats    │ ──> │               │
└──────┘     └────────────────┘     └───────────────────┘     └───────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: CLI-Based Read-Only"; flow: east; }
[ User ] -> [ mlflow-query\n(CLI Skill) ] -> [ MLflow CLI\n(uvx mlflow) ] -> [ MLflow Server ]
```

```
graph { label: "⏭️ After: Python API Unified Read+Write"; flow: east; }
[ User ] -> [ mlflow-python\n(Python Skill) ] -> [ MLflow Python API\n+ QuantStats ] -> [ MLflow Server ]
```

</details>

## Research Summary

| Agent Perspective     | Key Finding                                                                            | Confidence |
| --------------------- | -------------------------------------------------------------------------------------- | ---------- |
| MLflow-Query-Explorer | Existing skill uses CLI with Doppler atomic secrets pattern, 5 reference docs          | High       |
| Python-API-Researcher | Python API required for metrics/params logging; CLI cannot do this                     | High       |
| Python-API-Researcher | Python API also supports search_runs() with SQL-like filtering (superior to CLI)       | High       |
| QuantStats-Comparator | QuantStats has 70+ metrics vs empyrical-reloaded's 50+; includes trade-focused metrics | High       |
| MLflow-Auth-Prober    | MLflow server at mlflow.eonlabs.com:5000 accessible with Basic Auth; verified via curl | High       |
| MLflow-Auth-Prober    | Idiomatic pattern uses separate env vars (MLFLOW_TRACKING_URI + USERNAME/PASSWORD)     | High       |

## Decision Log

| Decision Area   | Options Evaluated                           | Chosen                  | Rationale                                                             |
| --------------- | ------------------------------------------- | ----------------------- | --------------------------------------------------------------------- |
| Skill Scope     | Focused write-only, Unified read+write      | Unified read+write      | Python API is strictly superior; CLI adds no value                    |
| Skill Name      | mlflow-write, mlflow-logging, mlflow-python | mlflow-python           | Reflects technology, clear purpose                                    |
| Old Skill       | Keep both, Deprecate, Delete                | Delete mlflow-query     | No deprecation period; unified skill replaces entirely                |
| Metrics Library | empyrical-reloaded, quantstats              | QuantStats              | 70+ metrics vs 50+; includes win_rate, profit_factor, kelly_criterion |
| Auth Pattern    | Doppler atomic secrets, mise + .env.local   | mise [env] + .env.local | Idiomatic MLflow pattern; simpler than Doppler for this use case      |

### Trade-offs Accepted

| Trade-off           | Choice      | Accepted Cost                                                     |
| ------------------- | ----------- | ----------------------------------------------------------------- |
| CLI vs Python       | Python only | Users must have Python environment (but already do for backtests) |
| QuantStats deps     | QuantStats  | Heavier dependencies (matplotlib, plotly) for 20+ more metrics    |
| Delete vs Deprecate | Delete      | No transition period; breaking change for mlflow-query users      |

## Decision Drivers

- MLflow CLI cannot log metrics/parameters (Python API required)
- Python API offers superior query capabilities (SQL-like filtering, DataFrame output)
- QuantStats provides comprehensive trade metrics out-of-box
- mise [env] pattern is the codebase standard for configuration

## Considered Options

- **Option A**: Create focused `mlflow-write` skill (write-only, keep mlflow-query for reads)
- **Option B**: Create unified `mlflow-python` skill replacing mlflow-query entirely <- Selected
- **Option C**: Extend mlflow-query with Python scripts for write operations

## Decision Outcome

Chosen option: **Option B (unified mlflow-python)**, because:

1. Python API is strictly superior for both read and write operations
2. No value in maintaining CLI-based queries when Python does it better
3. Single skill reduces maintenance burden
4. Consistent authentication pattern across all operations

## Synthesis

**Convergent findings**: All perspectives agreed that Python API is required for write operations and offers superior query capabilities.

**Divergent findings**: Initial assumption was that CLI might be simpler for ad-hoc queries. Research showed Python API with DataFrame output is actually more powerful.

**Resolution**: User confirmed unified Python skill approach with QuantStats for comprehensive metrics.

## Consequences

### Positive

- Single skill for all MLflow operations (simplified mental model)
- 70+ trading metrics available via QuantStats integration
- Superior query capabilities (SQL-like filtering, DataFrame output)
- Idiomatic MLflow authentication pattern
- mise [env] configuration follows codebase standards

### Negative

- Breaking change: mlflow-query skill deleted (no deprecation period)
- Heavier dependencies (QuantStats includes matplotlib, plotly)
- Requires Python environment (but users already have this for backtests)

## Architecture

```
🏗️ mlflow-python Skill Architecture

╭──────────╮     ┌───────────────┐     ┌─────────────────┐     ┌────────────┐     ╔════════╗
│ Backtest │     │  QuantStats   │     │ log_backtest.py │     │   MLflow   │     ║ MLflow ║
│ Returns  │ ──> │ (70+ metrics) │ ──> │                 │ ──> │ Python API │ ──> ║ Server ║
╰──────────╯     └───────────────┘     └─────────────────┘     └────────────┘     ╚════════╝
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ mlflow-python Skill Architecture"; flow: east; }
[ Backtest\nReturns ] { shape: rounded; } -> [ QuantStats\n(70+ metrics) ] -> [ log_backtest.py ] -> [ MLflow\nPython API ] -> [ MLflow\nServer ] { border: double; }
```

</details>

## References

- [MLflow Python API Documentation](https://mlflow.org/docs/latest/python_api/index.html)
- [QuantStats GitHub](https://github.com/ranaroussi/quantstats)
- [Global Plan](/docs/design/2025-12-12-mlflow-python-skill/spec.md)
