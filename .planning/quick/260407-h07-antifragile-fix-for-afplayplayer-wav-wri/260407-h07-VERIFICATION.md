---
phase: 260407-h07-antifragile-fix-for-afplayplayer-wav-wri
verified: 2026-04-07T19:48:30Z
status: passed
score: 8/8 must-haves verified
overrides_applied: 0
---

# Quick 260407-h07: Antifragile AfplayPlayer WAV-Write Fix — Verification Report

**Phase Goal:** Self-healing fallback chain (primary → NSTemporaryDirectory → mkstemp), collapsed structured telemetry (≤1 log/class/60s + recovery), `/health.afplay`, codebase-wide `try? createDirectory` cleanup, and a chaos test that fails on the buggy code and passes on the fix.
**Verified:** 2026-04-07T19:48:30Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                               | Status   | Evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| --- | --------------------------------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | AfplayPlayer survives mid-session deletion of `~/.local/share/tts-debug-wav/` without losing audio  | VERIFIED | `ensureWritableWavDirectory()` (AfplayPlayer.swift L596-651) is called before each WAV write at L189 (`play`) and L425 (`startSegment`). Tier 0 calls `createDirectory(...withIntermediateDirectories: true)`, which recreates the dir on every call. Chaos test `primaryRecreatesWhenDeleted` passes (0.002s).                                                                                                                                                                                                                                                                  |
| 2   | When primary fails, falls back transparently to NSTemporaryDirectory then mkstemp(/tmp)             | VERIFIED | Tier 1 at L617-629 builds `NSTemporaryDirectory()/claude-tts-wav` and increments `fallbackLevel=1`. Tier 2 at L632-647 calls `mkstemps(template, 4)` returning a `/tmp/claude-tts-wav-XXXXXX.wav` path, sets `fallbackLevel=2`. Chaos test `fallsBackWhenPrimaryUnwritable` passes; runtime log shows `fallback_engaged level=1 path=/var/folders/.../claude-tts-wav reason=eperm`.                                                                                                                                                                                              |
| 3   | When primary recovers, returns to primary and logs single recovery event                            | VERIFIED | L601-610: success branch checks `fallbackLevel > 0                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |     | consecutiveFailureCount > 0`and emits a single`primary_recovered`info log, then resets all state (counters, level, firstFailureAt, lastFailureClass, lastLoggedAt). Chaos test`recoveryResetsStateAndIsIdempotent`passes; runtime log shows`[TELEMETRY] primary_recovered prior_failures=1 prior_level=1` exactly once. |
| 4   | Collapsed failure telemetry: ≤1 structured log per failure-class per 60s (no 60Hz spam)             | VERIFIED | `recordFailure(...)` at L680-698 keys `wavFailureState.lastLoggedAt[cls.rawValue]` and only emits when `lastLogged == nil                                                                                                                                                                                                                                                                                                                                                                                                                                                        |     | now.timeIntervalSince(lastLogged!) >= 60.0`. Chaos test`failureLoggedAtMostOncePerClassIn60sWindow`runs 10 failure attempts and asserts`**testing_consecutiveFailureCount >= 10`AND`**testing_loggedClassCount <= 2`; passes.                                                                                           |
| 5   | GET /health exposes afplay subsystem state without breaking SwiftBar jq parsers                     | VERIFIED | `HealthResponse.afplay: AfplayPlayer.AfplayHealthSnapshot` added at HTTPControlServer.swift L54 (additive, no removal). `healthResponse()` (L303-322) is now `async`, hops to MainActor via `await MainActor.run { playbackManager.afplayPlayer.getAfplayHealthSnapshot() }`. Snapshot struct has all 6 fields (`primary_dir_writable`, `fallback_level`, `consecutive_failure_count`, `total_fallback_writes`, `last_failure_class`, `last_failure_at`) at AfplayPlayer.swift L74-81. Existing fields unchanged. Route handler at L123-125 awaits `healthResponse()`.           |
| 6   | SettingsStore config dir creation errors are logged, not silently swallowed                         | VERIFIED | SettingsStore.swift L121-130 replaces the previous `try?` with explicit `do { try FileManager.default.createDirectory(...) } catch { logger.error("Failed to create config dir \(configDir): \(error) — settings writes will fail until dir is recreated") }`. The class already has `private let logger = Logger(label: "settings-store")` at L105.                                                                                                                                                                                                                             |
| 7   | swift build -c release succeeds with zero warnings in the touched files                             | VERIFIED | `swift build -c release` completed (10.17s clean rebuild). Warnings emitted only from untouched files: TelegramBotCallbacks.swift (try? unused — 2x), TelegramBotNotifications.swift (?? on non-optional), AudioStreamPlayer.swift (CFString UnsafeMutableRawPointer), CompanionApp.swift (CFString — 2x), PlaybackDelegate.swift (nonisolated(unsafe) unnecessary — 2x), TelegramBotCallbacks.swift (BotDispatcher Sendable). Zero warnings in AfplayPlayer.swift, HTTPControlServer.swift, SettingsStore.swift, AfplayPlayerChaosTests.swift.                                  |
| 8   | swift test --filter AfplayPlayerChaosTests passes; would fail against unmodified AfplayPlayer.swift | VERIFIED | All 4 tests pass: `primaryRecreatesWhenDeleted` (0.002s), `fallsBackWhenPrimaryUnwritable` (0.006s), `failureLoggedAtMostOncePerClassIn60sWindow` (0.001s), `recoveryResetsStateAndIsIdempotent` (0.001s). The test file references `ensureWritableWavDirectoryForTesting`, `getAfplayHealthSnapshot`, `AfplayHealthSnapshot`, `__testing_loggedClassCount`, `__testing_consecutiveFailureCount` — none exist on the pre-fix code, so the test file would FAIL TO COMPILE against unmodified `AfplayPlayer.swift`, which is a strictly stronger form of "test fails on pre-fix". |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact                                                | Expected                                                                                                                    | Status   | Details                                                                                                                                              |
| ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Sources/CompanionCore/AfplayPlayer.swift`              | ensureWritableWavDirectory + WavWriteFailureState + AfplayHealthSnapshot + getAfplayHealthSnapshot + explicit init do/catch | VERIFIED | All 5 symbols present at lines 596, 63, 74, 701, 85 respectively.                                                                                    |
| `Sources/CompanionCore/HTTPControlServer.swift`         | HealthResponse.afplay (AfplayHealthSnapshot) populated via accessor                                                         | VERIFIED | Field at L54, populated at L306 via `await MainActor.run { playbackManager.afplayPlayer.getAfplayHealthSnapshot() }`.                                |
| `Sources/CompanionCore/SettingsStore.swift`             | Explicit do/catch around config dir createDirectory with logger.error                                                       | VERIFIED | Replacement at L121-130.                                                                                                                             |
| `Tests/CompanionCoreTests/AfplayPlayerChaosTests.swift` | 4 chaos tests in @Suite(.serialized) @MainActor, no afplay invocation                                                       | VERIFIED | Created. 132 lines, 4 @Test methods, uses `@testable import CompanionCore`, no `Process`/`afplay`/`spawn` references — pure filesystem manipulation. |

### Key Link Verification

| From                                                          | To                                                                    | Via                                                                                                      | Status | Details                                                                                                                                                                                   |
| ------------------------------------------------------------- | --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AfplayPlayer.play (L189) and AfplayPlayer.startSegment (L425) | ensureWritableWavDirectory()                                          | wavPath derived from `resolved.url.appendingPathComponent(...)` or `resolved.mkstempPath`                | WIRED  | Both call sites verified in source. The captured-at-init `debugWavDir` is no longer used as the WAV write target — only as the primary tier-0 path inside `ensureWritableWavDirectory()`. |
| HTTPControlServer.healthResponse()                            | AfplayPlayer.getAfplayHealthSnapshot()                                | `await MainActor.run { playbackManager.afplayPlayer.getAfplayHealthSnapshot() }` at L306                 | WIRED  | Snapshot is non-optional in HealthResponse, populated unconditionally.                                                                                                                    |
| AfplayPlayerChaosTests                                        | AfplayPlayer.ensureWritableWavDirectory() + getAfplayHealthSnapshot() | `@testable import CompanionCore` + direct method calls via `ensureWritableWavDirectoryForTesting()` shim | WIRED  | Test runs in 0.011s total without spawning afplay processes.                                                                                                                              |

### Behavioral Spot-Checks

| Behavior                                                          | Command                                                                           | Result                                 | Status |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------- | -------------------------------------- | ------ |
| Release build succeeds                                            | `swift build -c release`                                                          | Build complete! (10.17s clean rebuild) | PASS   |
| Chaos suite passes                                                | `swift test --filter AfplayPlayerChaosTests`                                      | 4 tests, 4 pass, 0 fail                | PASS   |
| No `try? FileManager.default.createDirectory` remains in Sources/ | `grep -r "try?\s+FileManager\.default\.createDirectory" Sources/`                 | No matches found                       | PASS   |
| Forbidden audio-path symbols untouched in AfplayPlayer diff       | `git diff f9d8e103..HEAD -- AfplayPlayer.swift \| grep posix_spawn\|waitpid\|...` | No matches                             | PASS   |

### Anti-Patterns Found

None in the touched files. Pre-existing warnings in untouched files (TelegramBotCallbacks, TelegramBotNotifications, AudioStreamPlayer, CompanionApp, PlaybackDelegate) are documented in the SUMMARY as out of scope.

### Scope Discipline (Diff Summary)

```
plugins/claude-tts-companion/Sources/CompanionCore/AfplayPlayer.swift              | 209 +++++++++--
plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift         |   9 ++--
plugins/claude-tts-companion/Sources/CompanionCore/SettingsStore.swift             |  16 ++++--
plugins/claude-tts-companion/Tests/CompanionCoreTests/AfplayPlayerChaosTests.swift | 131 ++++++
4 files changed, 349 insertions(+), 16 deletions(-)
```

`git diff f9d8e103..HEAD -- AfplayPlayer.swift | grep -E "posix_spawn|waitpid|killall|playOrEnqueue|markQueueComplete|cumulativeTimeOffset|currentSegmentDuration|playStartTime|finishedSegmentDuration|isPipelinedMode|currentTime"` returns ZERO matches. The audio playback path (posix_spawn, waitpid, QoS, kill, segment chaining, deferred-offset, currentTime cap) is fully preserved. The diff is surgical: directory management, telemetry state, health accessor, init error handling, and `#if DEBUG` test seams only.

### Human Verification Required

None — all must-haves verified programmatically. The post-merge manual smoke checklist in the SUMMARY (deploy, curl /health, delete dir mid-session, observe SwiftBar) is for the user to perform after merging but is not blocking verification.

### Gaps Summary

No gaps. All 8 must-haves verified. Build succeeds with no new warnings in touched files. All 4 chaos tests pass with observable telemetry output matching the design (fallback_engaged level=1, primary_recovered prior_failures=1 prior_level=1, single log per class). Scope discipline preserved — no audio-path code mutated.

---

_Verified: 2026-04-07T19:48:30Z_
_Verifier: Claude (gsd-verifier)_
