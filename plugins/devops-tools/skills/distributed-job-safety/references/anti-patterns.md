# Anti-Patterns (Learned from Production)

## AP-1: Redeploying Without Checking Running Jobs

**Symptom**: Killed running jobs, requeued new ones. Old checkpoint files from killed jobs persisted, causing collisions with new jobs.

**Fix**: Always run state audit before redeployment:

```bash
pueue status --json | jq '[.tasks[] | select(.status | keys[0] == "Running")] | length'
# If > 0, decide: wait, kill gracefully, or abort
```

See: [Deployment Checklist](./deployment-checklist.md)

## AP-2: Checkpoint Filename Missing Job Parameters

**Symptom**: `FileNotFoundError` on checkpoint delete -- Job A deleted Job B's checkpoint.

**Root cause**: Filename `{item}_{start}_{end}.json` lacked a differentiating parameter. Two jobs for the same item at different configurations shared the file.

**Fix**: Include ALL differentiating parameters: `{item}_{config}_{start}_{end}.json`

## AP-3: Trusting `pueue restart` Logs

**Symptom**: `pueue log <id>` shows old error after `pueue restart`, appearing as if the restart failed.

**Root cause**: Pueue appends output to existing log. After restart, the log contains BOTH the old failed run and the new attempt.

**Fix**: Check timestamps in the log, or add a new fresh job instead of restarting:

```bash
# More reliable than restart
pueue add --group mygroup --label "BTCUSDT@750-retry" -- <same command>
```

## AP-4: Assuming PyPI Propagation Is Instant

**Symptom**: `uv pip install pkg==X.Y.Z` fails with "no version found" immediately after publishing.

**Root cause**: PyPI CDN propagation takes 30-120 seconds.

**Fix**: Use `--refresh` flag to bust cache:

```bash
uv pip install --refresh --index-url https://pypi.org/simple/ mypkg==<version>
```

## AP-5: Confusing Editable Source vs. Installed Wheel

**Symptom**: Updated pip package to latest, but `uv run` still uses old code.

**Root cause**: `uv.lock` has `source = { editable = "." }` -- `uv run` reads Python files from the git working tree, not from the installed wheel.

**Fix**: On remote hosts, `git pull` updates the source that `uv run` reads. Pip install only matters for non-editable environments.

## AP-6: Sequential Phase Assumption

**Symptom**: Phase 2 jobs started while Phase 1 was still running for the same item, creating contention.

**Root cause**: All phases queued simultaneously.

**Fix**: Either use pueue dependencies (`--after <id>`) or queue phases sequentially after verification:

```bash
# Queue Phase 1, wait for completion, then Phase 2
pueue add --label "phase1" -- run_phase_1
# ... wait and verify ...
pueue add --label "phase2" -- run_phase_2
```

## AP-7: Manual Post-Processing Steps

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

## AP-8: Hardcoded Job IDs in Pipeline Monitors

**Symptom**: Background monitor crashes with empty variable or wrong comparison after jobs are removed, re-queued, or split into per-year jobs.

**Root cause**: Monitor uses `grep "^14|"` to find specific job IDs. When those IDs no longer exist (killed, removed, replaced by per-year splits), the grep returns empty and downstream comparisons fail.

**Fix**: Detect phase transitions by **group completion patterns**, not by tracking individual job IDs. Use `group_all_done()` to check if all jobs in a pueue group have finished.

**Principle**: Pueue group names and job labels are stable identifiers. Job IDs are ephemeral.

**Cross-reference**: See `devops-tools:pueue-job-orchestration` Pipeline Monitoring section for the full `group_all_done()` implementation and integrity check patterns.

## AP-9: Sequential Processing When Epoch Resets Enable Parallelism

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

## AP-10: State File Bloat Causing Silent Performance Regression

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

## AP-11: Wrong Working Directory in Remote Pueue Jobs

**Symptom**: Jobs fail immediately (exit code 2) with `can't open file 'scripts/populate.py': [Errno 2] No such file or directory`.

**Root cause**: `ssh host "pueue add -- uv run python scripts/process.py"` queues the job with the SSH session's cwd (typically `$HOME`), not the project directory. The script path is relative, so pueue looks for `~/scripts/process.py` instead of `~/project/scripts/process.py`.

**Fix**: Use `-w` (preferred) or `cd &&` to set the working directory:

```bash
# WRONG: pueue inherits SSH cwd ($HOME)
ssh host "pueue add --group mygroup -- uv run python scripts/process.py"

# RIGHT (preferred): -w flag sets working directory explicitly
ssh host "pueue add -w ~/project --group mygroup -- uv run python scripts/process.py"

# RIGHT (alternative): cd first, then pueue add inherits project cwd
ssh host "cd ~/project && pueue add --group mygroup -- uv run python scripts/process.py"
```

**Note**: Pueue v4 **does** have `-w` / `--working-directory`. Use it as the primary approach. Fall back to `cd &&` for SSH-piped commands where `-w` path expansion may differ. On macOS, `-w /tmp` resolves to `/private/tmp` (symlink).

**Test**: After queuing, verify the Path column in `pueue status` shows the project directory, not `$HOME`.

## AP-12: Per-File SSH for Bulk Job Submission

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

## AP-13: SIGPIPE Under set -euo pipefail

**Symptom**: Script exits with code 141 (128 + SIGPIPE=13) on harmless pipe operations.

**Root cause**: `ls *.sql | head -10` — `head` reads 10 lines then closes stdin. `ls` gets SIGPIPE writing to closed pipe. Under `set -o pipefail`, this propagates as exit 141.

**Fix**: Avoid piping to `head` in strict-mode scripts:

```bash
# WRONG (exit 141)
ls /tmp/sql/*.sql | head -10

# RIGHT (temp file)
ls /tmp/sql/*.sql > /tmp/filelist.txt
head -10 /tmp/filelist.txt
```

## AP-14: False Data Loss From Variable-Width NDJSON Output

**Symptom**: `wc -l` shows fewer lines than expected. Appears as 3-6% "data loss".

**Root cause**: Configs with 0 signals after feature filtering produce 1 NDJSON line (skipped entry), not N barrier lines. Example: 95 normal × 3 + 5 skipped × 1 = 290 (not 300).

**Fix**: Account for variable output width in line count validation:

```
expected = N_normal * barriers_per_query + N_skipped * 1 + N_error * 1
```

## AP-15: Cursor File Deletion on Completion

**Symptom**: ETL/indexer job succeeds, but next invocation does a full re-run instead of incremental resume.

**Root cause**: Code deletes the cursor/checkpoint/offset file after processing completes (e.g., `CURSOR_FILE.unlink()` in the "done" branch). The cursor IS the resume state — deleting it forces a full re-index.

**Fix**: Never delete checkpoint files on success. Add a filename-based fallback for recovery:

```python
# WRONG
if not has_more_data:
    cursor_file.unlink()  # "Clean up" destroys resume state

# RIGHT
# Leave cursor in place. Next run reads it, queries for new data, finds none, exits quickly.
# Add fallback: derive position from output filenames if cursor is lost.
```

See also: [G-17](./environment-gotchas.md#g-17-cursorcheckpoint-file-deletion-destroys-incremental-resume)

## AP-16: Using mise `[env]` for Secrets Consumed by Pueue/Cron/Systemd Jobs

**Symptom**: Jobs work in interactive shell but fail in pueue/cron/systemd with empty env vars.

**Root cause**: mise `[env]` variables require mise activation in the shell. Pueue jobs, cron jobs, and systemd services run in clean shells without mise. Workarounds (`eval "$(mise env)"` inside jobs) introduce trust issues, version incompatibilities, and `__MISE_DIFF` leakage over SSH. # PROCESS-STORM-OK (documentation of anti-pattern)

**Fix**: Use `python-dotenv` + `.env` for secrets. Use `mise.toml [tasks]` for task definitions only:

```toml
# mise.toml — tasks only, no [env] for secrets
[tasks.backfill]
run = "bash scripts/backfill.sh"

[tasks.ingest]
run = "bash scripts/ingest.sh"
```

```bash
# scripts/backfill.sh — just cd so python-dotenv finds .env
pueue add -- bash -c 'cd ~/project && uv run python my_indexer.py'
```

```python
# my_indexer.py — loads .env from cwd automatically
from dotenv import load_dotenv
load_dotenv()
API_KEY = os.getenv("API_KEY")  # Works in interactive shell AND pueue jobs
```

See also: [G-15](./environment-gotchas.md#g-15-pueue-jobs-cannot-see-mise-env-variables)

## AP-17: Unscoped Glob Consumes Artifacts From Other Pipeline Categories

**Symptom**: Phase A aggregation produces correct results. Phase B aggregation finds empty input (no files). Or Phase B produces mixed/contaminated results containing Phase A's data.

**Root cause**: Both phases write artifacts to the same directory with filenames that differ only by a dimension NOT included in the cleanup glob. Phase A's glob matches ALL artifacts, consuming or deleting Phase B's files.

```python
# WRONG: Unscoped glob matches ALL categories
chunk_files = folds_dir.glob("_chunk_*.parquet")  # Eats long AND short
for p in chunk_files:
    p.unlink()  # Deletes short's chunks too

# RIGHT: Category-scoped glob
chunk_files = folds_dir.glob(f"_chunk_{direction}_*.parquet")
for p in chunk_files:
    p.unlink()  # Only deletes this direction's chunks
```

**The pattern**: This occurs whenever:

1. Two pipeline phases share an output directory
2. Artifacts are named by a subset of discriminating dimensions
3. A glob pattern doesn't include ALL discriminating dimensions
4. One phase runs before the other and "cleans up" shared files

**Fix**: Apply INV-9 — include ALL category dimensions in filenames AND scope all globs to the current category. Add post-merge validation to catch contamination early.

**Discovery**: Gen720 WFO pipeline (2026-02-17). LONG aggregation consumed SHORT Parquet chunks via `_chunk_*.parquet` glob, producing a mixed 8.7M-row Parquet. SHORT aggregation found 0 chunks.
