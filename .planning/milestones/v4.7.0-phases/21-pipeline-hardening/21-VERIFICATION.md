---
phase: 21-pipeline-hardening
verified: 2026-03-28T03:10:00Z
status: passed
score: 5/5 must-haves verified
re_verification: false
---

# Phase 21: Pipeline Hardening Verification Report

**Phase Goal:** The streaming pipeline handles edge cases gracefully without crashes, queue corruption, or resource exhaustion
**Verified:** 2026-03-28T03:10:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                              | Status     | Evidence                                                                                                                                                      |
| --- | -------------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Five notifications in 10 seconds process without crash or audio queue corruption                   | ✓ VERIFIED | TTSPipelineCoordinator.startBatchPipeline() calls cancelCurrentPipeline() first — prevents buffer interleave                                                  |
| 2   | TTS test request arriving simultaneously with real notification does not produce interleaved audio | ✓ VERIFIED | Both TelegramBot and HTTPControlServer route through TTSPipelineCoordinator — coordinator serializes access                                                   |
| 3   | When TTS is busy, new requests show subtitle-only fallback (never silent drop)                     | ✓ VERIFIED | `isStreamingInProgress` guard now calls `showSubtitleOnlyFallback()` (TelegramBot.swift:248-251)                                                              |
| 4   | Bluetooth headphone disconnect mid-playback recovers gracefully                                    | ✓ VERIFIED | `AVAudioEngineConfigurationChange` observer in AudioStreamPlayer restarts engine; coordinator cancels pipeline                                                |
| 5   | Under memory pressure during synthesis, binary degrades to subtitle-only rather than crashing      | ✓ VERIFIED | `DispatchSource.makeMemoryPressureSource` in TTSPipelineCoordinator sets `isMemoryConstrained`; both consumers check `shouldUseSubtitleOnly` before synthesis |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact                                             | Expected                                     | Status     | Details                                                                                                                                                                                               |
| ---------------------------------------------------- | -------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Sources/CompanionCore/TTSPipelineCoordinator.swift` | Centralized TTS pipeline access coordination | ✓ VERIFIED | 188 lines; `class TTSPipelineCoordinator`, `cancelCurrentPipeline`, `startBatchPipeline`, `memoryPressureSource`, `shouldUseSubtitleOnly`, `startMonitoring`/`stopMonitoring` all present             |
| `Sources/CompanionCore/TelegramBot.swift`            | Updated TTS dispatch using coordinator       | ✓ VERIFIED | `pipelineCoordinator` property injected in init; `startBatchPipeline` called in `dispatchStreamingTTS`; `showSubtitleOnlyFallback` called in busy-state guard                                         |
| `Sources/CompanionCore/HTTPControlServer.swift`      | Updated TTS test using coordinator           | ✓ VERIFIED | `pipelineCoordinator` property injected; memory pressure check before synthesis; `startBatchPipeline` called for batch playback; `subtitle_only` JSON returned when constrained                       |
| `Sources/CompanionCore/AudioStreamPlayer.swift`      | AVAudioEngine configuration change recovery  | ✓ VERIFIED | `configChangeObserver` stored, `.AVAudioEngineConfigurationChange` observed in init, `handleConfigurationChange()` restarts engine, `onRouteChange` callback fires                                    |
| `Sources/CompanionCore/CompanionApp.swift`           | Coordinator created and wired                | ✓ VERIFIED | `TTSPipelineCoordinator(playbackManager:subtitlePanel:)` created; injected to both `HTTPControlServer` and `TelegramBot`; `startMonitoring()` called in `start()`, `stopMonitoring()` in `shutdown()` |

### Key Link Verification

| From                               | To                                              | Via                                      | Status  | Details                                                                                                                          |
| ---------------------------------- | ----------------------------------------------- | ---------------------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `TTSPipelineCoordinator`           | `AudioStreamPlayer`                             | exclusive reset/schedule lifecycle       | ✓ WIRED | `cancelCurrentPipeline()` calls `audioStreamPlayer.reset()`; no other code calls reset outside coordinator (confirmed with grep) |
| `TelegramBot.dispatchStreamingTTS` | `TTSPipelineCoordinator`                        | `pipelineCoordinator.startBatchPipeline` | ✓ WIRED | TelegramBot.swift:306 calls `self.pipelineCoordinator.startBatchPipeline(chunks:onComplete:)`                                    |
| `HTTPControlServer POST /tts/test` | `TTSPipelineCoordinator`                        | `pipelineCoordinator.startBatchPipeline` | ✓ WIRED | HTTPControlServer.swift:230 calls `self.pipelineCoordinator.startBatchPipeline(chunks:onComplete:)`                              |
| `AudioStreamPlayer`                | `AVAudioEngine.configurationChangeNotification` | `NotificationCenter` observer            | ✓ WIRED | AudioStreamPlayer.swift:92 observes `.AVAudioEngineConfigurationChange`; `handleConfigurationChange()` at line 180               |
| `TTSPipelineCoordinator`           | `DispatchSource.makeMemoryPressureSource`       | memory pressure event handler            | ✓ WIRED | TTSPipelineCoordinator.swift:62 creates source; event handler at line 66 sets `isMemoryConstrained`                              |
| `TTSPipelineCoordinator`           | `AudioStreamPlayer.onRouteChange`               | callback wired in `startMonitoring()`    | ✓ WIRED | TTSPipelineCoordinator.swift:90 sets `playbackManager.audioStreamPlayer.onRouteChange`                                           |

### Data-Flow Trace (Level 4)

Not applicable — these are control-flow / event-driven artifacts (audio pipeline coordination, hardware event handlers), not data-rendering components. No dynamic data rendering requires tracing.

### Behavioral Spot-Checks

| Behavior                                | Command                                                                                      | Result                        | Status |
| --------------------------------------- | -------------------------------------------------------------------------------------------- | ----------------------------- | ------ |
| swift build compiles cleanly            | `cd plugins/claude-tts-companion && swift build 2>&1 \| tail -3`                             | `Build complete! (1.45s)`     | ✓ PASS |
| No direct ASP.reset outside coordinator | `grep -r "audioStreamPlayer.reset" Sources/CompanionCore/ \| grep -v TTSPipelineCoordinator` | (empty — no matches)          | ✓ PASS |
| No activeSyncDriver outside coordinator | `grep -r "activeSyncDriver" Sources/CompanionCore/ \| grep -v TTSPipelineCoordinator`        | (empty — no matches)          | ✓ PASS |
| showSubtitleOnlyFallback called on busy | `grep -n "showSubtitleOnlyFallback" TelegramBot.swift`                                       | Lines 242, 250, 266, 302, 351 | ✓ PASS |
| All 4 task commits exist                | `git log --oneline d457d1a0 7267b8f8 ac47c354 920abab8`                                      | All 4 commits found           | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description                                                                                 | Status      | Evidence                                                                                                                                                            |
| ----------- | ----------- | ------------------------------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| HARD-01     | 21-01       | Rapid-fire notification handling (5 notifications in 10s without crash or queue corruption) | ✓ SATISFIED | Coordinator's `cancelCurrentPipeline()` called first in `startBatchPipeline()` — each new request cleanly preempts the previous without buffer interleave           |
| HARD-02     | 21-02       | Audio hardware disconnect recovery (Bluetooth headphones mid-playback)                      | ✓ SATISFIED | `AVAudioEngineConfigurationChange` observer restarts engine; coordinator cancels in-flight pipeline via `onRouteChange` callback                                    |
| HARD-03     | 21-02       | Memory pressure graceful degradation during synthesis                                       | ✓ SATISFIED | `DispatchSourceMemoryPressure` monitors `.warning` and `.critical`; `shouldUseSubtitleOnly` flag checked in both TelegramBot and HTTPControlServer before synthesis |
| HARD-04     | 21-01       | Concurrent TTS test + real notification race condition eliminated                           | ✓ SATISFIED | Both consumers now route through single `TTSPipelineCoordinator` — mutual exclusion via `cancelCurrentPipeline()` + `isActive` flag                                 |

No orphaned requirements: REQUIREMENTS.md maps HARD-01 through HARD-04 to Phase 21, and all four are claimed by plans 21-01 and 21-02.

### Anti-Patterns Found

No anti-patterns detected. Scanned `TTSPipelineCoordinator.swift`, `AudioStreamPlayer.swift`, `TelegramBot.swift`, `HTTPControlServer.swift`, and `CompanionApp.swift` for TODO/FIXME/placeholder comments, empty handlers, and hardcoded stub returns — all clean.

### Human Verification Required

The following behaviors require runtime observation and cannot be verified by static analysis:

#### 1. Rapid-Fire Notification Audio Quality

**Test:** Send 5 `/tts test` commands within 10 seconds via HTTP or Telegram while audio is playing.
**Expected:** Each new request preempts the previous without audible buffer interleave, clicks, or silence. Subtitles track each new request.
**Why human:** AVAudioEngine buffer cancellation timing can only be validated perceptually during actual playback.

#### 2. Bluetooth Disconnect Recovery

**Test:** Play a long TTS clip, then disconnect Bluetooth headphones mid-playback.
**Expected:** Audio resumes on built-in speakers within ~1 second; no crash; next TTS request works normally.
**Why human:** Requires physical Bluetooth hardware and real-time observation of recovery behavior.

#### 3. Memory Pressure Subtitle-Only Fallback

**Test:** Trigger memory pressure while synthesis is in progress (e.g., via `memory_pressure -S warn` or by filling RAM with other processes).
**Expected:** Current synthesis is cancelled (under `.critical`), subtitle is shown, next request after 60s resumes TTS normally.
**Why human:** Simulating real memory pressure events reliably requires OS-level tooling and runtime observation.

### Gaps Summary

No gaps. All must-haves from both plans verified. All four requirement IDs (HARD-01 through HARD-04) satisfied with direct code evidence. Build compiles cleanly. Key invariants confirmed:

- `audioStreamPlayer.reset()` is called exclusively from `TTSPipelineCoordinator.cancelCurrentPipeline()` — no other callers exist
- Neither `TelegramBot` nor `HTTPControlServer` holds its own `SubtitleSyncDriver` — coordinator is sole owner
- Subtitle-only fallback fires for three scenarios: memory pressure, TTS busy, and empty synthesis result

---

_Verified: 2026-03-28T03:10:00Z_
_Verifier: Claude (gsd-verifier)_
