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

## Related

- **Hook**: `itp-hooks/posttooluse-reminder.ts` - Reminds to use Pueue for detected long-running commands
- **Reference**: [Pueue GitHub](https://github.com/Nukesor/pueue)
- **Issue**: [rangebar-py#77](https://github.com/terrylica/rangebar-py/issues/77) - Original implementation
