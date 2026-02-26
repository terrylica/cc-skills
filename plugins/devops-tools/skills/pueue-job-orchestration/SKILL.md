---
name: pueue-job-orchestration
description: Pueue universal CLI telemetry and job orchestration. TRIGGERS - run on gpu-host, run on small-host, queue job, long-running task, cache population, batch processing, GPU workstation, pueue callback, pueue delay, pueue priority.
allowed-tools: Read, Bash, Write
---

# Pueue Job Orchestration

> Universal CLI telemetry layer and job management — every command routed through pueue gets precise timing, exit code capture, full stdout/stderr logs, environment snapshots, and callback-on-completion.

## Overview

[Pueue](https://github.com/Nukesor/pueue) is a Rust CLI tool for managing shell command queues. It provides:

- **Daemon persistence** - Survives SSH disconnects, crashes, reboots
- **Disk-backed queue** - Auto-resumes after any failure
- **Group-based parallelism** - Control concurrent jobs per group
- **Easy failure recovery** - Restart failed jobs with one command
- **Full telemetry** - Timing, exit codes, stdout/stderr logs, env snapshots per task

## When to Route Through Pueue

| Operation                             | Route Through Pueue? | Why                                    |
| ------------------------------------- | -------------------- | -------------------------------------- |
| Any command >30 seconds               | **Always**           | Telemetry, persistence, log capture    |
| Batch operations (>3 items)           | **Always**           | Parallelism control, failure isolation |
| Build/test pipelines                  | **Recommended**      | `--after` DAGs, group monitoring       |
| Data processing                       | **Always**           | Checkpoint resume, state management    |
| Quick one-off commands (<5s)          | Optional             | Overhead is ~100ms, but you get logs   |
| Interactive commands (editors, REPLs) | **Never**            | Pueue can't handle stdin interaction   |

## When to Use This Skill

Use this skill when the user mentions:

| Trigger                               | Example                                    |
| ------------------------------------- | ------------------------------------------ |
| Running tasks on gpu-host/small-host | "Run this on gpu-host"                     |
| Long-running data processing          | "Populate the cache for all symbols"       |
| Batch/parallel operations             | "Process these 70 jobs"                    |
| SSH remote execution                  | "Execute this overnight on the GPU server" |
| Cache population                      | "Fill the ClickHouse cache"                |
| Pueue features                        | "Set up a callback", "delay this job"      |

## Quick Reference

### Check Status

```bash
# Local
pueue status

# Remote (gpu-host)
ssh gpu-host "~/.local/bin/pueue status"
```

### Queue a Job

```bash
# Local (with working directory)
pueue add -w ~/project -- python long_running_script.py

# Local (simple)
pueue add -- python long_running_script.py

# Remote (gpu-host)
ssh gpu-host "~/.local/bin/pueue add -w ~/project -- uv run python script.py"

# With group (for parallelism control)
pueue add --group p1 --label "BTCUSDT@1000" -w ~/project -- python populate.py --symbol BTCUSDT
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
| gpu-host      | `~/.local/bin/pueue`      | p1 (16), p2 (2), p3 (3), p4 (1) |
| small-host   | `~/.local/bin/pueue`      | default (2)                     |
| Local (macOS) | `/opt/homebrew/bin/pueue` | default                         |

## Core Workflows

### 1. Queue Single Remote Job

```bash
# Step 1: Verify daemon is running
ssh gpu-host "~/.local/bin/pueue status"

# Step 2: Queue the job
ssh gpu-host "~/.local/bin/pueue add --label 'my-job' -- cd ~/project && uv run python script.py"

# Step 3: Monitor progress
ssh gpu-host "~/.local/bin/pueue follow <id>"
```

### 2. Batch Job Submission (Multiple Symbols)

For rangebar cache population or similar batch operations:

```bash
# Use the pueue-populate.sh script
ssh gpu-host "cd ~/rangebar-py && ./scripts/pueue-populate.sh setup"   # One-time
ssh gpu-host "cd ~/rangebar-py && ./scripts/pueue-populate.sh phase1"  # Queue Phase 1
ssh gpu-host "cd ~/rangebar-py && ./scripts/pueue-populate.sh status"  # Check progress
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

## Troubleshooting

| Issue                      | Cause                    | Solution                                            |
| -------------------------- | ------------------------ | --------------------------------------------------- |
| `pueue: command not found` | Not in PATH              | Use full path: `~/.local/bin/pueue`                 |
| `Connection refused`       | Daemon not running       | Start with `pueued -d`                              |
| Jobs stuck in Queued       | Group paused or at limit | Check `pueue status`, `pueue start`                 |
| SSH disconnect kills jobs  | Not using Pueue          | Queue via Pueue instead of direct SSH               |
| Job fails immediately      | Wrong working directory  | Use `pueue add -w /path` or `cd /path && pueue add` |

## Priority Scheduling (`--priority`)

Higher priority number = runs first when a queue slot opens:

```bash
# Urgent validation (runs before queued lower-priority jobs)
pueue add --priority 10 -- python validate_critical.py

# Normal compute (default priority is 0)
pueue add -- python train_model.py

# Low-priority background task
pueue add --priority -5 -- python cleanup_logs.py
```

Priority only affects **queued** jobs waiting for an open slot. Running jobs are not preempted.

## Per-Task Environment Override (`pueue env`)

Inject or override environment variables on **stashed or queued** tasks:

```bash
# Create a stashed job
JOB_ID=$(pueue add --stashed --print-task-id -- python train.py)

# Set environment variables (NOTE: separate args, NOT KEY=VALUE)
pueue env set "$JOB_ID" BATCH_SIZE 64
pueue env set "$JOB_ID" LEARNING_RATE 0.001

# Enqueue when ready
pueue enqueue "$JOB_ID"
```

**Syntax**: `pueue env set <id> KEY VALUE` -- the key and value are separate positional arguments.

**Constraint**: Only works on stashed/queued tasks. Cannot modify environment of running tasks.

**Relationship to mise.toml `[env]`**: mise `[env]` remains the SSoT for default environment. Use `pueue env set` only for one-off overrides (e.g., hyperparameter sweeps) without modifying config files.

## Blocking Wait (`pueue wait`)

Block until tasks complete -- simpler than polling loops for scripts:

```bash
# Wait for specific task
pueue wait 42

# Wait for all tasks in a group
pueue wait --group mygroup

# Wait for ALL tasks across all groups
pueue wait --all

# Wait quietly (no progress output)
pueue wait 42 --quiet

# Wait for tasks to reach a specific status
pueue wait --status queued
```

### Script Integration Pattern

```bash
# Queue -> wait -> process results
TASK_ID=$(pueue add --print-task-id -- python etl_pipeline.py)
pueue wait "$TASK_ID" --quiet
EXIT_CODE=$(pueue status --json | jq -r ".tasks[\"$TASK_ID\"].status.Done.result" 2>/dev/null)
if [ "$EXIT_CODE" = "Success" ]; then
    echo "Pipeline succeeded"
    pueue log "$TASK_ID" --full
else
    echo "Pipeline failed"
    pueue log "$TASK_ID" --full >&2
fi
```

---

## Deep-Dive References

| Topic                                                                                                 | Reference                                                              |
| ----------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Installation (macOS, Linux, systemd, launchd)                                                         | [Installation Guide](./references/installation-guide.md)               |
| Production lessons: `--after` chaining, forensic audit, per-year parallelization, pipeline monitoring | [Production Lessons](./references/production-lessons.md)               |
| State bloat prevention, bulk xargs -P submission, two-tier architecture (300K+ jobs), crash recovery  | [State Management & Bulk Submission](./references/state-management.md) |
| ClickHouse thread tuning, parallelism sizing formula, live tuning                                     | [ClickHouse Tuning](./references/clickhouse-tuning.md)                 |
| Callback hooks, template variables, delayed scheduling (`--delay`)                                    | [Callbacks & Scheduling](./references/callbacks-and-scheduling.md)     |
| python-dotenv secrets pattern, rangebar-py integration                                                | [Environment & Secrets](./references/environment-secrets.md)           |
| Claude Code integration, synchronous wrapper, telemetry queries                                       | [Claude Code Integration](./references/claude-code-integration.md)     |
| All `pueue.yml` settings (shared, client, daemon, profiles)                                           | [Pueue Config Reference](./references/pueue-config-reference.md)       |

---

## Related

- **Hook**: `itp-hooks/posttooluse-reminder.ts` - Reminds to use Pueue for detected long-running commands
- **Reference**: [Pueue GitHub](https://github.com/Nukesor/pueue)
- **Issue**: [rangebar-py#77](https://github.com/terrylica/rangebar-py/issues/77) - Original implementation
- **Issue**: [rangebar-py#88](https://github.com/terrylica/rangebar-py/issues/88) - Production deployment lessons
