---
phase: 35-provenance-foundation
plan: 01
subsystem: autonomous-loop
tags: [provenance, ledger, audit, schema-versioned, anti-fragility]

requires:
  - phase: prior-art
    provides: registry-lib.sh read_registry_entry; state-lib.sh now_us; CLAUDE.md Pitfall #4 mktemp+mv pattern
provides:
  - emit_provenance(loop_id, event, fields...) — atomic dual-write JSONL ledger primitive
  - rotate_global_provenance — idempotent 10k-line archival rotation
  - schema_version=1 contract with 14 required fields
  - cross-platform locking (flock | lockf | POSIX O_APPEND fallback)
affects:
  - Future consumers in Phase 36 (binding events), Phase 37 (waker refusals), Phase 38 (doctor checks)

tech-stack:
  added: [provenance-lib.sh]
  patterns:
    - "Append-only schema-versioned ledger (intent-before-state-write)"
    - "Cross-platform fd-9 flock + lockf fallback + POSIX O_APPEND atomicity"
    - "Forward-compat field handling (unknown fields silently ignored)"

key-files:
  created:
    - plugins/autonomous-loop/scripts/provenance-lib.sh
    - plugins/autonomous-loop/tests/test-provenance.sh
  modified: []

key-decisions:
  - "schema_version=1 with 14 required fields enforced via fixed jq template"
  - "Empty-string args coerce to JSON null; numeric strings coerce to JSON numbers"
  - "Returns 0 on all paths (fail-graceful for hook/waker callers — provenance must never block tool calls)"
  - "Decoupled from registry/heartbeat — this lib does NOT mutate either; callers do, and emit a provenance event before/after their own mutation"
  - "lockf fallback runs the rotation body unlocked after acquiring/releasing the lock — acceptable because rotation is idempotent on retry"
  - "Auto-detect agent via BASH_SOURCE[1] basename; override via _PROV_AGENT env var"

patterns-established:
  - "Cross-platform locking pattern matches registry-lib.sh _with_registry_lock"
  - "Test pattern: HOME-isolated mktemp -d, source library after env var overrides, stub registry callbacks"

requirements-completed: [PROV-01, PROV-02, PROV-03, PROV-04]

duration: ~25min (design pre-locked; impl + test + 1 macOS lock-tool fallback iteration)
completed: 2026-04-29
---

# Phase 35 Plan 01: Provenance Foundation Summary

**Append-only schema-versioned ledger primitive that subsequent v4.10.0 phases consume for auditing every state mutation in the autonomous-loop plugin.**

## Performance

- **Duration:** ~25 min
- **Tasks:** 3 (lib + tests + run-and-commit)
- **Tests:** 21 assertions across 5 cases, all green
- **shellcheck:** Clean (0 issues)
- **Plugin validation:** PASS (34/34 plugins)

## What Shipped

### `plugins/autonomous-loop/scripts/provenance-lib.sh` (~240 LOC)

Two exported functions:

- `emit_provenance(loop_id, event, fields...)` — writes one JSONL line to:
  - `<state_dir>/provenance.jsonl` (skipped silently if state_dir unresolvable from registry)
  - `~/.claude/loops/global-provenance.jsonl` (always, with fallback if global dir creation fails)
- `rotate_global_provenance` — when global mirror exceeds 10k lines, archives oldest 5k to gzipped `global-provenance.<unixts>.jsonl.gz`, leaves newest 5k in place

### `plugins/autonomous-loop/tests/test-provenance.sh` (~210 LOC)

Five test cases × 21 assertions:

1. **Happy path** — single emit writes valid schema to both ledgers
2. **Concurrent writes** — 10 parallel processes, no torn lines, all reasons present
3. **Rotation** — pre-populates 101 lines (with test thresholds), verifies archive/current line ranges and gzip success
4. **Missing state_dir** — graceful degrade: only global mirror written, no stray per-loop ledger
5. **Schema validation** — all required fields present, numeric coercion correct, empty→null

## Schema (`schema_version: 1`)

Each line is JSONL with these 14 keys (no exceptions):

```
ts_iso, ts_us, event, loop_id, agent, session_id,
cwd_observed, cwd_bound, registry_generation,
owner_pid_before, owner_pid_after, reason, decision,
schema_version
```

## Decisions Worth Calling Out

- **Cross-platform locking discovered mid-implementation** — initial `flock`-only version failed on macOS (which doesn't ship flock by default). Adopted the same fallback chain as `registry-lib.sh _with_registry_lock`: `flock` → `lockf` → unlocked POSIX O_APPEND. JSON lines are well under PIPE_BUF (4096B), so unlocked appends remain atomic per POSIX even when no lock tool is available.
- **Decoupling from registry/heartbeat is intentional** — Phase 36/37/38 will _call_ `emit_provenance` from inside their own atomic state mutations. This keeps the ledger primitive free of cyclic dependencies.

## Refs

- Requirements: PROV-01, PROV-02, PROV-03, PROV-04
- Commit: `124f8bb3 feat(autonomous-loop): add provenance-lib.sh foundation (PROV-01..04)`
- CLAUDE.md alignment: Pitfall #3 (cross-fs lock), Pitfall #4 (atomic mktemp+mv), fail-graceful exit-0-in-hooks convention
