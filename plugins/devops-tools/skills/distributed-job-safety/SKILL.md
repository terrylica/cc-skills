---
name: distributed-job-safety
description: >-
  Concurrency safety patterns for distributed pueue + mise + systemd-run job pipelines.
  TRIGGERS - queue pueue jobs, deploy to remote host, concurrent job collisions,
  checkpoint races, resource guards, cgroup memory limits, systemd-run, autoscale,
  batch processing safety, job parameter isolation.
allowed-tools: Read, Bash, Write
---

# Distributed Job Safety

Patterns and anti-patterns for concurrent job management with pueue + mise + systemd-run, learned from production failures in distributed data pipeline orchestration.

**Scope**: Universal principles for any pueue + mise workflow with concurrent parameterized jobs. Examples use illustrative names but the principles apply to any domain.

**Prerequisite skills**: `devops-tools:pueue-job-orchestration`, `itp:mise-tasks`, `itp:mise-configuration`

---

## The Seven Invariants

Non-negotiable rules for concurrent job safety. Violating any one causes silent data corruption or job failure.

Full formal specifications: [references/concurrency-invariants.md](./references/concurrency-invariants.md)

### 1. Filename Uniqueness by ALL Job Parameters

Every file path shared between concurrent jobs MUST include ALL parameters that differentiate those jobs.

```
WRONG:  {symbol}_{start}_{end}.json                    # Two thresholds collide
RIGHT:  {symbol}_{threshold}_{start}_{end}.json         # Each job gets its own file
```

**Test**: If two pueue jobs can run simultaneously with different parameter values, those values MUST appear in every shared filename, temp directory, and lock file.

### 2. Verify Before Mutate (No Blind Queueing)

Before queueing jobs, check what is already running. Before deleting state, check who owns it.

```bash
# WRONG: Blind queue
for item in "${ITEMS[@]}"; do
    pueue add --group mygroup -- run_job "$item" "$param"
done

# RIGHT: Check first
running=$(pueue status --json | jq '[.tasks[] | select(.status | keys[0] == "Running") | .label] | join(",")')
if echo "$running" | grep -q "${item}@${param}"; then
    echo "SKIP: ${item}@${param} already running"
    continue
fi
```

### 3. Idempotent File Operations (missing_ok=True)

All file deletion in concurrent contexts MUST tolerate the file already being gone.

```python
# WRONG: TOCTOU race
if path.exists():
    path.unlink()        # Crashes if another job deleted between check and unlink

# RIGHT: Idempotent
path.unlink(missing_ok=True)
```

### 4. Atomic Writes for Shared State

Checkpoint files must never be partially written. Use the tempfile-fsync-rename pattern.

```python
fd, temp_path = tempfile.mkstemp(dir=path.parent, prefix=".ckpt_", suffix=".tmp")
with os.fdopen(fd, "w") as f:
    f.write(json.dumps(data))
    f.flush()
    os.fsync(f.fileno())
os.replace(temp_path, path)  # POSIX atomic rename
```

### 5. Config File Is SSoT

The `.mise.toml` `[env]` section is the single source of truth for environment defaults. Per-job `env` overrides bypass the SSoT and allow arbitrary values with no review gate.

```bash
# WRONG: Per-job override bypasses mise SSoT
pueue add -- env MY_APP_MIN_THRESHOLD=50 uv run python script.py

# RIGHT: Set the correct value in .mise.toml, no per-job override needed
pueue add -- uv run python script.py
```

### 6. Maximize Parallelism Within Safe Margins

Always probe host resources and scale parallelism to use available capacity. Conservative defaults waste hours of idle compute.

```bash
# Probe host resources
ssh host 'nproc && free -h && uptime'

# Sizing formula (leave 20% margin for OS + DB + overhead)
# max_jobs = min(
#     (available_memory_gb * 0.8) / per_job_memory_gb,
#     (total_cores * 0.8) / per_job_cpu_cores
# )
```

**For ClickHouse workloads**: The bottleneck is often ClickHouse's `concurrent_threads_soft_limit` (default: 2 × nproc), not pueue's parallelism. Each query requests `max_threads` threads (default: nproc). Right-size `--max_threads` per query to match the effective thread count (soft_limit / pueue_slots), then increase pueue slots. Pueue parallelism can be adjusted live without restarting running jobs.

**Post-bump monitoring** (mandatory for 5 minutes after any parallelism change):

- `uptime` — load average should stay below 0.9 × nproc
- `vmstat 1 5` — si/so columns must remain 0 (no active swapping)
- ClickHouse errors: `SELECT count() FROM system.query_log WHERE event_time > now() - INTERVAL 5 MINUTE AND type = 'ExceptionWhileProcessing'` — must be 0

**Cross-reference**: See `devops-tools:pueue-job-orchestration` ClickHouse Parallelism Tuning section for the full decision matrix.

### 7. Per-Job Memory Caps via systemd-run

On Linux with cgroups v2, wrap each job with `systemd-run` to enforce hard memory limits.

```bash
systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 \
    uv run python scripts/process.py --symbol BTCUSDT --threshold 250
```

**Critical**: `MemorySwapMax=0` is mandatory. Without it, the process escapes into swap and the memory limit is effectively meaningless.

---

## Anti-Patterns (Learned from Production)

### AP-1: Redeploying Without Checking Running Jobs

**Symptom**: Killed running jobs, requeued new ones. Old checkpoint files from killed jobs persisted, causing collisions with new jobs.

**Fix**: Always run state audit before redeployment:

```bash
pueue status --json | jq '[.tasks[] | select(.status | keys[0] == "Running")] | length'
# If > 0, decide: wait, kill gracefully, or abort
```

See: [references/deployment-checklist.md](./references/deployment-checklist.md)

### AP-2: Checkpoint Filename Missing Job Parameters

**Symptom**: `FileNotFoundError` on checkpoint delete -- Job A deleted Job B's checkpoint.

**Root cause**: Filename `{item}_{start}_{end}.json` lacked a differentiating parameter. Two jobs for the same item at different configurations shared the file.

**Fix**: Include ALL differentiating parameters: `{item}_{config}_{start}_{end}.json`

### AP-3: Trusting `pueue restart` Logs

**Symptom**: `pueue log <id>` shows old error after `pueue restart`, appearing as if the restart failed.

**Root cause**: Pueue appends output to existing log. After restart, the log contains BOTH the old failed run and the new attempt.

**Fix**: Check timestamps in the log, or add a new fresh job instead of restarting:

```bash
# More reliable than restart
pueue add --group mygroup --label "BTCUSDT@750-retry" -- <same command>
```

### AP-4: Assuming PyPI Propagation Is Instant

**Symptom**: `uv pip install pkg==X.Y.Z` fails with "no version found" immediately after publishing.

**Root cause**: PyPI CDN propagation takes 30-120 seconds.

**Fix**: Use `--refresh` flag to bust cache:

```bash
uv pip install --refresh --index-url https://pypi.org/simple/ mypkg==<version>
```

### AP-5: Confusing Editable Source vs. Installed Wheel

**Symptom**: Updated pip package to latest, but `uv run` still uses old code.

**Root cause**: `uv.lock` has `source = { editable = "." }` -- `uv run` reads Python files from the git working tree, not from the installed wheel.

**Fix**: On remote hosts, `git pull` updates the source that `uv run` reads. Pip install only matters for non-editable environments.

### AP-6: Sequential Phase Assumption

**Symptom**: Phase 2 jobs started while Phase 1 was still running for the same item, creating contention.

**Root cause**: All phases queued simultaneously.

**Fix**: Either use pueue dependencies (`--after <id>`) or queue phases sequentially after verification:

```bash
# Queue Phase 1, wait for completion, then Phase 2
pueue add --label "phase1" -- run_phase_1
# ... wait and verify ...
pueue add --label "phase2" -- run_phase_2
```

### AP-7: Manual Post-Processing Steps

**Symptom**: Queue batch jobs, print "run optimize after they finish."

```bash
# WRONG
postprocess_all() {
    queue_batch_jobs
    echo "Run 'pueue wait' then manually run optimize and validate"  # NO!
}
```

**Fix**: Wire post-processing as pueue `--after` dependent jobs:

```bash
# RIGHT
postprocess_all() {
    JOB_IDS=()
    for param in 250 500 750 1000; do
        job_id=$(pueue add --print-task-id --group mygroup \
            --label "ITEM@${param}" -- uv run python process.py --param "$param")
        JOB_IDS+=("$job_id")
    done
    # Chain optimize after ALL batch jobs
    optimize_id=$(pueue add --print-task-id --after "${JOB_IDS[@]}" \
        -- clickhouse-client --query "OPTIMIZE TABLE mydb.mytable FINAL")
    # Chain validation after optimize
    pueue add --after "$optimize_id" -- uv run python scripts/validate.py
}
```

**Cross-reference**: See `devops-tools:pueue-job-orchestration` Dependency Chaining section for full `--after` patterns.

### AP-8: Hardcoded Job IDs in Pipeline Monitors

**Symptom**: Background monitor crashes with empty variable or wrong comparison after jobs are removed, re-queued, or split into per-year jobs.

**Root cause**: Monitor uses `grep "^14|"` to find specific job IDs. When those IDs no longer exist (killed, removed, replaced by per-year splits), the grep returns empty and downstream comparisons fail.

**Fix**: Detect phase transitions by **group completion patterns**, not by tracking individual job IDs:

```bash
# WRONG: Breaks when job 14 is removed
job14_status=$(echo "$JOBS" | grep "^14|" | cut -d'|' -f2)
if [ "$job14_status" = "Done" ]; then ...

# RIGHT: Check if ALL jobs in a group are done
group_all_done() {
    local group="$1"
    local group_jobs
    group_jobs=$(echo "$JOBS" | grep "|${group}$" || true)
    [ -z "$group_jobs" ] && return 1
    echo "$group_jobs" | grep -qE "\|(Running|Queued)\|" && return 1
    return 0
}
```

**Principle**: Pueue group names and job labels are stable identifiers. Job IDs are ephemeral.

### AP-9: Sequential Processing When Epoch Resets Enable Parallelism

**Symptom**: A multi-year job runs for days single-threaded while 25+ cores sit idle. ETA: 1,700 hours.

**Root cause**: Pipeline processor resets state at epoch boundaries (yearly, monthly) — each epoch is already independent. But the job was queued as one monolithic range.

**Fix**: Split into per-epoch pueue jobs running concurrently:

```bash
# WRONG: Single monolithic job, wastes idle cores
pueue add -- process --start 2019-01-01 --end 2026-12-31  # 1,700 hours single-threaded

# RIGHT: Per-year splits, 5x+ speedup on multi-core
for year in 2019 2020 2021 2022 2023 2024 2025 2026; do
    pueue add --group item-yearly --label "ITEM@250:${year}" \
        -- process --start "${year}-01-01" --end "${year}-12-31"
done
```

**When this applies**: Any pipeline where the processor explicitly resets state at time boundaries (ouroboros pattern, rolling windows, annual rebalancing). If the processor carries state across boundaries, per-epoch splitting is NOT safe.

**Cross-reference**: See `devops-tools:pueue-job-orchestration` Per-Year Parallelization section for full patterns.

### AP-10: State File Bloat Causing Silent Performance Regression

**Symptom**: Job submission that used to take 10 minutes now takes 6+ hours. No errors — just slow. Pipeline appears healthy but execution slots sit idle waiting for new jobs to be queued.

**Root cause**: Pueue's `state.json` grows with every completed task. At 50K+ completed tasks (80-100MB state file), each `pueue add` takes 1-2 seconds instead of <100ms. This is invisible — no errors, no warnings, just gradually degrading throughput.

**Why it's dangerous**: The regression is proportional to total completed tasks across the daemon's lifetime. A sweep that runs 10K jobs/day hits the problem by day 5. The first day runs fine, creating a false sense of security.

**Fix**: Treat `state.json` as infrastructure that requires periodic maintenance:

```bash
# Before bulk submission: always clean
pueue clean -g mygroup 2>/dev/null || true

# During long sweeps: clean between batches
# (See pueue-job-orchestration skill for full batch pattern)

# Monitor state size as part of health checks
STATE_FILE="$HOME/.local/share/pueue/state.json"
ls -lh "$STATE_FILE"  # Should be <10MB for healthy operation
```

**Invariant**: `state.json` size should stay below 50MB during active sweeps. Above 50MB, `pueue add` latency exceeds 500ms and parallel submission gains vanish.

**Cross-reference**: See `devops-tools:pueue-job-orchestration` State File Management section for benchmarks and the periodic clean pattern.

### AP-11: Wrong Working Directory in Remote Pueue Jobs

**Symptom**: Jobs fail immediately (exit code 2) with `can't open file 'scripts/populate.py': [Errno 2] No such file or directory`.

**Root cause**: `ssh host "pueue add -- uv run python scripts/process.py"` queues the job with the SSH session's cwd (typically `$HOME`), not the project directory. The script path is relative, so pueue looks for `~/scripts/process.py` instead of `~/project/scripts/process.py`.

**Fix**: Always `cd` to the project directory before `pueue add`:

```bash
# WRONG: pueue inherits SSH cwd ($HOME)
ssh host "pueue add --group mygroup -- uv run python scripts/process.py"

# RIGHT: cd first, then pueue add inherits project cwd
ssh host "cd ~/project && pueue add --group mygroup -- uv run python scripts/process.py"
```

**Why not `--working-directory`?** Pueue v4 doesn't have a `--working-directory` flag. The `cd && pueue add` pattern is the only way to set the job's working directory.

**Test**: After queuing, verify the Path column in `pueue status` shows the project directory, not `$HOME`.

### AP-12: Per-File SSH for Bulk Job Submission

**Symptom**: Submitting 300K jobs takes days because each `pueue add` requires a separate SSH round-trip from the local machine to the remote host.

**Root cause**: The submission script runs locally and calls `ssh host "pueue add ..."` per job. Each SSH connection has ~50-100ms overhead. At 300K jobs: 300K \* 75ms = 6.25 hours just for SSH, before any submission latency.

**Fix**: Generate a commands file locally, rsync it to the remote host, then run `xargs -P` **on the remote host** to eliminate SSH overhead entirely:

```bash
# Step 1 (local): Generate commands file
bash gen_commands.sh > /tmp/commands.txt

# Step 2 (local): Transfer to remote
rsync /tmp/commands.txt host:/tmp/commands.txt

# Step 3 (remote): Feed via xargs -P (no SSH per-job)
ssh host "xargs -P16 -I{} bash -c '{}' < /tmp/commands.txt"
```

**Invariant**: Bulk submission should run ON the same host as pueue. The only SSH call should be to start the feeder process, not per-job.

---

## The Mise + Pueue + systemd-run Stack

```
mise (environment + task discovery)
  |-- .mise.toml [env] -> SSoT for defaults
  |-- .mise/tasks/jobs.toml -> task definitions
  |     |-- mise run jobs:process-all
  |     |     |-- job-runner.sh (orchestrator)
  |     |           |-- pueue add (per-job)
  |     |                 |-- systemd-run --scope -p MemoryMax=XG -p MemorySwapMax=0
  |     |                       |-- uv run python scripts/process.py
  |     |                             |-- run_resumable_job()
  |     |                                   |-- get_checkpoint_path() -> param-aware
  |     |                                   |-- checkpoint.save() -> atomic write
  |     |                                   |-- checkpoint.unlink() -> missing_ok=True
  |     |
  |     |-- mise run jobs:autoscale-loop
  |           |-- autoscaler.sh --loop (60s interval)
  |                 |-- reads: free -m, uptime, pueue status --json
  |                 |-- adjusts: pueue parallel N --group <group>
```

**Responsibility boundaries**:

| Layer           | Responsibility                                             |
| --------------- | ---------------------------------------------------------- |
| **mise**        | Environment variables, tool versions, task discovery       |
| **pueue**       | Daemon persistence, parallelism limits, restart, `--after` |
| **systemd-run** | Per-job cgroup memory caps (Linux only, no-op on macOS)    |
| **autoscaler**  | Dynamic parallelism tuning based on host resources         |
| **Python/app**  | Domain logic, checkpoint management, data integrity        |

---

## Remote Deployment Protocol

When deploying a fix to a running host:

```
1. AUDIT:   ssh host 'pueue status --json' -> count running/queued/failed
2. DECIDE:  Wait for running jobs? Kill? Let them finish with old code?
3. PULL:    ssh host 'cd ~/project && git fetch origin main && git reset --hard origin/main'
4. VERIFY:  ssh host 'cd ~/project && python -c "import pkg; print(pkg.__version__)"'
5. UPGRADE: ssh host 'cd ~/project && uv pip install --python .venv/bin/python --refresh pkg==X.Y.Z'
6. RESTART: ssh host 'pueue restart <failed_id>' OR add fresh jobs
7. MONITOR: ssh host 'pueue status --group mygroup'
```

**Critical**: Step 1 (AUDIT) is mandatory. Skipping it is the root cause of cascade failures.

See: [references/deployment-checklist.md](./references/deployment-checklist.md) for full protocol.

---

## Concurrency Safety Decision Tree

```
Adding a new parameter to a resumable job function?
|-- Is it job-differentiating (two jobs can have different values)?
|   |-- YES -> Add to checkpoint filename
|   |          Add to pueue job label
|   |          Add to remote checkpoint key
|   |-- NO  -> Skip (e.g., verbose, notify are per-run, not per-job)
|
|-- Does the function delete files?
|   |-- YES -> Use missing_ok=True
|   |          Use atomic write for creates
|   |-- NO  -> Standard operation
|
|-- Does the function write to shared storage?
    |-- YES -> Force deduplication after write
    |          Use UPSERT semantics where possible
    |-- NO  -> Standard operation
```

---

## Autoscaler

Pueue has no resource awareness. The autoscaler complements it with dynamic parallelism tuning.

**How it works**: Reads CPU load + available memory, then adjusts `pueue parallel N` per group.

```
CPU < 40% AND MEM < 60%  ->  SCALE UP (+1 per group)
CPU > 80% OR  MEM > 80%  ->  SCALE DOWN (-1 per group)
Otherwise                 ->  HOLD
```

**Incremental scaling protocol** -- don't jump to max capacity. Ramp up in steps and verify stability at each level:

```
Step 1: Start with conservative defaults (e.g., group1=2, group2=3)
Step 2: After jobs stabilize (~5 min), probe: uptime + free -h + ps aux
Step 3: If load < 40% cores AND memory < 60% available:
        Bump by +1-2 jobs per group
Step 4: Wait ~5 min for new jobs to reach peak memory
Step 5: Probe again. If still within 80% margin, bump again
Step 6: Repeat until load ~50% cores OR memory ~70% available
```

**Why incremental**: Job memory footprint grows over time (a job may start at ~500 MB and peak at 5+ GB). Jumping straight to max parallelism risks OOM when all jobs hit peak simultaneously.

**Safety bounds**: Each group should have min/max limits the autoscaler won't exceed. It should also check per-job memory estimates before scaling up (don't add a 5 GB job if only 3 GB available).

**Dynamic adjustment** (pueue supports live tuning without restarting jobs):

```bash
# Scale up when resources are available
pueue parallel 4 --group group1
pueue parallel 5 --group group2

# Scale down if memory pressure detected
pueue parallel 2 --group group1
```

**Per-symbol/per-family groups**: When jobs have vastly different resource profiles, give each family its own pueue group. This prevents a single high-memory job type from starving lighter jobs:

```bash
# Example: high-volume symbols need fewer concurrent jobs (5 GB each)
pueue group add highvol-yearly --parallel 2

# Low-volume symbols can run more concurrently (1 GB each)
pueue group add lowvol-yearly --parallel 6
```

---

## Project-Specific Extensions

This skill provides **universal patterns** that apply to any distributed job pipeline. Projects should create a **local extension skill** (e.g., `myproject-job-safety`) in their `.claude/skills/` directory that provides:

| Local Extension Provides        | Example                                           |
| ------------------------------- | ------------------------------------------------- |
| Concrete function names         | `run_resumable_job()` -> `myapp_populate_cache()` |
| Application-specific env vars   | `MY_APP_MIN_THRESHOLD`, `MY_APP_CH_HOSTS`         |
| Memory profiles per job type    | "250 dbps peaks at 5 GB, use MemoryMax=8G"        |
| Database-specific audit queries | `SELECT ... FROM mydb.mytable ... countIf(x < 0)` |
| Issue provenance tracking       | "Checkpoint race: GH-84"                          |
| Host-specific configuration     | "bigblack: 32 cores, 61 GB, groups p1/p2/p3/p4"   |

**Two-layer invocation pattern**: When this skill is triggered, also check for and invoke any local `*-job-safety` skill in the project's `.claude/skills/` directory for project-specific configuration.

```
devops-tools:distributed-job-safety    (universal patterns - this skill)
  + .claude/skills/myproject-job-safety  (project-specific config)
  = Complete operational knowledge
```

---

## References

- [Concurrency Invariants](./references/concurrency-invariants.md) -- Formal invariant specifications (INV-1 through INV-7)
- [Deployment Checklist](./references/deployment-checklist.md) -- Step-by-step remote deployment protocol
- [Environment Gotchas](./references/environment-gotchas.md) -- Host-specific pitfalls (G-1 through G-11)
- **Cross-reference**: `devops-tools:pueue-job-orchestration` -- Pueue basics, dependency chaining, installation
