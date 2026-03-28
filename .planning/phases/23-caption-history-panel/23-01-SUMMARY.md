---
phase: 23-caption-history-panel
plan: 01
subsystem: ui
tags: [appkit, nspanel, nstableview, caption-history, clipboard]

requires:
  - phase: 22-bionic-reading-mode
    provides: CompanionCore library with SubtitlePanel and CaptionHistory
provides:
  - CaptionHistoryPanel scrollable NSPanel with timestamps and click-to-copy
  - HTTP endpoints POST /captions/panel/show and /captions/panel/hide
  - CaptionHistory onChange callback for live UI refresh
affects: [23-02, swiftbar-integration]

tech-stack:
  added: []
  patterns:
    [
      NSTableView data source/delegate in @MainActor NSPanel,
      onChange callback for cross-component refresh,
    ]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/CompanionCore/CaptionHistoryPanel.swift
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/CaptionHistory.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift

key-decisions:
  - "NSTableView with manual dataSource/delegate over NSTableViewDiffableDataSource for simplicity"
  - "Dark appearance with 95% opacity background for readability"
  - "onChange callback dispatches to main thread for safe UI refresh"

patterns-established:
  - "Interactive NSPanel pattern: titled + closable + resizable + nonactivatingPanel styleMask with ignoresMouseEvents=false"
  - "MainActor.assumeIsolated for nonisolated NSTableViewDataSource/Delegate protocol conformance"

requirements-completed: [CAPT-01, CAPT-02, CAPT-03, CAPT-04]

duration: 3min
completed: 2026-03-28
---

# Phase 23 Plan 01: Caption History Panel Summary

**Scrollable NSPanel with HH:mm timestamps, click-to-copy, auto-scroll with manual override, and HTTP show/hide endpoints**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-28T03:23:01Z
- **Completed:** 2026-03-28T03:25:36Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- CaptionHistoryPanel as @MainActor NSPanel with two-column NSTableView (time + caption)
- Click-to-copy: selecting a row copies caption text to NSPasteboard with visual feedback
- Auto-scroll to latest entry with isUserScrolling detection via NSScrollView.didLiveScrollNotification
- HTTP endpoints POST /captions/panel/show and POST /captions/panel/hide wired through CompanionApp

## Task Commits

Each task was committed atomically:

1. **Task 1: CaptionHistoryPanel NSPanel with scrollable table, timestamps, and click-to-copy** - `5b1c92a5` (feat)
2. **Task 2: HTTP panel endpoints + CompanionApp wiring** - `99141d3d` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/CompanionCore/CaptionHistoryPanel.swift` - New @MainActor NSPanel with NSTableView, HH:mm formatting, click-to-copy, auto-scroll
- `plugins/claude-tts-companion/Sources/CompanionCore/CaptionHistory.swift` - Added onChange callback for live panel refresh
- `plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift` - Added captionHistoryPanel property and POST /captions/panel/show + /hide endpoints
- `plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift` - Creates CaptionHistoryPanel, wires onChange, hides on shutdown

## Decisions Made

- Used NSTableView with manual dataSource/delegate rather than DiffableDataSource for simplicity (small dataset, full reload on each refresh)
- Dark appearance with 95% opacity background for readability while maintaining floating panel aesthetic
- MainActor.assumeIsolated used in nonisolated NSTableViewDataSource/Delegate protocol methods for Swift 6 compatibility

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Caption history panel fully functional with show/hide HTTP API
- Ready for Plan 02 (SwiftBar integration and additional refinements)

---

_Phase: 23-caption-history-panel_
_Completed: 2026-03-28_
