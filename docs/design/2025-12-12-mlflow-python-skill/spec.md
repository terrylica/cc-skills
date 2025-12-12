---
adr: 2025-12-12-mlflow-python-skill
source: ~/.claude/plans/peppy-yawning-hare.md
implementation-status: in_progress
phase: phase-1
last-updated: 2025-12-12
---

# Design Spec: Unified MLflow Python Skill with QuantStats Integration

**ADR**: [Unified MLflow Python Skill with QuantStats Integration](/docs/adr/2025-12-12-mlflow-python-skill.md)

## Summary

Create a new `devops-tools:mlflow-python` skill that replaces the existing CLI-based `mlflow-query` skill with a unified Python API approach for both reading AND writing to MLflow. Uses QuantStats for comprehensive backtest metrics calculation.

## Key Decisions (Confirmed)

| Decision        | Choice                  | Rationale                                                             |
| --------------- | ----------------------- | --------------------------------------------------------------------- |
| Skill name      | `mlflow-python`         | Reflects Python API usage                                             |
| Scope           | Unified read+write      | Replaces mlflow-query entirely                                        |
| mlflow-query    | **Delete**              | No deprecation period                                                 |
| Metrics library | **QuantStats**          | 70+ metrics, trade-focused (win_rate, profit_factor, kelly_criterion) |
| Credentials     | mise [env] + .env.local | Idiomatic, not Doppler                                                |

## Authentication Pattern

**Important**: MLflow does NOT support credentials in URI. Use idiomatic separate env vars:

```bash
# .env.local (gitignored)
MLFLOW_TRACKING_URI=http://mlflow.eonlabs.com:5000
MLFLOW_TRACKING_USERNAME=eonlabs
MLFLOW_TRACKING_PASSWORD=<password>
```

**Verified**: Server at `mlflow.eonlabs.com:5000` is accessible with Basic Auth (tested via curl).

## File Structure

The skill will be located at `plugins/devops-tools/skills/mlflow-python/` with:

- `SKILL.md` - Main skill documentation
- `.mise.toml` - Configuration SSoT
- `scripts/` - 4 Python scripts (log_backtest.py, query_experiments.py, create_experiment.py, get_metric_history.py)
- `references/` - 4 reference docs (authentication.md, quantstats-metrics.md, query-patterns.md, migration-from-cli.md)

## Implementation Tasks

### Task 1: Create Skill Directory Structure

- [ ] Create `plugins/devops-tools/skills/mlflow-python/`
- [ ] Create `scripts/` subdirectory
- [ ] Create `references/` subdirectory

### Task 2: Create SKILL.md

- [ ] Frontmatter: `name: mlflow-python`, `allowed-tools: Read, Bash, Grep, Glob`
- [ ] Trigger phrases: "log backtest", "MLflow metrics", "experiment tracking", "search runs"
- [ ] Sections: Overview, Authentication, Quick Start, Bundled Scripts, Reference Links

### Task 3: Create .mise.toml

Configuration with MLFLOW_TRACKING_URI default and `.env.local` file loading for secrets.

### Task 4: Create scripts/log_backtest.py (Primary Script)

- [ ] PEP 723 deps: `mlflow>=2.9.0`, `quantstats>=0.0.77`, `pydantic>=2.0`
- [ ] Calculate ALL QuantStats metrics from returns series
- [ ] Log to MLflow with `mlflow.log_metrics()`
- [ ] CLI: `uv run scripts/log_backtest.py --returns data.csv --experiment backtest`

### Task 5: Create scripts/query_experiments.py

- [ ] Replaces CLI `mlflow experiments search`, `mlflow runs list`
- [ ] Uses `mlflow.search_runs()` with DataFrame output
- [ ] CLI: `uv run scripts/query_experiments.py runs --filter "metrics.sharpe > 1.5"`

### Task 6: Create scripts/create_experiment.py

- [ ] Create experiment with name, description, tags
- [ ] CLI: `uv run scripts/create_experiment.py --name "crypto-2025"`

### Task 7: Create scripts/get_metric_history.py

- [ ] Time-series metric retrieval (Python-only feature)
- [ ] CLI: `uv run scripts/get_metric_history.py --run-id abc123 --metrics sharpe,cagr`

### Task 8: Create Reference Docs

- [ ] `references/authentication.md` - Idiomatic MLflow auth patterns
- [ ] `references/quantstats-metrics.md` - Full list of 70+ available metrics
- [ ] `references/query-patterns.md` - DataFrame query patterns
- [ ] `references/migration-from-cli.md` - CLI to Python API migration

### Task 9: Delete mlflow-query Skill

- [ ] Delete `plugins/devops-tools/skills/mlflow-query/` entirely

### Task 10: Update devops-tools/README.md

- [ ] Remove mlflow-query from skills table
- [ ] Add mlflow-python with description

## QuantStats Integration Pattern

The `log_backtest.py` script will use QuantStats to calculate comprehensive metrics:

- Core ratios: sharpe, sortino, calmar
- Drawdown: max_drawdown
- Returns: cagr, total_return (via `qs.stats.comp()`)
- Trade metrics: win_rate, profit_factor, payoff_ratio
- Advanced: kelly_criterion, recovery_factor, ulcer_index

All metrics are logged via `mlflow.log_metrics(metrics_dict)`.

## Critical Files Reference

| File                                                            | Purpose                                   |
| --------------------------------------------------------------- | ----------------------------------------- |
| `clickhouse-pydantic-config/scripts/generate_dbeaver_config.py` | Pattern for PEP 723 + Pydantic scripts    |
| `doppler-secret-validation/SKILL.md`                            | Pattern for SKILL.md with bundled scripts |
| `code-hardcode-audit/.mise.toml`                                | Pattern for mise [env] configuration      |

## Success Criteria

- [ ] All 4 scripts execute successfully with sample data
- [ ] SKILL.md triggers on "log backtest", "mlflow query"
- [ ] Authentication works with mise + .env.local pattern
- [ ] mlflow-query skill deleted
- [ ] devops-tools/README.md updated
