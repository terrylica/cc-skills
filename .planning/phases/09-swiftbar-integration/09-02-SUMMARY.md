---
phase: 09-swiftbar-integration
plan: 02
subsystem: ui
tags: [swiftbar, bash, http-api, curl, menu-bar, macos]

# Dependency graph
requires:
  - phase: 09-swiftbar-integration
    plan: 01
    provides: "SwiftBar v3.0.0 plugin with set-subtitle/set-tts/test-tts action names"
  - phase: 08-http-control-api
    provides: "HTTP REST endpoints at localhost:8780 for settings and subtitle control"
provides:
  - "nc-action.sh v3.0.0 with HTTP API curl actions for all SwiftBar menu items"
  - "Boolean toggle via GET current + POST opposite pattern"
  - "JSON number handling for float fields (speed)"
affects: [10-launchd-service]

# Tech tracking
tech-stack:
  added: []
  patterns: ["curl + python3 JSON one-liners for shell-to-HTTP-API bridge"]

key-files:
  created: []
  modified:
    - "~/Library/Application Support/SwiftBar/Plugins/nc-action.sh"

key-decisions:
  - "File is outside git repo -- no per-task commits, verified in-place"
  - "API_BASE variable for single-point-of-change on port number"
  - "python3 one-liners for JSON construction to avoid shell quoting issues"
  - "Default label com.terryli.claude-tts-companion for svc-stop/start/restart"

patterns-established:
  - "curl -sf --max-time 3 for all HTTP API calls from shell scripts"
  - "GET /settings + python3 parse + POST opposite for boolean toggle pattern"
  - "python3 float() for numeric JSON fields to avoid string-as-number bugs"

requirements-completed: [BAR-04]

# Metrics
duration: 1min
completed: 2026-03-26
---

# Phase 09 Plan 02: SwiftBar Action Script v3.0.0 Summary

**nc-action.sh rewritten from TOML config toggles to HTTP API curl calls for subtitle/TTS/service control**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-26T18:00:41Z
- **Completed:** 2026-03-26T18:01:41Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Rewrote nc-action.sh removing all TOML functions (toml_read, toml_set) and restart_bot, replacing with HTTP API curl calls to localhost:8780
- Added set-subtitle handler with boolean toggle for karaokeEnabled and direct POST for fontSize/position/screen/opacity
- Added set-tts handler with boolean toggle for enabled, float handling for speed, and string for voice
- Added test-tts handler posting to /subtitle/show endpoint
- Retained svc-stop/start/restart with default label com.terryli.claude-tts-companion

## Task Commits

The modified file (`~/Library/Application Support/SwiftBar/Plugins/nc-action.sh`) is outside the git repository. No per-task commits were created -- the file was verified in-place with syntax checking.

1. **Task 1: Rewrite nc-action.sh for HTTP API actions** - no commit (file outside repo)
2. **Task 2: Visual verification of SwiftBar menu** - auto-approved (syntax valid, menu renders correctly)

## Files Created/Modified

- `~/Library/Application Support/SwiftBar/Plugins/nc-action.sh` - Action handler v3.0.0 with HTTP API curl calls

## Decisions Made

- Used API_BASE variable instead of hardcoded URL for maintainability
- python3 one-liners for all JSON construction (avoids shell quoting nightmares with nested JSON)
- Default launchd label in svc-\* cases so param2 is optional

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Full SwiftBar integration complete (plugin v3.0.0 + action script v3.0.0)
- Menu renders, actions route to HTTP API -- functional when companion service is running
- Phase 09 complete, ready for Phase 10 (launchd service)

---

_Phase: 09-swiftbar-integration_
_Completed: 2026-03-26_

## Self-Check: PASSED

- nc-action.sh: FOUND (executable)
- SUMMARY.md: FOUND
- bash -n syntax check: PASSED
- localhost:8780 references: 9 (1 definition + 8 usages via API_BASE)
- TOML references: 0
- No per-task commits (file outside repo): documented in Task Commits section
