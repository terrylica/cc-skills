---
phase: 19-ttsengine-decomposition-actor-migration
plan: 02
subsystem: tts
tags: [swift, actor, concurrency, mainactor, playback-manager, tts-engine]

requires:
  - phase: 19-ttsengine-decomposition-actor-migration
    plan: 01
    provides: WordTimingAligner, PronunciationProcessor, SentenceSplitter, PlaybackDelegate, TTSError
provides:
  - PlaybackManager @MainActor class owning all audio playback lifecycle
  - TTSEngine as Swift actor with async methods and DispatchQueue bridge
  - synthesizeStreaming returns [ChunkResult] directly (replaces callback API)
  - All 4 callers updated for actor-based API
affects: [tts-testing, streaming-pipeline, memory-lifecycle]

tech-stack:
  added: []
  patterns:
    [
      actor-isolation-replaces-nslock,
      withCheckedThrowingContinuation-for-dispatch-queue-bridge,
      mainactor-playback-manager,
      return-based-streaming-api,
    ]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/CompanionCore/PlaybackManager.swift
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/TelegramBot.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/MemoryLifecycle.swift

key-decisions:
  - "synthesizeStreaming changed from callback-based to return-based API -- cleaner with async/await and avoids NSLock in async contexts"
  - "writeWav made static on TTSEngine to be callable from non-isolated DispatchQueue context"
  - "Actor deinit removed -- ARC handles cleanup; deinit cannot access non-Sendable actor-isolated properties"
  - "@preconcurrency import for MLX/MLXUtilsLibrary to suppress non-Sendable warnings from external types"

patterns-established:
  - "withCheckedThrowingContinuation to bridge blocking DispatchQueue synthesis to async/await"
  - "PlaybackManager @MainActor as single owner of all audio hardware (AVAudioPlayer + AudioStreamPlayer)"
  - "SubtitleSyncDriver receives AudioStreamPlayer directly instead of whole TTSEngine (decoupling)"
  - "Return-based streaming API replaces callback pattern for actor methods"

requirements-completed:
  [ARCH-02, ARCH-05, ARCH-06, CONC-01, CONC-02, CONC-03, CONC-04]

duration: 11min
completed: 2026-03-28
---

# Phase 19 Plan 02: PlaybackManager Extraction and TTSEngine Actor Migration Summary

**Extracted PlaybackManager as @MainActor class, migrated TTSEngine from class+NSLock to Swift actor with async methods and DispatchQueue bridge for blocking GPU synthesis**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-28T01:50:19Z
- **Completed:** 2026-03-28T02:01:24Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Created PlaybackManager @MainActor class with play(), preparePlayer(), stopPlayback(), warmUpAudioHardware(), audioStreamPlayer
- Converted TTSEngine from `class+NSLock` to `actor` with zero NSLock, zero @unchecked Sendable
- Bridged blocking GPU synthesis to DispatchQueue via withCheckedThrowingContinuation (CONC-03)
- Replaced inline circuit breaker with existing CircuitBreaker class instance
- Changed synthesizeStreaming from callback-based to return-based API
- Decoupled SubtitleSyncDriver from TTSEngine (receives AudioStreamPlayer directly)
- Updated all 4 callers (CompanionApp, TelegramBot, HTTPControlServer, SubtitleSyncDriver) + MemoryLifecycle
- swift build zero errors, swift test 30/30 pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Create PlaybackManager @MainActor class and migrate TTSEngine to actor** - `e9cf6ef0` (feat)
2. **Task 2: Update all callers to work with actor TTSEngine and PlaybackManager** - `f50cbc53` (feat)

## Files Created/Modified

- `Sources/CompanionCore/PlaybackManager.swift` - @MainActor class owning AVAudioPlayer lifecycle, pre-buffering, warm-up, AudioStreamPlayer
- `Sources/CompanionCore/TTSEngine.swift` - Swift actor with async synthesize/synthesizeWithTimestamps/synthesizeStreaming, DispatchQueue bridge, CircuitBreaker delegation
- `Sources/CompanionCore/CompanionApp.swift` - Creates PlaybackManager first, passes to TTSEngine and all callers
- `Sources/CompanionCore/SubtitleSyncDriver.swift` - Receives AudioStreamPlayer directly (decoupled from TTSEngine)
- `Sources/CompanionCore/TelegramBot.swift` - Uses playbackManager for audio ops, await for actor methods
- `Sources/CompanionCore/HTTPControlServer.swift` - Uses playbackManager for audio ops, await for actor methods
- `Sources/CompanionCore/MemoryLifecycle.swift` - checkMemoryLifecycleRestart() now async

## Decisions Made

- **synthesizeStreaming API change:** Changed from callback-based (`onChunkReady/onAllComplete`) to return-based (`-> [ChunkResult]`). The callback pattern caused Swift 6 errors: `@Sendable` closures cannot capture mutable locals, and `NSLock.lock()` is unavailable in async contexts. The return-based API is cleaner and eliminates all locking in callers.
- **writeWav made static:** Needed to be callable from the non-isolated DispatchQueue context inside `withCheckedThrowingContinuation`. Static methods on actors are nonisolated by default.
- **Actor deinit removed:** Swift 6 forbids accessing non-Sendable actor-isolated properties (KokoroTTS, MLXArray) from deinit (which is nonisolated). ARC handles all cleanup. WAV cleanup happens during normal synthesis flow via cleanupLastWav().
- **@preconcurrency imports:** MLX and MLXUtilsLibrary types (MLXArray, MToken) are not Sendable. `@preconcurrency import` suppresses warnings when these are captured in DispatchQueue closures.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] synthesizeStreaming API changed from callbacks to return value**

- **Found during:** Task 2 (build errors in TelegramBot and HTTPControlServer)
- **Issue:** Swift 6 forbids `NSLock.lock()` in async contexts and `var` mutation in `@Sendable` closures. The callback-based `synthesizeStreaming(onChunkReady:onAllComplete:)` required callers to collect chunks with locks.
- **Fix:** Changed `synthesizeStreaming` to return `[ChunkResult]` directly. All synthesis happens inside the actor, chunks are returned as a single array. Callers simply `await` the result.
- **Files modified:** TTSEngine.swift, TelegramBot.swift, HTTPControlServer.swift
- **Commits:** e9cf6ef0, f50cbc53

**2. [Rule 3 - Blocking] Actor deinit cannot access non-Sendable properties**

- **Found during:** Task 1 (build error on deinit)
- **Issue:** `deinit` on actors is nonisolated, cannot access actor-isolated properties of non-Sendable types (KokoroTTS, MLXArray)
- **Fix:** Removed explicit deinit -- ARC handles cleanup automatically
- **Files modified:** TTSEngine.swift
- **Commit:** e9cf6ef0

**3. [Rule 3 - Blocking] await cannot appear in || operator**

- **Found during:** Task 2 (build error in TelegramBot)
- **Issue:** `if await a || await b` is invalid Swift syntax -- `await` cannot appear to the right of non-assignment operators
- **Fix:** Split into separate `let` bindings before the `if` condition
- **Files modified:** TelegramBot.swift
- **Commit:** f50cbc53

---

**Total deviations:** 3 auto-fixed (3 blocking)
**Impact on plan:** All auto-fixes necessary for Swift 6 strict concurrency compilation. The synthesizeStreaming API change is a net improvement (cleaner, no locks needed in callers).

## Known Stubs

None -- all functionality is fully wired.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- TTSEngine is a proper Swift actor with compile-time concurrency safety
- PlaybackManager owns all audio hardware as a clean @MainActor boundary
- All callers use async/await for actor access
- Zero @unchecked Sendable on any TTSEngine-related type
- Ready for Phase 19+ testing and further hardening

## Self-Check: PASSED

- PlaybackManager.swift exists
- All 7 modified files exist
- Commit e9cf6ef0 found in git log
- Commit f50cbc53 found in git log
- swift build succeeds with zero errors
- swift test passes all 30 tests

---

_Phase: 19-ttsengine-decomposition-actor-migration_
_Completed: 2026-03-28_
