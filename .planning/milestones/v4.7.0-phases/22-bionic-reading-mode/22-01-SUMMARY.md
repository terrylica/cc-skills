---
phase: 22-bionic-reading-mode
plan: 01
subsystem: ui
tags: [swift, appkit, nsattributedstring, bionic-reading, subtitle]

requires:
  - phase: 18-library-extraction
    provides: CompanionCore library target with SubtitlePanel, SettingsStore, HTTPControlServer
provides:
  - DisplayMode enum with .karaoke, .bionic, .plain cases
  - BionicRenderer with 40% bold-prefix algorithm
  - displayMode field in SubtitleSettings with backward-compatible Codable
  - HTTP API displayMode parameter with mutual exclusion logic
  - SubtitlePanel bionic rendering integration
affects: [22-02, subtitle-display, settings-api]

tech-stack:
  added: []
  patterns: [bionic-reading bold-prefix split, display-mode mutual exclusion]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/CompanionCore/DisplayMode.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/BionicRenderer.swift
    - plugins/claude-tts-companion/Tests/CompanionCoreTests/BionicRendererTests.swift
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/SettingsStore.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/SubtitlePanel.swift

key-decisions:
  - "DisplayMode stored as String in SubtitleSettings for Codable simplicity with backward-compatible decoder"
  - "Bionic mode uses white text only (no gold/grey karaoke coloring) for clean reading experience"
  - "Mutual exclusion: setting bionic/plain disables karaokeEnabled, setting karaoke enables it"

patterns-established:
  - "Display mode enum with safe string parsing defaulting to karaoke"
  - "Backward-compatible Codable init with decodeIfPresent for new fields"

requirements-completed: [BION-02, BION-03, BION-04]

duration: 4min
completed: 2026-03-28
---

# Phase 22 Plan 01: Bionic Reading Mode Summary

**DisplayMode enum + BionicRenderer (40% bold-prefix) with SubtitlePanel integration and HTTP API toggle**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-28T03:04:37Z
- **Completed:** 2026-03-28T03:08:10Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- DisplayMode enum with .karaoke, .bionic, .plain cases and safe string parsing
- BionicRenderer computing 40% ceiling bold-prefix with NSAttributedString rendering
- Settings persistence with backward-compatible Codable decoder for existing settings files
- HTTP API accepts displayMode with automatic mutual exclusion of karaoke/bionic modes
- SubtitlePanel renders bionic text in show() and highlightWord() when displayMode is .bionic
- 14 swift-testing tests covering boldPrefixLength, render output, and DisplayMode parsing

## Task Commits

Each task was committed atomically:

1. **Task 1: DisplayMode enum + BionicRenderer + SettingsStore + HTTP API** - `51fbba3f` (feat, TDD)
2. **Task 2: SubtitlePanel bionic rendering integration** - `46d513f3` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/CompanionCore/DisplayMode.swift` - Enum with karaoke/bionic/plain cases
- `plugins/claude-tts-companion/Sources/CompanionCore/BionicRenderer.swift` - Bold-prefix algorithm + NSAttributedString render
- `plugins/claude-tts-companion/Tests/CompanionCoreTests/BionicRendererTests.swift` - 14 tests for renderer and display mode
- `plugins/claude-tts-companion/Sources/CompanionCore/SettingsStore.swift` - Added displayMode field with backward-compatible decoder
- `plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift` - displayMode in SubtitleSettingsUpdate with mutual exclusion
- `plugins/claude-tts-companion/Sources/CompanionCore/SubtitlePanel.swift` - Bionic/plain/karaoke rendering in show() and highlightWord()

## Decisions Made

- DisplayMode stored as String in SubtitleSettings (not enum) for JSON Codable simplicity
- Added custom `init(from:)` decoder with `decodeIfPresent` so existing settings.json files without displayMode load correctly (defaults to "karaoke")
- Bionic mode renders all text in white with bold/regular weight only -- no gold/grey karaoke coloring
- Mutual exclusion enforced in HTTP handler: bionic/plain sets karaokeEnabled=false, karaoke sets karaokeEnabled=true

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added backward-compatible Codable decoder**

- **Found during:** Task 1 (SettingsStore update)
- **Issue:** Adding displayMode field to SubtitleSettings would break deserialization of existing settings.json files on disk that lack the field
- **Fix:** Added custom `init(from decoder:)` using `decodeIfPresent` with "karaoke" default
- **Files modified:** SettingsStore.swift
- **Verification:** swift build + swift test pass
- **Committed in:** 51fbba3f (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Essential for backward compatibility with existing installations. No scope creep.

## Issues Encountered

- `init(from:)` required `public` access level to satisfy Decodable protocol conformance -- fixed immediately

## Known Stubs

None -- all data paths are wired end-to-end.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Bionic rendering engine and settings integration complete
- Ready for Plan 02: SwiftBar menu integration for display mode toggle

---

_Phase: 22-bionic-reading-mode_
_Completed: 2026-03-28_
