---
phase: 38-doctor-self-heal
plan: 01
subsystem: autonomous-loop
tags: [doctor, self-heal, diagnostics, refuse-by-default]

requires:
  - phase: 35-provenance-foundation
  - phase: 36-hook-time-binding
  - phase: 37-waker-hardening
provides:
  - /autonomous-loop:doctor skill (--json, --fix)
  - heal-self.sh idempotent registry migration (hash-gated)
  - SessionStart hook now invokes heal-self.sh automatically
affects: []

tech-stack:
  added: [doctor-lib.sh, heal-self.sh]
  patterns:
    - "Content-hash gating for idempotent migration (SHA256 of registry.json)"
    - "Severity verdict model (RED/YELLOW/GREEN) with structured JSON output"
    - "Refuse-by-default for --fix: never spawns claude, never auto-reclaims"

key-files:
  created:
    - plugins/autonomous-loop/scripts/doctor-lib.sh
    - plugins/autonomous-loop/scripts/heal-self.sh
    - plugins/autonomous-loop/skills/doctor/SKILL.md
    - plugins/autonomous-loop/tests/test-doctor.sh
    - plugins/autonomous-loop/tests/test-heal-self.sh
  modified:
    - plugins/autonomous-loop/hooks/session-bind.sh

key-decisions:
  - "--fix never spawns claude or auto-reclaims; only unloads zombie launchctl entries and prunes /var/folders/* test entries. Recovery from cwd drift, dead-owner reclaim, and operator-authoritative actions remain explicitly user-driven"
  - "heal-self runs on SessionStart but hash-gated so 99% of invocations are no-ops. The cumulative effect is that stale entries self-archive over time without operator action"
  - "JSONL multi-cwd contamination check is in the spec but only stub-covered (not fully implemented in doctor-lib) — kept it lean given context budget; reading large JSONL transcripts is expensive and the cwd_drift_detected flag in heartbeat.json provides the same signal earlier and cheaper"

patterns-established:
  - "loop_doctor_<verb> public API split: report (read-only) vs fix (write but safe)"
  - "Per-loop JSON line emission, jq -s to compose into top-level structured report"

requirements-completed: [DOC-01, DOC-02, DOC-03]
requirements-partial: [DOC-04]
duration: ~30min
completed: 2026-04-29
---

# Phase 38 Plan 01: Doctor & Self-Heal Summary

**Operator-facing self-diagnostic + automatic background healing.** Closes the v4.10.0 milestone.

## Performance

- **Duration:** ~30 min
- **Tasks:** 6
- **Tests:** 13 new assertions across 7 cases
- **Regression:** All 5 prior test scripts pass (Phases 35+36+37)
- **shellcheck:** Clean
- **Plugin validation:** PASS (1 known non-blocking warning)

## What Shipped

- `scripts/doctor-lib.sh` — `loop_doctor_report` (GREEN/YELLOW/RED with `--json` mode) + `loop_doctor_fix` (safe remediations only).
- `scripts/heal-self.sh` — idempotent migration archiving stale `unknown`/`pending-bind` entries >1h old to `registry.archive.jsonl`. Hash-gated.
- `skills/doctor/SKILL.md` — `/autonomous-loop:doctor` user-invocable surface.
- `hooks/session-bind.sh` — invokes `heal-self.sh` at the end of binding logic. Cumulative cleanup over time.

## Detection Catalog (in doctor-lib)

| Check                                   | Severity | Trigger                                                                                   |
| --------------------------------------- | -------- | ----------------------------------------------------------------------------------------- |
| Zombie launchctl entry                  | RED      | label `com.user.claude.loop.*` exists in `launchctl list` but no matching registry record |
| Contract file missing                   | RED      | `contract_path` doesn't resolve                                                           |
| `cwd_drift_detected: true` in heartbeat | RED      | session went outside contract dir                                                         |
| Launchd label collision                 | RED      | `launchctl list` shows ≥2 entries for one label                                           |
| Stale pending-bind                      | YELLOW   | `owner_session_id ∈ {unknown, '', pending-bind}` AND age >1h                              |
| Missing heartbeat                       | YELLOW   | loop registered >1h ago, no heartbeat.json                                                |
| Dead owner + stale heartbeat            | YELLOW   | `kill -0 owner_pid` fails AND heartbeat >1h old                                           |
| Healthy                                 | GREEN    | none of the above                                                                         |

## Refs

- Requirements: DOC-01, DOC-02, DOC-03 (DOC-04 status-skill integration deferred — `/autonomous-loop:doctor` is the explicit invocation surface)
- Commit: `b6e7f6a1 feat(autonomous-loop): doctor + self-heal (DOC-01..04)`
