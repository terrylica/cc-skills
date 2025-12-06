**Skill**: [MLflow Query Skill](../SKILL.md)

## 🔧 Understanding Constraints (MLflow Limitations)

### Constraint 1: AND-Only Filters (No OR)

**❌ This WILL NOT work:**

```bash
mlflow runs search --filter-string "params.status = 'prod' OR params.status = 'staging'"
# Error: Invalid clause(s) in filter string: 'OR'
```

**✅ Workaround - Multiple Queries:**

```bash
# Query 1: Production runs
mlflow runs search --filter-string "params.status = 'prod'" > prod_runs.txt

# Query 2: Staging runs
mlflow runs search --filter-string "params.status = 'staging'" > staging_runs.txt

# Merge results client-side
cat prod_runs.txt staging_runs.txt
```

### Constraint 2: Parameters Are Always Strings

**❌ This WILL NOT work:**

```bash
mlflow runs search --filter-string "params.learning_rate > 0.001"
# Error: Type mismatch (comparing string to number)
```

**✅ Workaround - Quote Values:**

```bash
# Exact match (works)
mlflow runs search --filter-string "params.learning_rate = '0.001'"

# Range queries (need client-side filtering)
mlflow runs search --experiment-id 1 | \
  grep learning_rate | \
  awk -F'|' '$3 > 0.001 {print}'
```

### Constraint 3: No Streaming (Use Pagination)

**❌ No real-time updates:**

```bash
# This returns static snapshot, not live stream
mlflow runs search --experiment-id 1
```

**✅ Workaround - Paginate Large Results:**

```bash
# Get first 100
mlflow runs search --experiment-id 1 --max-results 100

# For more, export to CSV (efficient for large datasets)
mlflow experiments csv --experiment-id 1 --filename results.csv
```

### Constraint 4: Metric History Requires Python API

**❌ CLI doesn't support time-series:**

```bash
# No CLI command for metric history over training steps
```

**✅ Workaround - Python Script:**

```python
#!/usr/bin/env python3
# /// script
# dependencies = ["mlflow>=2.9.0"]
# ///
from mlflow.tracking import MlflowClient

client = MlflowClient()
history = client.get_metric_history(run_id="<RUN_ID>", key="loss")
for entry in history:
    print(f"Step {entry.step}: {entry.value}")
```

Usage: `uv run get_history.py`

