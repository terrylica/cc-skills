---
phase: 19-ttsengine-decomposition-actor-migration
verified: 2026-03-27T19:10:00Z
status: passed
score: 12/12 must-haves verified
re_verification: false
---

# Phase 19: TTSEngine Decomposition & Actor Migration Verification Report

**Phase Goal:** TTSEngine is a thin stateless facade delegating to actor-isolated components with compile-time concurrency safety
**Verified:** 2026-03-27T19:10:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                                               | Status   | Evidence                                                                                                                                                                                                                                                                                           |
| --- | ------------------------------------------------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | WordTimingAligner is a standalone Sendable struct with all 6 static methods from TTSEngine                          | VERIFIED | `WordTimingAligner.swift` exists: `public struct WordTimingAligner: Sendable` with NativeTimings, ResolvedTimings, and 6 static methods                                                                                                                                                            |
| 2   | PronunciationProcessor is a standalone Sendable struct with preprocessText() and all pronunciation overrides        | VERIFIED | `PronunciationProcessor.swift` exists: `public struct PronunciationProcessor: Sendable` with `compiledOverrides` and `public static func preprocessText`                                                                                                                                           |
| 3   | SentenceSplitter is a standalone Sendable struct with splitIntoSentences()                                          | VERIFIED | `SentenceSplitter.swift` exists: `public struct SentenceSplitter: Sendable` with `public static func splitIntoSentences`                                                                                                                                                                           |
| 4   | PlaybackDelegate is in its own file as @MainActor (not @unchecked Sendable)                                         | VERIFIED | `PlaybackDelegate.swift` exists: `@MainActor public final class PlaybackDelegate` — zero `@unchecked Sendable` in file                                                                                                                                                                             |
| 5   | TTSError is in its own file with circuitBreakerOpen case                                                            | VERIFIED | `TTSError.swift` exists: `public enum TTSError: Error, CustomStringConvertible` with `.circuitBreakerOpen` case                                                                                                                                                                                    |
| 6   | TTSEngine.swift delegates to extracted types with no duplicate logic                                                | VERIFIED | Calls `PronunciationProcessor.preprocessText` (lines 171, 224, 337), `WordTimingAligner.resolveWordTimings` (lines 253, 369), `SentenceSplitter.splitIntoSentences` (line 320); zero self-references to these methods                                                                              |
| 7   | PlaybackManager is a @MainActor class owning AVAudioPlayer lifecycle, pre-buffering, warm-up, and AudioStreamPlayer | VERIFIED | `PlaybackManager.swift` exists: `@MainActor public final class PlaybackManager` with `play()`, `preparePlayer()`, `stopPlayback()`, `warmUpAudioHardware()`, `public let audioStreamPlayer`                                                                                                        |
| 8   | TTSEngine is a Swift actor (not class + NSLock) with all mutable state actor-isolated                               | VERIFIED | `public actor TTSEngine` (line 45); zero functional NSLock usage (3 comment-only references); `withCheckedThrowingContinuation` on lines 176, 229, 329                                                                                                                                             |
| 9   | Blocking TTS synthesis runs on dedicated DispatchQueue via withCheckedThrowingContinuation                          | VERIFIED | `synthesisQueue = DispatchQueue(label: "com.terryli.tts-engine")` bridges all three synthesis methods via `withCheckedThrowingContinuation`/`withCheckedContinuation`                                                                                                                              |
| 10  | SubtitleSyncDriver receives AudioStreamPlayer directly (not through TTSEngine)                                      | VERIFIED | `SubtitleSyncDriver.init(subtitlePanel:audioStreamPlayer:onStreamingComplete:)` (line 183); zero `ttsEngine: TTSEngine` in file                                                                                                                                                                    |
| 11  | All 4 callers compile and work against the decomposed API                                                           | VERIFIED | `swift build` passes in 1.44s; CompanionApp creates `PlaybackManager()` and `TTSEngine(playbackManager:)`; TelegramBot and HTTPControlServer accept `playbackManager: PlaybackManager`; MemoryLifecycle uses `async func checkMemoryLifecycleRestart()` with `await engine.shouldRestartForMemory` |
| 12  | Zero @unchecked Sendable on TTSEngine-related types                                                                 | VERIFIED | No `@unchecked Sendable` in TTSEngine.swift, PlaybackManager.swift, PlaybackDelegate.swift, WordTimingAligner.swift, PronunciationProcessor.swift, SentenceSplitter.swift — confirmed via grep                                                                                                     |

**Score:** 12/12 truths verified

---

### Required Artifacts

| Artifact                                                                          | Expected                                                                                                | Status   | Details                                                                                    |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------ |
| `plugins/claude-tts-companion/Sources/CompanionCore/WordTimingAligner.swift`      | Pure Sendable struct with NativeTimings, ResolvedTimings, and all word timing methods                   | VERIFIED | 6 static methods present, imports MLXUtilsLibrary (not KokoroSwift — auto-fixed deviation) |
| `plugins/claude-tts-companion/Sources/CompanionCore/PronunciationProcessor.swift` | Pure Sendable struct with pronunciation overrides and preprocessText()                                  | VERIFIED | 50 lines, full implementation with regex compilation                                       |
| `plugins/claude-tts-companion/Sources/CompanionCore/SentenceSplitter.swift`       | Pure Sendable struct with splitIntoSentences()                                                          | VERIFIED | 69 lines, handles abbreviations and decimal numbers                                        |
| `plugins/claude-tts-companion/Sources/CompanionCore/PlaybackDelegate.swift`       | AVAudioPlayerDelegate as @MainActor                                                                     | VERIFIED | @MainActor, nonisolated init, nonisolated(unsafe) let properties for Swift 6 compatibility |
| `plugins/claude-tts-companion/Sources/CompanionCore/TTSError.swift`               | TTSError enum with circuitBreakerOpen case                                                              | VERIFIED | 4 cases including `.circuitBreakerOpen`                                                    |
| `plugins/claude-tts-companion/Sources/CompanionCore/PlaybackManager.swift`        | @MainActor class with play(), preparePlayer(), stopPlayback(), warmUpAudioHardware(), audioStreamPlayer | VERIFIED | 190 lines, all required methods and properties present                                     |
| `plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift`              | Actor facade delegating to PlaybackManager, WordTimingAligner, PronunciationProcessor                   | VERIFIED | 508 lines (down from 1139), `public actor TTSEngine`, delegates to all extracted types     |

---

### Key Link Verification

| From                     | To                           | Via                                             | Status | Details                                                                                              |
| ------------------------ | ---------------------------- | ----------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------- |
| TTSEngine.swift          | WordTimingAligner.swift      | `WordTimingAligner.resolveWordTimings()` calls  | WIRED  | Lines 253, 369 — called after DispatchQueue continuation returns                                     |
| TTSEngine.swift          | PronunciationProcessor.swift | `PronunciationProcessor.preprocessText()` calls | WIRED  | Lines 171, 224, 337 — called before synthesis dispatch                                               |
| TTSEngine.swift          | SentenceSplitter.swift       | `SentenceSplitter.splitIntoSentences()` calls   | WIRED  | Line 320 — called before streaming loop                                                              |
| CompanionApp.swift       | PlaybackManager.swift        | `PlaybackManager()` creation                    | WIRED  | Line 34: `playbackManager = PlaybackManager()`, passed to TTSEngine and callers                      |
| TTSEngine.swift          | PlaybackManager.swift        | `playbackManager.` delegation                   | WIRED  | `let playbackManager: PlaybackManager` property (line 63), receives via init                         |
| SubtitleSyncDriver.swift | PlaybackManager.swift        | receives audioStreamPlayer directly at init     | WIRED  | `init(subtitlePanel:audioStreamPlayer:)` — receives `playbackManager.audioStreamPlayer` from callers |
| TelegramBot.swift        | TTSEngine.swift              | `await ttsEngine.synthesizeStreaming()` calls   | WIRED  | TelegramBot stores `ttsEngine: TTSEngine` and `playbackManager: PlaybackManager`, uses await         |
| MemoryLifecycle.swift    | TTSEngine.swift              | `shouldRestartForMemory` async check            | WIRED  | `async func checkMemoryLifecycleRestart()` with `await engine.shouldRestartForMemory`                |

---

### Data-Flow Trace (Level 4)

Not applicable — this phase is a structural refactoring of a binary service with no user-facing UI components or database queries. The "data" is TTS synthesis output (audio files) which is verified by `swift build` succeeding and 30 tests passing.

---

### Behavioral Spot-Checks

| Behavior                                          | Command                                                                                  | Result                                                                                                                    | Status |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ------ |
| swift build compiles clean                        | `cd plugins/claude-tts-companion && swift build`                                         | "Build complete! (1.44s)" — zero errors                                                                                   | PASS   |
| All 30 tests pass                                 | `cd plugins/claude-tts-companion && swift test`                                          | "Test run with 30 tests passed after 0.161 seconds"                                                                       | PASS   |
| TTSEngine declared as actor                       | `grep "public actor TTSEngine" TTSEngine.swift`                                          | Match at line 45                                                                                                          | PASS   |
| No NSLock in TTSEngine (functional)               | `grep -c "NSLock" TTSEngine.swift` → 3                                                   | All 3 matches are comments, not code                                                                                      | PASS   |
| No @unchecked Sendable on TTSEngine-related types | `grep -rn "@unchecked Sendable" key files`                                               | Zero matches in TTSEngine, PlaybackManager, PlaybackDelegate, WordTimingAligner, PronunciationProcessor, SentenceSplitter | PASS   |
| withCheckedThrowingContinuation present           | `grep -c "withCheckedThrowingContinuation\|withCheckedContinuation" TTSEngine.swift` → 4 | 4 occurrences bridging all three synthesis methods                                                                        | PASS   |
| Commits exist                                     | `git log --oneline \| grep c0de991\|e9cf6ef\|f50cbc5`                                    | All 3 commits verified                                                                                                    | PASS   |

---

### Requirements Coverage

| Requirement | Source Plan   | Description                                                                                     | Status             | Evidence                                                                                                                                                                                                                                                                                                                    |
| ----------- | ------------- | ----------------------------------------------------------------------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ARCH-02     | 19-02-PLAN.md | TTSEngine decomposed into PlaybackManager (AVAudioPlayer lifecycle, pre-buffering)              | SATISFIED          | PlaybackManager.swift exists as @MainActor class with full playback lifecycle; TTSEngine stores it at init                                                                                                                                                                                                                  |
| ARCH-03     | 19-01-PLAN.md | TTSEngine decomposed into WordTimingAligner (MToken-to-word alignment, onset resolution)        | SATISFIED          | WordTimingAligner.swift: `public struct WordTimingAligner: Sendable` with NativeTimings, ResolvedTimings, resolveWordTimings()                                                                                                                                                                                              |
| ARCH-04     | 19-01-PLAN.md | TTSEngine decomposed into PronunciationProcessor (overrides dictionary, regex preprocessing)    | SATISFIED          | PronunciationProcessor.swift: `public struct PronunciationProcessor: Sendable` with compiledOverrides and preprocessText()                                                                                                                                                                                                  |
| ARCH-05     | 19-02-PLAN.md | TTSEngine becomes thin orchestrator delegating to extracted components                          | SATISFIED          | TTSEngine reduced from 1139 to 508 lines; all complex logic delegated to WordTimingAligner, PronunciationProcessor, SentenceSplitter, PlaybackManager, CircuitBreaker                                                                                                                                                       |
| ARCH-06     | 19-02-PLAN.md | All callers updated to use decomposed TTSEngine API                                             | SATISFIED          | CompanionApp, TelegramBot, HTTPControlServer, SubtitleSyncDriver, MemoryLifecycle all updated; SubtitleSyncDriver decoupled from TTSEngine entirely                                                                                                                                                                         |
| CONC-01     | 19-02-PLAN.md | TTSEngine migrated from @unchecked Sendable + NSLock to Swift actor                             | SATISFIED          | `public actor TTSEngine` — zero NSLock, zero @unchecked Sendable on TTSEngine itself                                                                                                                                                                                                                                        |
| CONC-02     | 19-02-PLAN.md | All actor-isolated state mutations happen in synchronous methods (no reentrancy across await)   | SATISFIED          | `synthesisCount +=` and model load mutations occur before or after await boundaries, never across them; serial DispatchQueue prevents concurrent synthesis                                                                                                                                                                  |
| CONC-03     | 19-02-PLAN.md | Blocking TTS synthesis runs off cooperative thread pool (DispatchQueue bridge or Task.detached) | SATISFIED          | `synthesisQueue.async` + `withCheckedThrowingContinuation`/`withCheckedContinuation` in all three synthesis methods                                                                                                                                                                                                         |
| CONC-04     | 19-02-PLAN.md | Formal Sendable conformance across pipeline components                                          | SATISFIED (scoped) | TTSEngine (actor), PlaybackManager (@MainActor), WordTimingAligner/PronunciationProcessor/SentenceSplitter (Sendable structs), PlaybackDelegate (@MainActor) — all TTSEngine-related types use formal Sendable; TelegramBot/HTTPControlServer/CompanionApp @unchecked Sendable is explicitly out of Phase 19 scope per plan |

**Note on CONC-04:** TelegramBot.swift, HTTPControlServer.swift, CompanionApp.swift, and AudioStreamPlayer.swift remain `@unchecked Sendable`. This is expected and explicitly scoped by 19-02-PLAN.md: "AudioStreamPlayer: KEEP @unchecked Sendable (it has its own NSLock, not a TTSEngine type — out of scope)" and "CompanionApp: if still @unchecked Sendable, that's out of Phase 19 scope." The REQUIREMENTS.md scope is "pipeline components" meaning the TTS synthesis pipeline types.

---

### Anti-Patterns Found

| File       | Pattern | Severity | Impact |
| ---------- | ------- | -------- | ------ |
| None found | —       | —        | —      |

No TODO/FIXME/placeholder comments in any of the 7 phase-modified files. No empty implementations. No hardcoded empty data. The `synthesizeStreaming` callback-to-return API change (deviation from plan) is documented as intentional and produces real data.

---

### Human Verification Required

None required. All truths are verifiable programmatically via static analysis and compilation.

The one item that could benefit from human validation is runtime correctness of karaoke sync (word highlight timing under live TTS load) — but that is a behavioral regression concern for Phase 20+, not a Phase 19 structural goal.

---

## Gaps Summary

None. All 12 must-have truths verified. All 9 requirements satisfied. Three planned commits exist in git history. `swift build` passes. 30/30 tests pass.

**Key deviations that were auto-fixed and do not constitute gaps:**

1. `WordTimingAligner` imports `MLXUtilsLibrary` (not `KokoroSwift`) for `MToken` — correct fix
2. `PlaybackDelegate` uses `nonisolated(unsafe) let` + `nonisolated init` for Swift 6 MainActor compatibility — correct fix
3. `synthesizeStreaming` changed from callback-based to return-based API — net improvement, eliminates NSLock in callers
4. Actor `deinit` removed — Swift 6 constraint, ARC handles cleanup

---

_Verified: 2026-03-27T19:10:00Z_
_Verifier: Claude (gsd-verifier)_
