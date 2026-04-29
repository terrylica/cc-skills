---
phase: 19-ttsengine-decomposition-actor-migration
plan: 01
subsystem: tts
tags: [swift, refactoring, sendable, mainactor, tts-engine]

requires:
  - phase: 18-companioncore-library-test-infrastructure
    provides: CompanionCore library target with TTSEngine.swift and test infrastructure
provides:
  - WordTimingAligner Sendable struct with 6 static word timing methods
  - PronunciationProcessor Sendable struct with preprocessText() and pronunciation overrides
  - SentenceSplitter Sendable struct with splitIntoSentences()
  - PlaybackDelegate as @MainActor (replacing @unchecked Sendable)
  - TTSError standalone enum with circuitBreakerOpen case
  - TTSEngine.swift reduced from 1139 to 763 lines
affects: [19-02-actor-migration, tts-testing]

tech-stack:
  added: []
  patterns:
    [
      nonisolated-unsafe-for-immutable-delegate-properties,
      mainactor-delegate-pattern,
    ]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/CompanionCore/WordTimingAligner.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/PronunciationProcessor.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/SentenceSplitter.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/PlaybackDelegate.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSError.swift
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift

key-decisions:
  - "PlaybackDelegate uses @MainActor with nonisolated(unsafe) let properties and nonisolated init for Swift 6 compatibility"
  - "MToken type comes from MLXUtilsLibrary (not KokoroSwift) -- WordTimingAligner imports MLXUtilsLibrary"
  - "stripPunctuation made internal (was private) for testability"

patterns-established:
  - "nonisolated(unsafe) let for immutable properties in @MainActor delegates accessed from nonisolated callback methods"
  - "Extracted Sendable structs with static methods for pure-function code previously in class methods"

requirements-completed: [ARCH-03, ARCH-04]

duration: 10min
completed: 2026-03-28
---

# Phase 19 Plan 01: TTSEngine Pure Type Extraction Summary

**Extracted 5 pure types from 1139-line TTSEngine.swift into standalone files, reducing it to 763 lines with zero behavior changes**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-28T01:36:19Z
- **Completed:** 2026-03-28T01:47:14Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Extracted WordTimingAligner (6 static methods), PronunciationProcessor, SentenceSplitter as Sendable structs
- Converted PlaybackDelegate from @unchecked Sendable to @MainActor with proper Swift 6 isolation
- Added TTSError.circuitBreakerOpen case for Plan 02 actor migration
- All 30 existing tests pass with zero regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: Extract WordTimingAligner, PronunciationProcessor, SentenceSplitter, PlaybackDelegate, TTSError** - `c0de991c` (refactor)
2. **Task 2: Run existing tests to verify no regressions** - verification only, no commit needed

## Files Created/Modified

- `Sources/CompanionCore/WordTimingAligner.swift` - Sendable struct with NativeTimings, ResolvedTimings, and 6 static word timing methods
- `Sources/CompanionCore/PronunciationProcessor.swift` - Sendable struct with pronunciation overrides and preprocessText()
- `Sources/CompanionCore/SentenceSplitter.swift` - Sendable struct with splitIntoSentences()
- `Sources/CompanionCore/PlaybackDelegate.swift` - @MainActor AVAudioPlayerDelegate (replaces @unchecked Sendable)
- `Sources/CompanionCore/TTSError.swift` - Error enum with new circuitBreakerOpen case
- `Sources/CompanionCore/TTSEngine.swift` - Slimmed from 1139 to 763 lines, delegates to extracted types

## Decisions Made

- PlaybackDelegate uses `nonisolated(unsafe) let` for immutable properties accessed from nonisolated delegate callbacks -- this is safe because properties are set once in init and never mutated
- PlaybackDelegate init marked `nonisolated` so TTSEngine (non-MainActor) can construct it without async context
- WordTimingAligner imports MLXUtilsLibrary (not KokoroSwift) for MToken type -- discovered during build that MToken is defined in MLXUtilsLibrary

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed MToken import -- type is in MLXUtilsLibrary not KokoroSwift**

- **Found during:** Task 1 (first build attempt)
- **Issue:** Plan said to import KokoroSwift for MToken, but MToken is defined in MLXUtilsLibrary
- **Fix:** Changed WordTimingAligner.swift import from KokoroSwift to MLXUtilsLibrary
- **Files modified:** WordTimingAligner.swift
- **Verification:** swift build succeeds
- **Committed in:** c0de991c

**2. [Rule 3 - Blocking] PlaybackDelegate @MainActor required nonisolated init and nonisolated(unsafe) properties**

- **Found during:** Task 1 (build errors after @MainActor annotation)
- **Issue:** @MainActor class init cannot be called from non-MainActor TTSEngine context in Swift 6; nonisolated delegate methods cannot access MainActor-isolated stored properties
- **Fix:** Used nonisolated init, nonisolated(unsafe) let for immutable properties
- **Files modified:** PlaybackDelegate.swift
- **Verification:** swift build succeeds with zero errors
- **Committed in:** c0de991c

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both auto-fixes necessary for compilation. No scope creep.

## Issues Encountered

- TTSEngine.swift ended at 763 lines (plan target was under 650). The remaining code is core synthesis/playback/model-loading/circuit-breaker logic that is tightly coupled and will be further decomposed in Plan 02 (actor migration). The 33% reduction (1139 to 763) is the correct extraction boundary for pure types.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- TTSEngine surface area reduced, ready for Plan 02 actor migration
- WordTimingAligner, PronunciationProcessor, SentenceSplitter are independently testable Sendable structs
- PlaybackDelegate properly isolated with @MainActor for Swift 6 concurrency

## Self-Check: PASSED

- All 5 created files exist
- Commit c0de991c found in git log
- swift build succeeds with zero errors
- swift test passes all 30 tests

---

_Phase: 19-ttsengine-decomposition-actor-migration_
_Completed: 2026-03-28_
