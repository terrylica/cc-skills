# Phase 38: Doctor & Self-Heal - Context

**Gathered:** 2026-04-29
**Status:** Ready for planning (after Phases 35, 36, 37 complete)
**Mode:** Pre-authored

<domain>
## Phase Boundary

Operator-facing self-diagnostic: a `/autonomous-loop:doctor` skill that produces a per-loop GREEN/YELLOW/RED report with remediation hints. A `heal-self.sh` migration that auto-archives stale registry entries on every fresh SessionStart, idempotent via content-hash gating. The existing `status` skill surfaces a one-line doctor verdict at the top of its output.

This phase makes the system self-diagnostic — the user can ask "is everything OK?" from inside Claude Code at any time and get a structured answer, instead of having to reverse-engineer launchctl state and JSONL contents like we did in the 2026-04-29 incident.

</domain>

<decisions>
## Implementation Decisions

### Locked

- Doctor output format: terminal-friendly table with severity colors (where supported) + JSON mode for programmatic consumption.
- `--fix` mode is opt-in and only does SAFE operations: unload orphan plists, archive corrupted registry entries, prune `/var/folders/*` test entries. NEVER spawns claude. NEVER auto-reclaims an active loop.
- `heal-self.sh` runs on SessionStart but gated by content-hash of registry: skips work if registry hash matches last-healed hash (stored in `~/.claude/loops/.last-healed-hash`).
- "Stale" definition: `owner_session_id ∈ {"unknown", "unknown-session", "", "pending-bind"}` AND last_updated > 1 hour ago.

### Claude's Discretion

- Color codes (use ANSI if `[ -t 1 ]`, fall back to text symbols otherwise).
- Whether the doctor returns non-zero exit code on RED (probably yes; useful for shell pipelines).
- JSONL transcript scanning: read first/last 10 lines per session JSONL to detect multi-cwd contamination (full scan is too expensive on 277MB JSONLs).

</decisions>

<code_context>

## Files to Read Before Editing

- `plugins/autonomous-loop/scripts/status-lib.sh` — `loop_status`, `format_status_table`; doctor reuses verdict surface
- `plugins/autonomous-loop/scripts/registry-lib.sh` — registry parsing; content hash via `jq -S | shasum`
- `plugins/autonomous-loop/hooks/session-bind.sh` (from Phase 36) — invokes `heal-self.sh` once per registry hash
- `plugins/autonomous-loop/skills/status/SKILL.md` — to surface verdict at top
- `~/.claude/projects/<sanitized-cwd>/<sid>.jsonl` — multi-cwd contamination detection target

</code_context>

<doctor_checks>

## Doctor's Detection Catalog

| Check                  | RED                                                     | YELLOW                                               | GREEN                               |
| ---------------------- | ------------------------------------------------------- | ---------------------------------------------------- | ----------------------------------- |
| Registry vs launchctl  | plist has Label, registry has no entry (zombie waker)   | registry entry has launchd_label, plist file missing | match                               |
| Heartbeat freshness    | no heartbeat AND last_updated > 1h                      | no heartbeat AND last_updated < 1h                   | heartbeat present, age < 3× cadence |
| JSONL multi-cwd        | session JSONL contains 2+ distinct cwds (contamination) | session JSONL contains paths to deleted dirs         | single cwd, all paths exist         |
| Label uniqueness       | `launchctl list \| grep -c <label>` >= 2                | (n/a)                                                | exactly 1 (or 0 if not loaded)      |
| Owner liveness         | `kill -0 owner_pid` fails AND >1h since heartbeat       | dead pid but recent heartbeat (race)                 | alive                               |
| Pending-bind staleness | owner_session_id="pending-bind" AND created >1h ago     | pending-bind <1h                                     | bound                               |

</doctor_checks>

<tests>

## Test Coverage

- `test-doctor.sh` — 7 cases (synthesize each scenario, run doctor, assert verdict):
  1. Clean state → all GREEN
  2. Zombie launchctl entry (no registry) → RED, doctor lists exact `launchctl bootout` command
  3. Multi-cwd JSONL → RED, doctor cites the offending JSONL path + the two cwds
  4. Stale `pending-bind` (>1h) → YELLOW, suggest re-running `/autonomous-loop:start`
  5. Dead owner_pid + recent heartbeat → YELLOW
  6. `--fix` mode: zombie scenario → unloads, removes plist, prints what was done
  7. JSON output mode: parses as valid JSON with `loops[].verdict` and `loops[].issues[]`
- `test-heal-self.sh` — 4 cases:
  1. First call on dirty registry → archives stale entries, writes hash
  2. Second call same hash → no-op (gated)
  3. Registry mutated externally → hash mismatch, runs heal again
  4. Heal preserves entries with `owner_session_id` matching UUID (not in stale set)

</tests>
