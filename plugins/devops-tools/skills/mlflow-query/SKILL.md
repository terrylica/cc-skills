---
name: mlflow-query
description: Queries MLflow experiments and runs. Use when searching mlflow experiments, comparing run metrics, parameters, or analyzing model performance.
allowed-tools: Read, Bash, Grep, Glob
---

# MLflow Query Skill

**Query and analyze MLflow experiment tracking data within defined boundaries.**

______________________________________________________________________

## When to Use This Skill

**Use this skill when you need to:**

### ✅ What This Skill CAN Do (Within Boundaries)

**Read-Only Query Operations:**

1. **Find Best Models** - Search experiments and rank by metrics (accuracy, loss, custom metrics)
1. **Compare Runs** - Side-by-side comparison of hyperparameters and metrics
1. **Filter Runs** - Filter by metrics, parameters, tags, status (AND-only filters)
1. **Export Data** - Export run data to CSV/JSON for analysis
1. **Detect Issues** - Identify overfitting (train vs test gaps), failed runs, anomalies
1. **List Resources** - Show experiments, runs, artifacts available

**Available Commands:**

- `mlflow experiments search` - List all experiments
- `mlflow runs list --experiment-id <id>` - List runs in experiment
- `mlflow runs describe --run-id <id>` - Get complete run details (JSON)
- `mlflow experiments csv --experiment-id <id>` - Export all runs to CSV
- `mlflow artifacts list --run-id <id>` - List artifacts for a run

**Credential Management:**

- Doppler integration (zero-exposure credentials)
- Environment variable injection
- Remote tracking server authentication

### ❌ What This Skill CANNOT Do (Outside Boundaries)

**Write Operations (Blocked by Design):**

- ❌ Create, modify, or delete runs/experiments
- ❌ Upload artifacts
- ❌ Update tags or parameters
- ❌ Start training runs

**Technical Limitations (MLflow Constraints):**

- ❌ OR filters (only AND filters supported: `metric > 0.8 AND param = 'value'`)
- ❌ Streaming/real-time results (poll-based only, use pagination)
- ❌ Aggregation in queries (no SUM, AVG, COUNT in filters - do client-side)
- ❌ Parameter arithmetic in filters (params are strings, need workarounds)
- ❌ Metric history via CLI (use Python API for time-series)

**Security Restrictions:**

- ❌ Hardcoded credentials (must use Doppler or env vars)
- ❌ Network exfiltration (WebFetch blocked by allowed-tools)
- ❌ Arbitrary code execution

______________________________________________________________________

## 🎯 Available Workflows

**Select a workflow below or describe specific requirements:**

### Common Tasks (Select One)

**A. Find Best Performing Model**

- Input needed: Experiment ID, metric name (e.g., "accuracy", "loss")
- Output: Run ID, metric value, hyperparameters
- Time: ~2 minutes

**B. Compare Multiple Runs**

- Input needed: List of run IDs or experiment ID + filter criteria
- Output: Side-by-side comparison table
- Time: ~3 minutes

**C. Detect Overfitting**

- Input needed: Experiment ID, train metric name, test metric name
- Output: Runs with large train/test gaps, recommendations
- Time: ~5 minutes

**D. Export Experiment Data**

- Input needed: Experiment ID, output format (CSV/JSON)
- Output: File with all runs, metrics, parameters
- Time: ~2 minutes

**E. Filter Runs by Criteria**

- Input needed: Experiment ID, filter conditions (AND-only)
- Output: Matching runs list
- Time: ~3 minutes
- Example filters: `metrics.accuracy > 0.9 AND params.model = 'transformer'`

**F. List Available Resources**

- Input needed: None (or experiment ID for runs)
- Output: Experiments list or runs list
- Time: ~1 minute

**G. Custom Query**

- Describe requirements for guidance through available options

______________________________________________________________________

## 📋 Prerequisites Check

Before proceeding, verify these requirements:

**1. MLflow CLI Installed**

```bash
which mlflow || echo "Install: pip install mlflow"
```

**2. Tracking Server Access**

Choose one credential method:

**Option A: Doppler (Recommended - Zero Exposure)**

```bash
# Verify Doppler secrets exist
doppler secrets --project claude-config --config dev | grep MLFLOW
```

Required secrets:

- `MLFLOW_HOST` (e.g., mlflow.eonlabs.com)
- `MLFLOW_PORT` (e.g., 5000)
- `MLFLOW_USERNAME` (e.g., eonlabs)
- `MLFLOW_PASSWORD` (secure password)

**Option B: Environment Variable**

```bash
export MLFLOW_TRACKING_URI="http://localhost:5000"
# Or for remote with auth:
export MLFLOW_TRACKING_URI="http://user:pass@mlflow.example.com:5000"
```

**3. Connection Test**

```bash
# With Doppler
doppler run --project claude-config --config dev -- bash -c \
  'export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT" && \
   uvx mlflow experiments search' | head -5

# With env var
uvx mlflow experiments search | head -5
```

**Expected**: List of experiments (not an error)


______________________________________________________________________

## Reference Documentation

For detailed information, see:
- [Constraints & Workarounds](./references/constraints-workarounds.md) - MLflow limitations and solutions
- [Workflow Guides](./references/workflow-guides.md) - Step-by-step implementations
- [Security Patterns](./references/security-patterns.md) - Credential management
- [Troubleshooting](./references/troubleshooting.md) - Common errors and fixes
- [Capability Matrix](./references/capability-matrix.md) - Quick reference table
