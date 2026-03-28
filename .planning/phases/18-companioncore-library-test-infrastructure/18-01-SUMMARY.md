---
phase: 18-companioncore-library-test-infrastructure
plan: 01
subsystem: infra
tags: [swiftpm, library-target, testable-import, coordinator-pattern]

# Dependency graph
requires: []
provides:
  - CompanionCore library target with all 25 business logic files
  - CompanionApp coordinator facade (public init/start/shutdown)
  - Three-target SwiftPM manifest (library + executable + test)
  - Ultra-thin main.swift (42 lines) importing CompanionCore
affects:
  [
    18-02-test-infrastructure,
    phase-19-actor-concurrency,
    phase-20-tts-decomposition,
  ]

# Tech tracking
tech-stack:
  added: []
  patterns:
    [coordinator-facade, library-extraction, module-level-callback-registration]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/MemoryLifecycle.swift
  modified:
    - plugins/claude-tts-companion/Package.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/CircuitBreaker.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/SubtitlePanel.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/SummaryEngine.swift

key-decisions:
  - "CompanionApp is @unchecked Sendable with @MainActor init/start/shutdown (always called from main thread)"
  - "MemoryLifecycle module-level function pattern for cross-module restart triggering (avoids singleton)"
  - "All 27 CompanionCore types marked public; methods stay internal (tests use @testable import)"

patterns-established:
  - "Coordinator facade: CompanionApp owns all subsystems, main.swift only does NSApp + SIGTERM + run loop"
  - "Module-level callback registration: MemoryLifecycle.register() for cross-module function access"

requirements-completed: [ARCH-01]

# Metrics
duration: 8min
completed: 2026-03-28
---

# Phase 18 Plan 01: CompanionCore Library Extraction Summary

**Extracted 25 business logic files into CompanionCore library target with CompanionApp coordinator, enabling @testable import for all testing**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-28T00:59:15Z
- **Completed:** 2026-03-28T01:07:20Z
- **Tasks:** 2
- **Files modified:** 33 (25 moved + 2 created + 6 modified)

## Accomplishments

- All 25 business logic files moved from executable target to CompanionCore library target
- Package.swift updated with three targets: CompanionCore (library), claude-tts-companion (executable), CompanionCoreTests (test)
- CompanionApp coordinator created with public init/start/shutdown facade, owning all subsystems
- main.swift reduced from 352 lines to 42 lines (NSApplication setup, SIGTERM handler, run loop only)
- `swift build` succeeds with zero errors

## Task Commits

Each task was committed atomically:

1. **Task 1: Restructure Package.swift and move files to CompanionCore** - `681f59d8` (chore)
2. **Task 2: Create CompanionApp coordinator and slim main.swift** - `44455a91` (feat)

## Files Created/Modified

- `Sources/CompanionCore/CompanionApp.swift` - Coordinator facade owning all subsystems with notification handling, memory lifecycle, and helper methods
- `Sources/CompanionCore/MemoryLifecycle.swift` - Module-level checkMemoryLifecycleRestart() function with registered callback pattern
- `Package.swift` - Three-target manifest (CompanionCore library, executable, test)
- `Sources/claude-tts-companion/main.swift` - Ultra-thin entry point (42 lines)
- 25 files moved from `Sources/claude-tts-companion/` to `Sources/CompanionCore/` with public type declarations

## Decisions Made

- CompanionApp uses `@MainActor` on init/start/shutdown since it's always called from main thread (SubtitlePanel is @MainActor)
- Created MemoryLifecycle.swift with module-level function + registered callback instead of making CompanionApp a singleton (avoids tight coupling)
- Added Sendable conformance to ConversationTurn, TTSResult, SynthesisResult, SummaryResult (Swift 6 strict concurrency requires it for cross-isolation sends)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed public protocol conformance requirements**

- **Found during:** Task 2 (swift build)
- **Issue:** Public types conforming to CustomStringConvertible and AVAudioPlayerDelegate had internal description/delegate methods, which Swift 6 rejects
- **Fix:** Added `public` to `description` on SummaryError and TTSError, and to AVAudioPlayerDelegate methods on PlaybackDelegate
- **Files modified:** CircuitBreaker.swift, TTSEngine.swift
- **Committed in:** 44455a91

**2. [Rule 3 - Blocking] Created MemoryLifecycle module-level function**

- **Found during:** Task 2 (swift build)
- **Issue:** `checkMemoryLifecycleRestart()` was a free function in main.swift called from HTTPControlServer and TelegramBot -- moving it to CompanionApp made it inaccessible
- **Fix:** Created MemoryLifecycle.swift with module-level function and callback registration pattern
- **Files modified:** CompanionApp.swift (registers handler), MemoryLifecycle.swift (new file)
- **Committed in:** 44455a91

**3. [Rule 1 - Bug] Added Sendable conformance to data structs**

- **Found during:** Task 2 (swift build)
- **Issue:** ConversationTurn, TTSResult, SynthesisResult lacked Sendable, causing "sending risks data races" errors in Swift 6 strict concurrency
- **Fix:** Added `: Sendable` to affected struct declarations
- **Files modified:** SummaryEngine.swift, TTSEngine.swift
- **Committed in:** 44455a91

**4. [Rule 1 - Bug] Fixed NSPanel overriding property visibility**

- **Found during:** Task 2 (swift build)
- **Issue:** SubtitlePanel's `canBecomeKey`/`canBecomeMain` overrides must be as accessible as the public class
- **Fix:** Added `public` to both override properties
- **Files modified:** SubtitlePanel.swift
- **Committed in:** 44455a91

---

**Total deviations:** 4 auto-fixed (2 bugs, 1 blocking, 1 bug)
**Impact on plan:** All auto-fixes necessary for compilation under Swift 6 strict concurrency. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviations above.

## Known Stubs

None - all functionality fully wired.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- CompanionCore library target ready for `@testable import CompanionCore` in tests
- Tests/CompanionCoreTests/ directory created (empty, ready for Plan 02)
- Plan 02 can immediately add XCTest infrastructure with unit tests

---

_Phase: 18-companioncore-library-test-infrastructure_
_Completed: 2026-03-28_
