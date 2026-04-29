# Phase 35: Provenance Foundation - Context

**Gathered:** 2026-04-29
**Status:** Ready for planning
**Mode:** Pre-authored (design locked in v4.10.0 milestone scaffolding turn)

<domain>
## Phase Boundary

Introduce an append-only provenance ledger primitive (`provenance-lib.sh`) that all subsequent v4.10.0 phases (36, 37, 38) consume. Every state mutation writes a typed event to `<state_dir>/provenance.jsonl` with a mirror to the global `~/.claude/loops/global-provenance.jsonl` (rotated at 10k lines). No registry or heartbeat code is changed in this phase — only the new shared library plus tests.

This is a foundation phase: it adds a primitive that other phases will consume but doesn't change observable autonomous-loop behavior on its own.

</domain>

<decisions>
## Implementation Decisions

### Locked

- Schema is JSONL with one event per line, schema-versioned (`schema_version: 1`).
- Atomic writes via `mktemp` + atomic `mv` in same filesystem (defends Pitfall #4 documented in autonomous-loop CLAUDE.md).
- `flock` on the global mirror file via fd 9 to serialize cross-process writes.
- Rotation: when global mirror reaches 10000 lines, oldest 5000 are moved to `global-provenance.<unixts>.jsonl.gz` and gzipped.
- Per-loop ledger never rotates (loop lifetime is bounded; per-loop volume is small).

### Claude's Discretion

- Exact gzip tool (system `gzip` is fine; no need for `pigz` etc).
- Whether to expose `emit_provenance` as a single function with positional + named args (preferred) or a builder pattern. Pick whichever is smaller and clearer in shell.
- Test fixture isolation: use `mktemp -d` per test and override `HOME` so global mirror lives in the temp dir.

</decisions>

<code_context>

## Existing Code Insights

### Files to Read Before Editing

- `plugins/autonomous-loop/scripts/registry-lib.sh` — `_with_registry_lock` pattern for atomic JSON updates; mimic this for provenance writes
- `plugins/autonomous-loop/scripts/state-lib.sh` — `now_us` helper; `write_heartbeat` mktemp+mv pattern (CLAUDE.md "Pitfall #4")
- `plugins/autonomous-loop/CLAUDE.md` — 6 catastrophic pitfalls; new lib must respect Pitfalls #3, #4, #5
- `plugins/autonomous-loop/tests/test-registry-write.sh` — concurrent-write test pattern to mimic for provenance

### Key Constraints

- **No `gh` calls** in the new lib (per global CLAUDE.md "Process Storm Prevention").
- **`set -euo pipefail`** in every script.
- **Exit 0 on graceful failure** when called from a hook (matches existing convention; provenance failure must never block a tool call).
- **Tests use bash, not bats** (matches existing `tests/` style).

</code_context>

<schema>

## Provenance Line Schema (v1)

```json
{
  "ts_iso": "2026-04-29T03:14:15.926Z",
  "ts_us": 1777267455926000,
  "event": "bind_first|bind_resume|bind_refused|cwd_drift_detected|spawn_attempted|spawn_refused|spawn_succeeded|reclaim_attempted|reclaim_succeeded|label_collision_detected|heal_archived|doctor_check",
  "loop_id": "5966ec96ceb4",
  "agent": "session-bind.sh|heartbeat-tick.sh|waker.sh|doctor-lib.sh|start.SKILL|reclaim.SKILL",
  "session_id": "<observed UUID or null>",
  "cwd_observed": "/Users/.../opendeviationbar-patterns",
  "cwd_bound": "/Users/.../opendeviationbar-patterns",
  "registry_generation": 3,
  "owner_pid_before": 27466,
  "owner_pid_after": 41734,
  "reason": "<human-readable, e.g. 'session_id ambiguous: empty'>",
  "decision": "proceeded|refused|deferred",
  "schema_version": 1
}
```

Reserved-for-future fields (must not collide): `evict_reason`, `correlation_id`.

</schema>

<api>

## Library API

```bash
# emit_provenance <loop_id> <event> [field=value]...
# Writes one JSONL line to <state_dir>/provenance.jsonl AND ~/.claude/loops/global-provenance.jsonl
# state_dir is resolved from registry; agent is auto-detected from $0 (or override via _PROV_AGENT)
emit_provenance "5966ec96ceb4" "bind_first" \
  session_id="$SID" \
  cwd_observed="$CWD" \
  reason="first heartbeat after pending-bind"
```

```bash
# rotate_global_provenance
# Idempotent; checks line count and rotates if >10k
rotate_global_provenance
```

</api>

<tests>

## Test Coverage

- `test-provenance.sh` — 5 cases:
  1. Single-event happy path (per-loop + global mirror both written, schemas valid)
  2. Concurrent writes from 10 background processes (no torn lines, all 10 lines present in both)
  3. Rotation at line 10k (oldest 5k gzipped to `.jsonl.gz`, current file has 5k+1 lines)
  4. Missing state_dir (degrades gracefully: writes to global mirror only, returns 0)
  5. Schema validation (every line parses as JSON, has required fields, schema_version=1)

</tests>
