---
phase: 10-deployment-extras
plan: 02
subsystem: ui
tags:
  [
    swift,
    ring-buffer,
    clipboard,
    thinking-watcher,
    minimax,
    http-api,
    caption-history,
  ]

# Dependency graph
requires:
  - phase: 08-http-control-api
    provides: HTTPControlServer, FlyingFox HTTP endpoints
  - phase: 07-file-watching-auto-continue
    provides: JSONLTailer, MiniMaxClient
provides:
  - CaptionHistory ring buffer for subtitle scrollback
  - ThinkingWatcher for extended thinking JSONL summarization
  - GET /captions and POST /captions/copy HTTP endpoints
affects: [09-swiftbar-integration, 10-deployment-extras]

# Tech tracking
tech-stack:
  added: []
  patterns:
    [ring-buffer with NSLock, markSummarizingComplete sync pattern for Swift 6]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/CaptionHistory.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/ThinkingWatcher.swift
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/HTTPControlServer.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift

key-decisions:
  - "Ring buffer capacity 100 entries -- sufficient for typical session scrollback"
  - "ThinkingWatcher 500-char threshold before summarization -- avoids excessive API calls"
  - "markSummarizingComplete() pattern to avoid NSLock in async context (Swift 6 strict concurrency)"

patterns-established:
  - "Ring buffer with NSLock for fixed-capacity history: CaptionHistory"
  - "Sync flag reset via separate method to avoid NSLock in async context"

requirements-completed: [EXT-01, EXT-02, EXT-04]

# Metrics
duration: 4min
completed: 2026-03-26
---

# Phase 10 Plan 02: Caption History, Clipboard Copy, and Thinking Watcher Summary

**Ring buffer caption history with clipboard copy, thinking JSONL watcher with MiniMax summarization, and two new HTTP endpoints**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-26T18:15:34Z
- **Completed:** 2026-03-26T18:19:07Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- CaptionHistory ring buffer stores up to 100 timestamped subtitle entries with NSLock thread safety
- ThinkingWatcher monitors transcript JSONL for extended thinking blocks, summarizes via MiniMax when threshold reached
- HTTPControlServer extended with GET /captions (history retrieval) and POST /captions/copy (clipboard)
- All new code compiles with zero errors under Swift 6 strict concurrency

## Task Commits

Each task was committed atomically:

1. **Task 1: CaptionHistory ring buffer** - `ae9ff50f` (feat)
2. **Task 2: ThinkingWatcher** - `27cf09d0` (feat)
3. **Task 3: HTTP endpoints + main.swift wiring** - `226d1f91` (feat)

## Files Created/Modified

- `CaptionHistory.swift` - Ring buffer with record/getAll/copyToClipboard/clear
- `ThinkingWatcher.swift` - JSONL tailer for thinking blocks, MiniMax summarization
- `HTTPControlServer.swift` - Added /captions and /captions/copy endpoints, captionHistory dependency
- `main.swift` - Created CaptionHistory and ThinkingWatcher instances, wired into lifecycle

## Decisions Made

- Ring buffer capacity 100 -- sufficient for typical session, avoids unbounded memory growth
- ThinkingWatcher 500-char threshold prevents excessive MiniMax API calls on small thinking blocks
- Used markSummarizingComplete() pattern (sync method) instead of NSLock in defer block to satisfy Swift 6 concurrency rules

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] NSLock in async context**

- **Found during:** Task 2 (ThinkingWatcher)
- **Issue:** Swift 6 forbids NSLock.unlock() in async contexts (defer block inside Task)
- **Fix:** Extracted lock manipulation to synchronous markSummarizingComplete() method
- **Files modified:** ThinkingWatcher.swift
- **Verification:** swift build succeeds with zero errors
- **Committed in:** 27cf09d0

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential for Swift 6 compliance. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviation.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all components are fully wired with real data sources.

## Next Phase Readiness

- Caption history and thinking watcher are functional and wired into the application lifecycle
- HTTP API now has 8 endpoints (health, settings, subtitle show/hide, captions, captions/copy)

---

_Phase: 10-deployment-extras_
_Completed: 2026-03-26_
