---
phase: 36-hook-time-binding
plan: 01
subsystem: autonomous-loop
tags: [hooks, session-binding, stdin-payload, cwd-drift, anti-fragility]

requires:
  - phase: 35-provenance-foundation
    provides: emit_provenance primitive (consumed by all binding decisions)
provides:
  - hooks/session-bind.sh — SessionStart hook with stdin-driven atomic binding state machine
  - heartbeat-tick.sh rewrite — reads stdin payload; bound_cwd recording + cwd-drift detection; survives write_heartbeat overwrite via read-before/merge-after pattern
  - hook-install-lib.sh — install_all_hooks / uninstall_all_hooks composites; per-hook installers for SessionStart
  - skills/start — owner_session_id=pending-bind canonical placeholder; install_all_hooks bootstrap
affects:
  - Phase 37 will consume bound_cwd + cwd_drift_detected in waker pre-spawn invariant
  - Phase 38 doctor will consume bind_first/observer/stale_owner_detected provenance events for fleet diagnostics

tech-stack:
  added: [SessionStart hook, two-pass loop matching by session_id then cwd]
  patterns:
    - "Hook-stdin payload as authoritative session identity source (working around anthropics/claude-code#47018)"
    - "Read-before/merge-after to preserve hook-extension fields across write_heartbeat overwrites"
    - "State-machine binding: pending-bind | observer | stale_owner_detected | bind_resume"
    - "Refuse-by-default: stale_owner_detected emits provenance but does NOT auto-reclaim"

key-files:
  created:
    - plugins/autonomous-loop/hooks/session-bind.sh
    - plugins/autonomous-loop/tests/test-session-bind.sh
    - plugins/autonomous-loop/tests/test-heartbeat-stdin.sh
  modified:
    - plugins/autonomous-loop/hooks/heartbeat-tick.sh
    - plugins/autonomous-loop/scripts/hook-install-lib.sh
    - plugins/autonomous-loop/skills/start/SKILL.md

key-decisions:
  - "Two-pass loop match in heartbeat-tick: primary by owner_session_id, fallback by cwd-prefix. Without this a session that drifts out of contract dir would silently lose its loop binding (and we couldn't detect the drift) — defense became the test that exposed the design gap"
  - "bound_cwd persistence: write_heartbeat replaces the entire JSON; we read bound_cwd BEFORE the rewrite and merge it back AFTER via jq tmp+mv pattern"
  - "stale_owner_detected does NOT auto-reclaim — Phase 38 doctor + manual /autonomous-loop:reclaim are the only sanctioned recovery paths. Worst outcome: loop didn't auto-resume → user notices via doctor. Never: loop resumed wrong session → silent corruption"
  - "Multi-session same-folder is now first-class: first session in folder owns the loop; subsequent sessions log observer and do NOT mutate. Eliminates the cross-contamination scenario that produced the 1c58cfbc JSONL with two cwds"

patterns-established:
  - "Hook env var deprecation pattern: stdin payload primary, $CLAUDE_SESSION_ID env-var as deprecated back-compat fallback"
  - "FILE-SIZE-OK escape hatch when split would create artificial cohesion break (used in hook-install-lib.sh at 700+ lines after extension)"

requirements-completed: [BIND-01, BIND-02, BIND-03, BIND-04]

duration: ~50min (impl + 1 design-gap fix iteration uncovered by test 2 for cwd-drift)
completed: 2026-04-29
---

# Phase 36 Plan 01: Hook-Time Binding Summary

**Move session→loop binding from skill-Bash-subprocess (broken `$CLAUDE_SESSION_ID`) to hook-time stdin payloads; detect cwd drift on every heartbeat tick.**

## Performance

- **Duration:** ~50 min
- **Tasks:** 7 (session-bind hook + heartbeat rewrite + hook-install lib extension + start skill update + 2 test scripts + run+commit)
- **Tests:** 16 new assertions across 8 cases (10 in test-session-bind.sh, 6 in test-heartbeat-stdin.sh)
- **Regression:** Phase 35 test-provenance.sh continues to pass (21/21)
- **shellcheck:** Clean on all 6 touched .sh files
- **Plugin validation:** PASS (1 non-blocking warning — scanner can't classify SessionStart hooks)

## What Shipped

### `hooks/session-bind.sh` (new, ~190 LOC)

Authoritative SessionStart hook. Reads `{session_id, cwd, source}` from stdin (Claude Code's documented hook contract). For each registered loop where `cwd` lies under `dirname(contract_path)`:

```
owner_session_id state                  → action
─────────────────────────────────────   ──────────────
"" / unknown / unknown-session /         bind_first (atomic CAS)
  pending-bind
matches current session_id               bind_resume (idempotent)
other UUID, owner_pid alive              observer (NO mutation)
other UUID, owner_pid dead, age >1h      stale_owner_detected (NO auto-reclaim)
other UUID, owner_pid dead, age <1h      observer (race-window grace)
```

Every transition logs to provenance via the Phase 35 primitive.

### `hooks/heartbeat-tick.sh` (rewritten)

- **stdin first**: reads `session_id` and `cwd` from JSON payload; falls back to `$CLAUDE_SESSION_ID` env var only as a deprecated back-compat path.
- **Two-pass loop match**: primary by `owner_session_id == this_session`, fallback by cwd-prefix. Survives mid-session cwd drift so the drift can actually be detected.
- **bound_cwd preservation**: reads bound_cwd from existing heartbeat BEFORE `write_heartbeat` (which would overwrite it), then re-merges via jq tmp+mv after the write completes.
- **Drift detection**: if `bound_cwd` is set and current `CWD` doesn't start with it, sets `cwd_drift_detected: true` in heartbeat.json AND emits `cwd_drift_detected` provenance event.

### `scripts/hook-install-lib.sh` (extended, ~250 LOC added)

New: `install_session_bind`, `uninstall_session_bind`, `install_session_bind_impl`, `uninstall_session_bind_impl`, `is_session_bind_installed`, `hook_path_default_session_bind`, plus composites `install_all_hooks` / `uninstall_all_hooks` (recommended public entry points).

### `skills/start/SKILL.md`

- Step 1 now calls `install_all_hooks` instead of `install_hook` — both hooks installed atomically.
- Step 5 sets `owner_session_id="pending-bind"` and `bound_cwd=""` instead of capturing the broken env var. Inline note links the upstream issue.

## Decisions Worth Calling Out

- **The drift-detection test exposed a design gap that drove the two-pass match.** Initial implementation matched only by cwd-prefix; once a session drifted _out_ of its contract dir, no loop would match in heartbeat-tick, so the drift was undetectable. Adding the primary `owner_session_id`-based match made drift visible — this is the test reaching back and improving the design.
- **bound_cwd persistence required reading-before-write.** `write_heartbeat` (in state-lib.sh) replaces the entire JSON object — it doesn't merge. Phase 38's doctor will eventually want more fields here, so the read-before/merge-after pattern is now the canonical extension point.
- **No auto-reclaim** — even when an owner is dead AND last_updated >1h. The doctor (Phase 38) will surface stale_owner_detected events for explicit user action via `/autonomous-loop:reclaim` or `doctor --fix`. This is the refuse-by-default principle in action.

## Refs

- Requirements: BIND-01, BIND-02, BIND-03, BIND-04
- Commit: `76359bfd feat(autonomous-loop): hook-time session-loop binding (BIND-01..04)`
- Upstream context: [anthropics/claude-code#47018](https://github.com/anthropics/claude-code/issues/47018) (env var not exposed to skill Bash subprocesses)
