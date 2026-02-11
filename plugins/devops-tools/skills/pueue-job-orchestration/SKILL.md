---
name: pueue-job-orchestration
description: Pueue job queue for long-running tasks on remote GPU workstations. TRIGGERS - run on bigblack, run on littleblack, queue job, long-running task, cache population, batch processing, GPU workstation.
allowed-tools: Read, Bash, Write
---

# Pueue Job Orchestration

> Manage long-running tasks on BigBlack/LittleBlack GPU workstations using Pueue job queue.

## Overview

[Pueue](https://github.com/Nukesor/pueue) is a Rust CLI tool for managing shell command queues. It provides:

- **Daemon persistence** - Survives SSH disconnects, crashes, reboots
- **Disk-backed queue** - Auto-resumes after any failure
- **Group-based parallelism** - Control concurrent jobs per group
- **Easy failure recovery** - Restart failed jobs with one command

## When to Use This Skill

Use this skill when the user mentions:

| Trigger                               | Example                                    |
| ------------------------------------- | ------------------------------------------ |
| Running tasks on BigBlack/LittleBlack | "Run this on bigblack"                     |
| Long-running data processing          | "Populate the cache for all symbols"       |
| Batch/parallel operations             | "Process these 70 jobs"                    |
| SSH remote execution                  | "Execute this overnight on the GPU server" |
| Cache population                      | "Fill the ClickHouse cache"                |

## Quick Reference

### Check Status

```bash
# Local
pueue status

# Remote (BigBlack)
ssh bigblack "~/.local/bin/pueue status"
```

### Queue a Job

```bash
# Local
pueue add -- python long_running_script.py

# Remote (BigBlack)
ssh bigblack "~/.local/bin/pueue add -- cd ~/project && uv run python script.py"

# With group (for parallelism control)
pueue add --group p1 --label "BTCUSDT@1000" -- python populate.py --symbol BTCUSDT
```

### Monitor Jobs

```bash
pueue follow <id>         # Watch job output in real-time
pueue log <id>            # View completed job output
pueue log <id> --full     # Full output (not truncated)
```

### Manage Jobs

```bash
pueue restart <id>        # Restart failed job
pueue restart --all-failed # Restart ALL failed jobs
pueue kill <id>           # Kill running job
pueue clean               # Remove completed jobs from list
pueue reset               # Clear all jobs (use with caution)
```

## Host Configuration

| Host          | Location                  | Parallelism Groups             |
| ------------- | ------------------------- | ------------------------------ |
| BigBlack      | `~/.local/bin/pueue`      | p1 (4), p2 (2), p3 (3), p4 (1) |
| LittleBlack   | `~/.local/bin/pueue`      | default (2)                    |
| Local (macOS) | `/opt/homebrew/bin/pueue` | default                        |

## Workflows

### 1. Queue Single Remote Job

```bash
# Step 1: Verify daemon is running
ssh bigblack "~/.local/bin/pueue status"

# Step 2: Queue the job
ssh bigblack "~/.local/bin/pueue add --label 'my-job' -- cd ~/project && uv run python script.py"

# Step 3: Monitor progress
ssh bigblack "~/.local/bin/pueue follow <id>"
```

### 2. Batch Job Submission (Multiple Symbols)

For rangebar cache population or similar batch operations:

```bash
# Use the pueue-populate.sh script
ssh bigblack "cd ~/rangebar-py && ./scripts/pueue-populate.sh setup"   # One-time
ssh bigblack "cd ~/rangebar-py && ./scripts/pueue-populate.sh phase1"  # Queue Phase 1
ssh bigblack "cd ~/rangebar-py && ./scripts/pueue-populate.sh status"  # Check progress
```

### 3. Configure Parallelism Groups

```bash
# Create groups with different parallelism limits
pueue group add fast      # Create 'fast' group
pueue parallel 4 --group fast  # Allow 4 parallel jobs

pueue group add slow
pueue parallel 1 --group slow  # Sequential execution

# Queue jobs to specific groups
pueue add --group fast -- echo "fast job"
pueue add --group slow -- echo "slow job"
```

### 4. Handle Failed Jobs

```bash
# Check what failed
pueue status | grep Failed

# View error output
pueue log <id>

# Restart specific job
pueue restart <id>

# Restart all failed jobs
pueue restart --all-failed
```

## Installation

### macOS (Local)

```bash
brew install pueue
pueued -d  # Start daemon
```

### Linux (BigBlack/LittleBlack)

```bash
# Download from GitHub releases (see https://github.com/Nukesor/pueue/releases for latest)
curl -sSL https://raw.githubusercontent.com/terrylica/rangebar-py/main/scripts/setup-pueue-linux.sh | bash

# Or manually:
# SSoT-OK: Version from GitHub releases page
PUEUE_VERSION="v4.0.2"
curl -sSL "https://github.com/Nukesor/pueue/releases/download/${PUEUE_VERSION}/pueue-x86_64-unknown-linux-musl" -o ~/.local/bin/pueue
curl -sSL "https://github.com/Nukesor/pueue/releases/download/${PUEUE_VERSION}/pueued-x86_64-unknown-linux-musl" -o ~/.local/bin/pueued
chmod +x ~/.local/bin/pueue ~/.local/bin/pueued

# Start daemon
~/.local/bin/pueued -d
```

### Systemd Auto-Start (Linux)

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/pueued.service << 'EOF'
[Unit]
Description=Pueue Daemon
After=network.target

[Service]
ExecStart=%h/.local/bin/pueued -v
Restart=on-failure

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now pueued
```

## Integration with rangebar-py

The rangebar-py project has Pueue integration scripts:

| Script                           | Purpose                                                  |
| -------------------------------- | -------------------------------------------------------- |
| `scripts/pueue-populate.sh`      | Queue cache population jobs with group-based parallelism |
| `scripts/setup-pueue-linux.sh`   | Install Pueue on Linux servers                           |
| `scripts/populate_full_cache.py` | Python script for individual symbol/threshold jobs       |

### Phase-Based Execution

```bash
# Phase 1: 1000 dbps (fast, 4 parallel)
./scripts/pueue-populate.sh phase1

# Phase 2: 250 dbps (moderate, 2 parallel)
./scripts/pueue-populate.sh phase2

# Phase 3: 500, 750 dbps (3 parallel)
./scripts/pueue-populate.sh phase3

# Phase 4: 100 dbps (resource intensive, 1 at a time)
./scripts/pueue-populate.sh phase4
```

## Troubleshooting

| Issue                      | Cause                    | Solution                              |
| -------------------------- | ------------------------ | ------------------------------------- |
| `pueue: command not found` | Not in PATH              | Use full path: `~/.local/bin/pueue`   |
| `Connection refused`       | Daemon not running       | Start with `pueued -d`                |
| Jobs stuck in Queued       | Group paused or at limit | Check `pueue status`, `pueue start`   |
| SSH disconnect kills jobs  | Not using Pueue          | Queue via Pueue instead of direct SSH |
| Job fails immediately      | Wrong working directory  | Use `cd /path && command` pattern     |

## Production Lessons (Issue #88)

Battle-tested patterns from real production deployments.

### Dependency Chaining with `--after`

Pueue supports automatic job dependency resolution via `--after`. This is critical for post-processing pipelines where steps must run sequentially after batch jobs complete.

**Key flags:**

- `--after <id>...` -- Start job only after ALL specified jobs succeed. If any dependency fails, this job fails too.
- `--print-task-id` (or `-p`) -- Return only the numeric job ID (for scripting).

**Pattern: Capturing job IDs for dependency wiring**

```bash
# Capture job IDs during batch submission
JOB_IDS=()
for symbol in BTCUSDT ETHUSDT; do
    job_id=$(pueue add --print-task-id --group mygroup \
        --label "${symbol}@250" \
        --working-directory /path/to/project \
        -- uv run python scripts/process.py --symbol "$symbol")
    JOB_IDS+=("$job_id")
done

# Chain post-processing after ALL batch jobs
optimize_id=$(pueue add --print-task-id --group mygroup \
    --label "optimize-table" \
    --after "${JOB_IDS[@]}" \
    -- clickhouse-client --query "OPTIMIZE TABLE mydb.mytable FINAL")

# Chain validation after optimize
pueue add --group mygroup \
    --label "validate" \
    --after "$optimize_id" \
    -- uv run python scripts/validate.py
```

**Result in pueue status:**

```
Job 0  BTCUSDT@250    Running
Job 1  ETHUSDT@250    Running
Job 2  optimize-table Queued  Deps: 0, 1
Job 3  validate       Queued  Deps: 2
```

**When to use `--after`:**

- Post-processing steps (OPTIMIZE TABLE, validation scripts, cleanup)
- Multi-stage pipelines where Stage N depends on Stage N-1
- Verification jobs that should only run after data is fully written

**Anti-pattern: Manual waiting**

```bash
# BAD: Manual polling or instructions to "run this after that finishes"
postprocess_all() {
    queue_repopulation_jobs
    echo "Run 'pueue wait --group postfix' then run optimize manually"  # NO!
}

# GOOD: Automatic dependency chain
postprocess_all() {
    queue_repopulation_jobs  # captures JOB_IDS
    pueue add --after "${JOB_IDS[@]}" -- optimize_command
    pueue add --after "$optimize_id" -- validate_command
}
```

### Mise Task to Pueue Pipeline Integration

Pattern for `mise run` commands that build pueue DAGs:

```toml
# .mise/tasks/cache.toml
["cache:postprocess-all"]
description = "Full post-fix pipeline via pueue: repopulate -> optimize -> detect (auto-chained)"
run = "./scripts/pueue-populate.sh postprocess-all"
```

The shell script captures pueue job IDs and chains them with `--after`. Mise provides the entry point; pueue provides the execution engine with dependency resolution.

### Forensic Audit Before Deployment

ALWAYS audit the remote host before mutating anything:

```bash
# 1. Pueue job state
ssh host 'pueue status'
ssh host 'pueue status --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(sum(1 for t in d[\"tasks\"].values() if \"Running\" in str(t[\"status\"])))"'

# 2. Database state (ClickHouse example)
ssh host 'clickhouse-client --query "SELECT symbol, threshold, count(), countIf(volume < 0) FROM mytable GROUP BY ALL"'

# 3. Checkpoint state
ssh host 'ls -la ~/.cache/myapp/checkpoints/'
ssh host 'cat ~/.cache/myapp/checkpoints/latest.json'

# 4. System resources
ssh host 'uptime && free -h && df -h /home'

# 5. Installed version
ssh host 'cd ~/project && git log --oneline -1'
```

### Force-Refresh vs Checkpoint Resume

Decision matrix for restarting killed/failed jobs:

| Scenario                                     | Action                 | Flag                 |
| -------------------------------------------- | ---------------------- | -------------------- |
| Job killed mid-run, data is clean            | Resume from checkpoint | (no --force-refresh) |
| Data is corrupt (overflow, schema bug)       | Wipe and restart       | --force-refresh      |
| Code fix changes output format               | Wipe and restart       | --force-refresh      |
| Code fix is internal-only (no output change) | Resume from checkpoint | (no --force-refresh) |

### PATH Gotcha: Rust Not in PATH via `uv run`

On remote hosts, `uv run maturin develop` may fail because `~/.cargo/bin` is not in `uv run`'s PATH:

```bash
# FAILS: rustc not found
ssh host 'cd ~/project && uv run maturin develop --uv'

# WORKS: Prepend cargo bin to PATH
ssh host 'cd ~/project && PATH="$HOME/.cargo/bin:$PATH" uv run maturin develop --uv'
```

For pueue jobs that need Rust compilation:

```bash
pueue add -- env PATH="/home/user/.cargo/bin:$PATH" uv run maturin develop
```

### Per-Year (Epoch) Parallelization

When a processing pipeline has natural reset boundaries (yearly, monthly, etc.) where processor state resets, each epoch becomes an independent processing unit. This enables massive speedup by splitting a multi-year sequential job into concurrent per-year pueue jobs.

**Why it's safe** (three isolation layers):

| Layer            | Why No Conflicts                                                 |
| ---------------- | ---------------------------------------------------------------- |
| Checkpoint files | Filename includes `{start}_{end}` — each year gets unique file   |
| Database writes  | INSERT is append-only; `OPTIMIZE TABLE FINAL` deduplicates after |
| Source data      | Read-only files (Parquet, CSV, etc.) — no write contention       |

**Pattern: Per-symbol pueue groups**

Give each symbol (or job family) its own pueue group for independent parallelism control:

```bash
# Create per-symbol groups
pueue group add btc-yearly --parallel 4
pueue group add eth-yearly --parallel 4
pueue group add shib-yearly --parallel 4

# Queue per-year jobs
for year in 2019 2020 2021 2022 2023 2024 2025 2026; do
    pueue add --group btc-yearly \
        --label "BTC@250:${year}" \
        -- uv run python scripts/process.py \
        --symbol BTCUSDT --threshold 250 \
        --start-date "${year}-01-01" --end-date "${year}-12-31"
done

# Chain post-processing after ALL groups complete
ALL_JOB_IDS=($(pueue status --json | jq -r \
    '.tasks | to_entries[] | select(.value.group | test("-yearly$")) | .value.id'))
pueue add --after "${ALL_JOB_IDS[@]}" \
    --label "optimize-table:final" \
    -- clickhouse-client --query "OPTIMIZE TABLE mydb.mytable FINAL"
```

**When to use per-year vs sequential:**

| Scenario                                | Approach                 |
| --------------------------------------- | ------------------------ |
| High-volume symbol (many output items)  | Per-year (5+ cores idle) |
| Low-volume symbol (fast enough already) | Sequential (simpler)     |
| Single parameter, long backfill         | Per-year                 |
| Multiple parameters, same symbol        | Sequential per parameter |

**Critical rules:**

1. First year uses domain-specific effective start date, not `01-01`
2. Last year uses actual latest available date as end
3. Chain `OPTIMIZE TABLE FINAL` after ALL year-jobs via `--after`
4. Memory budget: each job peaks independently — with 61 GB total, 4-5 concurrent jobs at 5 GB each are safe

### Pipeline Monitoring (Group-Based Phase Detection)

For multi-group pipelines, monitor job phases by **group completion**, not hardcoded job IDs. Job IDs change when jobs are removed, re-queued, or split into per-year jobs.

**Anti-pattern: Hardcoded job IDs in monitors**

```bash
# WRONG: Breaks when jobs are removed/re-queued
job14=$(echo "$JOBS" | grep "^14|")
if [ "$(echo "$job14" | cut -d'|' -f2)" = "Done" ]; then
    echo "Phase 1 complete"
fi
```

**Correct pattern: Dynamic group detection**

```bash
get_job_status() {
    ssh host "pueue status --json 2>/dev/null" | jq -r \
        '.tasks | to_entries[] |
         "\(.value.id)|\(.value.status | if type == "object" then keys[0] else . end)|\(.value.label // "-")|\(.value.group)"'
}

group_all_done() {
    local group="$1"
    local group_jobs
    group_jobs=$(echo "$JOBS" | grep "|${group}$" || true)
    [ -z "$group_jobs" ] && return 1
    echo "$group_jobs" | grep -qE "\|(Running|Queued)\|" && return 1
    return 0
}

# Detect phase transitions by group name
SEEN_GROUPS=""
for group in $(echo "$JOBS" | cut -d'|' -f4 | sort -u); do
    if group_all_done "$group" && [[ "$SEEN_GROUPS" != *"|${group}|"* ]]; then
        echo "GROUP COMPLETE: $group"
        run_integrity_checks "$group"
        SEEN_GROUPS="${SEEN_GROUPS}|${group}|"
    fi
done
```

**Integrity checks at phase boundaries:**

Run automated validation when a group finishes, before starting the next phase:

```bash
run_integrity_checks() {
    local phase="$1"
    # Check 1: Data corruption (negative values, out-of-bounds)
    ssh host 'clickhouse-client --query "SELECT ... countIf(value < 0) ... HAVING count > 0"'
    # Check 2: Duplicate rows
    ssh host 'clickhouse-client --query "SELECT ... count(*) - uniqExact(key) as dupes HAVING dupes > 0"'
    # Check 3: Coverage gaps (NULL required fields)
    ssh host 'clickhouse-client --query "SELECT ... countIf(field IS NULL) ... HAVING missing > 0"'
    # Check 4: System resources (load, memory)
    ssh host 'uptime && free -h'
}
```

**Monitoring as a background loop:**

```bash
POLL_INTERVAL=300  # 5 minutes
while true; do
    JOBS=$(get_job_status)
    # Count statuses, detect failures, detect group completions
    # Run integrity checks at phase boundaries
    # Exit when all jobs complete
    sleep "$POLL_INTERVAL"
done
```

## Related

- **Hook**: `itp-hooks/posttooluse-reminder.ts` - Reminds to use Pueue for detected long-running commands
- **Reference**: [Pueue GitHub](https://github.com/Nukesor/pueue)
- **Issue**: [rangebar-py#77](https://github.com/terrylica/rangebar-py/issues/77) - Original implementation
- **Issue**: [rangebar-py#88](https://github.com/terrylica/rangebar-py/issues/88) - Production deployment lessons
