# Phase 32: Audio Device Resilience - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning
**Source:** Web research + codebase scout (all 4 gray areas accepted from research)

<domain>
## Phase Boundary

AVAudioEngine recovers automatically when the system default audio output changes (Bluetooth connect/disconnect, HDMI, speaker switch). Three-layer detection (CoreAudio HAL listener + AVAudioEngineConfigurationChange backup + periodic health check) with full engine rebuild and debounce.

Scope: AudioStreamPlayer.swift recovery logic + Config.swift constants + TTSPipelineCoordinator integration. No changes to TTS synthesis, subtitle sync, or Telegram bot.

</domain>

<decisions>
## Implementation Decisions

### D-01: Recovery Strategy — Full Engine Teardown + Rebuild

- Current `handleConfigurationChange()` only stops player node and calls `engine.start()` — insufficient when aggregate device is stale
- Recovery sequence: `engine.stop()` → detach all nodes → `engine.reset()` → re-attach player node → re-connect to main mixer → `engine.prepare()` → `try engine.start()`
- This matches AudioKit's `rebuildGraph()` pattern — the only reliable approach per community consensus
- Must preserve 48kHz mono float32 format when rebuilding (re-read from engine.outputNode.outputFormat or use stored format)
- `onRouteChange` callback to TTSPipelineCoordinator remains — it cancels the current pipeline during rebuild

### D-02: Detection Layer 1 — CoreAudio HAL Listener (Primary)

- Use raw CoreAudio C API: `AudioObjectAddPropertyListener` on `kAudioObjectSystemObject` with `kAudioHardwarePropertyDefaultOutputDevice` selector
- ~30 lines of Swift calling C functions — no external dependency needed
- This is the most reliable detection: fires immediately on device change, works for background/accessory apps
- Listener callback triggers the rebuild sequence (with debounce from D-05)

### D-03: Detection Layer 2 — AVAudioEngineConfigurationChange (Backup)

- Already implemented in AudioStreamPlayer — keep as backup
- Catches sample rate changes that HAL listener might not surface
- Both listeners feed into the same debounced rebuild path

### D-04: Detection Layer 3 — Periodic Health Check (Safety Net)

- Timer interval: 30 seconds (constant in Config.swift: `audioHealthCheckInterval`)
- Health check logic: compare engine's current output device ID vs system default output device ID
- If IDs diverge → trigger rebuild (with debounce from D-05)
- Health check should NOT run during active playback (audio is clearly working if playing) — only between sessions or when idle
- Use DispatchSourceTimer (consistent with existing memory pressure monitoring pattern in TTSPipelineCoordinator)

### D-05: Debounce & Timing

- 200ms debounce window for all rebuild triggers (HAL, notification, health check)
- Prevents format mismatch races during BT reconnect flapping
- Cooldown: no more than 1 rebuild per 5 seconds (prevents rebuild storms from rapid device cycling)
- Constant in Config.swift: `audioRebuildDebounceMs` and `audioRebuildCooldownSeconds`

### D-06: Telemetry & Logging

- Log output device ID + name on every engine start/rebuild
- Log device change events: old device → new device (from HAL listener)
- Log health check results: match/mismatch + device IDs compared
- Log rebuild events: trigger source (HAL/notification/healthcheck), duration, success/failure
- Use existing swift-log logger (already in AudioStreamPlayer)

### Claude's Discretion

- Internal code organization (helper methods, extensions)
- Exact NSLock usage patterns for thread safety during rebuild
- Whether to extract CoreAudio HAL listener into a separate file or keep inline in AudioStreamPlayer
- DispatchSourceTimer scheduling details for health check

</decisions>

<canonical_refs>

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audio Architecture

- `plugins/claude-tts-companion/Sources/CompanionCore/AudioStreamPlayer.swift` — Current device change handling, engine lifecycle, gapless streaming
- `plugins/claude-tts-companion/Sources/CompanionCore/PlaybackManager.swift` — Hardware warm-up, AudioStreamPlayer ownership
- `plugins/claude-tts-companion/Sources/CompanionCore/TTSPipelineCoordinator.swift` — Route change callback wiring, memory pressure monitoring pattern (reuse for health check timer)
- `plugins/claude-tts-companion/Sources/CompanionCore/Config.swift` — Constants file for new audio health check values

### Integration Points

- `plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift` — Uses AudioStreamPlayer.currentTime for karaoke sync, must handle rebuild gracefully
- `plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift` — Subsystem initialization order, pipelineCoordinator.startMonitoring()

### External References

- [Chris Liscio: It's Over Between Us, AVAudioEngine](https://supermegaultragroovy.com/2021/01/26/it-s-over-avaudioengine/) — Documents aggregate device stale problem
- [More on AVAudioEngine + AirPods](https://supermegaultragroovy.com/2021/01/28/more-on-avaudioengine-airpods/) — AirPods-specific aggregate device behavior
- [AudioKit Issue #2130](https://github.com/AudioKit/AudioKit/issues/2130) — AVAudioEngine device selection limitations
- [AudioKit Issue #2384](https://github.com/AudioKit/AudioKit/issues/2384) — Default device change handling recommendations
- [terrylica/cc-skills#73](https://github.com/terrylica/cc-skills/issues/73) — Source issue with full problem description and solution layers

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- `AudioStreamPlayer.handleConfigurationChange()` — Existing notification observer, will be enhanced with full rebuild
- `TTSPipelineCoordinator.handleAudioRouteChange()` — Already wired as callback, cancels pipeline on route change
- `DispatchSource.makeMemoryPressureSource()` pattern in TTSPipelineCoordinator — Reuse for health check timer
- `NSLock` pattern in AudioStreamPlayer — Thread safety for engine operations
- `PlaybackManager.warmUpHardware()` — May need to run after rebuild to prevent stutter

### Established Patterns

- AudioStreamPlayer uses `@unchecked Sendable` with NSLock for thread safety
- TTSPipelineCoordinator uses DispatchSource for async monitoring
- Config.swift uses static let constants grouped by subsystem
- swift-log Logger used throughout for structured logging

### Integration Points

- `AudioStreamPlayer.onRouteChange` callback → `TTSPipelineCoordinator.handleAudioRouteChange()` — must fire on rebuild
- `SubtitleSyncDriver` polls `audioStreamPlayer.currentTime` — rebuild resets currentTime to 0
- `CompanionApp.start()` calls `pipelineCoordinator.startMonitoring()` — health check timer starts here

</code_context>

<specifics>
## Specific Ideas

- User requested "anti-fragile" approach — three detection layers ensure no single point of failure
- SimplyCoreAudio is **archived** (read-only since March 2024, v4.1.1) — raw CoreAudio HAL API is the correct choice, zero new dependencies
- AudioKit's `rebuildGraph()` validates the full teardown+rebuild approach over lighter restart attempts
- Nonstrict.eu blog confirms audio gaps during device switches exist at CoreAudio stack level — graceful pipeline cancellation is the right response (already handled by TTSPipelineCoordinator)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

_Phase: 32-audio-device-resilience_
_Context gathered: 2026-03-29 via web research + codebase scout_
