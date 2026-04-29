---
phase: 32-audio-device-resilience
verified: 2026-03-29T08:00:00Z
status: human_needed
score: 10/11 must-haves verified
re_verification: false
human_verification:
  - test: "Audio plays correctly on new device after switching"
    expected: "After connecting/disconnecting Bluetooth or switching output in System Settings, TTS playback resumes on the new device within 200ms-5s. Log shows 'Rebuild triggered by halListener' and 'Audio engine rebuilt successfully on <device name>'"
    why_human: "Requires live hardware device switch (Bluetooth/HDMI). Cannot simulate CoreAudio HAL callback or AVAudioEngine device routing in a static code scan."
---

# Phase 32: Audio Device Resilience Verification Report

**Phase Goal:** AVAudioEngine recovers automatically when the system default audio output changes (Bluetooth connect/disconnect, HDMI, speaker switch) — CoreAudio HAL listener + periodic health check + engine rebuild with debounce

**Verified:** 2026-03-29T08:00:00Z
**Status:** human_needed (10/11 automated truths verified; 1 truth requires live hardware test)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                | Status   | Evidence                                                                                                                                                                                                                                                                                        |
| --- | ------------------------------------------------------------------------------------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | CoreAudio HAL listener fires when default output device changes                      | VERIFIED | `defaultOutputDeviceChanged` free function (line 16-28) dispatches to `triggerRebuild(source: .halListener)` via `DispatchQueue.main.async`. `setupHALListener()` uses `AudioObjectAddPropertyListener` with C function pointer (not block variant). `halListenerRegistered = true` on success. |
| 2   | Engine fully tears down and rebuilds graph on device change                          | VERIFIED | `rebuildEngine()` (line 403-446): stop → detach(playerNode) → reset() → attach(playerNode) → connect(playerNode, to: mainMixerNode, format: format) → prepare() → start(). Uses stored `format` (48kHz mono float32), NOT engine.outputNode.outputFormat.                                       |
| 3   | Rapid device flapping collapses into single rebuild via 200ms debounce               | VERIFIED | `triggerRebuild(source:)` (line 372-399): cancels pending `rebuildWorkItem`, creates new `DispatchWorkItem`, schedules via `asyncAfter(.now() + .milliseconds(Int(Config.audioRebuildDebounceMs)))`. Config value: 200ms.                                                                       |
| 4   | No more than 1 rebuild per 5 seconds (cooldown)                                      | VERIFIED | Inside `triggerRebuild` work item (line 382-386): checks `CFAbsoluteTimeGetCurrent() - lastRebuildTime < Config.audioRebuildCooldownSeconds`. Logs "Rebuild skipped (cooldown active, Xs remaining)" and returns early. Config value: 5s.                                                       |
| 5   | AVAudioEngineConfigurationChange notification feeds into same debounced rebuild path | VERIFIED | `handleConfigurationChange()` (line 244-247): body is exactly `triggerRebuild(source: .configNotification)`. Observer registered in `init()` on `NotificationCenter.default` for `.AVAudioEngineConfigurationChange`.                                                                           |
| 6   | 48kHz mono float32 format preserved after rebuild                                    | VERIFIED | `rebuildEngine()` line 431: `engine.connect(playerNode, to: engine.mainMixerNode, format: format)` — uses stored `format` initialized with `sampleRate: 48000.0, channels: 1, .pcmFormatFloat32`. Comment at line 402 explicitly states the anti-pattern being avoided.                         |
| 7   | Health check timer runs every 30 seconds comparing engine device vs system default   | VERIFIED | `startHealthCheck()` (line 299-311): `DispatchSource.makeTimerSource(queue: .main)` with `schedule(deadline: .now() + Config.audioHealthCheckInterval, repeating: Config.audioHealthCheckInterval)`. Config value: 30s.                                                                         |
| 8   | Health check skips during active playback                                            | VERIFIED | `performHealthCheck()` (line 322-335): first line is `guard !playerNode.isPlaying else { return }`.                                                                                                                                                                                             |
| 9   | Device mismatch in health check triggers the debounced rebuild path                  | VERIFIED | `performHealthCheck()` line 333: `triggerRebuild(source: .healthCheck)` called when `systemDevice != engineDevice && systemDevice != AudioDeviceID(kAudioDeviceUnknown)`.                                                                                                                       |
| 10  | Health check timer starts on init and stops on deinit                                | VERIFIED | `init()` line 143: `startHealthCheck()`. `deinit` line 152: `stopHealthCheck()`. Both calls confirmed.                                                                                                                                                                                          |
| 11  | Audio plays correctly on new device after switching (manual verification)            | ? HUMAN  | Requires live hardware device switch. Cannot verify statically.                                                                                                                                                                                                                                 |

**Score:** 10/11 automated truths verified (1 requires human hardware test)

---

## Required Artifacts

| Artifact                                                                     | Expected                               | Status   | Details                                                                                                                                                                                |
| ---------------------------------------------------------------------------- | -------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `plugins/claude-tts-companion/Sources/CompanionCore/Config.swift`            | Audio resilience constants             | VERIFIED | Lines 180-193: `audioHealthCheckInterval = 30`, `audioRebuildDebounceMs = 200`, `audioRebuildCooldownSeconds = 5`. All under `// MARK: - Audio Device Resilience`.                     |
| `plugins/claude-tts-companion/Sources/CompanionCore/AudioStreamPlayer.swift` | HAL listener + full rebuild + debounce | VERIFIED | 551 lines. All required functions present (see Key Links table). `import CoreAudio` at line 7. Free function `defaultOutputDeviceChanged` at line 16. `RebuildSource` enum at line 83. |

---

## Key Link Verification

### Plan 01 Key Links

| From                                        | To                                            | Via                        | Status | Details                                                                            |
| ------------------------------------------- | --------------------------------------------- | -------------------------- | ------ | ---------------------------------------------------------------------------------- |
| `defaultOutputDeviceChanged` (HAL callback) | `triggerRebuild(source: .halListener)`        | `DispatchQueue.main.async` | WIRED  | Line 25: `player.triggerRebuild(source: .halListener)` inside main async block     |
| `handleConfigurationChange()`               | `triggerRebuild(source: .configNotification)` | direct call                | WIRED  | Line 246: `triggerRebuild(source: .configNotification)` — only line in method body |
| `rebuildEngine()`                           | `onRouteChange?()`                            | callback after rebuild     | WIRED  | Line 392: `self.onRouteChange?()` called after `rebuildEngine()` inside work item  |

### Plan 02 Key Links

| From                   | To                                     | Via                | Status | Details                                                                |
| ---------------------- | -------------------------------------- | ------------------ | ------ | ---------------------------------------------------------------------- |
| `performHealthCheck()` | `triggerRebuild(source: .healthCheck)` | device ID mismatch | WIRED  | Line 333: `triggerRebuild(source: .healthCheck)` inside mismatch guard |

### Coordinator Wiring (Level 3)

| From                              | To                       | Via                 | Status | Details                                                                                                        |
| --------------------------------- | ------------------------ | ------------------- | ------ | -------------------------------------------------------------------------------------------------------------- |
| `AudioStreamPlayer.onRouteChange` | `TTSPipelineCoordinator` | callback assignment | WIRED  | TTSPipelineCoordinator.swift line 90: `playbackManager.audioStreamPlayer.onRouteChange = { [weak self] in ...` |

---

## Data-Flow Trace (Level 4)

Not applicable — AudioStreamPlayer is not a rendering component with a dynamic data source. It is an audio engine with hardware I/O. The "data" is the CoreAudio device ID obtained via `AudioObjectGetPropertyData` (a live system query, not static). Confirmed: `getSystemDefaultOutputDeviceID()` queries `kAudioHardwarePropertyDefaultOutputDevice` at lines 340-351 — no hardcoded return values.

---

## Behavioral Spot-Checks

| Behavior                                | Command                                                                                                                               | Result                                    | Status |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- | ------ |
| `swift build` compiles with zero errors | `cd plugins/claude-tts-companion && swift build`                                                                                      | "Build complete! (1.03s)"                 | PASS   |
| Deprecated constant absent              | `grep kAudioObjectPropertyElementMaster AudioStreamPlayer.swift`                                                                      | No matches                                | PASS   |
| All required functions defined          | `grep -c "rebuildEngine\|triggerRebuild\|setupHALListener\|removeHALListener\|startHealthCheck\|stopHealthCheck\|performHealthCheck"` | 16 occurrences (definitions + call sites) | PASS   |
| Config constants present (3 of 3)       | `grep -c "audioHealthCheckInterval\|audioRebuildDebounceMs\|audioRebuildCooldownSeconds" Config.swift`                                | 3                                         | PASS   |
| Commit hashes valid                     | `git log af9c0e75 4becbd35 ad9c319f`                                                                                                  | All 3 commits found in history            | PASS   |

---

## Requirements Coverage

| Requirement | Source Plan | Description                                                                          | Status    | Evidence                                                                                                                                                                                      |
| ----------- | ----------- | ------------------------------------------------------------------------------------ | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AUDIO-01    | 32-01       | CoreAudio HAL listener fires immediately when default output device changes          | SATISFIED | `setupHALListener()` registers `AudioObjectAddPropertyListener` with `kAudioHardwarePropertyDefaultOutputDevice` on init. Free function dispatches to `triggerRebuild(source: .halListener)`. |
| AUDIO-02    | 32-01       | Full AVAudioEngine teardown + rebuild on device change                               | SATISFIED | `rebuildEngine()`: detach → reset → attach → connect(format:) → prepare → start. All 7 steps confirmed at lines 415-445.                                                                      |
| AUDIO-03    | 32-01       | 200ms debounce + 5s cooldown prevents rebuild storms                                 | SATISFIED | `triggerRebuild(source:)` cancels prior `DispatchWorkItem` and schedules after 200ms. Work item body enforces 5s cooldown via `CFAbsoluteTimeGetCurrent()` comparison.                        |
| AUDIO-04    | 32-01       | AVAudioEngineConfigurationChange notification feeds into same debounced rebuild path | SATISFIED | `handleConfigurationChange()` body: single call `triggerRebuild(source: .configNotification)`.                                                                                                |
| AUDIO-05    | 32-02       | 30-second periodic health check detects device mismatch                              | SATISFIED | `startHealthCheck()` using `DispatchSourceTimer` with 30s interval. `performHealthCheck()` compares `cachedOutputDeviceID` vs `getSystemDefaultOutputDeviceID()`.                             |
| AUDIO-06    | 32-02       | Device ID + name logged on every engine start, rebuild, and health check mismatch    | SATISFIED | Line 178: engine start logs device name + ID. Line 412: rebuild logs old→new device. Line 332: health check logs mismatch with both device names and IDs.                                     |

All 6 requirements (AUDIO-01 through AUDIO-06) are SATISFIED. No orphaned requirements found.

---

## Anti-Patterns Found

| File                      | Line | Pattern                                                          | Severity | Impact                                                                                                                                     |
| ------------------------- | ---- | ---------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `AudioStreamPlayer.swift` | 51   | Doc comment says "24kHz mono float32" but actual format is 48kHz | Info     | Stale comment only — actual `AVAudioFormat` initialized at 48000.0 Hz (line 116). Rebuild also uses stored `format`. No functional impact. |

No blocking anti-patterns found. No TODO/FIXME/placeholder comments. No stub implementations. No empty handlers.

---

## Human Verification Required

### 1. Audio Recovery After Live Device Switch

**Test:** Build release binary (`swift build -c release`). Start the companion. Trigger TTS via `tts_kokoro.sh "Testing audio device resilience"`. While audio plays (or immediately after), switch audio output in System Settings > Sound or connect/disconnect Bluetooth.

**Expected:**

- Log shows: "Rebuild triggered by halListener" (within ~200ms of device change)
- Log shows: "Rebuilding audio engine: device X -> Y (DeviceName)"
- Log shows: "Audio engine rebuilt successfully on DeviceName (took Xms)"
- Subsequent TTS call (`tts_kokoro.sh "Audio should play on new device"`) plays on the new output device

**Why human:** Requires live CoreAudio HAL callback which fires only during real hardware device enumeration change. Cannot be exercised with static analysis or by inspecting build output.

---

## Gaps Summary

No automated gaps. All 10 programmatically verifiable truths are confirmed in the codebase. The single human-verification item (truth #11) is a mandatory checkpoint from Plan 02 Task 2 and is not a code defect — it is a behavioral integration test that requires real hardware.

The phase goal is structurally achieved: HAL listener, full engine teardown/rebuild, 200ms debounce, 5s cooldown, 30s health check, and `onRouteChange` coordinator callback are all present, wired, and substantive. `swift build` passes cleanly.

---

_Verified: 2026-03-29T08:00:00Z_
_Verifier: Claude (gsd-verifier)_
