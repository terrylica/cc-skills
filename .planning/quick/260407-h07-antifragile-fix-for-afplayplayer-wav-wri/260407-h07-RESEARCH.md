# Research: Antifragile AfplayPlayer fix

**Researched:** 2026-04-07
**Domain:** macOS audio playback + filesystem robustness (Swift 6, AppKit, CoreAudio)
**Confidence:** HIGH on history and current architecture, MEDIUM on AVAudioPlayer fitness

## Bottom line recommendation

**Option A+C+D+E (self-healing fallback chain + telemetry + /health + codebase cleanup + chaos test).** Option B (replace afplay with AVAudioPlayer) is structurally tempting but carries a **specific, documented regression risk**: AVAudioPlayer was the previous implementation. Commit `e2e80e1e` ("replace AVAudioEngine with afplay subprocess for jitter-free playback") and its three follow-ups (`2be60672`, `c3525c2e`, `815844e2`) show that _any_ AVAudioEngine/AVAudioPlayer path on this machine produced audible jitter under CPU contention (concurrent Rust compilation was the canonical reproducer). The fix was not "tune AVAudioEngine" — it was "stop touching CoreAudio state entirely; launch `afplay` as its own process group with USER_INTERACTIVE QoS so macOS treats it like a terminal-launched player." Even _initializing_ `AVAudioEngine` in the same process polluted the hardware buffer size and HAL listener state so badly that afplay's own audio path became jittery (see `AudioStreamPlayer.init` comment at lines 133-139). The risk that AVAudioPlayer (which shares the same CoreAudio plumbing under the hood) re-introduces that jitter is non-trivial and hard to detect until a user hits a real compile-workload reproducer.

Option A+C+D+E fixes the actual bug (dir went missing for the process's lifetime) without touching the audio path at all. It is strictly smaller blast radius. The existing architecture is already antifragile in the interesting dimensions (subprocess isolation, SIGKILL, QoS inheritance) — the missing piece is filesystem robustness, which is exactly what the fallback + telemetry + chaos test add. Option B should be reserved as a fallback plan if A+C+D+E telemetry later reveals the fallback is firing frequently and fragility remains a concern.

## AfplayPlayer current architecture

Reverse-engineered from `Sources/CompanionCore/AfplayPlayer.swift` (555 lines) plus its consumers:

### Class shape

- `@MainActor public final class AfplayPlayer` — main-thread isolated. One instance, owned by `PlaybackManager` (created in its `init`, line 46 of `PlaybackManager.swift`). Shared across all TTS sessions; `reset()` clears per-session state.
- State is plain stored properties (no locks), safe because `@MainActor` serializes all mutation.

### Two modes sharing ~60% of logic

**Batch mode** (legacy, used by `SubtitleSyncDriver.startBatchPlayback()`):

- `appendChunk(samples:)` → accumulates into `pendingSamples`
- `play(label:onComplete:)` at line 111 → writes one big WAV, spawns afplay once, fires `onComplete` via background `waitpid` thread
- WAV write at **line 137**: `try writeWav(samples: pendingSamples, sampleRate: 48000, to: wavPath)`

**Pipelined mode** (current, used by `TTSPipelineCoordinator.addStreamingChunk()`):

- `playOrEnqueue(samples:label:)` at line 274 → if afplay running, queue; else start a segment
- `startSegment(samples:label:)` at line 326 → writes WAV for this paragraph, spawns new afplay, monitors exit, chains to next via `advanceQueue()`
- `markQueueComplete(onComplete:)` at line 304 → signals end-of-stream, fires callback when queue drains
- WAV write at **line 366**: `try writeWav(samples: samples, sampleRate: 48000, to: wavPath)`

### The deferred-offset + segment-duration cap pattern (critical to preserve)

This is the timing fix introduced to eliminate subtitle sync drift caused by afplay startup delay:

- `cumulativeTimeOffset` — sum of durations of all **finished** segments that have been "committed"
- `finishedSegmentDuration` — duration of the just-finished segment, waiting to be committed
- `currentSegmentDuration` — duration of the currently-playing segment
- `playStartTime` — wall-clock `Date` when current afplay spawned

**Key invariant (line 230-246, `currentTime` getter):**

```
currentTime = cumulativeTimeOffset + min(elapsed, currentSegmentDuration)
```

Clamping `elapsed` to `currentSegmentDuration` prevents `currentTime` from racing ahead of audio during afplay startup delay at the next segment boundary. Between segments (when `playStartTime == nil`), `currentTime` is frozen at `cumulativeTimeOffset`.

**Why deferred offset (line 336-342, `startSegment`):** `cumulativeTimeOffset` is advanced with `finishedSegmentDuration` **when the next segment's afplay actually launches**, not when the previous one finishes. This keeps the tick sitting at the boundary of the current chunk during the inter-segment gap instead of jumping forward prematurely.

**Why resyncPlayStart (line 263, called from TTSPipelineCoordinator line 465):** First chunk re-anchors `playStartTime = Date()` to absorb the 50-200ms between WAV write / posix_spawn and first audible sample, so subtitles don't start ~100ms ahead of audio.

### Process management

- `posix_spawn` directly (not Foundation `Process`), with:
  - `POSIX_SPAWN_SETPGROUP` → own process group
  - stdin/stdout/stderr redirected to `/dev/null` via `posix_spawn_file_actions_addopen`
  - `posix_spawnattr_set_qos_class_np(QOS_CLASS_USER_INTERACTIVE)` → inherited only because launchd plist sets `ProcessType=Interactive` (fix `815844e2`)
- Exit monitored by a detached `Thread` running `waitpid(pid, &status, 0)`, which dispatches back to main via `DispatchQueue.main.async`.
- `stop()` sends `SIGKILL` (not SIGTERM — realtime audio thread ignores catchable signals) and also runs `killall -9 afplay` as a belt-and-suspenders orphan sweeper.

### `currentTime` consumers

- `SubtitleSyncDriver.tickStreaming()` (line 519-533 of SubtitleSyncDriver.swift) — polls `afplay.currentTime` at 60Hz. This is the only external consumer. It also reads `isPipelinedMode` and `isPlaying` to decide whether to trigger the "playback stopped" safety net.

### The debug WAV directory (the bug site)

- `debugWavDir` at line 44-48: lazy static init, `try?` swallowed. Dir is `~/.local/share/tts-debug-wav`. Files are **retained** (per comment line 512-514) for manual listening to diagnose whether jitter is in synthesis or playback.
- No guard inside `play()` or `startSegment()` before calling `writeWav` — if the dir disappears after init, all subsequent writes fail.
- Nothing in the codebase deletes this dir (grep confirmed).

### State that would NOT survive an AVAudioPlayer switch

- `afplayPID` tracking (no analog)
- `waitThread` and `waitpid` — replaced by `AVAudioPlayerDelegate.audioPlayerDidFinishPlaying`
- `killall -9 afplay` safety net — no analog; AVAudioPlayer.stop() is in-process
- QoS inheritance via launchd plist — doesn't apply; AVAudioPlayer runs on the parent process's audio thread

## AVAudioPlayer fitness matrix

| AfplayPlayer requirement                  | AVAudioPlayer equivalent                                                                                                                                                                                                                                                                                                                                    | Gap?                                                                                                                                                                                                          |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Play `[Float]` samples without filesystem | `init(data: Data)` — but needs a WAV container. `AVAudioPlayer` requires a file-format-wrapped blob, not raw PCM. You'd still build the WAV header bytes in-memory, then pass as `Data` — structurally eliminates the disk write.                                                                                                                           | No disk I/O. Structurally safer.                                                                                                                                                                              |
| Per-segment "finished, start next"        | `AVAudioPlayerDelegate.audioPlayerDidFinishPlaying(_:successfully:)`                                                                                                                                                                                                                                                                                        | Matches pipelined chain model.                                                                                                                                                                                |
| `currentTime` accessor                    | `player.currentTime: TimeInterval`                                                                                                                                                                                                                                                                                                                          | Exact analog.                                                                                                                                                                                                 |
| Segment duration                          | `player.duration: TimeInterval`                                                                                                                                                                                                                                                                                                                             | Exact analog.                                                                                                                                                                                                 |
| Pause / stop                              | `pause()` / `stop()`                                                                                                                                                                                                                                                                                                                                        | Analog, but in-process (no SIGKILL needed).                                                                                                                                                                   |
| Gap-free chaining                         | **NOT built-in.** Alternatives: (a) pre-init next `AVAudioPlayer`, call `play()` in delegate; (b) `AVQueuePlayer` with `AVPlayerItem`; (c) `AVAudioEngine + AVAudioPlayerNode.scheduleBuffer` (already exists in codebase as `AudioStreamPlayer`).                                                                                                          | **Big gap.** (a) has ~0-5ms gap typically but unbounded under CPU pressure. (b) is the wrong abstraction (built for video assets). (c) **is the exact approach that was previously abandoned** due to jitter. |
| Volume/rate                               | `volume`, `enableRate`+`rate`                                                                                                                                                                                                                                                                                                                               | Analog, unused today.                                                                                                                                                                                         |
| Thread model                              | `AVAudioPlayer` is thread-safe for control, delegate callbacks fire on the queue that created it (main thread here). `@MainActor` preserved.                                                                                                                                                                                                                | Matches current model.                                                                                                                                                                                        |
| Jitter resistance under CPU contention    | **UNKNOWN / LIKELY REGRESSED.** AVAudioPlayer uses the same CoreAudio render thread in-process. Commit `c3525c2e` documents that even _creating_ AVAudioEngine in this process polluted the hardware buffer state enough to re-introduce jitter in afplay's path. AVAudioPlayer may not trigger the same buffer-size change, but it uses the same HAL path. | **This is the dealbreaker for Option B.**                                                                                                                                                                     |

**The gap-free chaining question:** AVAudioPlayer has no built-in chaining. Of the three alternatives, only the pre-init pattern `(a)` is at all viable for Option B — and it still doesn't give true sample-accurate gapless playback. For the current system this is probably OK (there are already 50-200ms inter-segment gaps with afplay — search the code for "Inter-segment gap" telemetry), but it should be validated against the deferred-offset pattern. The existing `AudioStreamPlayer` is specifically inert on this machine because of the jitter problem, so route `(c)` is off the table.

## Why afplay was originally chosen

**Hard evidence from git log:**

| Commit     | Message                                                                                                                                                                                            |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `e2e80e1e` | "feat(tts): replace AVAudioEngine with afplay subprocess for jitter-free playback" — **initial replacement**                                                                                       |
| `2be60672` | "fix(tts): eliminate audio jitter via posix_spawn afplay backend"                                                                                                                                  |
| `c3525c2e` | "fix(claude-tts-companion): eliminate audio jitter via posix_spawn backend" — documents that `AudioStreamPlayer.init` alone (without playing anything) caused jitter via CoreAudio state pollution |
| `815844e2` | "fix(tts): fix audio jitter via launchd ProcessType=Interactive scheduling" — required for afplay QoS inheritance                                                                                  |
| `7eb74ae4` | "fix(tts): use SIGKILL instead of SIGTERM to stop afplay"                                                                                                                                          |
| `be32ab2b` | "fix(tts): add killall afplay safety net to stop() for race condition"                                                                                                                             |
| `7d0964b2` | "feat(claude-tts-companion): pipelined paragraph playback"                                                                                                                                         |
| `72884aa3` | "fix(claude-tts-companion): audit fixes for pipelined playback state machine"                                                                                                                      |

**Quoting `c3525c2e`:**

> Jitter root cause: AudioStreamPlayer init modified CoreAudio hardware state (buffer sizes, HAL listeners, health check timer) affecting afplay's audio path even when engine was "stopped". Solution: complete disablement.

**Quoting `815844e2`:**

> Root cause: launchd ProcessType=Adaptive allowed macOS to downgrade the companion to background QoS (PRI=4). posix_spawnattr_set_qos_class_np (USER_INTERACTIVE) was silently ignored because macOS overrides child QoS when the parent is in background scheduling band.
> Before: companion PRI=4, afplay PRI=4 (background band, jittery)
> After: companion PRI=60, afplay PRI=97 (interactive band, clean)

**The canonical reproducer** mentioned in `e2e80e1e` was "CPU contention (e.g., concurrent compilation)" — this is a real failure mode the user hit. afplay was not chosen for convenience; it was chosen because it's a separate process whose audio rendering is untouchable by whatever CPU chaos is happening in the Swift companion. That property is fundamental to the design, not incidental.

**Implication for Option B:** Replacing afplay with AVAudioPlayer is NOT a free structural simplification — it re-couples audio rendering to the main binary's CPU scheduling band. The user would need to run a concurrent-compile stress test to validate equivalence. Hidden regression risk.

## Option B implementation sketch

Smallest viable diff that preserves the timing pattern:

```swift
// AfplayPlayer.swift — pseudocode for the ~200-line rewrite
@MainActor public final class AfplayPlayer {
    private var currentPlayer: AVAudioPlayer?
    private var nextPlayer: AVAudioPlayer?  // pre-loaded for gap minimization
    private var playbackDelegate: ChainedDelegate?
    // Keep: cumulativeTimeOffset, currentSegmentDuration, finishedSegmentDuration,
    // playStartTime, didLogCap, lastSegmentEndTime, isPipelinedMode,
    // playQueue, queueComplete, isWaitingForNextChunk, allCompleteCallback
    // DROP: afplayPID, waitThread, debugWavDir, writeWav(to path:)

    // NEW: build WAV header in-memory, return Data
    private func buildWavData(samples: [Float], sampleRate: Int) -> Data { ... }

    func playOrEnqueue(samples: [Float], label: String?) {
        // same as before, but startSegment() goes in-memory
    }

    private func startSegment(samples: [Float], label: String?) {
        // ... timing state updates identical to current code ...
        let data = buildWavData(samples: samples, sampleRate: 48000)
        do {
            let player = try AVAudioPlayer(data: data)
            let delegate = ChainedDelegate(owner: self)
            player.delegate = delegate
            player.prepareToPlay()
            currentSegmentDuration = player.duration  // or Double(samples.count) / 48000.0
            playbackDelegate = delegate
            currentPlayer = player
            playStartTime = Date()
            player.play()
        } catch {
            logger.error("AVAudioPlayer init failed: \(error)")
            advanceQueue()
        }
    }

    // Delegate callback (on main thread) replaces waitpid thread
    fileprivate func audioPlayerFinished() {
        playStartTime = nil
        lastSegmentEndTime = Date()
        finishedSegmentDuration = currentSegmentDuration
        currentPlayer = nil
        advanceQueue()
    }

    // stop() becomes currentPlayer?.stop(); currentPlayer = nil
    // No killall, no SIGKILL, no waitpid — all in-process
}

private final class ChainedDelegate: NSObject, AVAudioPlayerDelegate {
    weak var owner: AfplayPlayer?
    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in owner?.audioPlayerFinished() }
    }
}
```

**Preserved:** deferred-offset, segment-duration cap, `currentTime` semantics, `resyncPlayStart`, pipelined queue, `markQueueComplete`, `isPipelinedMode` flag for SubtitleSyncDriver.

**Dropped (net simplification):** 100+ lines of posix_spawn/waitpid/killall/QoS/file-actions plumbing, `debugWavDir`, `writeWav(to:)`, `afplayPID`, `waitThread`, the `kill(pid, 0)` liveness probe (replaced by `currentPlayer != nil && currentPlayer.isPlaying`).

**Risk (restated):** Jitter regression under CPU contention. No automated test can detect this; requires manual reproducer.

**Chaos test for Option B:** Write a test that instantiates AfplayPlayer, calls `playOrEnqueue` with real samples, and asserts that `~/.local/share/tts-debug-wav/` and `NSTemporaryDirectory()` are both untouched after playback completes. Use a sentinel file approach:

1. `touch ~/.local/share/tts-debug-wav/SENTINEL`
2. `rm -rf ~/.local/share/tts-debug-wav` (so the dir is gone)
3. `playOrEnqueue(samples:)` — should NOT recreate the dir and NOT write any file
4. Assert dir still missing after playback

## Option A+C+D+E implementation sketch

**Scope:** 4 changes, all in `AfplayPlayer.swift`, plus one small `HTTPControlServer` change.

### A. Self-healing fallback chain

Replace both `debugWavDir + "/tts-..."` construction sites (lines 135, 364) with a helper:

```swift
/// Resolve a writable WAV path. Tries in order:
///   1. debugWavDir (primary, retained for inspection)
///   2. NSTemporaryDirectory() + "claude-tts-wav/" (ephemeral, self-healing on reboot)
///   3. mkstemp in /tmp (guaranteed-writable last resort)
/// Logs each fallback transition once per process lifetime.
private func resolveWavPath(slug: String, timestamp: String) -> String? {
    let filename = "tts-\(timestamp)_\(slug).wav"

    // Try primary
    if ensureDirectoryExists(debugWavDir, tier: .primary) {
        return debugWavDir + "/" + filename
    }
    // Try tmp fallback
    let tmpDir = NSTemporaryDirectory() + "claude-tts-wav"
    if ensureDirectoryExists(tmpDir, tier: .tmpFallback) {
        return tmpDir + "/" + filename
    }
    // Last resort: mkstemp
    return mkstempFallback(filename: filename)
}

private enum WavPathTier: String { case primary, tmpFallback, mkstemp }

/// Ensure directory exists; returns false on failure.
/// Does NOT use `try?` — errors are logged with full NSError context.
private func ensureDirectoryExists(_ path: String, tier: WavPathTier) -> Bool {
    do {
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true
        )
        recordTierSuccess(tier)
        return true
    } catch {
        recordTierFailure(tier, error: error)
        return false
    }
}
```

The critical difference from the current code: `ensureDirectoryExists` is called **on every write**, not once at lazy init. Creating a directory that already exists is a ~microsecond syscall — idempotent and cheap. This alone would have prevented the observed bug.

Call sites:

```swift
// Replace line 135 and line 364:
guard let wavPath = resolveWavPath(slug: slug, timestamp: timestamp) else {
    logger.error("All WAV path tiers exhausted — cannot play audio")
    onComplete?()  // or advanceQueue() in pipelined path
    return false   // or return in pipelined path
}
```

### C. Structured telemetry

Single logger call per failure-class transition, rate-limited to once per transition (not once per tick):

```swift
private var tierState: [WavPathTier: TierState] = [:]
private struct TierState {
    var lastFailure: Date?
    var failureCount: Int = 0
    var lastError: String?
    var currentlyFailing: Bool = false
}

private func recordTierFailure(_ tier: WavPathTier, error: Error) {
    var state = tierState[tier] ?? TierState()
    state.failureCount += 1
    state.lastFailure = Date()
    state.lastError = "\(error)"
    let wasFailing = state.currentlyFailing
    state.currentlyFailing = true
    tierState[tier] = state
    if !wasFailing {
        // First failure in this streak: log structured event
        logger.warning("[TELEMETRY] WAV path tier failed: tier=\(tier.rawValue) count=\(state.failureCount) error=\(error)")
    }
}

private func recordTierSuccess(_ tier: WavPathTier) {
    if var state = tierState[tier], state.currentlyFailing {
        state.currentlyFailing = false
        tierState[tier] = state
        logger.info("[TELEMETRY] WAV path tier recovered: tier=\(tier.rawValue)")
    }
}
```

### D. /health endpoint extension

In `HTTPControlServer.swift`, extend `HealthResponse` and `healthResponse()`:

```swift
private struct WavPathStatus: Codable {
    let primary_available: Bool
    let active_tier: String  // "primary" | "tmpFallback" | "mkstemp" | "all_failed"
    let fallback_count: Int  // total fallback activations since process start
    let last_failure_at: String?  // ISO8601
    let last_error: String?
}

private struct HealthResponse: Codable {
    let status: String
    let uptime_seconds: Int
    let rss_mb: Double
    let subsystems: SubsystemStatus
    let audio_routing_clean: Bool?
    let audio_routing_warnings: [String]?
    let wav_path_status: WavPathStatus  // NEW
}
```

Expose via new read-only accessor on `AfplayPlayer`:

```swift
public struct WavPathTelemetry: Sendable {
    public let primaryAvailable: Bool
    public let activeTier: String
    public let fallbackCount: Int
    public let lastFailureAt: Date?
    public let lastError: String?
}
var wavPathTelemetry: WavPathTelemetry { ... }
```

`HTTPControlServer.healthResponse()` reads it via `await MainActor.run { playbackManager.afplayPlayer.wavPathTelemetry }`.

**Overall health status becomes `degraded`** when `activeTier != "primary"`, alongside the existing `audioRoutingClean` check.

### E. Codebase-wide `try? createDirectory` cleanup

Grep results (`try?\s*FileManager\.default\.createDirectory`):

| File:line                 | Current                                                            | Action                                                                                                                                                                                                                            |
| ------------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AfplayPlayer.swift:46`   | lazy init of `debugWavDir`, swallowed error                        | Replace with `do { try ... } catch { logger.error(...) }`. Init is best-effort — the `resolveWavPath` fallback chain handles runtime failures.                                                                                    |
| `SettingsStore.swift:122` | config dir for `settings.json` (`~/.config/claude-tts-companion/`) | Replace with `do { try ... } catch { logger.error("Failed to create config dir: \(error)") }`. Settings load already handles the "file missing" case, but if dir creation fails silently, settings writes will fail silently too. |

No other hits. These are the only two `try? createDirectory` calls in the codebase.

**Only AfplayPlayer has the per-write fallback chain.** SettingsStore's failure mode is benign (settings revert to defaults; not a user-visible audio failure) and doesn't need fallback tiers, just visibility.

### Chaos test for Option A+C+D+E

```swift
// plugins/claude-tts-companion/Tests/CompanionCoreTests/AfplayPlayerChaosTests.swift
@testable import CompanionCore
import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct AfplayPlayerChaosTests {

    /// Generates ~0.5s of silent 48kHz mono samples.
    private func silentSamples(seconds: Double = 0.5) -> [Float] {
        Array(repeating: 0.0, count: Int(48000 * seconds))
    }

    @Test func playbackSurvivesDeletedDebugDir() async throws {
        let debugDir = NSHomeDirectory() + "/.local/share/tts-debug-wav"
        let player = AfplayPlayer()

        // Chaos: obliterate the primary dir AFTER init but BEFORE playback
        try? FileManager.default.removeItem(atPath: debugDir)
        #expect(!FileManager.default.fileExists(atPath: debugDir))

        // Act: play a short buffer
        player.playOrEnqueue(samples: silentSamples(), label: "chaos-test")
        player.markQueueComplete { }

        // Wait for playback start (poll for up to 500ms)
        var started = false
        for _ in 0..<50 {
            if player.isPlaying { started = true; break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // Assert: either primary recovered OR fallback tier activated
        let telemetry = player.wavPathTelemetry
        #expect(started, "Playback must start even with primary dir missing")
        #expect(telemetry.activeTier != "all_failed", "All tiers exhausted — unrecoverable")
        if telemetry.activeTier != "primary" {
            #expect(telemetry.fallbackCount >= 1, "Fallback should have activated")
        }

        player.stop()
    }

    @Test func playbackSurvivesReadOnlyPrimary() async throws {
        // Harder chaos: primary dir exists but is read-only (chmod 0o400)
        // Forces the mkdir check to succeed but writeWav to fail — tests the
        // "dir exists but write fails" branch.
        let debugDir = NSHomeDirectory() + "/.local/share/tts-debug-wav"
        try? FileManager.default.createDirectory(atPath: debugDir, withIntermediateDirectories: true)
        _ = chmod(debugDir, 0o500)  // r-x, no write
        defer { _ = chmod(debugDir, 0o755) }

        let player = AfplayPlayer()
        player.playOrEnqueue(samples: silentSamples(), label: "chaos-test-ro")
        player.markQueueComplete { }

        try? await Task.sleep(nanoseconds: 200_000_000)
        let telemetry = player.wavPathTelemetry
        #expect(telemetry.activeTier == "tmpFallback" || telemetry.activeTier == "mkstemp",
                "Read-only primary should trigger fallback")
        player.stop()
    }
}
```

**This test would FAIL on the current buggy code** because:

1. Current code has no `wavPathTelemetry` accessor
2. Current code returns `false` from `play()` / bails in `startSegment()` on write failure — `isPlaying` stays false
3. There is no fallback to recreate the dir or use `NSTemporaryDirectory`

## Test infrastructure

- Framework: `swift-testing` (the new Apple Testing framework, not XCTest). `@Suite`, `@Test`, `#expect(...)`. See `StreamingPipelineTests.swift` for the pattern.
- Location: `plugins/claude-tts-companion/Tests/CompanionCoreTests/`
- Test target already wired in `Package.swift` (lines 58-65).
- Convention: `@Suite(.serialized) @MainActor struct FooTests { @Test func ... }`. `.serialized` is important here because audio tests cannot run in parallel.
- No existing test touches `AfplayPlayer` directly — the chaos test file would be net-new.
- Run: `swift test --filter AfplayPlayerChaosTests` from `plugins/claude-tts-companion/`.
- **Caveat:** Unit tests running in-process will actually try to spawn afplay. If run on CI without audio hardware this may noop-succeed (afplay tolerates `/dev/null` output device) — validate. For local runs, the test will play ~0.5s of silence, which is fine.

## AfplayPlayer in the wider system

- **Single shared instance** — `PlaybackManager.afplayPlayer` (public let, line 46). All TTS paths funnel through this one instance via `TTSPipelineCoordinator.startBatchPipeline` / `addStreamingChunk`.
- **`isPlaying` semantics for SubtitleSyncDriver:** Used only as a safety-net termination signal in non-pipelined mode (line 523 of SubtitleSyncDriver). In pipelined mode, `isPipelinedMode` flag makes the driver ignore `!isPlaying` (because it goes false briefly between every chained afplay). Definitive completion signal is `currentChunkComplete`, set by `onPipelinedPlaybackComplete()` called from `TTSPipelineCoordinator.finalizeStreamingPipeline`'s `markQueueComplete` callback.
- **Other afplay invocations:** None. Grep for `afplay` in `Sources/` returns only `AfplayPlayer.swift` + files that reference it by name in comments/logs (TTSPipelineCoordinator, SubtitleSyncDriver, PlaybackManager, AudioStreamPlayer). There is no second "batch-only" path that would need a parallel fix. The `AudioStreamPlayer` is inert (see PlaybackManager init comment line 51-55) — it exists but is never started.

## Spike references

Spike 10 is mentioned in the plugin CLAUDE.md as validating AVAudioPlayer for WAV playback ("Spike 10 validated: plays 24kHz mono 16-bit WAV from sherpa-onnx output. Alternative `afplay` subprocess works but AVAudioPlayer gives programmatic control..."). **This spike predates the jitter discovery.** The spike notes directory (`~/tmp/subtitle-spikes-7aqa/` per PROJECT.md) is outside the repo and not accessible from here. The text in CLAUDE.md is specifically contradicted by the subsequent git history: the project was later forced to abandon AVAudioPlayer/AVAudioEngine entirely under real workloads. Treat the spike 10 conclusion as historically interesting but **superseded by commits `e2e80e1e` → `815844e2`**.

Spike 19 (karaoke timing) is mentioned in CLAUDE.md as "6us per update, 37x headroom" — it validates subtitle highlighting performance, not the audio backend. Not relevant to this decision.

## Risks and unknowns

1. **AVAudioPlayer jitter under CPU contention is unknown-until-tested.** No amount of unit testing will surface it; only a concurrent-compile reproducer reveals it. If Option B is chosen, the planner should include a manual validation step: "run `swift build -c release` on sherpa-onnx (heavy compile) while running a long TTS request and listen for pops/jitter." This cannot be automated.

2. **Why did the directory disappear?** The debug diagnosis (`tts-no-audio-260406.md`) could not identify the deletion cause. Grep confirms nothing in this repo removes it. Suspects: manual cleanup during a previous `/gsd:quick` session, external sweeper, or the dir was never created because `.local/share` didn't exist at AfplayPlayer init time on first run. The Option A fix is robust to all of these because it re-creates on every write. Option B (in-memory) sidesteps the question entirely.

3. **`writeWav` is the only disk I/O in AfplayPlayer.** Confirmed by reading the file. There is no secondary log-file write, no WAV-manifest, nothing else in this class that touches the disk. So Option A's fallback chain is a complete fix for the playback path; no further audit needed.

4. **The chaos test may have false negatives on systems without audio hardware.** On CI or headless systems, afplay may exit immediately with a non-zero status because it can't open the default output device — the test's `isPlaying` assertion could be flaky. The sentinel-file approach (check that a specific file path was/wasn't written) is more robust than asserting `isPlaying`. The test above combines both for belt-and-suspenders coverage. If CI proves flaky, strip the `isPlaying` assertion and keep only the telemetry/path assertions.

5. **SwiftBar / HTTP `/health` consumers:** The planner should check whether the SwiftBar plugin (`~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.sh`) parses the `/health` response with a strict schema. Adding a new top-level key (`wav_path_status`) should be backward-compatible for most JSON parsers, but `jq` expressions that enumerate keys could break. Grep the SwiftBar plugin before making it a locked decision. (Out of scope for this research — flag for the planner to verify.)

6. **Assumed: Option A's `ensureDirectoryExists` call overhead is negligible.** `mkdir` on an existing directory is a single `stat`-like syscall (~1-10μs). Called twice per TTS segment, this is far below the 50-200ms inter-segment gap and invisible in the pipeline. [ASSUMED — not benchmarked. If the planner wants certainty, a single `ProcessInfo` timestamp pair around the call will confirm.]

## Assumptions Log

| #   | Claim                                                                                                                                   | Risk if Wrong                                                                                                                                                      |
| --- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| A1  | AVAudioPlayer shares enough CoreAudio plumbing with AVAudioEngine that it would re-introduce the documented jitter under CPU contention | If wrong, Option B is structurally superior and we should pick it. Cost to verify: 1 hour of manual stress-testing on a branch.                                    |
| A2  | `mkdir` on an existing directory is sub-millisecond and safe to call on every WAV write                                                 | If wrong (e.g., on a network filesystem), adds latency to every TTS segment. Mitigation: cache a "dir verified at time T" flag and re-verify only every N seconds. |
| A3  | The SwiftBar `/health` consumer tolerates new top-level JSON keys                                                                       | If wrong, extending `HealthResponse` breaks SwiftBar parsing. Mitigation: verify before execution, or put new fields under an optional nested object.              |
| A4  | Swift Testing `@Suite(.serialized) @MainActor` is the correct pattern for AfplayPlayer tests                                            | Low risk — pattern is copied verbatim from existing `StreamingPipelineTests.swift`.                                                                                |

## RESEARCH COMPLETE

**File:** `/Users/<you>/eon/cc-skills/.planning/quick/260407-h07-antifragile-fix-for-afplayplayer-wav-wri/260407-h07-RESEARCH.md`
