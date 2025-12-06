**Skill**: [MLflow Query Skill](../SKILL.md)

## 📖 Common Workflows (Guided)

### Workflow A: Find Best Performing Model

**Input Questions:**

1. What experiment ID? (or experiment name)
1. What metric to optimize? (e.g., accuracy, f1_score, loss)
1. Higher is better or lower is better?

**Example:**

```bash
# User inputs:
# - Experiment ID: 1
# - Metric: accuracy
# - Direction: higher is better

# Step 1: List runs ordered by metric
doppler run --project claude-config --config dev -- bash -c \
  'export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT" && \
   uvx mlflow runs list --experiment-id 1' | \
  grep -E "accuracy|run_id" | \
  head -10

# Step 2: Get full details of best run
# (Extract run_id from above, e.g., abc123)
doppler run --project claude-config --config dev -- bash -c \
  'export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT" && \
   uvx mlflow runs describe --run-id abc123'
```

**Output:**

- Run ID
- Accuracy value
- All hyperparameters
- Model artifacts location

### Workflow B: Compare Multiple Runs

**Input Questions:**

1. What experiment ID?
1. What run IDs to compare? (or filter criteria)
1. What fields to compare? (metrics/params/both)

**Example:**

```bash
# User inputs:
# - Experiment ID: 1
# - Run IDs: abc123, def456, ghi789
# - Fields: metrics.accuracy, params.learning_rate, params.batch_size

# Export to CSV for easy comparison
doppler run --project claude-config --config dev -- bash -c \
  'export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT" && \
   uvx mlflow experiments csv --experiment-id 1 --filename /tmp/exp1.csv'

# Filter specific runs
grep -E "abc123|def456|ghi789" /tmp/exp1.csv | \
  awk -F',' '{print $1, $5, $8, $9}'  # Adjust columns as needed
```

### Workflow C: Detect Overfitting

**Input Questions:**

1. What experiment ID?
1. What train metric? (e.g., train_accuracy)
1. What test metric? (e.g., test_accuracy)
1. What gap threshold? (default: 0.05 = 5%)

**Example:**

```bash
# User inputs:
# - Experiment ID: 1
# - Train metric: train_accuracy
# - Test metric: test_accuracy
# - Threshold: 0.05 (5% gap = overfitting)

# Export all runs
doppler run --project claude-config --config dev -- bash -c \
  'export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT" && \
   uvx mlflow experiments csv --experiment-id 1 --filename /tmp/exp1.csv'

# Analyze gaps (awk calculation)
awk -F',' 'NR>1 {
  train=$5; test=$6;  # Adjust column numbers
  gap=train-test;
  if (gap > 0.05) print $1, "Overfitting:", gap
}' /tmp/exp1.csv
```

**Output:**

- Run IDs with overfitting
- Train-test gap values
- Recommendations

### Workflow D: Export Experiment Data

**Input Questions:**

1. What experiment ID?
1. Output format? (CSV recommended for large data)
1. Output location? (default: /tmp/)

**Example:**

```bash
# User inputs:
# - Experiment ID: 1
# - Format: CSV
# - Location: /tmp/crypto_backtest.csv

doppler run --project claude-config --config dev -- bash -c \
  'export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT" && \
   uvx mlflow experiments csv --experiment-id 1 --filename /tmp/crypto_backtest.csv'

# Verify
wc -l /tmp/crypto_backtest.csv
head -3 /tmp/crypto_backtest.csv
```

### Workflow E: Filter Runs by Criteria

**Input Questions:**

1. What experiment ID?
1. Filter conditions? (AND-only, examples provided)
1. How many results? (default: all)

**Valid filter patterns:**

```bash
# Metric filters (use actual metric values)
"metrics.accuracy > 0.9"
"metrics.loss < 0.1"

# Parameter filters (MUST quote values - params are strings!)
"params.model = 'transformer'"
"params.learning_rate = '0.001'"

# Tag filters
"tags.status = 'production'"

# Status filters
"attributes.status = 'FINISHED'"

# Combined (AND-only)
"metrics.accuracy > 0.9 AND params.model = 'transformer'"
```

**Example:**

```bash
# User inputs:
# - Experiment ID: 1
# - Filter: metrics.accuracy > 0.9 AND params.model = 'transformer'

# Note: runs search doesn't support --filter-string, use runs list
doppler run --project claude-config --config dev -- bash -c \
  'export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT" && \
   uvx mlflow runs list --experiment-id 1' | \
  grep transformer | \
  grep -E "accuracy.*0.9[0-9]"  # Adjust pattern for metric values
```

**Note**: For complex filters, export to CSV and use awk/python.

### Workflow F: List Available Resources

**No input needed** - Just explores what's available.

**Example:**

```bash
# List all experiments
doppler run --project claude-config --config dev -- bash -c \
  'export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT" && \
   uvx mlflow experiments search'

# Pick an experiment ID (e.g., 1), list its runs
doppler run --project claude-config --config dev -- bash -c \
  'export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT" && \
   uvx mlflow runs list --experiment-id 1' | head -20

# Pick a run ID, see its details
doppler run --project claude-config --config dev -- bash -c \
  'export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT" && \
   uvx mlflow runs describe --run-id <RUN_ID>'
```

