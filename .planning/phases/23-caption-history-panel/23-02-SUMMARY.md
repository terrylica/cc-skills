---
phase: 23-caption-history-panel
plan: 02
subsystem: ui
tags: [swiftbar, bash, macos-menu, caption-history]

# Dependency graph
requires:
  - phase: 23-caption-history-panel-01
    provides: CaptionHistoryPanel NSPanel with HTTP endpoints /captions/panel/show and /hide
provides:
  - SwiftBar "Caption History" menu button triggering panel show via HTTP API
  - nc-action.sh toggle-captions handler with telemetry logging
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SwiftBar SF Symbol buttons for panel toggles"
    - "nc-action.sh curl POST for panel visibility control"

key-files:
  created: []
  modified:
    - "~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.sh"
    - "~/Library/Application Support/SwiftBar/Plugins/nc-action.sh"

key-decisions:
  - "SwiftBar button always calls /show (no toggle state tracking needed -- user closes panel via title bar X)"

patterns-established:
  - "Panel visibility via HTTP POST from SwiftBar action scripts"

requirements-completed: [CAPT-04]

# Metrics
duration: 1min
completed: 2026-03-28
---

# Phase 23 Plan 02: SwiftBar Caption History Button Summary

**SwiftBar menu button with :text.bubble: icon triggers caption history panel via POST /captions/panel/show**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-28T03:27:12Z
- **Completed:** 2026-03-28T03:28:04Z
- **Tasks:** 2 (1 auto + 1 checkpoint auto-approved)
- **Files modified:** 2

## Accomplishments

- Added "Caption History" button with :text.bubble: SF Symbol to SwiftBar Subtitle section
- Added toggle-captions case handler in nc-action.sh calling POST /captions/panel/show
- Button includes structured JSONL telemetry logging for action tracing

## Task Commits

Each task was committed atomically:

1. **Task 1: SwiftBar Caption History button + nc-action.sh handler** - No git commit (local-only deployment artifacts per Phase 22 decision)
2. **Task 2: Visual verification checkpoint** - Auto-approved in auto mode

**Plan metadata:** See final commit below (docs: complete plan)

_Note: SwiftBar plugin files are local-only deployment artifacts not tracked in git (established Phase 22 decision)._

## Files Created/Modified

- `~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.sh` - Added Caption History button line in Subtitle section after Bionic Reading toggle
- `~/Library/Application Support/SwiftBar/Plugins/nc-action.sh` - Added toggle-captions case with curl POST to /captions/panel/show and JSONL telemetry

## Decisions Made

- SwiftBar button always calls /show (not a true toggle) -- user closes panel via title bar X button (standard NSPanel .closable behavior)
- No state tracking needed for panel visibility -- simplest correct approach

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 23 (caption-history-panel) is fully complete
- Caption history feature end-to-end: Swift panel + HTTP API + SwiftBar control surface
- Ready for next milestone phase

---

_Phase: 23-caption-history-panel_
_Completed: 2026-03-28_
