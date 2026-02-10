# Deployment Checklist

Step-by-step protocol for deploying code changes to a remote host running pueue jobs.

**Critical principle**: AUDIT before MUTATE. Never modify running state without understanding it first.

---

## Pre-Deployment Audit

Run BEFORE any code changes on the remote host.

```bash
# 1. Count running/queued/failed jobs
ssh host 'pueue status --json' | python3 -c "
import json, sys
data = json.load(sys.stdin)
tasks = data.get('tasks', {})
states = {'Running': 0, 'Queued': 0, 'Success': 0, 'Failed': 0}
for t in tasks.values():
    status = t.get('status', '')
    if isinstance(status, dict):
        key = list(status.keys())[0]
        if key == 'Done':
            result = status['Done'].get('result', '')
            if result == 'Success' or (isinstance(result, dict) and 'Success' in result):
                states['Success'] += 1
            else:
                states['Failed'] += 1
        else:
            states[key] = states.get(key, 0) + 1
print(states)
"

# 2. List active job labels (what's actually running)
ssh host 'pueue status --json' | jq -r '
  [.tasks[] | select(.status | keys[0] == "Running") | .label] | .[]
'

# 3. Check for stale checkpoints
ssh host 'ls -la ~/.cache/myapp/checkpoints/'
```

---

## Forensic Database Audit

Before deployment, audit the database for corruption that the fix addresses:

```bash
# ClickHouse: Check for corruption indicators
ssh host "clickhouse-client --query \"
  SELECT symbol, threshold,
    count() as rows,
    countIf(value < 0) as neg_values,
    round(countIf(value < 0) * 100.0 / count(), 2) as pct_corrupt
  FROM mydb.mytable
  GROUP BY symbol, threshold
  HAVING neg_values > 0
  ORDER BY symbol, threshold
  FORMAT PrettyCompact\""
```

This baseline is critical for:

1. Confirming the scope of corruption (which items/parameters affected)
2. Deciding which jobs need `--force-refresh` vs checkpoint resume
3. Post-deployment verification (expect zero corrupt rows after reprocessing)

---

## Decision Matrix

| Running Jobs | Failed Jobs | Action                                                                                    |
| ------------ | ----------- | ----------------------------------------------------------------------------------------- |
| 0            | 0           | Safe to deploy and requeue                                                                |
| 0            | >0          | Deploy fix, then restart failed jobs                                                      |
| >0           | 0           | Wait for completion, OR deploy + let running finish with old code                         |
| >0           | >0          | Deploy fix, restart failed, let running finish (new code only affects new/restarted jobs) |

**Never**: Kill running jobs and immediately requeue without cleaning up checkpoints.

---

## Force-Refresh vs Checkpoint Resume

When restarting jobs after a code upgrade, choose based on data integrity:

| Scenario                           | Action         | Flag              | Example                                          |
| ---------------------------------- | -------------- | ----------------- | ------------------------------------------------ |
| Job killed mid-run, data is clean  | Resume         | (none)            | DOGEUSDT killed for upgrade, checkpoint intact   |
| Data is corrupt (overflow, schema) | Wipe + restart | `--force-refresh` | Items with negative values from integer overflow |
| Code fix changes output format     | Wipe + restart | `--force-refresh` | New columns added, existing data missing them    |
| Code fix is internal-only          | Resume         | (none)            | Optimization, logging changes                    |

**Critical**: Jobs with clean checkpoints should NOT use `--force-refresh` -- it deletes the checkpoint and all cached data, losing hours/days of progress.

```bash
# Clean data, just upgrade -- resume from checkpoint
pueue add --label "DOGEUSDT@250" -- uv run python process.py --symbol DOGEUSDT --threshold 250

# Corrupt data -- wipe and restart
pueue add --label "ITEM@250" -- uv run python process.py --symbol ITEM --threshold 250 --force-refresh
```

---

## Deployment Steps

### Step 1: Pull Code

```bash
ssh host 'cd ~/project && git fetch origin main && git reset --hard origin/main'
```

**Verify**: Check the commit hash matches expected release.

```bash
ssh host 'cd ~/project && git log --oneline -1'
```

### Step 2: Upgrade Package (if non-editable env exists)

```bash
# For project .venv (editable source, updated by git pull)
# No action needed - uv run reads from working tree

# For standalone .venv (non-editable, needs pip upgrade)
ssh host 'cd ~/project && uv pip install --python .venv/bin/python --refresh mypkg==<version>'
```

### Step 3: Verify Fix Is Active

Use `inspect.getsource()` to confirm the deployed code contains the expected fix:

```bash
ssh host 'cd ~/project && .venv/bin/python -c "
import inspect, mypkg.checkpoint as cp
src = inspect.getsource(cp.get_checkpoint_path)
assert \"threshold\" in src, \"FIX NOT APPLIED: threshold not in checkpoint path\"
print(\"OK: fix verified\")
"'
```

**Adapt the assertion** to match whatever the fix changes. The key pattern is: inspect the source code of the fixed function and assert the fix signature is present.

### Step 4: Handle Failed Jobs

```bash
# Option A: Add fresh replacement job (preferred)
ssh host 'pueue add --group mygroup --label "SYMBOL@THRESHOLD-retry" -- <command>'

# Option B: Restart in-place (may show stale logs -- see AP-3)
ssh host 'pueue restart <job_id>'
```

### Step 5: Monitor

```bash
# Watch specific job
ssh host 'pueue follow <job_id>'

# Periodic status check
ssh host 'pueue status --group mygroup'
```

---

## Post-Deployment Verification

After all jobs complete:

```bash
# 1. Check for failures
ssh host 'pueue status --json' | jq '[.tasks[] | select(.status.Done.result != "Success")] | length'

# 2. Run domain-specific validation script
ssh host 'cd ~/project && uv run python scripts/validate.py'

# 3. Clean up completed jobs
ssh host 'pueue clean'
```

---

## Emergency: Killing All Jobs

If absolutely necessary (corrupted state, runaway processes):

```bash
# 1. Kill all running jobs
ssh host 'pueue kill --all'

# 2. Remove all jobs from queue
ssh host 'pueue clean'
ssh host 'pueue status --json' | jq -r '.tasks | keys[]' | while read id; do
    ssh host "pueue remove $id"
done

# 3. Clean stale checkpoints
ssh host 'rm -f ~/.cache/myapp/checkpoints/*.json'

# 4. Unpause groups (pueue kill pauses groups as safety measure)
ssh host 'pueue start --all'
```

**After emergency cleanup**: Deploy fresh code, then requeue from scratch.
