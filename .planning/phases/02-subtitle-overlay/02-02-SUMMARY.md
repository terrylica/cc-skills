---
phase: 02-subtitle-overlay
plan: 02
subsystem: ui
tags: [appkit, nsattributedstring, karaoke, subtitle, swift6, nspanel]

# Dependency graph
requires:
  - phase: 02-subtitle-overlay
    provides: SubtitlePanel.swift with floating NSPanel, SubtitleStyle.swift with color/font constants
provides:
  - Karaoke highlighting engine (highlightWord, showUtterance) in SubtitlePanel.swift
  - Demo mode cycling 3 sentences at 200ms/word with linger
  - main.swift wiring that creates SubtitlePanel and launches demo on startup
affects: [03-tts-engine, 07-http-api]

# Tech tracking
tech-stack:
  added: []
  patterns:
    [
      NSMutableAttributedString word-by-word construction,
      DispatchWorkItem cancellation for utterance scheduling,
    ]

key-files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitlePanel.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift

key-decisions:
  - "DispatchWorkItem array for scheduled highlights enables clean cancellation when a new utterance starts"
  - "Cumulative timing offsets (not per-word delays) for accurate word-to-time mapping"

patterns-established:
  - "showUtterance(_:wordTimings:) as the public API for karaoke -- takes text + timing array"
  - "cancelScheduledHighlights() before each new utterance to prevent overlapping highlight chains"

requirements-completed: [SUB-03, SUB-04, SUB-05]

# Metrics
duration: 2min
completed: 2026-03-26
---

# Phase 02 Plan 02: Karaoke Demo Summary

**Word-level karaoke highlighting with gold/silver-grey/white NSAttributedString coloring, 200ms/word demo mode, and main.swift wiring with SIGTERM cleanup**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-26T05:50:50Z
- **Completed:** 2026-03-26T05:53:00Z
- **Tasks:** 2 (of 3; Task 3 is a human-verify checkpoint)
- **Files modified:** 2

## Accomplishments

- Karaoke highlighting engine: highlightWord(at:in:) builds NSAttributedString with gold current word, silver-grey past words, white future words
- showUtterance(\_:wordTimings:) schedules word-by-word highlights via DispatchWorkItem with cancellation support
- demo() method cycles 3 sentences at 200ms/word with 2-second linger between sentences
- main.swift creates SubtitlePanel, positions it, launches demo 0.5s after startup, hides on SIGTERM

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement karaoke highlighting engine and demo mode** - `bdeba498` (feat)
2. **Task 2: Wire SubtitlePanel into main.swift and launch demo** - `9c503883` (feat)
3. **Task 3: Visual verification** - checkpoint:human-verify (pending)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitlePanel.swift` - Added highlightWord, showUtterance, demo, cancelScheduledHighlights methods + karaoke state properties
- `plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift` - Panel creation, positioning, demo launch, SIGTERM hide

## Decisions Made

- Used DispatchWorkItem array pattern for scheduled highlights so that cancelScheduledHighlights() can cleanly cancel all pending work when a new utterance starts (prevents overlapping highlight chains)
- Used cumulative timing offsets for word scheduling (each word fires at sum of all preceding timings) rather than chained asyncAfter calls, enabling accurate word-to-time mapping when real TTS timings replace the 200ms demo values

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - demo mode is intentionally hardcoded (200ms/word) and will be replaced by real TTS-driven timings in Phase 3.

## Next Phase Readiness

- showUtterance(\_:wordTimings:) is the public API that Phase 3 (TTS engine) will call with real word timestamps from sherpa-onnx
- Panel creation and positioning in main.swift ready for Phase 3 to replace demo() with actual TTS-driven highlighting
- Pending: Task 3 human-verify checkpoint for visual confirmation of karaoke behavior

## Self-Check: PASSED

- [x] SubtitlePanel.swift contains highlightWord(at:in:)
- [x] SubtitlePanel.swift contains showUtterance(\_:wordTimings:)
- [x] SubtitlePanel.swift contains demo()
- [x] main.swift contains SubtitlePanel()
- [x] main.swift contains subtitlePanel.demo()
- [x] main.swift contains subtitlePanel.hide() in SIGTERM handler
- [x] Commit bdeba498 exists
- [x] Commit 9c503883 exists

---

_Phase: 02-subtitle-overlay_
_Completed: 2026-03-26_
