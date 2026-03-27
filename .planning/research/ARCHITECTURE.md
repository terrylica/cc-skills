# Architecture Patterns <!-- # SSoT-OK -->

**Domain:** macOS TTS/subtitle companion app -- architecture hardening + feature expansion
**Researched:** 2026-03-27

## Current Architecture (As-Is)

```
main.swift (imperative boot)
    |
    +-- NSApplication.shared (.accessory, no dock icon)
    |       |
    |       +-- SubtitlePanel (@MainActor, NSPanel)
    |       +-- SettingsStore (@unchecked Sendable, NSLock)
    |       +-- CaptionHistory (@unchecked Sendable, NSLock)
    |
    +-- TTSEngine (@unchecked Sendable, NSLock)
    |       |-- kokoro-ios MLX synthesis (serial DispatchQueue)
    |       |-- AVAudioPlayer playback (main thread)
    |       |-- Word timing extraction (static, pure)
    |       |-- Pronunciation preprocessing (static, pure)
    |       |-- Circuit breaker (NSLock)
    |       |-- Audio hardware warm-up
    |       \-- WAV file I/O
    |
    +-- SubtitleSyncDriver (@MainActor)
    |       |-- 60Hz DispatchSourceTimer
    |       |-- Single-shot + streaming modes
    |       \-- Pre-buffered chunk transitions
    |
    +-- TelegramBot (@unchecked Sendable, NSLock)
    |       |-- swift-telegram-sdk long polling
    |       |-- InlineButtonManager
    |       |-- PromptExecutor
    |       \-- TTS dispatch orchestration
    |
    +-- HTTPControlServer (@unchecked Sendable)
    |       \-- FlyingFox async/await routes
    |
    +-- NotificationWatcher (DispatchSource)
    |       \-- NotificationProcessor (dedup + rate limit)
    |
    +-- MiniMaxClient (@unchecked Sendable)
    |       |-- SummaryEngine
    |       |-- AutoContinueEvaluator
    |       \-- ThinkingWatcher
    |
    \-- SIGTERM handler (DispatchSource)
```

### Threading Model (Current)

| Thread/Queue                      | Components                                                | Synchronization              |
| --------------------------------- | --------------------------------------------------------- | ---------------------------- |
| Main thread (NSApp.run)           | SubtitlePanel, SubtitleSyncDriver, AVAudioPlayer delegate | @MainActor                   |
| `com.example.tts-engine` (serial) | TTSEngine synthesis, WAV writing                          | DispatchQueue serialization  |
| FlyingFox async context           | HTTPControlServer routes                                  | Swift Concurrency (Task)     |
| swift-telegram-sdk polling        | TelegramBot update handlers                               | @unchecked Sendable + NSLock |
| DispatchSource callbacks          | NotificationWatcher, FileWatcher                          | Callback-based               |

### Current Pain Points

1. **TTSEngine is a god object** -- 1058 lines combining synthesis, playback, timing extraction, pronunciation preprocessing, circuit breaker, WAV I/O, and audio hardware management
2. **@unchecked Sendable everywhere** -- TTSEngine, TelegramBot, HTTPControlServer, CaptionHistory, SettingsStore all bypass compiler concurrency checking
3. **No tests** -- executable target prevents `@testable import`; no library target exists
4. **TelegramBot orchestrates TTS** -- `dispatchStreamingTTS()` creates SubtitleSyncDriver, manages streaming state, owns sync driver lifecycle -- coupling that belongs in a coordinator

## Recommended Architecture (To-Be)

### Package.swift Split: Library + Executable

```
Sources/
  CompanionCore/              <-- Library target (all business logic)
    WordTimingAligner.swift
    PronunciationProcessor.swift
    TTSCircuitBreaker.swift
    SynthesisEngine.swift
    PlaybackManager.swift
    SubtitleChunker.swift
    LanguageDetector.swift
    TranscriptParser.swift
    TelegramFormatter.swift
    SubtitleStyle.swift
    Config.swift
    CaptionHistory.swift
    NotificationProcessor.swift
    BionicRenderer.swift        <-- NEW
  claude-tts-companion/         <-- Executable target (thin shell)
    main.swift
    SubtitlePanel.swift
    SubtitleSyncDriver.swift
    TelegramBot.swift
    HTTPControlServer.swift
    CaptionHistoryPanel.swift   <-- NEW
    FocusMonitor.swift          <-- NEW
Tests/
  CompanionCoreTests/
    WordTimingAlignerTests.swift
    PronunciationProcessorTests.swift
    TTSCircuitBreakerTests.swift
    LanguageDetectorTests.swift
    TranscriptParserTests.swift
    BionicRendererTests.swift
    SubtitleChunkerTests.swift
```

### TTSEngine Decomposition

Split TTSEngine into focused components with clear single responsibilities:

```
TTSEngine (facade, thin coordinator)
    |
    +-- SynthesisEngine (actor)
    |       |-- kokoro-ios model loading + lazy init
    |       |-- generateAudio() calls
    |       |-- Sentence splitting
    |       \-- Streaming sentence pipeline
    |
    +-- PlaybackManager (@MainActor)
    |       |-- AVAudioPlayer lifecycle
    |       |-- Audio hardware warm-up / re-warm
    |       |-- preparePlayer() for pre-buffering
    |       |-- stopPlayback()
    |       \-- PlaybackDelegate ownership
    |
    +-- WordTimingAligner (struct, pure functions)
    |       |-- extractTimingsFromTokens()
    |       |-- alignOnsetsToWords()
    |       |-- extractWordTimings() (character-weighted fallback)
    |       |-- resolveWordTimings()
    |       \-- stripPunctuation()
    |
    +-- PronunciationProcessor (struct, pure functions)
    |       |-- compiledOverrides
    |       \-- preprocessText()
    |
    \-- TTSCircuitBreaker (actor)
            |-- recordSuccess() / recordFailure()
            |-- isOpen computed property
            \-- Auto-reset after cooldown
```

#### Decomposition Strategy: Extract-and-Delegate

**Do NOT break callers.** The existing `TTSEngine` becomes a thin facade that delegates to the new components. All current call sites (`TelegramBot.dispatchTTS`, `HTTPControlServer`, `main.swift` demo) continue calling `TTSEngine.synthesizeStreaming()`, `TTSEngine.play()`, etc. -- same API, different internals.

Steps:

1. Extract `WordTimingAligner` and `PronunciationProcessor` first (pure functions, zero risk)
2. Extract `PlaybackManager` next (owns AVAudioPlayer state, @MainActor)
3. Extract `TTSCircuitBreaker` (isolated state)
4. Extract `SynthesisEngine` last (most complex, owns model lifecycle)
5. TTSEngine becomes a facade composing all four

### Component Boundaries

| Component                               | Responsibility                                                   | Communicates With                                                   |
| --------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------- |
| `SynthesisEngine` (actor)               | Model loading, audio generation, streaming pipeline              | TTSEngine (via async calls)                                         |
| `PlaybackManager` (@MainActor)          | AVAudioPlayer lifecycle, hardware warm-up, pre-buffering         | TTSEngine, SubtitleSyncDriver                                       |
| `WordTimingAligner` (struct)            | MToken-to-subtitle alignment, character-weighted fallback        | SynthesisEngine (called after generation)                           |
| `PronunciationProcessor` (struct)       | Text preprocessing before phonemization                          | SynthesisEngine (called before generation)                          |
| `TTSCircuitBreaker` (actor)             | Failure tracking, auto-reset cooldown                            | SynthesisEngine (checked before each synthesis)                     |
| `CaptionHistoryPanel` (@MainActor, new) | Scrollable NSPanel with caption entries, copy button             | CaptionHistory (data), SubtitlePanel (display coordination)         |
| `FocusMonitor` (new)                    | Reads DND/Focus state, publishes changes                         | PlaybackManager (suppress audio), SubtitlePanel (optional suppress) |
| `BionicRenderer` (struct, new)          | Converts text to bold-prefix + regular-suffix attributed strings | SubtitlePanel (rendering), SubtitleChunker (width calculation)      |

### Actor Migration Strategy

**Incremental, not big-bang.** Migrate one component at a time from `@unchecked Sendable + NSLock` to proper Swift Concurrency.

#### Step 1: Extract pure types (no concurrency change)

- `WordTimingAligner` -- struct with static functions, already pure
- `PronunciationProcessor` -- struct with static functions, already pure
- These are copy-paste extractions with `internal` visibility

#### Step 2: New components as actors from day one

- `TTSCircuitBreaker` as an `actor` -- replaces `circuitBreakerLock + NSLock` in TTSEngine
- `SynthesisEngine` as an `actor` -- replaces `lock + NSLock` and `queue` serial DispatchQueue

#### Step 3: Existing components migrate to @MainActor or actor

- `PlaybackManager` as `@MainActor` class -- playback already must run on main thread
- `CaptionHistory` -- migrate from NSLock to actor (low risk, simple state)
- `SettingsStore` -- migrate from NSLock to actor

#### Step 4: Remove @unchecked Sendable from TTSEngine

- Once all mutable state is delegated to actor-isolated sub-components, TTSEngine becomes a simple coordinator with no mutable state of its own
- Can become `Sendable` naturally (or remain a class with actor-isolated properties)

**Key constraint:** TTSEngine's `queue.async { [self] in ... }` pattern (serial DispatchQueue for synthesis) maps directly to an actor's serial execution:

```swift
// Before: @unchecked Sendable + NSLock + serial DispatchQueue
final class TTSEngine: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.example.tts-engine")

    func synthesize(..., completion: @escaping ...) {
        queue.async { [self] in
            lock.lock()
            let tts = try ensureModelLoaded()
            lock.unlock()
            ...
        }
    }
}

// After: actor (serial execution is implicit)
actor SynthesisEngine {
    private var ttsInstance: KokoroTTS?

    func synthesize(...) async throws -> SynthesisResult {
        let tts = try ensureModelLoaded()
        ...
    }
}
```

**Callback-to-async migration:** Current callers use completion handlers. The facade bridges:

```swift
// TTSEngine facade bridges old callback API to new async actor
func synthesize(text: String, completion: @escaping (Result<SynthesisResult, Error>) -> Void) {
    Task {
        do {
            let result = try await synthesisEngine.synthesize(text: text)
            completion(.success(result))
        } catch {
            completion(.failure(error))
        }
    }
}
```

This lets callers migrate to async/await incrementally without forcing all call sites to change at once.

### XCTest Infrastructure

#### The SwiftPM Executable Target Problem

SwiftPM **cannot** `@testable import` executable targets. The solution is the standard "library extraction" pattern -- create a `CompanionCore` library target containing all business logic, with the executable target reduced to a thin boot shell.

#### What goes in CompanionCore vs executable target

**CompanionCore (library, testable):**

- `WordTimingAligner` -- pure functions, highly testable
- `PronunciationProcessor` -- pure functions, regex validation
- `SubtitleChunker` -- pure functions, width calculation
- `SynthesisEngine` -- actor (can be tested with async test methods)
- `TTSCircuitBreaker` -- actor, state machine testing
- `LanguageDetector` -- pure function
- `TranscriptParser` -- pure function
- `TelegramFormatter` -- pure function
- `SubtitleStyle` -- constants
- `Config` -- constants + environment reading
- `CaptionHistory` -- ring buffer logic
- `BionicRenderer` -- pure function (new)
- `NotificationProcessor` -- dedup logic

**Executable target (thin shell, not tested directly):**

- `main.swift` -- boot sequence, wiring
- `SubtitlePanel` -- AppKit UI (needs UI testing if at all)
- `TelegramBot` -- external API integration
- `HTTPControlServer` -- HTTP route wiring
- `SubtitleSyncDriver` -- timer-based UI driver

#### Test Categories

| Category    | What                                     | How                                    |
| ----------- | ---------------------------------------- | -------------------------------------- |
| Unit        | WordTimingAligner alignment edge cases   | XCTest, pure function in/out           |
| Unit        | PronunciationProcessor regex correctness | XCTest, string assertions              |
| Unit        | SubtitleChunker page boundaries          | XCTest, mock font metrics              |
| Unit        | TTSCircuitBreaker state transitions      | XCTest async, actor isolation          |
| Unit        | LanguageDetector CJK thresholds          | XCTest, Unicode string inputs          |
| Unit        | TranscriptParser JSONL edge cases        | XCTest, fixture files                  |
| Unit        | BionicRenderer word splitting            | XCTest, attributed string verification |
| Integration | SynthesisEngine model load + generate    | XCTest async, requires model files     |
| Integration | Streaming pipeline chunk sequencing      | XCTest async, mock synthesis           |

### Data Flow Changes

#### Current: TTS Streaming Flow

```
TelegramBot.dispatchStreamingTTS()
    |-- ttsEngine.synthesizeStreaming(onChunkReady:, onAllComplete:)
    |       |-- [TTS queue] split sentences, synthesize each
    |       |-- [TTS queue] onChunkReady(chunk) -> DispatchQueue.main
    |       \-- [TTS queue] onAllComplete() -> DispatchQueue.main
    |
    |-- [Main] Create SubtitleSyncDriver
    |-- [Main] driver.addChunk(pages, timings)
    |-- [Main] driver starts 60Hz timer
    \-- [Main] timer polls player.currentTime -> updates SubtitlePanel
```

#### Proposed: Actor-Based TTS Streaming Flow

```
TelegramBot.dispatchStreamingTTS()
    |-- Task {
    |       for await chunk in synthesisEngine.streamSentences(text) {
    |           await MainActor.run {
    |               syncDriver.addChunk(chunk)
    |           }
    |       }
    |   }
    |
    |-- SynthesisEngine (actor, serial)
    |       |-- split sentences
    |       |-- for each: circuitBreaker.check() -> preprocessor.process() -> generate()
    |       |-- yield ChunkResult via AsyncStream
    |       \-- aligner.resolveTimings()
    |
    |-- [MainActor] SubtitleSyncDriver
    |       |-- playbackManager.play(chunk.wavPath)
    |       |-- 60Hz timer polls playbackManager.currentTime
    |       \-- updates SubtitlePanel
```

The key change: replace callback-based `onChunkReady` / `onAllComplete` with `AsyncStream<ChunkResult>`. This eliminates the `NSLock`-protected `firstChunkDispatched` flag in TelegramBot and the `isStreamingInProgress` lock.

### New Feature Components

#### Chinese TTS Fallback (CJK)

The `SynthesisEngine` actor should define a `Synthesizer` protocol:

```swift
protocol Synthesizer {
    func generate(text: String, voice: String, speed: Float) async throws -> (audio: [Float], tokens: [Any]?)
}
```

`LanguageDetector` routes to `KokoroMLXSynthesizer` (English) or `SherpaOnnxSynthesizer` (Chinese). This enables plugging in sherpa-onnx for Chinese without modifying the existing kokoro-ios path.

#### Bionic Reading Mode

`BionicRenderer` is a pure struct that splits each word into bold prefix (40% of characters) + regular suffix. It composes with karaoke highlighting -- both are NSAttributedString transformations applied in sequence.

#### Caption History Panel

`CaptionHistoryPanel` is a new @MainActor NSPanel with NSScrollView + NSTextView. Reads from CaptionHistory ring buffer. Copy button writes to NSPasteboard. Toggled via HTTP API (`POST /captions/panel/toggle`). Positioned above SubtitlePanel, non-activating.

#### Focus/DND Awareness

**No public macOS API exists for querying Focus mode.** The viable approach is file-based monitoring of `~/Library/DoNotDisturb/DB/Assertions.json`. Wrap in a `FocusDetecting` protocol so it can be swapped for a future public API.

```swift
protocol FocusDetecting: Sendable {
    var isFocusActive: Bool { get async }
    func onFocusChanged(_ handler: @Sendable @escaping (Bool) -> Void)
}
```

**Caveat:** This file path is undocumented and may break across macOS versions. LOW confidence in long-term stability.

## Patterns to Follow

### Pattern 1: Facade Preserves API During Refactor

**What:** TTSEngine keeps its existing public API but delegates internally to decomposed components.
**When:** Decomposing a god object that has many callers.
**Why:** Zero caller changes needed. Callers migrate to direct component access incrementally.

### Pattern 2: AsyncStream for Streaming Pipelines

**What:** Replace callback pairs (`onChunkReady` + `onAllComplete`) with `AsyncStream<ChunkResult>`.
**When:** Converting callback-based streaming to structured concurrency.
**Why:** Eliminates manual lock management, enables `for await` consumption, natural back-pressure.

### Pattern 3: Protocol-Based Synthesizer Selection

**What:** `Synthesizer` protocol enabling kokoro-ios (English) and sherpa-onnx (Chinese) backends.
**When:** Adding language-specific TTS engines.
**Why:** Open-closed principle. New languages don't modify existing synthesis code.

### Pattern 4: Synchronous State Mutation Within Actors

**What:** All state changes happen in synchronous methods. Async methods call synchronous helpers.
**When:** Every actor method that mutates state.
**Why:** Actor reentrancy means state can change across `await`. Synchronous blocks run atomically.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Actor Reentrancy Surprise

**What:** Assuming actor methods execute atomically across await points.
**Why bad:** An actor can interleave work at any `await`. If `ensureModelLoaded()` has an await, another call could enter before it completes.
**Instead:** Use synchronous initialization (current approach) or guard with a boolean + continuation pattern.

### Anti-Pattern 2: Main Actor Blocking from Actor

**What:** Calling `await MainActor.run { ... }` from inside an actor method that holds exclusive state.
**Why bad:** If the main thread is blocked waiting on the actor, deadlock.
**Instead:** Return results from actor methods, let the caller dispatch to MainActor.

### Anti-Pattern 3: Testing AppKit Components Directly

**What:** Trying to unit-test SubtitlePanel, SubtitleSyncDriver via XCTest.
**Why bad:** NSPanel requires a running NSApplication. Timer-based sync requires real-time progression.
**Instead:** Test the data transformations (WordTimingAligner, SubtitleChunker) that feed these components.

### Anti-Pattern 4: Premature Protocol Abstraction

**What:** Creating protocols for every component "for testability."
**Why bad:** Adds indirection without value when there's only one implementation.
**Instead:** Use protocols only where there's a concrete second implementation (e.g., Synthesizer for kokoro-ios vs sherpa-onnx). Use `internal` access + `@testable import` for testing concrete types.

### Anti-Pattern 5: Calling C FFI from Actor-Isolated Context

**What:** Calling kokoro-ios / sherpa-onnx C functions directly from within an actor.
**Why bad:** C functions block the cooperative thread pool thread.
**Instead:** The kokoro-ios MLX synthesis is synchronous and CPU/GPU-bound. Keep it on a dedicated thread via `Task.detached` or a custom executor, not the cooperative pool.

## Build Order (Dependency-Aware)

The build order respects these dependency chains:

- Testing depends on Decomposition -- can't test what isn't extracted
- New Features depend on Decomposition -- Chinese TTS needs Synthesizer protocol
- Edge-case hardening depends on Decomposition -- hardening applies to decomposed components

### Suggested Build Order

```
Phase: TTSEngine Decomposition + Actor Migration + XCTest Infrastructure
    |
    |-- Step 1: Create CompanionCore library target in Package.swift
    |           Move pure types: WordTimingAligner, PronunciationProcessor,
    |           SubtitleChunker, LanguageDetector, TranscriptParser,
    |           TelegramFormatter, SubtitleStyle, Config
    |           Result: `swift test` runs, even with zero tests
    |
    |-- Step 2: Add test target, write unit tests for pure types
    |           WordTimingAligner edge cases, PronunciationProcessor regex,
    |           SubtitleChunker page boundaries, LanguageDetector thresholds
    |           Result: Test suite validates existing behavior before refactoring
    |
    |-- Step 3: Extract TTSCircuitBreaker as actor (into CompanionCore)
    |           Replace circuitBreakerLock + NSLock in TTSEngine
    |           TTSEngine delegates to TTSCircuitBreaker actor
    |           Write TTSCircuitBreaker state machine tests
    |
    |-- Step 4: Extract PlaybackManager as @MainActor class
    |           Move AVAudioPlayer lifecycle, warm-up, preparePlayer
    |           TTSEngine.play() delegates to PlaybackManager
    |           No tests needed (AppKit-dependent)
    |
    |-- Step 5: Extract SynthesisEngine as actor
    |           Move model loading, generateAudio, streaming pipeline
    |           Define Synthesizer protocol (prep for Chinese TTS)
    |           TTSEngine.synthesize*() delegates to SynthesisEngine
    |           Write async integration tests (require model files)
    |
    |-- Step 6: Convert streaming to AsyncStream
    |           Replace onChunkReady/onAllComplete callbacks
    |           Remove NSLock-protected firstChunkDispatched flag
    |           TelegramBot uses `for await chunk in ...`
    |
    |-- Step 7: Remove @unchecked Sendable from TTSEngine
    |           All mutable state now in actor-isolated sub-components
    |           TTSEngine is a stateless facade
    |
Phase: Streaming Pipeline Edge-Case Hardening
    |
    |-- Rapid-fire dispatch (new session while streaming)
    |-- Hardware disconnect mid-playback
    |-- Memory pressure during synthesis
    |-- Tests for each edge case
    |
Phase: New Feature Components
    |
    |-- Step A: BionicRenderer (pure struct, add to CompanionCore)
    |           Write tests, integrate with SubtitlePanel
    |
    |-- Step B: CaptionHistoryPanel (@MainActor NSPanel)
    |           Reads from CaptionHistory, copy button, HTTP toggle
    |
    |-- Step C: FocusMonitor (file-based DND detection)
    |           Wrap in protocol for future API replacement
    |           Integrate with PlaybackManager (suppress audio)
    |
    |-- Step D: Chinese TTS via sherpa-onnx
    |           Implement SherpaOnnxSynthesizer conforming to Synthesizer
    |           SynthesisEngine routes based on LanguageDetector
    |           Requires sherpa-onnx static libs + kokoro-multi-lang model
```

## Scalability Considerations

| Concern          | Current (1 user)                 | Future                      | Notes                                                             |
| ---------------- | -------------------------------- | --------------------------- | ----------------------------------------------------------------- |
| TTS model memory | 561MB peak (one model)           | ~1.1GB if two models loaded | Lazy-load Chinese model only when CJK detected; unload after idle |
| Streaming chunks | ~5-10 sentences per notification | Same                        | Serial synthesis is fine for single-user                          |
| Caption history  | 100-entry ring buffer            | Sufficient                  | Ring buffer prevents unbounded growth                             |
| HTTP API         | ~1 req/sec from SwiftBar         | Same                        | FlyingFox handles this trivially                                  |

## Sources

- [SwiftPM executable target testability limitation](https://github.com/swiftlang/swift-package-manager/issues/7596) -- HIGH confidence
- [SwiftPM library extraction pattern for testing](https://forums.swift.org/t/executable-target-testability/52351) -- HIGH confidence
- [SE-0337: Incremental Migration to Concurrency Checking](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0337-support-incremental-migration-to-concurrency-checking.md) -- HIGH confidence
- [@unchecked Sendable with NSLock pattern](https://gist.github.com/dterekhov/a75ad354add68eb356fdb3b2366182a8) -- HIGH confidence
- [macOS Focus/DND -- no public API](https://developer.apple.com/forums/thread/682143) -- HIGH confidence
- [File-based DND detection workaround](https://gist.github.com/drewkerr/0f2b61ce34e2b9e3ce0ec6a92ab05c18) -- MEDIUM confidence (undocumented file path)
- [sherpa-onnx Kokoro multi-language support](https://github.com/k2-fsa/sherpa-onnx/pull/1795) -- MEDIUM confidence
- [Beware @unchecked Sendable pitfalls](https://jaredsinclair.com/2024/11/12/beware-unchecked.html) -- HIGH confidence
