---
phase: 27-mlx-dependency-removal
plan: 01
subsystem: dependencies
tags: [swiftpm, mlx, kokoro-ios, dependency-removal, binary-size]

# Dependency graph
requires:
  - phase: 26-python-tts-native-timestamps
    provides: Python MLX server with native word timestamps replacing Swift MLX synthesis
provides:
  - Clean Package.swift without kokoro-ios, mlx-swift, or MLXUtilsLibrary
  - WordTimingAligner reduced to character-weighted fallback only
  - Zero MLX symbols in release binary
affects: [28-remove-restart-lifecycle, python-tts-launchd]

# Tech tracking
tech-stack:
  added: []
  patterns: [dependency-removal-with-dead-code-pruning]

key-files:
  created: []
  modified:
    - plugins/claude-tts-companion/Package.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/WordTimingAligner.swift
    - plugins/claude-tts-companion/Tests/CompanionCoreTests/WordTimingAlignerTests.swift
    - plugins/claude-tts-companion/Package.resolved
    - plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/TelegramBot.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/Config.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/LanguageDetector.swift

key-decisions:
  - "Keep sherpa-onnx static libs for CJK TTS fallback -- only MLX packages removed"
  - "Remove stripPunctuation and alignOnsetsToWords alongside MToken code -- only used by dead paths"
  - "Binary 22.2MB (not 20MB target) -- sherpa-onnx static libs account for the difference"

patterns-established:
  - "Dead code removal: trace callers before removing functions, remove transitive dead code"

requirements-completed: [DEP-01, DEP-02, DEP-03, DEP-04, DEP-05]

# Metrics
duration: 4min
completed: 2026-03-28
---

# Phase 27 Plan 01: MLX Dependency Removal Summary

**Removed kokoro-ios, mlx-swift, MLXUtilsLibrary from Package.swift and pruned all dead MToken code paths, producing a clean 22.2MB binary with zero MLX symbols**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-28T08:06:21Z
- **Completed:** 2026-03-28T08:10:36Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Removed 3 package dependencies and 3 product dependencies from Package.swift
- Pruned 6 dead functions/types from WordTimingAligner (extractTimingsFromTokens, alignOnsetsToWords, resolveWordTimings, NativeTimings, ResolvedTimings, stripPunctuation)
- Removed 11 dead tests and MToken test fixtures, keeping 5 active extractWordTimings tests
- Updated Package.resolved -- dependency graph now excludes MLX packages
- All 82 tests pass, release build clean in 11.97s

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove MLX packages from Package.swift and strip dead MToken code** - `c2637314` (refactor)
2. **Task 2: Update tests, resolve Package.resolved, verify build** - `570ac962` (test)
3. **Deviation: Update kokoro-ios doc comment references** - `35be10fe` (docs)

## Files Created/Modified

- `plugins/claude-tts-companion/Package.swift` - Removed 3 MLX package deps and 3 product deps
- `plugins/claude-tts-companion/Sources/CompanionCore/WordTimingAligner.swift` - Stripped to extractWordTimings only (236 -> 38 lines)
- `plugins/claude-tts-companion/Tests/CompanionCoreTests/WordTimingAlignerTests.swift` - Removed MToken tests (237 -> 46 lines)
- `plugins/claude-tts-companion/Package.resolved` - Regenerated without MLX packages
- `plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift` - Doc comments: MToken.start_ts -> Python MLX server
- `plugins/claude-tts-companion/Sources/CompanionCore/TelegramBot.swift` - Doc comment: kokoro-ios MLX -> Python MLX server
- `plugins/claude-tts-companion/Sources/CompanionCore/Config.swift` - Doc comments: kokoro-ios -> Kokoro
- `plugins/claude-tts-companion/Sources/CompanionCore/LanguageDetector.swift` - Doc comments: kokoro-ios -> Python MLX server

## Decisions Made

- Kept sherpa-onnx static libs (CJK TTS fallback path still active via synthesizeCJK)
- Removed stripPunctuation helper alongside alignOnsetsToWords since it had no other callers
- Binary at 22.2MB exceeds aspirational 20MB target due to sherpa-onnx static libs (not MLX-related)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Updated kokoro-ios references in doc comments across 4 files**

- **Found during:** Task 2 verification (grep found 6 "kokoro-ios" references in comments)
- **Issue:** Plan verification criteria required zero matches for kokoro-ios pattern, but doc comments in TelegramBot, Config, and LanguageDetector still referenced kokoro-ios
- **Fix:** Updated all doc comments to reference "Python MLX server" or "Kokoro TTS" instead of "kokoro-ios"
- **Files modified:** TelegramBot.swift, Config.swift, LanguageDetector.swift, SubtitleSyncDriver.swift
- **Verification:** `grep -r 'kokoro-ios' Sources/` returns 0 matches
- **Committed in:** 35be10fe

---

**Total deviations:** 1 auto-fixed (Rule 2 - documentation accuracy)
**Impact on plan:** Necessary to meet verification criteria. No scope creep.

## Issues Encountered

- Binary size 22.2MB vs 20MB target: sherpa-onnx static libraries account for the difference. This is expected -- the 20MB target was aspirational. The MLX removal itself was successful (0 MLX symbols confirmed via `nm`).

## Known Stubs

None -- all code paths are fully wired.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 28 (remove restart lifecycle) can proceed -- no MLX memory leak means exit(42) restart is no longer needed
- Python TTS launchd service dependency management is a separate phase

---

_Phase: 27-mlx-dependency-removal_
_Completed: 2026-03-28_
