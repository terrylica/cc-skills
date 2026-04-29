---
phase: 18-companioncore-library-test-infrastructure
plan: 02
subsystem: testing
tags: [swift-testing, unit-tests, proof-of-life, main-actor, xctest-alternative]

# Dependency graph
requires:
  - phase: 18-01
    provides: CompanionCore library target with @testable import support
provides:
  - 30 unit tests across 5 test files for pure CompanionCore types
  - Swift Testing framework integration via swift-testing package dependency
  - @MainActor test pattern for AppKit-dependent SubtitleChunker
affects:
  [
    phase-19-actor-concurrency,
    phase-20-tts-decomposition,
  ]

# Tech tracking
tech-stack:
  added: [swift-testing 0.12.0]
  patterns: [swift-testing-over-xctest, main-actor-test-isolation]

key-files:
  created:
    - plugins/claude-tts-companion/Tests/CompanionCoreTests/LanguageDetectorTests.swift
    - plugins/claude-tts-companion/Tests/CompanionCoreTests/TelegramFormatterTests.swift
    - plugins/claude-tts-companion/Tests/CompanionCoreTests/TranscriptParserTests.swift
    - plugins/claude-tts-companion/Tests/CompanionCoreTests/CircuitBreakerTests.swift
    - plugins/claude-tts-companion/Tests/CompanionCoreTests/SubtitleChunkerTests.swift
  modified:
    - plugins/claude-tts-companion/Package.swift

key-decisions:
  - "swift-testing package dependency instead of built-in Testing framework (CommandLineTools SDK lacks it)"
  - "Swift Testing (@Test, #expect) over XCTest (neither XCTest nor Testing available without Xcode; swift-testing package resolves both)"

patterns-established:
  - "@Suite(.serialized) @MainActor for AppKit-dependent tests (SubtitleChunker uses NSFont measurement)"
  - "Swift Testing framework with @Test func, #expect, Issue.record for all new tests"

requirements-completed: [TEST-01]

# Metrics
duration: 6min
completed: 2026-03-28
---

# Phase 18 Plan 02: Unit Tests for Five Pure Types Summary

**30 Swift Testing unit tests across 5 files validating LanguageDetector, TelegramFormatter, TranscriptParser, CircuitBreaker, and SubtitleChunker via @testable import CompanionCore**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-28T01:09:50Z
- **Completed:** 2026-03-28T01:16:30Z
- **Tasks:** 2
- **Files modified:** 6 (5 created + 1 modified)

## Accomplishments

- 30 tests passing across 5 test files covering all five target types
- Swift Testing framework integrated via swift-testing package dependency
- @MainActor test isolation pattern established for SubtitleChunker (AppKit NSFont dependency)
- `swift test` runs end-to-end in ~0.16 seconds (all 30 tests)

## Task Commits

Each task was committed atomically:

1. **Task 1: Unit tests for LanguageDetector, TelegramFormatter, TranscriptParser, CircuitBreaker** - `f124db46` (test)
2. **Task 2: SubtitleChunker tests with @MainActor isolation** - `f3fd2524` (test)

## Files Created/Modified

- `Tests/CompanionCoreTests/LanguageDetectorTests.swift` - 4 tests: English default, CJK threshold, mixed text, empty string
- `Tests/CompanionCoreTests/TelegramFormatterTests.swift` - 7 tests: bold/code/fence markdown-to-HTML, escaping, chunking
- `Tests/CompanionCoreTests/TranscriptParserTests.swift` - 8 tests: JSONL parsing (user/assistant/tool_use), invalid JSON, noise detection, file-based parsing
- `Tests/CompanionCoreTests/CircuitBreakerTests.swift` - 6 tests: state machine, cooldown expiry, failure counting, success reset
- `Tests/CompanionCoreTests/SubtitleChunkerTests.swift` - 5 tests: single page, empty, multi-page, word index tracking, whitespace normalization
- `Package.swift` - Added swift-testing dependency and linked to test target

## Decisions Made

- Used `swift-testing` package (swiftlang/swift-testing 0.12.0+) instead of relying on the built-in Testing framework because CommandLineTools SDK does not ship the Testing module (only Xcode does). XCTest is also unavailable without Xcode.
- Kept Swift Testing framework (`@Test`, `#expect`, `@Suite`) as specified in the plan rather than falling back to a custom test runner, since the package dependency resolves the availability issue cleanly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added swift-testing package dependency**

- **Found during:** Task 1 (initial test compilation)
- **Issue:** `import Testing` and `import XCTest` both fail -- CommandLineTools SDK ships neither module. The Testing.framework exists on disk at `/Library/Developer/CommandLineTools/Library/Developer/Frameworks/` but SwiftPM cannot resolve it for the macOS 15 deployment target.
- **Fix:** Added `swift-testing` (from: "0.12.0") as a package dependency and linked it to the CompanionCoreTests target
- **Files modified:** Package.swift
- **Verification:** `swift test` compiles and runs all 30 tests successfully
- **Committed in:** f124db46 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Essential fix to enable any testing. The swift-testing package is the official Apple package for the Swift Testing framework. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviation above.

## Known Stubs

None - all tests exercise real CompanionCore APIs.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Test infrastructure fully operational with 30 passing tests
- Swift Testing patterns established for future test additions
- Phase 19 (actor concurrency) and Phase 20 (TTS decomposition) can add tests using the same framework
- @MainActor isolation pattern documented for AppKit-dependent tests

---

_Phase: 18-companioncore-library-test-infrastructure_
_Completed: 2026-03-28_
