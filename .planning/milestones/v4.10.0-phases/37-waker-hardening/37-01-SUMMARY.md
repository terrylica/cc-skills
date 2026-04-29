---
phase: 37-waker-hardening
plan: 01
subsystem: autonomous-loop
tags: [waker, launchd, invariants, refuse-by-default, anti-fragility]

requires:
  - phase: 35-provenance-foundation
    provides: emit_provenance for typed spawn refusals
  - phase: 36-hook-time-binding
    provides: bound_cwd field, cwd_drift_detected flag, owner_session_id binding
provides:
  - Five-check invariant gate before every claude --resume spawn
  - cd to dirname(contract_path) on resume (was: dirname(state_dir))
  - Launchd Label collision detection in generate_plist with orphan archival
  - Typed spawn_refused_<which> provenance + notification on every refusal
affects:
  - Phase 38 doctor will surface the spawn_refused_* events for operator visibility

tech-stack:
  added: []
  patterns:
    - "Refuse-by-default invariant gate inside spawn function"
    - "BASH_SOURCE guard for main() dispatch (lets tests source the file)"
    - "PATH-shim for testing launchctl-dependent code"

key-files:
  created:
    - plugins/autonomous-loop/tests/test-spawn-invariant.sh
    - plugins/autonomous-loop/tests/test-plist-collision.sh
  modified:
    - plugins/autonomous-loop/scripts/waker.sh
    - plugins/autonomous-loop/scripts/launchd-lib.sh

key-decisions:
  - "5 invariants ordered cheap-to-expensive: UUID syntax (free) → heartbeat exists (1 stat) → bound_cwd field (1 jq) → launchctl list (process spawn) → registry re-read under generation check (most expensive)"
  - "launchd Label collision is auto-resolved (archive + bootout + regenerate), not refused — regenerating a fresh plist is the safe healing action; refusing would leave the loop unstartable"
  - "Spawn refusal returns 0, not 1 — refusing is a normal control-flow outcome, not an error. Caller (waker.sh main) treats it as 'cycle complete, no action this tick'"
  - "Wrap main() dispatch in BASH_SOURCE guard so tests can source waker.sh and call _invariant_check_spawn directly without triggering the cron entrypoint"

patterns-established:
  - "PATH-shim test pattern: stub-bin/<command> with a state-file-driven fake; export PATH=stub-bin:$PATH"
  - "find-with-existence-guard pattern in tests: avoid pipefail trap from find on non-existent dir"

requirements-completed: [WAKE-01, WAKE-02, WAKE-03, WAKE-04, WAKE-05]

duration: ~45min (impl + 2 small fixes: shellcheck SC2155 in launchd-lib, test-stack issue with find on missing dir)
completed: 2026-04-29
---

# Phase 37 Plan 01: Waker Hardening + launchd Collision Defense Summary

**Make `claude --resume` structurally impossible to spawn unless five invariants hold; auto-resolve launchd Label collisions in `generate_plist`.**

## Performance

- **Duration:** ~45 min
- **Tasks:** 5 (waker hardening + launchd collision + 2 test scripts + run+commit)
- **Tests:** 13 new assertions across 9 cases (6 in test-spawn-invariant.sh, 7 in test-plist-collision.sh)
- **Regression:** Phase 35 + 36 tests (37 assertions) all green
- **shellcheck:** Clean
- **Plugin validation:** PASS (1 known non-blocking warning about SessionStart hook classifier)

## What Shipped

### `scripts/waker.sh` modifications

- New `_invariant_check_spawn(loop_id, entry, session_id, cadence)` function — runs 5 checks; emits typed `spawn_refused_<which>` provenance + notification on any failure; returns 1 (caller bails). On all-pass: emits `spawn_invariants_passed` provenance, returns 0.
- `spawn_claude_resume` rewired: invariant gate first, then cd to `dirname(contract_path)` (was: `dirname(state_dir)`).
- `main()` dispatch wrapped in `${BASH_SOURCE[0]} == $0` guard so tests can source the file without triggering cron entrypoint.

### `scripts/launchd-lib.sh` modifications

- `generate_plist` now detects pre-existing launchd Labels and stale plist files. Archives both to `state_dir/orphans/<unixts>/`, calls `launchctl bootout` if loaded, then regenerates. Emits `label_collision_resolved` provenance event.

### Tests

- `test-spawn-invariant.sh` — 6 cases: invalid-UUID (`pending-bind`), no-heartbeat, cwd drift (bound_cwd mismatch), cwd_drift_detected flag set, generation drift mid-check, happy path.
- `test-plist-collision.sh` — 3 cases via PATH-shimmed `launchctl`: no existing plist (clean write), stale plist file (archived), loaded plist (bootout + archive + regen).

## The Five-Check Invariant

```
spawn_claude_resume(loop_id) gate:

  (a) session_id =~ ^[0-9a-f-]{36}$        # real UUID
  (b) heartbeat.json exists                # proof of life
  (c) bound_cwd == dirname(contract_path)  # no cwd drift
       AND cwd_drift_detected != true      # no flagged drift
  (d) launchctl list | count(label) <= 1   # no collision
  (e) registry generation unchanged         # no concurrent reclaim

ALL pass:  emit spawn_invariants_passed; proceed
ANY fail:  emit spawn_refused_<which> + notification; return 0 (no spawn)
```

## Decisions Worth Calling Out

- **Refusal returns 0, not 1.** A refused spawn is a _normal_ control-flow outcome (the system is intentionally not auto-resuming because something is off), not an error. Returning 1 would propagate up and set off error traps; 0 communicates "tick complete, no action this iteration."
- **Label collision auto-heals; cwd drift refuses.** They sound similar but are categorically different: a stale plist is a recoverable artefact (regenerating is safe), while cwd drift means a session went somewhere it shouldn't and we can't tell if its identity is still trustworthy — only an operator decision (`/autonomous-loop:reclaim` or `doctor --fix`) can clear it.
- **The test design forced one waker.sh refactor.** Tests need to source waker.sh to call `_invariant_check_spawn` directly, but the bottom of the file ran `main "$1"` unconditionally — sourcing would fail-and-exit because no `$1` was provided. Wrapping in a `BASH_SOURCE[0] == $0` guard is the canonical fix and now enables future direct-test patterns for any other waker functions.

## Refs

- Requirements: WAKE-01, WAKE-02, WAKE-03, WAKE-04, WAKE-05
- Commit: `8feb534b feat(autonomous-loop): waker hardening + launchd collision defense (WAKE-01..05)`
- Root cause traceability: `1c58cfbc-…jsonl` (two distinct cwds) was caused by `cd $(dirname state_dir)` in spawn_claude_resume — fixed by WAKE-02.
