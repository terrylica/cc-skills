---
name: status
description: "Machine-wide loop status enumeration and health reporting. TRIGGERS - autonomous-loop status, loop state, all loops, show loops, machine status."
allowed-tools: Bash, Read
argument-hint: "[--json | --reclaim-candidates | <loop_id>]"
disable-model-invocation: false
---

# autonomous-loop: Machine-Wide Status

Enumerates all registered loops on the machine and reports health, dead-time ratio, staleness, and reclaim candidacy. Works as a table view for human inspection or JSONL for machine consumers.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Arguments

- No arguments: show all loops as an ASCII table (default)
- `--json`: emit JSONL (one loop per line) for machine consumers
- `--reclaim-candidates`: filter table to only loops flagged for reclaim
- `<loop_id>`: show single loop in detail (preserves Phase 8 behavior as fallback)

## Implementation

### Step 1: Load libraries

```bash
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PLUGIN_DIR/scripts/status-lib.sh" || {
  echo "ERROR: Cannot load status-lib.sh" >&2
  exit 1
}
```

### Step 2: Parse arguments

```bash
case "${1:-}" in
  --json)
    enumerate_loops | cat  # Raw JSONL output
    exit 0
    ;;
  --reclaim-candidates)
    enumerate_loops | jq -r 'select(.reclaim_candidate == "yes") | @json' | format_status_table
    exit 0
    ;;
  "")
    # Default: show all loops as table
    enumerate_loops | format_status_table
    exit 0
    ;;
  *)
    # Fallback: treat as loop_id (single-loop detail from Phase 8)
    # This preserves backward compatibility
    loop_id="$1"
    enumerate_loops | jq -r "select(.loop_id == \"$loop_id\")" | jq .
    exit 0
    ;;
esac
```

## Output Formats

### Table (default)

```
LOOP_ID      SESSION  STATUS    LAST_WAKE  DEAD STALE  RECLAIM
———————————— ———————— ————————— —————————— —————— —————— ————
a1b2c3d4e5f6 session1 ACTIVE    2m ago     0.15 fresh  no
deadbeef1234 session2 STALE     1h ago     0.78 stale  yes
```

**Columns:**

| Column    | Meaning                                                                     |
| --------- | --------------------------------------------------------------------------- |
| LOOP_ID   | 12-character hexadecimal loop identifier                                    |
| SESSION   | First 8 characters of owner_session_id (session context)                    |
| STATUS    | ACTIVE (owner alive, fresh heartbeat) / STALE / DEAD                        |
| LAST_WAKE | Relative time of last heartbeat (e.g., "2m ago", "—" if never)              |
| DEAD      | Dead-time ratio (0.00–1.00): fraction of lifespan the loop was inactive     |
| STALE     | Staleness flag: "fresh" (within 3× cadence), "stale" (>3×), "—" (no data)   |
| RECLAIM   | "yes" if loop can be reclaimed (dead owner + old state dir), "no" otherwise |

### JSONL (--json)

One JSON object per line, no top-level array. Fields:

```json
{
  "loop_id": "a1b2c3d4e5f6",
  "session_id": "session1",
  "status": "ACTIVE",
  "last_wake_us": "1725000000000000",
  "last_wake_human": "2m ago",
  "dead_time_ratio": "0.15",
  "staleness_flag": "fresh",
  "reclaim_candidate": "no"
}
```

### Reclaim Candidates (--reclaim-candidates)

Filters JSONL to `reclaim_candidate == "yes"` and formats as table. Use with `/autonomous-loop:reclaim <loop_id>` to clean up.

### Single Loop Detail (<loop_id>)

Shows a single loop's entry as formatted JSON (Phase 8 compatibility).

## Status Derivation

- **ACTIVE**: owner_pid is alive AND staleness ≤ 3× expected_cadence
- **STALE**: owner_pid alive but staleness > 3× expected_cadence (stuck/paused process)
- **DEAD**: owner_pid dead OR staleness > 4× expected_cadence (no recovery possible)
- **SATURATED** (Phase 11): contract marked done or stop event in revision-log

## Reclaim Candidacy (Phase 10 STAT-02)

A loop is flagged "reclaim_candidate: yes" if:

1. Owner PID is dead AND state-dir mtime > 7 days, OR
2. Original Phase 4 predicate (owner dead OR heartbeat >3× cadence stale)

Use `/autonomous-loop:reclaim <loop_id>` to manually clean up stale entries.

## Dead-Time Ratio Formula

```
dead_time_ratio = 1 - (heartbeat_count × cadence / lifespan)
```

- Approximates activity by counting heartbeat iterations
- Clamped to [0.00, 1.00]
- Helps identify chronically hung or underutilized loops

## Examples

```bash
# Show all loops
/autonomous-loop:status

# Export to JSON for external processing
/autonomous-loop:status --json | jq '.[] | select(.status == "STALE")'

# Find loops ready for cleanup
/autonomous-loop:status --reclaim-candidates

# Check single loop (backward compat)
/autonomous-loop:status a1b2c3d4e5f6
```

## Troubleshooting

| Symptom              | Fix                                                                    |
| -------------------- | ---------------------------------------------------------------------- |
| "No active loops"    | No loops registered; run `/autonomous-loop:start` to create one        |
| All loops DEAD       | Likely system restart; loops recover on next iteration                 |
| high dead_time_ratio | Loop may be saturated or paused; check reclaim eligibility             |
| JSONL parse error    | Heartbeat file corrupted; check state_dir for malformed heartbeat.json |

## Anti-patterns

- Do NOT modify the registry or state-dir while status is running
- Do NOT use status to trigger cleanup (use explicit `/autonomous-loop:reclaim` command)

## Post-Execution Reflection

0. **Locate yourself.** — Confirm this SKILL.md is the canonical file before any edit.
1. **What failed?** — Fix the instruction that caused it.
2. **What drifted?** — Update status derivation or output format if registry schema changed.
3. **Log it.** — Evolution-log entry.
