# Phase 19: TTSEngine Decomposition & Actor Migration - Research

**Researched:** 2026-03-28
**Domain:** Swift 6 concurrency, actor isolation, code decomposition
**Confidence:** HIGH

## Summary

TTSEngine.swift is a 1139-line god object combining five distinct concerns: TTS synthesis/model management, audio playback lifecycle, word timing alignment, pronunciation preprocessing, and sentence splitting. All mutable state is protected by NSLock with `@unchecked Sendable` -- a pattern that compiles but provides no compile-time safety guarantees.

The decomposition extracts four components (PlaybackManager, WordTimingAligner, PronunciationProcessor, SentenceSplitter) and migrates TTSEngine from `class + NSLock` to a Swift `actor`. The critical challenge is bridging blocking MLX Metal synthesis (`tts.generateAudio()`) off the cooperative thread pool via `withCheckedThrowingContinuation` + a dedicated DispatchQueue -- a pattern already validated by the existing codebase.

**Primary recommendation:** Extract pure structs first (zero-risk, testable), then PlaybackManager (@MainActor), then migrate TTSEngine to actor last. This order minimizes risk because each extraction reduces the surface area of the final actor migration.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** PlaybackManager (@MainActor class) -- owns AVAudioPlayer lifecycle, pre-buffering, warm-up, AudioStreamPlayer. Must be @MainActor because AVAudioPlayer delegate requires main run loop.
- **D-02:** WordTimingAligner (pure struct) -- extractTimingsFromTokens(), alignOnsetsToWords(), resolveWordTimings(), extractWordTimings(), stripPunctuation(). All static methods, no mutable state.
- **D-03:** PronunciationProcessor (pure struct) -- pronunciationOverrides, compiledOverrides, preprocessText(). All static/pure, no mutable state.
- **D-04:** TTSEngine becomes thin facade -- delegates synthesis to internal model, playback to PlaybackManager, timing to WordTimingAligner, preprocessing to PronunciationProcessor. Holds no mutable state except actor-isolated synthesis state.
- **D-05:** SentenceSplitter (pure struct or free function) -- splitIntoSentences() extracted from TTSEngine. Currently static, stays pure.
- **D-06:** PlaybackDelegate stays as-is -- simple NSObject delegate, already in its own concern area.
- **D-07:** TTSEngine migrates from `@unchecked Sendable + NSLock` to Swift `actor`. All mutable state (ttsInstance, voicesDict, voice, synthesisCount, circuitBreaker state) becomes actor-isolated.
- **D-08:** Blocking TTS synthesis (`tts.generateAudio()`) stays on dedicated DispatchQueue, bridged to actor via `withCheckedThrowingContinuation`. Per v4.7.0 decision -- cooperative thread pool cannot handle blocking Metal calls.
- **D-09:** PlaybackManager is `@MainActor` (not actor) because AVAudioPlayer requires main thread.
- **D-10:** WordTimingAligner, PronunciationProcessor, SentenceSplitter are `Sendable` structs -- no actor needed, no mutable state.
- **D-11:** Migrate callback-based synthesis methods to async/await (`async throws -> TTSResult`). Callers already use `Task { await ... }` patterns.
- **D-12:** All callers (TelegramBot, HTTPControlServer, SubtitleSyncDriver, CompanionApp) updated to use decomposed API. No behavior changes -- same observable output.

### Claude's Discretion

- Whether to keep circuitBreaker state inside TTSEngine actor or extract to a separate CircuitBreaker actor
- Exact file organization (one file per component or grouped)
- Whether writeWav() moves to a utility or stays in TTSEngine
- Whether ChunkResult stays as nested type or becomes top-level

### Deferred Ideas (OUT OF SCOPE)

None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>

## Phase Requirements

| ID      | Description                                                                                   | Research Support                                                                                                                    |
| ------- | --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| ARCH-02 | TTSEngine decomposed into PlaybackManager (AVAudioPlayer lifecycle, pre-buffering)            | D-01, D-09: PlaybackManager @MainActor class owns play(), preparePlayer(), stopPlayback(), warmUpAudioHardware(), AudioStreamPlayer |
| ARCH-03 | TTSEngine decomposed into WordTimingAligner (MToken-to-word alignment, onset resolution)      | D-02, D-10: Pure struct with all 6 static methods extracted verbatim from TTSEngine lines 702-925                                   |
| ARCH-04 | TTSEngine decomposed into PronunciationProcessor (overrides dictionary, regex preprocessing)  | D-03, D-10: Pure struct with static let pronunciationOverrides/compiledOverrides and preprocessText() from lines 89-131             |
| ARCH-05 | TTSEngine becomes thin orchestrator delegating to extracted components                        | D-04, D-07: Actor with ~200 lines of synthesis orchestration, delegating all other concerns                                         |
| ARCH-06 | All callers updated to use decomposed TTSEngine API                                           | D-12: TelegramBot, HTTPControlServer, SubtitleSyncDriver, CompanionApp -- 4 callers identified with exact call sites                |
| CONC-01 | TTSEngine migrated from @unchecked Sendable + NSLock to Swift actor                           | D-07: Remove class + NSLock + @unchecked Sendable, replace with actor keyword                                                       |
| CONC-02 | All actor-isolated state mutations happen in synchronous methods (no reentrancy across await) | Architecture pattern: increment synthesisCount before await, circuit breaker checks in sync context                                 |
| CONC-03 | Blocking TTS synthesis runs off cooperative thread pool                                       | D-08: DispatchQueue bridge via withCheckedThrowingContinuation -- same pattern as existing code                                     |
| CONC-04 | Formal Sendable conformance across pipeline components                                        | D-10: Pure structs are automatically Sendable; PlaybackManager is @MainActor (implicitly Sendable); actor TTSEngine is Sendable     |

</phase_requirements>

## Architecture Patterns

### Recommended File Structure

```
Sources/CompanionCore/
  TTSEngine.swift              # actor TTSEngine (thin facade, ~250 lines)
  PlaybackManager.swift        # @MainActor class (~200 lines)
  WordTimingAligner.swift       # struct (~230 lines)
  PronunciationProcessor.swift  # struct (~50 lines)
  SentenceSplitter.swift        # struct (~70 lines)
  AudioStreamPlayer.swift       # (unchanged, owned by PlaybackManager)
  PlaybackDelegate.swift        # (extracted from TTSEngine.swift bottom, unchanged)
  TTSError.swift               # (extracted enum, unchanged)
```

**Recommendation:** One file per component. The current TTSEngine.swift is 1139 lines; splitting into separate files improves navigability. PlaybackDelegate and TTSError are already logically separate (bottom of TTSEngine.swift) and should get their own files.

### Pattern 1: Actor with DispatchQueue Bridge for Blocking Work

**What:** Swift actor for state isolation + dedicated DispatchQueue for blocking Metal/GPU calls, bridged via `withCheckedThrowingContinuation`.

**When to use:** When an actor needs to call blocking C/C++ code that would starve the cooperative thread pool.

**Why not Task.detached:** Task.detached still runs on the cooperative pool. DispatchQueue.async runs on a dedicated thread outside the pool.

```swift
public actor TTSEngine {
    private let synthesisQueue = DispatchQueue(label: "com.terryli.tts-engine", qos: .userInitiated)
    private var ttsInstance: KokoroTTS?
    private var synthesisCount: Int = 0

    func synthesize(text: String) async throws -> SynthesisResult {
        // Validate state synchronously (actor-isolated, no reentrancy risk)
        guard !isDisabledDueToMissingModel else {
            throw TTSError.modelLoadFailed(path: "TTS disabled")
        }
        guard !isTTSCircuitBreakerOpen else {
            throw TTSError.circuitBreakerOpen
        }

        let tts = try ensureModelLoaded()  // synchronous, actor-isolated
        let processedText = PronunciationProcessor.preprocessText(text)

        // Bridge blocking GPU work to dedicated queue
        let (audio, tokens) = try await withCheckedThrowingContinuation { cont in
            synthesisQueue.async {
                do {
                    let result = try tts.generateAudio(
                        voice: activeVoice, language: .enUS,
                        text: processedText, speed: speed
                    )
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }

        // Back on actor -- safe to mutate state
        synthesisCount += 1
        recordSynthesisSuccess()

        return SynthesisResult(...)
    }
}
```

**Critical detail on CONC-02 (reentrancy):** When `await withCheckedThrowingContinuation` suspends, another call to `synthesize()` could start executing on the actor. The current code is safe because:

1. `ensureModelLoaded()` is synchronous -- it runs to completion before the await
2. `synthesisCount += 1` runs after the await but is a simple increment (idempotent ordering)
3. The dedicated DispatchQueue is serial -- only one `generateAudio()` runs at a time

However, if two `synthesize()` calls interleave, both could call `ensureModelLoaded()` before either reaches the await. This is safe because `ensureModelLoaded()` is idempotent (checks if already loaded, returns existing instance).

### Pattern 2: @MainActor Class for UI-Bound Components

**What:** `@MainActor` annotation on PlaybackManager ensures all AVAudioPlayer operations run on the main thread.

```swift
@MainActor
public final class PlaybackManager {
    private var audioPlayer: AVAudioPlayer?
    private var playbackDelegate: PlaybackDelegate?
    private var warmUpPlayer: AVAudioPlayer?
    let audioStreamPlayer = AudioStreamPlayer()

    func play(wavPath: String, completion: (() -> Void)? = nil) -> AVAudioPlayer? { ... }
    func preparePlayer(wavPath: String, completion: (() -> Void)?) -> (AVAudioPlayer, PlaybackDelegate)? { ... }
    func stopPlayback() { ... }
    func warmUpAudioHardware() { ... }
}
```

**Sendable:** `@MainActor` types are implicitly `Sendable` because all access is serialized on the main thread. No `@unchecked Sendable` needed.

### Pattern 3: Pure Sendable Structs

**What:** Structs with no mutable state are automatically `Sendable` in Swift 6. All methods are either `static` or operate only on parameters.

```swift
public struct WordTimingAligner: Sendable {
    // All methods are static -- no instance state
    static func extractTimingsFromTokens(_ tokens: [MToken]?) -> NativeTimings? { ... }
    static func alignOnsetsToWords(native: NativeTimings, subtitleWords: [String], audioDuration: TimeInterval) -> (durations: [TimeInterval], onsets: [TimeInterval])? { ... }
    static func resolveWordTimings(tokenArray: [MToken]?, text: String, audioDuration: TimeInterval, logger: Logger) -> ResolvedTimings { ... }
    static func extractWordTimings(text: String, audioDuration: TimeInterval) -> [TimeInterval] { ... }
}
```

**Note:** These could equally be enums with no cases (caseless enum pattern) to prevent instantiation, since all methods are static. Structs are fine too -- both are Sendable.

### Pattern 4: Callback-to-Async Migration

**Current (callback-based):**

```swift
ttsEngine.synthesizeWithTimestamps(text: text) { result in
    switch result { ... }
}
```

**New (async/await):**

```swift
let result = try await ttsEngine.synthesizeWithTimestamps(text: text)
```

**For synthesizeStreaming (callback sequence):** Keep the callback pattern but make it async-friendly:

```swift
func synthesizeStreaming(
    text: String,
    voiceName: String = Config.defaultVoiceName,
    speed: Float = 1.2,
    onChunkReady: @Sendable @escaping (ChunkResult) -> Void,
    onAllComplete: @Sendable @escaping () -> Void
)
```

The `@Sendable` annotation on closures is required because the actor will pass them to the DispatchQueue. Alternatively, synthesizeStreaming could return an `AsyncStream<ChunkResult>`, but that is a larger API change and callers already work with the callback pattern.

### Anti-Patterns to Avoid

- **Calling actor methods from DispatchQueue.async callbacks:** The continuation must resume exactly once. Never call actor methods directly from inside the DispatchQueue closure -- use the continuation to return values to the actor context.
- **Holding NSLock across an await:** Actors do not use locks. If you find yourself reaching for NSLock inside an actor, the design is wrong. Actor isolation IS the lock.
- **Making PlaybackManager an actor:** AVAudioPlayer requires main thread. Making it a custom actor would require hopping to main for every AVAudioPlayer call. `@MainActor` is the correct isolation.
- **Using nonisolated(unsafe) on actor properties:** This defeats the purpose of actor isolation. If a property needs to be accessed from outside, make it a computed property or an async accessor.

## Don't Hand-Roll

| Problem                             | Don't Build                          | Use Instead                         | Why                                                                    |
| ----------------------------------- | ------------------------------------ | ----------------------------------- | ---------------------------------------------------------------------- |
| Thread-safe mutable state           | NSLock + @unchecked Sendable         | Swift actor                         | Compile-time verification, no runtime lock bugs                        |
| Main-thread audio playback          | DispatchQueue.main.async wrappers    | @MainActor annotation               | Compiler enforces main-thread access at call sites                     |
| Sendable conformance for pure types | @unchecked Sendable on structs       | Automatic Sendable (Swift 6)        | Structs with only Sendable properties are automatically Sendable       |
| Callback-to-async bridging          | Manual continuation management       | withCheckedThrowingContinuation     | Built-in Swift concurrency primitive, runtime checks for double-resume |
| Circuit breaker                     | Inline state management in TTSEngine | Existing CircuitBreaker.swift class | Already exists in codebase, tested, just needs to be wired in          |

**Key insight:** The existing `CircuitBreaker.swift` class already implements the exact same logic that TTSEngine has inline (lines 183-235). The inline version should be replaced with an instance of `CircuitBreaker`. Since CircuitBreaker uses its own NSLock internally and TTSEngine will become an actor, the CircuitBreaker can be stored as an actor-isolated property. Its internal NSLock is redundant when accessed only from the actor, but harmless -- removing it would be a separate refactor.

## Common Pitfalls

### Pitfall 1: Actor Reentrancy on Synthesis

**What goes wrong:** Two concurrent `synthesize()` calls interleave at the `await` boundary. Call A suspends at `withCheckedThrowingContinuation`, call B enters the actor and modifies state before A resumes.

**Why it happens:** Swift actors are reentrant by default -- they process new messages while awaiting.

**How to avoid:** Ensure all pre-await state reads and all post-await state writes are correct regardless of interleaving. In this case: `ensureModelLoaded()` is idempotent, `synthesisCount += 1` is a monotonic counter (order doesn't matter), circuit breaker success/failure recording is independent per call. The serial DispatchQueue ensures only one `generateAudio()` runs at a time, which is the actual serialization point.

**Warning signs:** Shared mutable state read before await and written after await. Review every `await` in actor methods for what could change between suspension and resumption.

### Pitfall 2: Blocking the Cooperative Thread Pool

**What goes wrong:** Calling `tts.generateAudio()` directly inside an actor method (without DispatchQueue bridge) blocks one of the ~CPU-count cooperative threads for seconds.

**Why it happens:** MLX Metal synthesis is blocking C++ code that takes 2-18 seconds per call.

**How to avoid:** Always bridge to the dedicated DispatchQueue via `withCheckedThrowingContinuation`. Never call `generateAudio()` in actor context.

**Warning signs:** `swift build` won't warn about this. Look for any `tts.generateAudio()` call that isn't inside a DispatchQueue.async block.

### Pitfall 3: SubtitleSyncDriver TTSEngine Coupling

**What goes wrong:** SubtitleSyncDriver holds a `TTSEngine?` reference but only uses it for `ttsEngine.audioStreamPlayer`. After migration, accessing `audioStreamPlayer` on an actor requires `await`.

**Why it happens:** SubtitleSyncDriver is `@MainActor` -- it cannot call `await` on actor properties in synchronous code paths (like the 60Hz timer tick).

**How to avoid:** Pass `AudioStreamPlayer` directly to SubtitleSyncDriver instead of the full TTSEngine. SubtitleSyncDriver never calls synthesis methods -- it only needs the AudioStreamPlayer for buffer scheduling. PlaybackManager should own AudioStreamPlayer and provide it to SubtitleSyncDriver at construction time.

**Warning signs:** Compiler error "Expression is 'async' but is not marked with 'await'" in SubtitleSyncDriver timer callbacks.

### Pitfall 4: MemoryLifecycle Static References

**What goes wrong:** `MemoryLifecycle.ttsEngine` is a `nonisolated(unsafe) static var` holding a reference to TTSEngine. When TTSEngine becomes an actor, calling `engine.shouldRestartForMemory` requires `await`.

**Why it happens:** `checkMemoryLifecycleRestart()` is a synchronous module-level function called from callback contexts.

**How to avoid:** Make `checkMemoryLifecycleRestart()` an async function, or provide a synchronous `shouldRestartForMemory` property on the actor that uses `nonisolated` access to a thread-safe atomic counter.

**Best approach:** Since `synthesisCount` only increments and the threshold is a static constant, expose it as a `nonisolated` computed property:

```swift
actor TTSEngine {
    // Use Atomic for the counter so it can be read nonisolated
    private let _synthesisCount = ManagedAtomic<Int>(0)

    nonisolated var shouldRestartForMemory: Bool {
        _synthesisCount.load(ordering: .relaxed) >= Self.maxSynthesisBeforeRestart
    }
}
```

Or simpler: make `checkMemoryLifecycleRestart()` async and update all call sites.

### Pitfall 5: PlaybackDelegate @unchecked Sendable

**What goes wrong:** PlaybackDelegate is `NSObject, AVAudioPlayerDelegate, @unchecked Sendable`. The delegate callbacks fire on the main thread. After extracting to its own file, the `@unchecked Sendable` needs justification.

**Why it happens:** AVAudioPlayerDelegate methods are called by the system on the main thread. The delegate holds a completion closure and a logger -- both are used only in callbacks.

**How to avoid:** Mark PlaybackDelegate as `@MainActor` instead. AVAudioPlayerDelegate callbacks always come on the main thread. If the closure needs to be Sendable, annotate it as `@Sendable`.

### Pitfall 6: CompanionApp is @unchecked Sendable and Holds TTSEngine

**What goes wrong:** CompanionApp stores `private let ttsEngine: TTSEngine`. When TTSEngine changes from a class to an actor, CompanionApp's property type changes but the usage pattern (calling methods that are now async) requires `await`.

**Why it happens:** CompanionApp creates TTSEngine in its `@MainActor init()` and passes it to subsystems.

**How to avoid:** This is expected -- update CompanionApp to use `await` for TTSEngine calls. Since CompanionApp's `start()` is already `@MainActor`, it can contain `Task { await ttsEngine.synthesize(...) }` blocks.

## Code Examples

### TTSEngine Actor Skeleton

```swift
// Source: Derived from current TTSEngine.swift + Swift 6 actor patterns
public actor TTSEngine {
    private let logger = Logger(label: "tts-engine")
    private let synthesisQueue = DispatchQueue(label: "com.terryli.tts-engine", qos: .userInitiated)

    // Actor-isolated mutable state (was protected by NSLock)
    private var ttsInstance: KokoroTTS?
    private var voicesDict: [String: MLXArray]?
    private var voice: MLXArray?
    private var synthesisCount: Int = 0
    private var lastWavPath: String?
    private(set) var isDisabledDueToMissingModel: Bool = false

    // Delegate to existing CircuitBreaker instead of inline state
    private let circuitBreaker = CircuitBreaker(maxFailures: 3, cooldownSeconds: 300)

    // Delegate to extracted components
    let playbackManager: PlaybackManager  // @MainActor, created externally

    init(playbackManager: PlaybackManager) {
        self.playbackManager = playbackManager
        // Model validation...
    }

    // Async API (replaces callback-based)
    func synthesize(text: String, voiceName: String = Config.defaultVoiceName, speed: Float = 1.2) async throws -> SynthesisResult {
        guard !isDisabledDueToMissingModel else { throw TTSError.modelLoadFailed(path: "disabled") }
        guard !circuitBreaker.isOpen else { throw TTSError.circuitBreakerOpen }

        let tts = try ensureModelLoaded()
        let processedText = PronunciationProcessor.preprocessText(text)

        let (audio, _) = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<([Float], [MToken]?), Error>) in
            synthesisQueue.async {
                do {
                    let result = try tts.generateAudio(voice: self.voice!, language: .enUS, text: processedText, speed: speed)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }

        synthesisCount += 1
        circuitBreaker.recordSuccess()

        let audioDuration = Double(audio.count) / 24000.0
        let wavPath = NSTemporaryDirectory() + "tts-\(UUID().uuidString).wav"
        try WavWriter.write(samples: audio, to: wavPath)

        return SynthesisResult(wavPath: wavPath, audioDuration: audioDuration, durations: nil)
    }
}
```

### PlaybackManager @MainActor Class

```swift
// Source: Extracted from TTSEngine.swift lines 338-700, 927-990
@MainActor
public final class PlaybackManager {
    private let logger = Logger(label: "playback-manager")
    private var audioPlayer: AVAudioPlayer?
    private var playbackDelegate: PlaybackDelegate?
    private var warmUpPlayer: AVAudioPlayer?
    private var audioHardwareWarmed = false
    private var lastPlaybackTime: CFAbsoluteTime = 0
    private static let audioIdleThreshold: CFAbsoluteTime = 30.0

    /// Gapless streaming player -- shared across sessions.
    public let audioStreamPlayer = AudioStreamPlayer()

    init() {
        warmUpAudioHardware()
        audioStreamPlayer.start()
    }

    @discardableResult
    func play(wavPath: String, completion: (() -> Void)? = nil) -> AVAudioPlayer? { ... }
    func preparePlayer(wavPath: String, completion: (() -> Void)?) -> (AVAudioPlayer, PlaybackDelegate)? { ... }
    func stopPlayback() { ... }
    private func warmUpAudioHardware() { ... }
}
```

### Caller Migration (TelegramBot)

```swift
// Before (callback):
ttsEngine.synthesizeStreaming(text: text, voiceName: voiceName,
    onChunkReady: { chunk in ... },
    onAllComplete: { ... }
)

// After (async, if using AsyncStream):
for await chunk in ttsEngine.synthesizeStreaming(text: text, voiceName: voiceName) {
    // process chunk
}

// Or after (async, keeping callbacks but with @Sendable):
await ttsEngine.synthesizeStreaming(text: text, voiceName: voiceName,
    onChunkReady: { @Sendable chunk in ... },
    onAllComplete: { @Sendable in ... }
)
```

## State of the Art

| Old Approach                               | Current Approach                     | When Changed                   | Impact                                             |
| ------------------------------------------ | ------------------------------------ | ------------------------------ | -------------------------------------------------- |
| `class + NSLock + @unchecked Sendable`     | Swift `actor`                        | Swift 5.5+ (mature in Swift 6) | Compile-time concurrency safety                    |
| Callback-based async (`completion:`)       | `async throws ->`                    | Swift 5.5+                     | Cleaner call sites, structured concurrency         |
| `DispatchQueue.main.async` for main thread | `@MainActor` annotation              | Swift 5.5+                     | Compile-time enforcement of main-thread access     |
| Manual `Sendable` conformance              | Automatic for value types in Swift 6 | Swift 6.0                      | Structs with Sendable properties are auto-Sendable |

## Open Questions

1. **CircuitBreaker inside actor vs. separate instance**
   - What we know: CircuitBreaker.swift already exists with its own NSLock. TTSEngine has inline circuit breaker logic (lines 183-235) that duplicates it.
   - What's unclear: Whether the inline CB should be replaced with a `CircuitBreaker` instance (cleaner) or whether the actor isolation makes the NSLock inside CircuitBreaker redundant overhead.
   - Recommendation: Use the existing `CircuitBreaker` class as an actor-isolated property. The internal NSLock is harmless (double-locking with actor isolation) and avoids touching CircuitBreaker.swift. Phase 19 scope is TTSEngine decomposition, not CircuitBreaker refactoring.

2. **MemoryLifecycle.ttsEngine static reference**
   - What we know: It holds a TTSEngine reference and calls synchronous properties on it.
   - What's unclear: How to make `checkMemoryLifecycleRestart()` work with an actor (needs await).
   - Recommendation: Make `checkMemoryLifecycleRestart()` async. Call sites in TelegramBot and HTTPControlServer already run in Task contexts where await is available.

3. **synthesizeStreaming callback vs AsyncStream**
   - What we know: Current pattern uses onChunkReady/onAllComplete callbacks. Callers collect chunks with a lock and dispatch to main.
   - What's unclear: Whether AsyncStream is a better API or over-engineering.
   - Recommendation: Keep callback pattern with `@Sendable` annotations for Phase 19. AsyncStream migration is a nice-to-have but changes caller patterns significantly.

4. **AudioStreamPlayer ownership**
   - What we know: SubtitleSyncDriver accesses `ttsEngine.audioStreamPlayer`. AudioStreamPlayer is `@unchecked Sendable` with its own NSLock.
   - What's unclear: Should AudioStreamPlayer be owned by PlaybackManager or TTSEngine?
   - Recommendation: PlaybackManager owns it (D-01 says PlaybackManager owns AudioStreamPlayer). SubtitleSyncDriver receives `audioStreamPlayer` directly at init instead of through TTSEngine. This breaks the coupling that would otherwise require `await` in the 60Hz timer.

## Validation Architecture

### Test Framework

| Property           | Value                                                                       |
| ------------------ | --------------------------------------------------------------------------- |
| Framework          | swift-testing 0.12.0+ (via SwiftPM)                                         |
| Config file        | Package.swift testTarget "CompanionCoreTests"                               |
| Quick run command  | `cd plugins/claude-tts-companion && swift test --filter CompanionCoreTests` |
| Full suite command | `cd plugins/claude-tts-companion && swift test`                             |

### Phase Requirements -> Test Map

| Req ID  | Behavior                                        | Test Type          | Automated Command                                               | File Exists? |
| ------- | ----------------------------------------------- | ------------------ | --------------------------------------------------------------- | ------------ |
| ARCH-02 | PlaybackManager extracted as @MainActor class   | build-verification | `swift build` (compile-time check)                              | N/A          |
| ARCH-03 | WordTimingAligner extracted as pure struct      | unit               | `swift test --filter WordTimingAlignerTests`                    | Wave 0       |
| ARCH-04 | PronunciationProcessor extracted as pure struct | unit               | `swift test --filter PronunciationProcessorTests`               | Wave 0       |
| ARCH-05 | TTSEngine is thin facade                        | build-verification | `swift build` (compile-time check)                              | N/A          |
| ARCH-06 | All callers compile and work                    | build-verification | `swift build` (compile-time check)                              | N/A          |
| CONC-01 | TTSEngine is actor (not class + NSLock)         | build-verification | `swift build` (compile-time check)                              | N/A          |
| CONC-02 | No reentrancy bugs                              | manual-only        | Code review -- Swift compiler does not detect reentrancy issues | N/A          |
| CONC-03 | Blocking synthesis off cooperative pool         | build-verification | `swift build` + code review                                     | N/A          |
| CONC-04 | Formal Sendable conformance                     | build-verification | `swift build` with zero @unchecked Sendable on TTSEngine types  | N/A          |

### Sampling Rate

- **Per task commit:** `cd plugins/claude-tts-companion && swift build`
- **Per wave merge:** `cd plugins/claude-tts-companion && swift test`
- **Phase gate:** `swift build` + `swift test` + verify zero `@unchecked Sendable` on TTSEngine-related types

### Wave 0 Gaps

- [ ] `Tests/CompanionCoreTests/WordTimingAlignerTests.swift` -- covers ARCH-03 (pure struct, highly testable)
- [ ] `Tests/CompanionCoreTests/PronunciationProcessorTests.swift` -- covers ARCH-04 (pure struct, highly testable)

Note: Most requirements (ARCH-02, ARCH-05, ARCH-06, CONC-01, CONC-03, CONC-04) are verified by successful compilation (`swift build`). The actor migration and @MainActor annotations are compile-time constructs -- if it builds without `@unchecked Sendable` warnings on TTSEngine types, the concurrency model is correct.

## Sources

### Primary (HIGH confidence)

- TTSEngine.swift (1139 lines) -- full source code analysis, every line mapped to decomposition targets
- SubtitleSyncDriver.swift -- caller analysis, AudioStreamPlayer coupling identified
- TelegramBot.swift -- caller analysis, streaming + full TTS paths identified
- HTTPControlServer.swift -- caller analysis, streaming TTS test endpoint identified
- CompanionApp.swift -- wiring coordinator, TTSEngine creation and lifecycle
- MemoryLifecycle.swift -- static reference pattern that needs async migration
- CircuitBreaker.swift -- existing class that can replace inline circuit breaker
- Package.swift -- swift-tools-version: 6.0, swift-testing dependency confirmed

### Secondary (MEDIUM confidence)

- Swift 6 actor model documentation (from training data, verified against swift-tools-version: 6.0 in Package.swift)
- withCheckedThrowingContinuation pattern (standard Swift concurrency, used widely in ecosystem)

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH -- no new dependencies needed, all Swift 6 built-in
- Architecture: HIGH -- decomposition boundaries clearly defined by CONTEXT.md decisions, source code fully analyzed
- Pitfalls: HIGH -- identified from actual code analysis (SubtitleSyncDriver coupling, MemoryLifecycle statics, actor reentrancy)

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable -- Swift 6 actor model is mature)
