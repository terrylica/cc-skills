---
phase: 09-swiftbar-integration
plan: 01
subsystem: ui
tags: [swiftbar, python, http-api, menu-bar, macos]

# Dependency graph
requires:
  - phase: 08-http-control-api
    provides: "HTTP REST endpoints at localhost:8780 for health, settings, subtitle, TTS control"
provides:
  - "SwiftBar v3.0.0 plugin monitoring unified claude-tts-companion service via HTTP API"
  - "Menu bar subtitle controls (font size, position, karaoke, screen selection)"
  - "Menu bar TTS controls (enable/disable, speed, test)"
  - "Per-subsystem health display (bot, tts, subtitle)"
affects: [09-02-action-script]

# Tech tracking
tech-stack:
  added: []
  patterns: ["urllib.request with 2s timeout for SwiftBar HTTP integration"]

key-files:
  created: []
  modified:
    - "~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.py"

key-decisions:
  - "File is outside git repo -- no per-task commits possible, verified in-place"
  - "Float comparison with 0.01 epsilon for speed checkmarks (handles 1.0 vs 1.00)"

patterns-established:
  - "api_get/api_post helpers with 2s timeout for all SwiftBar-to-companion communication"
  - "nc-action.sh param1/param2/param3 pattern for set-subtitle and set-tts actions"

requirements-completed: [BAR-01, BAR-02, BAR-03, BAR-04, BAR-05, EXT-03]

# Metrics
duration: 2min
completed: 2026-03-26
---

# Phase 09 Plan 01: SwiftBar Plugin v3.0.0 Summary

**SwiftBar plugin rewritten from dual-service TOML monitoring to single HTTP API control surface with subtitle/TTS/health sections**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-26T17:57:08Z
- **Completed:** 2026-03-26T17:58:45Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Rewrote claude-hq.10s.py from v2.0.0 to v3.0.0, replacing all TOML config reading and dual-service launchctl monitoring with HTTP API calls to localhost:8780
- Added subtitle controls: font size (S/M/L), position (top/bottom), karaoke toggle, screen selection (builtin/external)
- Added TTS controls: enable/disable toggle, speed submenu (0.8x-2.0x), test TTS button
- Per-subsystem health display (bot, tts, subtitle) from /health endpoint with uptime and RSS
- Graceful degradation when service is offline (no tracebacks, shows "Service not running")

## Task Commits

The modified file (`~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.py`) is outside the git repository. No per-task commits were created -- the file was verified in-place with syntax checking and runtime execution.

1. **Task 1: Rewrite claude-hq.10s.py v3.0.0** - no commit (file outside repo)
2. **Task 2: Verify menu output structure** - no commit (verification only)

## Files Created/Modified

- `~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.py` - SwiftBar v3.0.0 plugin with HTTP API integration, subtitle/TTS/health sections

## Decisions Made

- Used float epsilon comparison (0.01) for speed checkmarks since API returns float (1.0) vs display strings ("1.00")
- Kept `svc_pid()` function for launchd PID check alongside HTTP health check for dual-confirmation of service status

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plugin v3.0.0 is deployed and renders correctly
- nc-action.sh needs updating (Plan 02) to handle new action names: set-subtitle, set-tts, test-tts
- Until Plan 02 completes, menu items will render but clicking them will fail

---

_Phase: 09-swiftbar-integration_
_Completed: 2026-03-26_

## Self-Check: PASSED

- SUMMARY.md: FOUND
- claude-hq.10s.py: FOUND
- No per-task commits (file outside repo): documented in Task Commits section
