---
phase: 02-subtitle-overlay
plan: 01
subsystem: ui
tags: [appkit, nspanel, subtitle, overlay, karaoke, swift6]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: Package.swift, main.swift with NSApp accessory, Config.swift
provides:
  - SubtitleStyle.swift with centralized color/font/layout constants
  - SubtitlePanel.swift with floating NSPanel overlay (all window behaviors)
  - Public API for karaoke highlighting (show/hide/updateAttributedText)
affects: [02-02-karaoke-demo, 03-tts-engine, 07-http-api]

# Tech tracking
tech-stack:
  added: []
  patterns: [@MainActor enum for UI constants, NSPanel subclass with Auto Layout]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleStyle.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitlePanel.swift
  modified: []

key-decisions:
  - "@MainActor on SubtitleStyle enum for Swift 6 strict concurrency (NSFont/NSColor not Sendable)"
  - "NSTextField(labelWithString:) instead of wrappingLabelField: (API name changed in recent SDK)"

patterns-established:
  - "@MainActor for all UI-touching types in Swift 6 strict concurrency mode"
  - "SubtitleStyle.* namespace for all visual constants consumed by panel and future karaoke engine"

requirements-completed: [SUB-01, SUB-02, SUB-06, SUB-07, SUB-08, SUB-09, SUB-10, SUB-11]

# Metrics
duration: 3min
completed: 2026-03-26
---

# Phase 02 Plan 01: Subtitle Panel Summary

**Floating NSPanel overlay with dark 30% background, click-through, screen-sharing-invisible, bottom-center positioned with 2-line word-wrap and karaoke-ready API**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-26T05:45:46Z
- **Completed:** 2026-03-26T05:48:39Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- SubtitleStyle.swift with all color (#FFD700 gold, #A0A0A0 grey, white, 30% black), font (SF Pro Display with fallback, S/M/L presets), and layout constants (10px corners, 80px bottom, 70% width, 2 lines, 2s linger)
- SubtitlePanel.swift implementing all 8 behavioral requirements: floating (SUB-01), bottom-center (SUB-02), dark background (SUB-06), 2-line wrap (SUB-07), sharing-invisible (SUB-08), no-focus (SUB-09), click-through (SUB-10), all-Spaces (SUB-11)
- Public API surface ready for karaoke: show(text:), hide(), updateAttributedText(\_:)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create SubtitleStyle.swift** - `e91d0a71` (feat)
2. **Task 2: Create SubtitlePanel.swift** - `e16bdc98` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleStyle.swift` - Color, font, and layout constants for subtitle overlay
- `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitlePanel.swift` - NSPanel subclass with floating, click-through, screen-sharing-invisible behavior

## Decisions Made

- Used `@MainActor` on `SubtitleStyle` enum because NSFont/NSColor are not Sendable in Swift 6 strict concurrency mode. All consumers (SubtitlePanel) are also @MainActor, so this is the correct isolation boundary.
- Used `NSTextField(labelWithString:)` with explicit `wraps = true` and `lineBreakMode = .byWordWrapping` instead of `NSTextField(wrappingLabelField:)` which is not available in the current SDK.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Swift 6 concurrency: @MainActor on SubtitleStyle**

- **Found during:** Task 1 (SubtitleStyle.swift)
- **Issue:** Static NSFont properties caused "not concurrency-safe" errors under Swift 6 strict concurrency
- **Fix:** Added `@MainActor` annotation to the enum
- **Files modified:** SubtitleStyle.swift
- **Verification:** `swift build` succeeds with zero errors
- **Committed in:** e91d0a71

**2. [Rule 3 - Blocking] NSTextField API name change**

- **Found during:** Task 2 (SubtitlePanel.swift)
- **Issue:** `NSTextField(wrappingLabelField:)` not available in current SDK; correct API is `NSTextField(labelWithString:)`
- **Fix:** Switched to `labelWithString:` with explicit wrapping configuration
- **Files modified:** SubtitlePanel.swift
- **Verification:** `swift build` succeeds with zero errors
- **Committed in:** e16bdc98

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes necessary for compilation. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- SubtitlePanel ready for Plan 02 (karaoke demo mode) to wire word-level highlighting
- `updateAttributedText(_:)` stub ready for NSAttributedString karaoke highlighting
- main.swift not yet modified to create/show the panel (Plan 02 will handle this)

## Self-Check: PASSED

- [x] SubtitleStyle.swift exists
- [x] SubtitlePanel.swift exists
- [x] Commit e91d0a71 exists
- [x] Commit e16bdc98 exists

---

_Phase: 02-subtitle-overlay_
_Completed: 2026-03-26_
