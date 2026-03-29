# Phase 32: Audio Device Resilience - Research

**Researched:** 2026-03-29
**Domain:** CoreAudio HAL + AVAudioEngine recovery on macOS
**Confidence:** HIGH

## Summary

This phase adds three-layer audio device change detection (CoreAudio HAL listener, AVAudioEngineConfigurationChange notification, periodic health check) and a full engine teardown/rebuild recovery path to AudioStreamPlayer.swift. The CONTEXT.md decisions are thorough and well-researched -- all six decisions (D-01 through D-06) align with established patterns in AudioKit and community best practices.

The primary technical risk is thread safety during rebuild: the HAL listener fires on a CoreAudio-internal thread, the AVAudioEngineConfigurationChange notification fires on the main queue, and the health check timer fires on the main queue. All three must converge to a single debounced rebuild path protected by the existing NSLock pattern.

**Primary recommendation:** Implement the three detection layers feeding into a single `rebuildEngine()` method with 200ms debounce + 5s cooldown, all coordinated through NSLock. Extract CoreAudio HAL listener into a small helper (~50 lines) for clarity.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01: Full Engine Teardown + Rebuild** -- engine.stop() -> detach all nodes -> engine.reset() -> re-attach player node -> re-connect to main mixer -> engine.prepare() -> try engine.start(). Must preserve 48kHz mono float32 format.
- **D-02: CoreAudio HAL Listener (Primary)** -- AudioObjectAddPropertyListener on kAudioObjectSystemObject with kAudioHardwarePropertyDefaultOutputDevice. Raw C API, no external dependency.
- **D-03: AVAudioEngineConfigurationChange (Backup)** -- Already implemented, keep as backup. Both listeners feed into same debounced rebuild.
- **D-04: Periodic Health Check (Safety Net)** -- 30-second DispatchSourceTimer. Compare engine output device ID vs system default. Skip during active playback.
- **D-05: Debounce & Timing** -- 200ms debounce, 5s cooldown. Constants in Config.swift.
- **D-06: Telemetry & Logging** -- Log device ID + name on every start/rebuild, change events, health check results, rebuild trigger source + duration + success/failure.

### Claude's Discretion

- Internal code organization (helper methods, extensions)
- Exact NSLock usage patterns for thread safety during rebuild
- Whether to extract CoreAudio HAL listener into a separate file or keep inline
- DispatchSourceTimer scheduling details for health check

### Deferred Ideas (OUT OF SCOPE)

None -- discussion stayed within phase scope.

</user_constraints>

## Architecture Patterns

### Current AudioStreamPlayer Structure

```
AudioStreamPlayer (@unchecked Sendable)
├── engine: AVAudioEngine (created once in init)
├── playerNode: AVAudioPlayerNode (created once in init)
├── format: AVAudioFormat (48kHz mono float32)
├── engineLock: NSLock
├── configChangeObserver: NSObjectProtocol
├── onRouteChange: (() -> Void)?
├── start() / stop() / reset()
├── handleConfigurationChange() -- REPLACE with full rebuild
└── scheduleChunk() / scheduleFile()
```

### Proposed Rebuild Architecture

```
AudioStreamPlayer
├── [existing properties]
├── NEW: halListenerRegistered: Bool
├── NEW: healthCheckTimer: DispatchSourceTimer?
├── NEW: lastRebuildTime: CFAbsoluteTime (for cooldown)
├── NEW: rebuildWorkItem: DispatchWorkItem? (for debounce)
│
├── [existing methods]
├── NEW: setupHALListener() -- register CoreAudio property listener
├── NEW: removeHALListener() -- unregister on deinit
├── NEW: startHealthCheck() / stopHealthCheck()
├── NEW: triggerRebuild(source:) -- debounce entry point
├── NEW: rebuildEngine() -- actual teardown + rebuild
└── NEW: getSystemDefaultOutputDeviceID() -> AudioDeviceID
```

### Integration Flow

```
Detection Layer 1: CoreAudio HAL listener ─┐
Detection Layer 2: AVAudioEngineConfigChange ─┼─▶ triggerRebuild(source:)
Detection Layer 3: 30s health check timer ──┘       │
                                                      ▼
                                              200ms debounce
                                                      │
                                              5s cooldown check
                                                      │
                                                      ▼
                                              rebuildEngine()
                                              ├── engine.stop()
                                              ├── engine.detach(playerNode)
                                              ├── engine.reset()
                                              ├── engine.attach(playerNode)
                                              ├── engine.connect(playerNode, mixer, format)
                                              ├── engine.prepare()
                                              ├── try engine.start()
                                              └── onRouteChange?()
```

### Anti-Patterns to Avoid

- **Just calling engine.start() after config change:** This is what the current code does. It fails when the aggregate device is stale (the core bug this phase fixes).
- **Creating a new AVAudioEngine instance:** Unnecessary and expensive. engine.reset() clears the stale aggregate device reference. The same engine instance works after detach/reset/re-attach.
- **Using AudioObjectAddPropertyListenerBlock:** Known Apple bug -- `AudioObjectRemovePropertyListenerBlock` does not work reliably. Use the C function pointer variant `AudioObjectAddPropertyListener` instead, which has reliable removal via `AudioObjectRemovePropertyListener`.

## Code Examples

### Pattern 1: CoreAudio HAL Listener (C Function Pointer)

```swift
import CoreAudio

// Global C function (cannot capture context -- use AudioObjectAddPropertyListener)
private func defaultOutputDeviceChanged(
    _ objectID: AudioObjectID,
    _ numberAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = clientData else { return noErr }
    let player = Unmanaged<AudioStreamPlayer>.fromOpaque(clientData).takeUnretainedValue()
    // Dispatch to main queue for thread safety (HAL callback fires on CoreAudio thread)
    DispatchQueue.main.async {
        player.triggerRebuild(source: .halListener)
    }
    return noErr
}

// Registration (in AudioStreamPlayer)
func setupHALListener() {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain  // Note: kAudioObjectPropertyElementMaster is deprecated
    )
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    let status = AudioObjectAddPropertyListener(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        defaultOutputDeviceChanged,
        selfPtr
    )
    if status == noErr {
        halListenerRegistered = true
        logger.info("CoreAudio HAL listener registered for default output device changes")
    } else {
        logger.error("Failed to register CoreAudio HAL listener: \(status)")
    }
}
```

**Source:** [CoreAudio output device gist](https://gist.github.com/rlxone/584467a63ac0ddf4d62fe1a983b42d0e), [Apple AudioObjectPropertyListenerBlock docs](https://developer.apple.com/documentation/coreaudio/audioobjectpropertylistenerblock)

### Pattern 2: Get System Default Output Device ID

```swift
func getSystemDefaultOutputDeviceID() -> AudioDeviceID {
    var deviceID = AudioDeviceID(kAudioDeviceUnknown)
    var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil,
        &propertySize, &deviceID
    )
    return deviceID
}
```

**Source:** [CoreAudio output device gist](https://gist.github.com/rlxone/584467a63ac0ddf4d62fe1a983b42d0e)

### Pattern 3: Get Device Name from AudioDeviceID

```swift
func getDeviceName(deviceID: AudioDeviceID) -> String {
    var name: CFString = "" as CFString
    var propertySize = UInt32(MemoryLayout<CFString>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &name)
    return name as String
}
```

### Pattern 4: Full Engine Rebuild Sequence

```swift
private func rebuildEngine() {
    engineLock.lock()
    defer { engineLock.unlock() }

    let startTime = CFAbsoluteTimeGetCurrent()
    let oldDeviceID = /* cached from previous start */
    let newDeviceID = getSystemDefaultOutputDeviceID()
    let newDeviceName = getDeviceName(deviceID: newDeviceID)

    logger.warning("Rebuilding audio engine: device \(oldDeviceID) -> \(newDeviceID) (\(newDeviceName))")

    // 1. Stop everything
    playerNode.stop()
    bufferCountLock.lock()
    scheduledBufferCount = 0
    bufferCountLock.unlock()

    if isRunning {
        engine.stop()
        isRunning = false
    }

    // 2. Teardown graph
    engine.detach(playerNode)
    engine.reset()

    // 3. Rebuild graph (preserves 48kHz mono float32 format)
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    engine.prepare()

    // 4. Start
    do {
        try engine.start()
        isRunning = true
        lastRebuildTime = CFAbsoluteTimeGetCurrent()
        let duration = lastRebuildTime - startTime
        logger.info("Audio engine rebuilt successfully on \(newDeviceName) (took \(String(format: "%.1f", duration * 1000))ms)")
    } catch {
        logger.error("Failed to rebuild audio engine: \(error)")
    }
}
```

**Source:** Derived from [AudioKit rebuildGraph() pattern](https://github.com/AudioKit/AudioKit/blob/main/Sources/AudioKit/Internals/Engine/AudioEngine.swift)

### Pattern 5: Debounce + Cooldown

```swift
enum RebuildSource: String {
    case halListener, configNotification, healthCheck
}

func triggerRebuild(source: RebuildSource) {
    logger.info("Rebuild triggered by \(source.rawValue)")

    // Cancel pending debounce
    rebuildWorkItem?.cancel()

    let work = DispatchWorkItem { [weak self] in
        guard let self = self else { return }

        // Cooldown check
        let now = CFAbsoluteTimeGetCurrent()
        if now - self.lastRebuildTime < Config.audioRebuildCooldownSeconds {
            self.logger.info("Rebuild skipped (cooldown active, \(String(format: "%.1f", Config.audioRebuildCooldownSeconds - (now - self.lastRebuildTime)))s remaining)")
            return
        }

        self.rebuildEngine()

        // Notify coordinator
        self.onRouteChange?()
    }
    rebuildWorkItem = work
    DispatchQueue.main.asyncAfter(
        deadline: .now() + .milliseconds(Int(Config.audioRebuildDebounceMs)),
        execute: work
    )
}
```

### Pattern 6: Health Check Timer (DispatchSourceTimer)

```swift
func startHealthCheck() {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(
        deadline: .now() + Config.audioHealthCheckInterval,
        repeating: Config.audioHealthCheckInterval
    )
    timer.setEventHandler { [weak self] in
        self?.performHealthCheck()
    }
    timer.resume()
    healthCheckTimer = timer
    logger.info("Audio health check started (interval: \(Int(Config.audioHealthCheckInterval))s)")
}

private func performHealthCheck() {
    // Skip during active playback -- audio is working if playing
    guard !playerNode.isPlaying else { return }

    let systemDevice = getSystemDefaultOutputDeviceID()
    let engineDevice = getEngineOutputDeviceID()  // from engine.outputNode

    if systemDevice != engineDevice {
        logger.warning("Health check: device mismatch (engine=\(engineDevice), system=\(systemDevice))")
        triggerRebuild(source: .healthCheck)
    }
}
```

### Pattern 7: Getting Engine's Current Output Device

```swift
func getEngineOutputDeviceID() -> AudioDeviceID {
    var deviceID = AudioDeviceID(kAudioDeviceUnknown)
    var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsAlive,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    // The engine's outputNode has an audioUnit whose current device can be queried
    // Alternative: cache the device ID at engine start and compare against system default
    // Caching is simpler and avoids AudioUnit API complexity
    return cachedOutputDeviceID
}
```

**Note:** Querying the engine's current output device via AudioUnit is complex. The simpler approach is to cache the device ID when the engine starts/rebuilds and compare it against the system default in the health check.

## Common Pitfalls

### Pitfall 1: AudioObjectRemovePropertyListenerBlock Does Not Work

**What goes wrong:** Registering a HAL listener with `AudioObjectAddPropertyListenerBlock` and then trying to remove it with `AudioObjectRemovePropertyListenerBlock` fails silently -- the listener keeps firing.
**Why it happens:** Known Apple bug documented in [Apple Developer Forums](https://developer.apple.com/forums/thread/30277).
**How to avoid:** Use the C function pointer variant `AudioObjectAddPropertyListener` / `AudioObjectRemovePropertyListener` instead. These work reliably.
**Warning signs:** Listener callbacks continue firing after removal.

### Pitfall 2: HAL Listener Fires on CoreAudio Internal Thread

**What goes wrong:** The `AudioObjectPropertyListenerProc` callback fires on an internal CoreAudio thread, not the main thread. Directly accessing AVAudioEngine or NSLock-protected state from this callback causes thread safety violations.
**Why it happens:** CoreAudio uses its own threading model.
**How to avoid:** Dispatch to main queue immediately in the callback. The debounce mechanism (DispatchWorkItem on main queue) naturally handles this.
**Warning signs:** Sporadic crashes in engine methods during device changes.

### Pitfall 3: Rapid Device Flapping During Bluetooth Reconnect

**What goes wrong:** Bluetooth reconnection can trigger 2-4 rapid device change events within 200-500ms as macOS cycles through aggregate devices. Without debounce, each triggers a full rebuild, causing engine thrashing.
**Why it happens:** macOS creates/destroys aggregate devices as Bluetooth negotiation proceeds (A2DP vs HFP profiles).
**How to avoid:** 200ms debounce window + 5s cooldown (D-05). The debounce collapses rapid events; the cooldown prevents storms.
**Warning signs:** Multiple "Rebuilding audio engine" log lines in rapid succession.

### Pitfall 4: Format Mismatch After Rebuild

**What goes wrong:** After rebuild, the engine's output format may differ from the stored format (e.g., 44.1kHz from a USB DAC vs 48kHz Bluetooth). Scheduling 48kHz buffers to a 44.1kHz output produces pitch-shifted audio.
**Why it happens:** AVAudioEngine auto-selects the hardware's native format for its output node.
**How to avoid:** Always connect playerNode to mainMixerNode with the stored 48kHz format. The engine handles sample rate conversion between the mixer and the output node automatically. Do NOT read format from engine.outputNode.outputFormat for the player connection.
**Warning signs:** Audio plays at wrong pitch after switching devices.

### Pitfall 5: kAudioObjectPropertyElementMaster is Deprecated

**What goes wrong:** Code using `kAudioObjectPropertyElementMaster` generates deprecation warnings on macOS 12+.
**Why it happens:** Apple renamed the constant to `kAudioObjectPropertyElementMain` in macOS 12.
**How to avoid:** Use `kAudioObjectPropertyElementMain` (same integer value, no behavior change).
**Warning signs:** Deprecation warnings in build output.

### Pitfall 6: SubtitleSyncDriver currentTime Resets to 0 During Rebuild

**What goes wrong:** `SubtitleSyncDriver` polls `audioStreamPlayer.currentTime`, which returns 0 when the player node is stopped during rebuild. If the sync driver is active, it could misinterpret this as "playback complete" and advance incorrectly.
**Why it happens:** `playerNode.lastRenderTime` returns nil when the node is not playing.
**How to avoid:** The `onRouteChange` callback fires TTSPipelineCoordinator.cancelCurrentPipeline(), which stops the active SubtitleSyncDriver before rebuild. This is already wired correctly. Ensure onRouteChange fires AFTER rebuild completes (not before).
**Warning signs:** Subtitle glitch or premature completion during device switch.

## Don't Hand-Roll

| Problem                   | Don't Build                  | Use Instead                                  | Why                                                                         |
| ------------------------- | ---------------------------- | -------------------------------------------- | --------------------------------------------------------------------------- |
| Audio device monitoring   | Custom kqueue/IOKit observer | CoreAudio HAL AudioObjectAddPropertyListener | This is the official macOS API; any other approach is fragile               |
| Debounce logic            | Manual timer management      | DispatchWorkItem.cancel() + asyncAfter       | Built into GCD, handles cancellation correctly                              |
| Thread-safe engine access | Actors or semaphores         | NSLock (existing pattern)                    | Consistent with codebase; actors would require @Sendable changes throughout |

## Validation Architecture

### Test Framework

| Property           | Value                                                                       |
| ------------------ | --------------------------------------------------------------------------- |
| Framework          | XCTest (Swift Package Manager)                                              |
| Config file        | plugins/claude-tts-companion/Package.swift (testTarget: CompanionCoreTests) |
| Quick run command  | `cd plugins/claude-tts-companion && swift test --filter CompanionCoreTests` |
| Full suite command | `cd plugins/claude-tts-companion && swift test`                             |

### Phase Requirements -> Test Map

| Req ID | Behavior                                | Test Type   | Automated Command                             | File Exists?         |
| ------ | --------------------------------------- | ----------- | --------------------------------------------- | -------------------- |
| D-01   | Full engine teardown + rebuild sequence | manual-only | Manual: switch BT device while TTS is playing | N/A                  |
| D-02   | HAL listener registers and fires        | manual-only | Manual: connect/disconnect BT device          | N/A                  |
| D-03   | ConfigChange notification backup        | manual-only | Already tested by existing code path          | N/A                  |
| D-04   | Health check detects device mismatch    | unit        | `swift test --filter CompanionCoreTests`      | Wave 0 (if feasible) |
| D-05   | Debounce collapses rapid triggers       | unit        | `swift test --filter CompanionCoreTests`      | Wave 0               |
| D-06   | Logging on all events                   | manual-only | Manual: verify log output                     | N/A                  |

**Justification for manual-only tests:** D-01, D-02, D-03 require real hardware (audio device) changes that cannot be simulated in CI. The debounce/cooldown logic (D-05) and device ID comparison logic (D-04) are unit-testable.

### Sampling Rate

- **Per task commit:** `cd plugins/claude-tts-companion && swift build`
- **Per wave merge:** `cd plugins/claude-tts-companion && swift test`
- **Phase gate:** swift build succeeds + manual device switch test

### Wave 0 Gaps

- [ ] Debounce/cooldown unit test -- covers D-05 timing logic
- [ ] Device ID comparison helper test -- covers D-04 mismatch detection logic

## Config.swift Constants to Add

```swift
// MARK: - Audio Device Resilience

/// Interval between audio health checks (seconds). Compares engine output
/// device against system default to catch missed device changes.
static let audioHealthCheckInterval: TimeInterval = 30

/// Debounce window for audio engine rebuild triggers (milliseconds).
/// Prevents format mismatch races during Bluetooth reconnect flapping.
static let audioRebuildDebounceMs: Double = 200

/// Minimum time between audio engine rebuilds (seconds).
/// Prevents rebuild storms from rapid device cycling.
static let audioRebuildCooldownSeconds: TimeInterval = 5
```

## State of the Art

| Old Approach                          | Current Approach                              | When Changed           | Impact                               |
| ------------------------------------- | --------------------------------------------- | ---------------------- | ------------------------------------ |
| `kAudioObjectPropertyElementMaster`   | `kAudioObjectPropertyElementMain`             | macOS 12 (2021)        | Deprecation warning only, same value |
| `AudioObjectAddPropertyListenerBlock` | `AudioObjectAddPropertyListener` (C func ptr) | Always available       | Block variant has known removal bug  |
| engine.start() after config change    | Full detach/reset/re-attach/start             | AudioKit best practice | Fixes stale aggregate device bug     |

## Open Questions

1. **Engine output device ID query method**
   - What we know: Can cache device ID at engine start and compare vs system default
   - What's unclear: Whether querying the AudioUnit on engine.outputNode directly is more reliable
   - Recommendation: Use cached approach (simpler, avoids AudioUnit API complexity). Cache on every successful engine.start() and rebuildEngine().

## Sources

### Primary (HIGH confidence)

- [AudioKit AudioEngine.swift](https://github.com/AudioKit/AudioKit/blob/main/Sources/AudioKit/Internals/Engine/AudioEngine.swift) - rebuildGraph() pattern, output property observer teardown/rebuild
- [CoreAudio output device methods gist](https://gist.github.com/rlxone/584467a63ac0ddf4d62fe1a983b42d0e) - getDefaultOutputDevice(), getDeviceName() Swift implementations
- [Apple kAudioHardwarePropertyDefaultOutputDevice docs](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultoutputdevice) - Official property selector reference
- [Apple AudioObjectPropertyListenerBlock docs](https://developer.apple.com/documentation/coreaudio/audioobjectpropertylistenerblock) - Listener block type definition

### Secondary (MEDIUM confidence)

- [Apple Developer Forums: AudioObjectRemovePropertyListenerBlock bug](https://developer.apple.com/forums/thread/30277) - Known bug with block-based listener removal
- [Chris Liscio: It's Over Between Us, AVAudioEngine](https://supermegaultragroovy.com/2021/01/26/it-s-over-avaudioengine/) - Aggregate device stale problem documentation (referenced in CONTEXT.md)
- [AudioKit Issue #2384](https://github.com/AudioKit/AudioKit/issues/2384) - Default device change handling recommendations

### Tertiary (LOW confidence)

- [Medium: How does Mac's Core Audio read audio device info](https://medium.com/@zpcat/how-does-macs-core-audio-read-audio-device-info-3cb4c5d40ce8) - AudioObjectRemovePropertyListenerBlock bug confirmation (code samples not extractable from iframes)

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH - All APIs are Apple system frameworks (CoreAudio, AVFoundation), no new dependencies needed
- Architecture: HIGH - Pattern validated by AudioKit + community, decisions locked in CONTEXT.md with thorough analysis
- Pitfalls: HIGH - Well-documented issues (stale aggregate device, HAL thread safety, block listener removal bug)
- Code examples: MEDIUM - Synthesized from multiple sources + AudioKit patterns, not copy-pasted from a single verified example

**Research date:** 2026-03-29
**Valid until:** 2026-06-29 (stable -- CoreAudio HAL API is decades old and rarely changes)
