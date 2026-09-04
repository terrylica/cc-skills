**Skill**: [Pueue Job Orchestration](../SKILL.md)

# State File Management & Bulk Submission

## State Bloat (CRITICAL)

Pueue stores ALL task metadata in a single `state.json` file. This file grows with every completed task and is read/written on EVERY `pueue add` call. Neglecting state hygiene is the #1 cause of slow job submission in large sweeps.

### The State Bloat Anti-Pattern

**Symptom**: `pueue add` takes 1-2 seconds instead of <100ms.

**Root cause**: Pueue serializes/deserializes the entire state file on every operation. With 50K+ completed tasks, `state.json` grows to 80-100MB. Each `pueue add` becomes 80MB read + 80MB write = 160MB I/O.

**Benchmarks** (pueue v4, NVMe SSD, 32-core Linux):

| Completed Tasks | state.json Size | `pueue add` Latency (sequential) | `pueue add` Latency (xargs -P16) |
| --------------- | --------------- | -------------------------------- | -------------------------------- |
| 53,000          | 94 MB           | 1,300 ms/add                     | 455 ms/add (mutex contention)    |
| 0 (after clean) | 245 KB          | 106 ms/add                       | 8 ms/add (effective)             |

**Key insight**: Parallelism does NOT help when state is bloated -- the pueue daemon serializes all operations through a mutex. The 455ms at P16 is WORSE per-operation than 1,300ms sequential because of lock contention overhead. **Clean first, then parallelize.**

### Pre-Submission Clean (Mandatory Pattern)

Before any bulk submission (>100 jobs), clean completed tasks:

```bash
# ALWAYS clean before bulk submission
pueue clean -g mygroup 2>/dev/null || true

# Verify state is manageable
STATE_FILE="$HOME/.local/share/pueue/state.json"
STATE_SIZE=$(stat -c%s "$STATE_FILE" 2>/dev/null || stat -f%z "$STATE_FILE" 2>/dev/null || echo 0)
if [ "$STATE_SIZE" -gt 52428800 ]; then  # 50MB
    echo "WARNING: state.json is $(( STATE_SIZE / 1048576 ))MB -- running extra clean"
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

### Compressed State File

Reduce I/O for state persistence with zstd compression:

```yaml
# In pueue.yml
daemon:
  compress_state_file: true
```

**Compression ratio**: ~10:1 (from pueue source code).

**When to enable**:

- I/O-constrained hosts (spinning disks, NFS mounts)
- Large task histories (hundreds of completed tasks)
- Defense-in-depth alongside periodic `pueue clean`

**Note**: Compression helps I/O performance. `pueue clean` reduces data volume. They are complementary, not alternatives.

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
    echo "moreutils parallel (or none) -- use xargs -P instead"
fi
```

**Safe default**: Always use `xargs -P` -- it's POSIX standard and available everywhere.

### Batch Command File Pattern

**Step 1: Generate commands file** (one `pueue add` per line):

```bash
# gen_commands.sh -- generates commands.txt
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

For sweeps exceeding 10K queries, the single-tier "pueue add per query" pattern is unusable -- `pueue add` has 148ms overhead per call even with clean state (= 8+ hours for 196K jobs). The fix is eliminating `pueue add` at the query level entirely.

### Architecture

```
macOS (local)
  mise run gen:generate   -> N SQL files
  mise run gen:submit-all -> rsync + queue M pueue units
  mise run gen:collect    -> scp + validate JSONL

gpu-host-1 (remote)
  pueue group p1 (parallel=1)   <- sequential units (avoid log contention)
    |-- Unit 1: submit_unit.sh pattern1 BTCUSDT 750
    |     \-- xargs -P16 -> K queries (direct clickhouse-client, no pueue add)
    |-- Unit 2: submit_unit.sh pattern1 BTCUSDT 1000
    |     \-- xargs -P16 -> K queries
    \-- ... (M total units)
```

### Key Principles

| Principle                                      | Rationale                                                                       |
| ---------------------------------------------- | ------------------------------------------------------------------------------- |
| Pueue at **unit** level (100s of tasks)        | Crash recovery per unit, `pueue status` readable                                |
| xargs -P16 at **query** level (1000s per unit) | Zero overhead, direct process execution                                         |
| Sequential units (`parallel=1`)                | Each unit appends to one JSONL file via `flock` -- parallel units would contend |
| Skip-done dedup inside each unit               | `comm -23` on sorted config lists (O(N+M))                                      |

### When to Use Each Tier

| Job Count | Pattern                                                          |
| --------- | ---------------------------------------------------------------- |
| 1-10      | Direct `pueue add` per job                                       |
| 10-1K     | Batch `pueue add` via xargs -P (see Bulk Submission above)       |
| 1K-10K    | Batch `pueue add` with periodic `pueue clean` between batches    |
| **10K+**  | **Two-tier: pueue per unit + xargs -P per query (this section)** |

### Shell Script Safety (set -euo pipefail)

| Trap                    | Symptom                                                                 | Fix                                                           |
| ----------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------- |
| SIGPIPE (exit 141)      | `ls path/*.sql \| head -10` -- `head` closes pipe early                 | Write to temp file first, or use `find -print0 \| head -z`    |
| Pipe subshell data loss | `echo "$OUT" \| while read ...; done > file` -- writes lost in subshell | Process substitution: `while read ...; done < <(echo "$OUT")` |
| eval injection          | `eval "val=\$$var"` with untrusted input                                | Use `case` statement or parameter expansion instead           |

### Skipped Config NDJSON Pattern

Configs with 0 signals after feature filtering produce **1 JSONL line** (skipped entry), not N barrier lines. This is correct behavior, not data loss.

When validating line counts:

```
expected_lines = (N_normal x barriers_per_query) + (N_skipped x 1) + (N_error x 1)
```

Example: 95 normal configs x 3 barriers + 5 skipped x 1 = 290 lines (not 300).

### comm -23 for Large Skip-Done Sets (100K+)

For done-sets exceeding 10K entries, `comm -23` (sorted set difference) is O(N+M) vs grep-per-file O(N\*M):

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
