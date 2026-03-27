---
phase: 17-tts-streaming-subtitle-chunking
plan: 01
subsystem: ui
tags: [appkit, nspanel, karaoke, subtitle, text-chunking, nsattributedstring]

# Dependency graph
requires: []
provides:
  - SubtitleChunker with pixel-width 2-line page breaking
  - SubtitlePanel.showPages() for multi-page karaoke display
  - Generation counter for interruption-safe work item scheduling
affects: [17-02, tts-playback, subtitle-streaming]

# Tech tracking
tech-stack:
  added: []
  patterns:
    [
      pixel-width text measurement via NSAttributedString.size(),
      generation counter for stale work item invalidation,
      clause/phrase break priority for natural line splits,
    ]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleChunker.swift
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitlePanel.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleStyle.swift

key-decisions:
  - "Bottom-heavy line preference: shorter first line, longer second for visual balance"
  - "Generation counter pattern for interruption safety instead of DispatchWorkItem.cancel() alone"

patterns-established:
  - "SubtitlePage struct as the interchange format between chunker and panel"
  - "showPages() as primary API, showUtterance() as backward-compat wrapper"

requirements-completed: [STREAM-01, STREAM-02, STREAM-03]

# Metrics
duration: 2min
completed: 2026-03-27
---

# Phase 17 Plan 01: Subtitle Chunker and Paged Karaoke Summary

**Pixel-width SubtitleChunker splits text into 2-line pages with clause-priority line breaking; SubtitlePanel.showPages() drives sequential page-flip karaoke with generation-counter interruption safety**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-27T04:06:54Z
- **Completed:** 2026-03-27T04:08:58Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Created SubtitleChunker with pixel-width measurement using NSAttributedString.size() and SubtitleStyle.regularFont
- Implemented clause/phrase break priority (3 for clause endings, 2 for conjunctions/prepositions) with bottom-heavy line preference
- Added showPages() to SubtitlePanel for multi-page karaoke with automatic page flips at word boundaries
- Refactored showUtterance() to delegate to showPages() preserving full backward compatibility with demo() and simple text

## Task Commits

Each task was committed atomically:

1. **Task 1: Create SubtitleChunker with SubtitlePage model and width-based line breaking** - `92e0f560` (feat)
2. **Task 2: Refactor SubtitlePanel with showPages(), generation counter, and backward-compatible showUtterance()** - `c25ca6fc` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleChunker.swift` - Text-to-pages chunking algorithm with SubtitlePage model
- `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitlePanel.swift` - Paged karaoke display with generation counter
- `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleStyle.swift` - Added truncatesLastVisibleLine constant

## Decisions Made

- Bottom-heavy line preference: line 1 uses preferShorter=true to backtrack to clause/phrase breaks, producing shorter first lines and longer second lines for visual balance
- Generation counter incremented in both showPages() and cancelScheduledHighlights() for double protection against stale work items

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- SubtitleChunker and showPages() are ready for integration with TTS streaming pipeline
- Plan 17-02 can wire TTSEngine output through SubtitleChunker into showPages()

---

_Phase: 17-tts-streaming-subtitle-chunking_
_Completed: 2026-03-27_
