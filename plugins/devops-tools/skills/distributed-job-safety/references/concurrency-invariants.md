# Concurrency Invariants

Formal specifications for concurrent job safety. Each invariant includes a violation scenario and enforcement pattern.

---

## INV-1: Checkpoint File Isolation

**Statement**: For any two concurrent jobs J_a and J_b where `params(J_a) != params(J_b)`, the checkpoint paths must be distinct: `checkpoint_path(J_a) != checkpoint_path(J_b)`.

**Violation scenario**:

```
J_a = (symbol=BTCUSDT, threshold=1000, start=2024-01-01, end=2024-12-31)
J_b = (symbol=BTCUSDT, threshold=750,  start=2024-01-01, end=2024-12-31)

# Without threshold in filename:
checkpoint_path(J_a) = checkpoints/BTCUSDT_2024-01-01_2024-12-31.json
checkpoint_path(J_b) = checkpoints/BTCUSDT_2024-01-01_2024-12-31.json  # COLLISION

# J_a finishes, deletes checkpoint
# J_b tries to read/delete -> FileNotFoundError
```

**Enforcement**:

```python
def get_checkpoint_path(symbol, threshold, start_date, end_date, ...):
    filename = f"{symbol}_{threshold}_{start_date}_{end_date}.json"
    return checkpoint_dir / filename
```

**Verification**: For every pair of pueue job labels in the same group, assert their checkpoint paths differ.

---

## INV-2: Idempotent Cleanup

**Statement**: For any file deletion operation `delete(path)`, the operation must be idempotent: calling `delete(path)` when the file does not exist must not raise an exception.

**Violation scenario**:

```python
# J_a finishes at T=100, calls: checkpoint_path.unlink()  -> OK (file deleted)
# J_b finishes at T=101, calls: checkpoint_path.unlink()  -> FileNotFoundError!

# Even worse with TOCTOU:
# J_a: if checkpoint_path.exists():  -> True (T=100)
# J_b:   checkpoint_path.unlink()    -> OK (T=100.5, deletes file)
# J_a:   checkpoint_path.unlink()    -> FileNotFoundError! (T=101, file already gone)
```

**Enforcement**:

```python
# ALWAYS use missing_ok=True
path.unlink(missing_ok=True)

# NEVER use exists() + unlink() pair
# NEVER use try/except for this (verbose, error-prone)
```

---

## INV-3: Atomic State Writes

**Statement**: A checkpoint file must always contain either the complete previous state or the complete new state, never a partial write.

**Violation scenario**:

```
# Job writing checkpoint (no atomic write):
open("checkpoint.json", "w")
write(first_half_of_json)     # <- process killed here by OOM
# File now contains truncated JSON
# On resume: json.loads() -> JSONDecodeError
```

**Enforcement**: Tempfile + fsync + atomic rename:

```python
fd, temp_path = tempfile.mkstemp(dir=path.parent, prefix=".ckpt_", suffix=".tmp")
with os.fdopen(fd, "w") as f:
    f.write(json.dumps(data))
    f.flush()
    os.fsync(f.fileno())         # Force to disk
os.replace(temp_path, path)      # POSIX guarantees atomic rename
```

**Recovery**: The checkpoint loader should handle `JSONDecodeError` gracefully by returning `None`, triggering a fresh start from the last known-good state.

---

## INV-4: Environment Override Scoping

**Statement**: An environment variable override for a pueue job MUST NOT affect other concurrent jobs or the host's default configuration.

**Violation scenario**:

```bash
# WRONG: Global modification
export MY_APP_MIN_THRESHOLD=250
pueue add -- uv run python script.py --threshold 250
pueue add -- uv run python script.py --threshold 1000  # Also uses 250 minimum!

# Even worse: editing .mise.toml
```

**Enforcement**: Use `env` prefix per-job when overrides are truly needed:

```bash
pueue add -- env MY_APP_MIN_THRESHOLD=250 uv run python script.py --threshold 250
pueue add -- env MY_APP_MIN_THRESHOLD=250 uv run python script.py --threshold 1000
# Each job gets its own environment scope
```

**Preferred**: Set the correct value in `.mise.toml` so per-job overrides are unnecessary.

---

## INV-5: Post-Write Deduplication

**Statement**: After writing data to a storage backend that uses eventual-consistency deduplication (e.g., ClickHouse ReplacingMergeTree), an explicit deduplication step must follow.

**Violation scenario**:

```
# Job fails at day 2024-06-15, retries from checkpoint
# Day 2024-06-15 is reprocessed, rows are INSERT'd again
# ClickHouse ReplacingMergeTree: dedup happens in background merge (hours later)
# Query immediately after: sees duplicate rows for 2024-06-15
```

**Enforcement**:

```python
# After processing loop completes:
with MyCache() as cache:
    cache.deduplicate(symbol, threshold)
```

**Applies to**: Any storage engine with lazy deduplication (ClickHouse ReplacingMergeTree, Parquet append, eventual-consistency stores).

---

## INV-6: Gate Before Compute

**Statement**: Validation gates (input registry, parameter bounds) MUST execute before any expensive operation (data fetch, computation, cache write).

**Violation scenario**:

```python
# WRONG: Validate after fetch
data = fetch_data(symbol, start, end)   # 10 minutes of download
validate_input(symbol)                   # Fails! Wasted 10 minutes.

# WORSE: No validation at all
data = fetch_data("MATIC_USDT", ...)    # Typo, but fetches garbage data
result = process(data)                   # Computes from garbage
cache.store(result)                      # Stores garbage permanently
```

**Enforcement**:

```python
def run_resumable_job(symbol, ...):
    validate_input(symbol)                      # FIRST
    start_date = validate_and_clamp(symbol, start_date)  # SECOND
    checkpoint_path = get_checkpoint_path(...)   # THEN proceed
```

---

## INV-7: Per-Job Memory Isolation

**Statement**: Each concurrent job must have an enforced upper bound on physical memory consumption, preventing any single job from starving the host via swap thrashing.

**Violation scenario**:

```
# Job memory profile: starts ~500 MB, peaks at 5+ GB over hours
# 6 concurrent heavy jobs peak simultaneously:
# 6 * 5 GB = 30 GB demand on 61 GB host -> triggers swap
# All jobs now swap-thrashing -> load 50+ -> SSH unresponsive -> host frozen
```

**Enforcement**: `systemd-run --user --scope` with cgroups v2:

```bash
systemd-run --user --scope \
    -p MemoryMax=8G \
    -p MemorySwapMax=0 \
    uv run python scripts/process.py --symbol BTCUSDT --threshold 250
```

**Critical**: `MemorySwapMax=0` is mandatory. Without it, Linux memory overcommit allows processes to spill into swap, defeating the purpose of `MemoryMax`.

**Verification** (while job is running):

```bash
SCOPE=$(pueue log <id> | grep "Running as unit" | grep -o "run-r[a-z0-9]*.scope")
CGROUP=$(find /sys/fs/cgroup/user.slice -name "$SCOPE" -type d | head -1)
cat $CGROUP/memory.current    # Should be < MemoryMax
cat $CGROUP/memory.max        # Should match MemoryMax
cat $CGROUP/memory.swap.max   # Should be 0
```

**Platform**: Linux with cgroups v2 only. Falls back to plain execution on macOS. Bypass with `MY_APP_NO_CGROUP=1`.

---

## INV-8: Monitor by Stable Identifiers, Not Ephemeral IDs

**Statement**: Pipeline monitors and orchestration scripts must identify jobs by stable attributes (group names, label patterns) — never by ephemeral numeric IDs that change when jobs are removed, re-queued, or restructured.

**Violation scenario**:

```bash
# Monitor hardcodes job IDs from initial queue submission
optimize_job=14
detect_job=15
backfill_jobs=(16 17 18)

# Later: jobs 16-18 are killed and replaced with per-year splits (IDs 21-47)
# Monitor still checks job 16 -> empty result -> crash or false positive
```

**Enforcement**: Use group names and label patterns:

```bash
# Query by group (stable)
group_jobs=$(pueue status --json | jq -r \
    '.tasks | to_entries[] | select(.value.group == "btc-yearly") | .value.id')

# Query by label pattern (stable)
optimize_job=$(pueue status --json | jq -r \
    '.tasks | to_entries[] | select(.value.label == "optimize-table:final") | .value.id')
```

**Principle**: Pueue group names and job labels are chosen by the user and remain stable. Job IDs are auto-incremented integers that shift with every queue mutation.

---

## INV-9: Derived Artifact Category Isolation

**Statement**: For any two pipeline phases P_a and P_b that write derived artifacts to a shared directory, every artifact filename must include ALL dimensions that differentiate P_a from P_b. Glob patterns used for reading, merging, or deleting artifacts must be scoped to the executing phase's dimensions.

**Violation scenario**:

```
P_a = (direction=long, formation=exh_l, symbol=SOLUSDT, threshold=500)
P_b = (direction=short, formation=exh_s, symbol=SOLUSDT, threshold=500)

# Without direction in filename:
artifact(P_a) = folds/_chunk_exh_l_SOLUSDT_500.parquet
artifact(P_b) = folds/_chunk_exh_s_SOLUSDT_500.parquet

# P_a merges with: glob("_chunk_*.parquet")
# COLLISION: glob matches BOTH P_a and P_b artifacts
# P_a merges all into long_folds.parquet (now contaminated with SHORT data)
# P_a deletes all chunks (P_b's chunks are gone)
# P_b runs: glob("_chunk_*.parquet") -> 0 files -> empty output
```

**Enforcement**:

```python
# Include ALL category dimensions in filename
chunk_path = folds_dir / f"_chunk_{direction}_{formation}_{symbol}_{threshold}.parquet"

# Scope glob to current phase's category
chunk_files = folds_dir.glob(f"_chunk_{direction}_*.parquet")

# Post-merge validation
merged_df = pl.concat([pl.read_parquet(p) for p in chunk_files])
expected_strategies = {"standard"} if direction == "long" else {"A_mirrored", "B_reverse"}
actual = set(merged_df["strategy"].unique().to_list())
assert actual == expected_strategies, f"Category contamination: expected {expected_strategies}, got {actual}"
```

**Verification**: After merging derived artifacts, assert that category columns contain only the expected values for the current phase. This catches contamination even if filenames are accidentally unscoped.

**Relationship to INV-1**: INV-1 ensures runtime checkpoint uniqueness. INV-9 extends the same principle to derived artifacts that persist across pipeline phases and may be consumed by later phases running in different category contexts.

---

## Testing Invariants

Verify these invariants hold after any code change:

```python
# INV-1: Filename uniqueness
path_a = get_checkpoint_path("BTCUSDT", 1000, "2024-01-01", "2024-12-31")
path_b = get_checkpoint_path("BTCUSDT", 750,  "2024-01-01", "2024-12-31")
assert path_a != path_b, "INV-1 violated: same path for different thresholds"

# INV-2: Idempotent delete
from pathlib import Path
p = Path("/tmp/test_inv2.json")
p.unlink(missing_ok=True)  # Should not raise even if file doesn't exist
p.unlink(missing_ok=True)  # Second call also safe

# INV-3: Atomic write recovery
# Kill process during checkpoint.save(), verify file is either old or new, never partial

# INV-4: Env scoping
# Run two pueue jobs with different env overrides, verify they don't interfere

# INV-5: Post-dedup
# Write duplicate rows, verify deduplicate() removes them

# INV-6: Gate ordering
# Call run_resumable_job("INVALID_INPUT", ...) -> must fail before any I/O

# INV-7: Memory isolation
# Run job under systemd-run with MemoryMax, verify cgroup limits are enforced

# INV-8: Monitor by stable identifiers
# After re-queuing a job, verify monitoring scripts still find it by group/label
# (not by old job ID which no longer exists)

# INV-9: Derived artifact category isolation
# Write artifacts with two different category values to same directory
# Verify that merging for category A does not include category B's artifacts
# Verify that cleanup for category A does not delete category B's artifacts
```
