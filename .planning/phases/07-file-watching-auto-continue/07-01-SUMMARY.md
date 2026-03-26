---
phase: 07-file-watching-auto-continue
plan: 01
subsystem: file-watching
tags: [dispatchsource, fsevents, jsonl, offset-tailing, swift]

requires:
  - phase: 01-foundation-build
    provides: Config.swift pattern, Swift 6 build system
provides:
  - NotificationWatcher class for detecting new .json notification files
  - JSONLTailer class for offset-based JSONL transcript tailing
  - Config.notificationDir and Config.transcriptBaseDir path constants
affects: [07-02-auto-continue, 08-http-control-api]

tech-stack:
  added: []
  patterns:
    [
      DispatchSource.makeFileSystemObjectSource for file/directory monitoring,
      O_EVTONLY file descriptors,
      offset-based file tailing with partial line handling,
    ]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/FileWatcher.swift
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift

key-decisions:
  - "NSLock for thread safety in file watchers (consistent with TTSEngine, CircuitBreaker)"
  - "O_EVTONLY file descriptors for read-only notification without blocking writers"
  - "Partial line rewind in JSONLTailer to avoid yielding incomplete JSON"

patterns-established:
  - "DispatchSource strong reference pattern: store as instance var to prevent ARC deallocation"
  - "Offset-based tailing: seek to end on init, read only new bytes on write events"

requirements-completed: [WATCH-01, WATCH-02, WATCH-03, WATCH-04]

duration: 2min
completed: 2026-03-26
---

# Phase 07 Plan 01: File Watching Summary

**DispatchSource-based NotificationWatcher for .json file detection and JSONLTailer for offset-based JSONL transcript tailing**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-26T17:31:23Z
- **Completed:** 2026-03-26T17:33:02Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- NotificationWatcher detects new .json files via directory DispatchSource monitoring with deduplication
- JSONLTailer reads growing JSONL files using offset tracking with partial line handling
- Both watchers use strong DispatchSource references preventing ARC deallocation
- Config.swift extended with notificationDir and transcriptBaseDir with env var overrides

## Task Commits

Each task was committed atomically:

1. **Task 1: Add notification and transcript directory paths to Config.swift** - `85a308ac` (feat)
2. **Task 2: Create FileWatcher.swift with NotificationWatcher and JSONLTailer** - `7e46c66f` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/FileWatcher.swift` - NotificationWatcher and JSONLTailer classes using DispatchSource
- `plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift` - Added notificationDir, transcriptBaseDir, fileWatcherLatencyTarget constants

## Decisions Made

- NSLock for thread safety in file watchers (consistent with TTSEngine, CircuitBreaker patterns)
- O_EVTONLY file descriptors for read-only notification without blocking other writers
- Partial line rewind in JSONLTailer: if last chunk lacks trailing newline, subtract partial bytes from offset for re-read on next event

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all functionality is wired and operational.

## Next Phase Readiness

- FileWatcher.swift ready for integration by auto-continue evaluator (07-02)
- NotificationWatcher callback can be wired to session detection logic
- JSONLTailer callback can feed TranscriptParser for live transcript processing

---

_Phase: 07-file-watching-auto-continue_
_Completed: 2026-03-26_
