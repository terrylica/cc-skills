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

| Host          | Location                  | Parallelism Groups              |
| ------------- | ------------------------- | ------------------------------- |
| BigBlack      | `~/.local/bin/pueue`      | p1 (16), p2 (2), p3 (3), p4 (1) |
| LittleBlack   | `~/.local/bin/pueue`      | default (2)                     |
| Local (macOS) | `/opt/homebrew/bin/pueue` | default                         |

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

| Issue                      | Cause                    | Solution                                                          |
| -------------------------- | ------------------------ | ----------------------------------------------------------------- |
| `pueue: command not found` | Not in PATH              | Use full path: `~/.local/bin/pueue`                               |
| `Connection refused`       | Daemon not running       | Start with `pueued -d`                                            |
| Jobs stuck in Queued       | Group paused or at limit | Check `pueue status`, `pueue start`                               |
| SSH disconnect kills jobs  | Not using Pueue          | Queue via Pueue instead of direct SSH                             |
| Job fails immediately      | Wrong working directory  | Use `cd /path && pueue add` (see AP-11 in distributed-job-safety) |

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
    job_id=$(cd /path/to/project && pueue add --print-task-id --group mygroup \
        --label "${symbol}@250" \
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

### Per-Year (Epoch) Parallelization — DEFAULT STRATEGY

**This is the default approach for all multi-year cache population.** Never queue a monolithic multi-year job when epoch boundaries exist. A single DOGEUSDT@500 job estimated 22 days; per-year splits brought it to ~3-4 days with 4 parallel cores.

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

1. **Working directory**: Always `cd ~/project &&` before `pueue add` — SSH cwd defaults to `$HOME`, not the project directory. Jobs fail instantly with `No such file or directory` if this is missed.
2. First year uses domain-specific effective start date, not `01-01`
3. Last year uses actual latest available date as end
4. Chain `OPTIMIZE TABLE FINAL` after ALL year-jobs via `--after`
5. Memory budget: each job peaks independently — with 61 GB total, 4-5 concurrent jobs at 5 GB each are safe
6. **No `--force-refresh` on per-year jobs** when other year-jobs for the same symbol are running — it deletes cached bars by date range and can conflict with concurrent writes.

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

## State File Management (CRITICAL)

Pueue stores ALL task metadata in a single `state.json` file. This file grows with every completed task and is read/written on EVERY `pueue add` call. Neglecting state hygiene is the #1 cause of slow job submission in large sweeps.

### The State Bloat Anti-Pattern

**Symptom**: `pueue add` takes 1-2 seconds instead of <100ms.

**Root cause**: Pueue serializes/deserializes the entire state file on every operation. With 50K+ completed tasks, `state.json` grows to 80-100MB. Each `pueue add` becomes 80MB read + 80MB write = 160MB I/O.

**Benchmarks** (pueue v4, NVMe SSD, 32-core Linux):

| Completed Tasks | state.json Size | `pueue add` Latency (sequential) | `pueue add` Latency (xargs -P16) |
| --------------- | --------------- | -------------------------------- | -------------------------------- |
| 53,000          | 94 MB           | 1,300 ms/add                     | 455 ms/add (mutex contention)    |
| 0 (after clean) | 245 KB          | 106 ms/add                       | 8 ms/add (effective)             |

**Key insight**: Parallelism does NOT help when state is bloated — the pueue daemon serializes all operations through a mutex. The 455ms at P16 is WORSE per-operation than 1,300ms sequential because of lock contention overhead. **Clean first, then parallelize.**

### Pre-Submission Clean (Mandatory Pattern)

Before any bulk submission (>100 jobs), clean completed tasks:

```bash
# ALWAYS clean before bulk submission
pueue clean -g mygroup 2>/dev/null || true

# Verify state is manageable
STATE_FILE="$HOME/.local/share/pueue/state.json"
STATE_SIZE=$(stat -c%s "$STATE_FILE" 2>/dev/null || stat -f%z "$STATE_FILE" 2>/dev/null || echo 0)
if [ "$STATE_SIZE" -gt 52428800 ]; then  # 50MB
    echo "WARNING: state.json is $(( STATE_SIZE / 1048576 ))MB — running extra clean"
    pueue clean 2>/dev/null || true
fi
```

### Periodic Clean During Long Sweeps

For sweeps with 100K+ jobs, clean periodically between submission batches:

```bash
BATCH_SIZE=5000
POS=0
while [ "$POS" -lt "$TOTAL" ]; do
    # Submit batch
    tail -n +$((POS + 1)) "$CMDFILE" | head -n "$BATCH_SIZE" | \
        xargs -P16 -I{} bash -c '{}' 2>/dev/null || true
    POS=$((POS + BATCH_SIZE))

    # Prevent state bloat between batches
    pueue clean -g mygroup 2>/dev/null || true
done
```

---

## Bulk Submission with xargs -P (High-Throughput Pattern)

For large job counts (1K+), submitting one `pueue add` at a time via SSH is prohibitively slow. Use a **batch command file** fed through `xargs -P` for parallel submission.

### Why Not GNU Parallel?

**CRITICAL**: Many Linux hosts (including Ubuntu/Debian) ship with **moreutils `parallel`**, NOT **GNU Parallel**. They share the binary name `/usr/bin/parallel` but are completely different tools:

| Feature            | GNU Parallel                     | moreutils parallel         |
| ------------------ | -------------------------------- | -------------------------- |
| Job file           | `--jobs 16 --bar < commands.txt` | Not supported              |
| Progress bar       | `--bar`, `--eta`                 | None                       |
| Resume             | `--resume --joblog log.txt`      | Not supported              |
| Syntax             | `parallel ::: arg1 arg2`         | `parallel -- cmd1 -- cmd2` |
| `--version` output | `GNU parallel YYYY`              | `parallel from moreutils`  |

**Detection**:

```bash
if parallel --version 2>&1 | grep -q 'GNU'; then
    echo "GNU Parallel available"
else
    echo "moreutils parallel (or none) — use xargs -P instead"
fi
```

**Safe default**: Always use `xargs -P` — it's POSIX standard and available everywhere.

### Batch Command File Pattern

**Step 1: Generate commands file** (one `pueue add` per line):

```bash
# gen_commands.sh — generates commands.txt
for SQL_FILE in /tmp/sweep_sql/*.sql; do
    echo "pueue add -g p1 -- /tmp/run_job.sh '${SQL_FILE}' '${LOG_FILE}'"
done > /tmp/commands.txt
echo "Generated $(wc -l < /tmp/commands.txt) commands"
```

**Step 2: Feed via xargs -P** (parallel submission):

```bash
# Submit in batches with periodic state cleanup
BATCH=5000
P=16
TOTAL=$(wc -l < /tmp/commands.txt)
POS=0

while [ "$POS" -lt "$TOTAL" ]; do
    tail -n +$((POS + 1)) /tmp/commands.txt | head -n "$BATCH" | \
        xargs -P"$P" -I{} bash -c '{}' 2>/dev/null || true
    POS=$((POS + BATCH))

    # Clean between batches to prevent state bloat
    pueue clean -g p1 2>/dev/null || true

    QUEUED=$(pueue status -g p1 --json 2>/dev/null | python3 -c \
        "import json,sys; d=json.load(sys.stdin); print(sum(1 for t in d.get('tasks',{}).values() if 'Queued' in str(t.get('status',''))))" 2>/dev/null || echo "?")
    echo "Batch: ${POS}/${TOTAL} | Queued: ${QUEUED}"
done
```

### Crash Recovery with Skip-Done

For idempotent resubmission after SSH drops or crashes:

```bash
# Build done-set from existing JSONL output
declare -A DONE_SET
for logfile in /tmp/sweep_*.jsonl; do
    while IFS= read -r config_id; do
        DONE_SET["${config_id}"]=1
    done < <(jq -r '.feature_config // empty' "$logfile" 2>/dev/null | sort -u)
done

# Generate commands, skipping completed configs
for SQL_FILE in /tmp/sweep_sql/*.sql; do
    CONFIG_ID=$(basename "$SQL_FILE" .sql)
    if [ "${DONE_SET[${CONFIG_ID}]+_}" ]; then
        continue  # Already completed
    fi
    echo "pueue add -g p1 -- /tmp/run_job.sh '${SQL_FILE}' '${LOG_FILE}'"
done > /tmp/commands.txt
```

**Requirements**: bash 4+ for associative arrays (`declare -A`).

---

## Two-Tier Architecture (300K+ Jobs)

For sweeps exceeding 10K queries, the single-tier "pueue add per query" pattern is unusable — `pueue add` has 148ms overhead per call even with clean state (= 8+ hours for 196K jobs). The fix is eliminating `pueue add` at the query level entirely.

### Architecture

```
macOS (local)
  mise run gen:generate   → N SQL files
  mise run gen:submit-all → rsync + queue M pueue units
  mise run gen:collect    → scp + validate JSONL

BigBlack (remote)
  pueue group p1 (parallel=1)   ← sequential units (avoid log contention)
    ├── Unit 1: submit_unit.sh pattern1 BTCUSDT 750
    │     └── xargs -P16 → K queries (direct clickhouse-client, no pueue add)
    ├── Unit 2: submit_unit.sh pattern1 BTCUSDT 1000
    │     └── xargs -P16 → K queries
    └── ... (M total units)
```

### Key Principles

| Principle                                      | Rationale                                                                      |
| ---------------------------------------------- | ------------------------------------------------------------------------------ |
| Pueue at **unit** level (100s of tasks)        | Crash recovery per unit, `pueue status` readable                               |
| xargs -P16 at **query** level (1000s per unit) | Zero overhead, direct process execution                                        |
| Sequential units (`parallel=1`)                | Each unit appends to one JSONL file via `flock` — parallel units would contend |
| Skip-done dedup inside each unit               | `comm -23` on sorted config lists (O(N+M))                                     |

### When to Use Each Tier

| Job Count | Pattern                                                              |
| --------- | -------------------------------------------------------------------- |
| 1-10      | Direct `pueue add` per job                                           |
| 10-1K     | Batch `pueue add` via xargs -P (see "Bulk Submission" section above) |
| 1K-10K    | Batch `pueue add` with periodic `pueue clean` between batches        |
| **10K+**  | **Two-tier: pueue per unit + xargs -P per query (this section)**     |

### Shell Script Safety (set -euo pipefail)

| Trap                    | Symptom                                                                | Fix                                                           |
| ----------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------- |
| SIGPIPE (exit 141)      | `ls path/*.sql \| head -10` — `head` closes pipe early                 | Write to temp file first, or use `find -print0 \| head -z`    |
| Pipe subshell data loss | `echo "$OUT" \| while read ...; done > file` — writes lost in subshell | Process substitution: `while read ...; done < <(echo "$OUT")` |
| eval injection          | `eval "val=\$$var"` with untrusted input                               | Use `case` statement or parameter expansion instead           |

### Skipped Config NDJSON Pattern

Configs with 0 signals after feature filtering produce **1 JSONL line** (skipped entry), not N barrier lines. This is correct behavior, not data loss.

When validating line counts:

```
expected_lines = (N_normal × barriers_per_query) + (N_skipped × 1) + (N_error × 1)
```

Example: 95 normal configs × 3 barriers + 5 skipped × 1 = 290 lines (not 300).

### comm -23 for Large Skip-Done Sets (100K+)

For done-sets exceeding 10K entries, `comm -23` (sorted set difference) is O(N+M) vs grep-per-file O(N×M):

```bash
# Build sorted done-set from JSONL
python3 -c "
import json
seen = set()
for line in open('\${LOG_FILE}'):
    try:
        d = json.loads(line)
        fc = d.get('feature_config','')
        if fc: seen.add(fc)
    except: pass
for s in sorted(seen): print(s)
" > /tmp/done.txt

# Build sorted all-configs, compute set difference
ls \${DIR}/*.sql | xargs -n1 basename | sed 's/\.sql$//' | sort > /tmp/all.txt
comm -23 /tmp/all.txt /tmp/done.txt > /tmp/todo.txt

# Submit remaining via xargs
cat /tmp/todo.txt | while read C; do echo "\${DIR}/\${C}.sql"; done | \
    xargs -P16 -I{} bash /tmp/wrapper.sh {} \${LOG} \${SYM} \${THR} \${GIT}
```

---

## ClickHouse Parallelism Tuning (pueue + ClickHouse)

When using pueue to orchestrate ClickHouse queries, the interaction between pueue parallelism and ClickHouse's thread scheduler determines actual throughput.

### The Thread Soft Limit

ClickHouse has a `concurrent_threads_soft_limit_ratio_to_cores` setting (default: 2). On a 32-core machine, this means ClickHouse allows **64 concurrent execution threads** total, regardless of how many queries are running.

Each query requests `max_threads` threads (default: auto = nproc = 32 on a 32-core machine). With 8 parallel queries each requesting 32 threads (= 256 requested), ClickHouse throttles to 64 actual threads. **The queries get ~8 effective threads each, not 32.**

### Right-Size `max_threads` Per Query

**Anti-pattern**: Letting each query request 32 threads when it only gets 8 effective threads. This creates scheduling overhead for no benefit.

**Fix**: Set `--max_threads` to match the effective thread count:

```bash
# In the job wrapper script:
clickhouse-client --max_threads=8 --multiquery < "$SQL_FILE"
```

This reduces thread scheduling overhead and allows higher pueue parallelism without oversubscription.

### Parallelism Sizing Formula

```
effective_threads_per_query = concurrent_threads_soft_limit / pueue_parallel_slots
concurrent_threads_soft_limit = nproc * concurrent_threads_soft_limit_ratio_to_cores

# Example: 32-core machine, ratio=2, soft_limit=64
# 8 pueue slots  → 8 effective threads/query  → ~55% CPU (baseline)
# 16 pueue slots → 4 effective threads/query  → ~87% CPU (1.5-1.8x throughput)
# 24 pueue slots → 2-3 effective threads/query → ~95% CPU (diminishing returns)
```

### Decision Matrix

| Dimension     | Check                                         | Safe Threshold                     |
| ------------- | --------------------------------------------- | ---------------------------------- |
| **Memory**    | p99 per-query × N slots < server memory limit | < 50% of `max_server_memory_usage` |
| **CPU**       | Load average < 90% of nproc                   | load < 0.9 × nproc                 |
| **I/O**       | `iostat` disk utilization                     | < 70%                              |
| **Swap**      | `vmstat` si/so columns                        | Must be 0                          |
| **CH errors** | `system.query_log` ExceptionWhileProcessing   | Must be 0                          |

### Live Tuning (No Restart Required)

Pueue parallelism can be changed live — running jobs finish with old settings, new jobs use the new limit:

```bash
# Check current
pueue group | grep mygroup

# Bump up
pueue parallel 16 -g mygroup

# Monitor for 2-3 minutes, then check
uptime                    # Load average
free -h                   # Memory
vmstat 1 3                # Swap (si/so = 0?)
clickhouse-client --query "SELECT count() FROM system.query_log
    WHERE event_time > now() - INTERVAL 5 MINUTE
    AND type = 'ExceptionWhileProcessing'"  # Errors = 0?
```

---

## Related

- **Hook**: `itp-hooks/posttooluse-reminder.ts` - Reminds to use Pueue for detected long-running commands
- **Reference**: [Pueue GitHub](https://github.com/Nukesor/pueue)
- **Issue**: [rangebar-py#77](https://github.com/terrylica/rangebar-py/issues/77) - Original implementation
- **Issue**: [rangebar-py#88](https://github.com/terrylica/rangebar-py/issues/88) - Production deployment lessons
