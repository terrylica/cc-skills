# Coding Conventions

**Analysis Date:** 2026-04-02

## Naming Patterns

**Files:**

- CamelCase with descriptive names: `CircuitBreaker.swift`, `SubtitleChunker.swift`, `TTSPipelineCoordinator.swift`
- Postfix-descriptive for supporting modules: `TelegramBotCallbacks.swift`, `TelegramBotCommands.swift`, `TelegramFormatterFencing.swift`
- Functional modules (not types) use simple lowercase: `main.swift`, `module.modulemap` (C interop)

**Functions:**

- camelCase starting with lowercase: `chunkIntoPages()`, `recordFailure()`, `play()`, `splitIntoSentences()`
- Verb-first for actions: `checkPythonServerHealth()`, `recordSuccess()`, `auditAudioRouting()`
- Property accessors use descriptive names: `isOpen`, `audioRoutingClean`, `isTTSCircuitBreakerOpen`
- Static factory functions: `from(string:)` returns enum instances

**Variables:**

- camelCase: `logger`, `urlSession`, `playbackManager`, `wavPath`, `wordTimings`
- Private properties use `_` prefix where semantics matter (rare; mostly avoided)
- Module references: `settingsStore`, `subtitlePanel`, `sherpaOnnxEngine` (noun-based)

**Types:**

- Classes: `CircuitBreaker`, `TTSEngine`, `PlaybackManager` (final classes marked explicitly)
- Enums: `DisplayMode`, `TTSError`, `SummaryError` (PascalCase, concise names)
- Structs: `SynthesisResult`, `TTSResult`, `SubtitlePage` (noun-based, no "Result" suffix for most)
- Protocols: Use action/interface names (e.g., `Sendable`, `CustomStringConvertible`)

## Code Style

**Formatting:**

- No external formatter (SwiftFormat/Prettier not configured)
- 2-space indentation (inferred from standard Swift)
- Line length: no hard limit observed; pragmatic wrapping at logical boundaries (parameters, closures)
- Trailing commas in multiline collections observed but inconsistent

**Linting:**

- No linter configuration found (no .swiftlint.yml, eslint, biome.json)
- Code quality enforced via code review and Swift 6 strict concurrency checking
- MARK comments used liberally to organize large files: `// MARK: - Lifecycle`, `// MARK: - Public API`, `// MARK: - TTS Circuit Breaker`

**Concurrency:**

- Swift 6 strict concurrency with actor isolation (not @unchecked Sendable carelessly)
- `@MainActor` for UI-bound classes: `SubtitlePanel`, `BionicRenderer.render()`, `PlaybackManager`
- Actor-isolated classes for background work: `TTSEngine`, `SummaryEngine`, `MiniMaxClient`
- `@unchecked Sendable` used sparingly with clear comments: `CompanionApp: @unchecked Sendable` with lifetime management for SIGTERM handler
- `nonisolated(unsafe)` for global keepAlive references in main.swift (documented as anti-pattern with fallback reason)

## Import Organization

**Order:**

1. Framework imports (AppKit, Foundation, AVFoundation, CoreAudio, Logging)
2. Package imports (CompanionCore, SwiftTelegramBot, Testing)
3. Conditional: `@testable import CompanionCore` in test files only

**Examples:**

```swift
// From main.swift
import AppKit
import CompanionCore
import Foundation
import Logging

// From TTSEngine.swift
import AVFoundation
import Foundation
import Logging

// From test files
@testable import CompanionCore
import Testing
import AppKit
```

**Path Aliases:**

- Not observed; no target aliases or custom import paths used

## Error Handling

**Patterns:**

- Explicit error enums with `CustomStringConvertible`: `TTSError`, `SummaryError`
- Associated values for context: `.apiError(statusCode: Int, body: String)`
- Human-readable descriptions in switch cases (no generic "Unknown error")
- Errors propagated via `throws`, caught with `do/catch`, logged with `logger.warning()` or `logger.error()`
- Circuit breaker pattern for API failures (TTSEngine, SummaryEngine): fail fast after N consecutive failures, cooldown before retry
- Async tasks wrapped with `Task { do { ... } catch { logger.error(...) } }` (fire-and-forget patterns used sparingly)

**Error Types:**

- `TTSError`: synthesis, server unavailability, circuit breaker state
- `SummaryError`: circuit breaker, missing API key, decoding failures
- URLError: network transport errors (wrapped in higher-level errors)

## Logging

**Framework:** `swift-log` with `StreamLogHandler.standardError` (launchd stderr capture)

**Patterns:**

- Logger created per class: `private let logger = Logger(label: "module-name")`
- Structured logging: `logger.info("Message")`, `logger.warning(...)`, `logger.error(...)`
- Context-rich messages: include affected resource names, counts, paths
- Examples:
  - `logger.info("TTS backend: Python Kokoro server (\(Config.pythonTTSServerURL)) + sherpa-onnx CJK")`
  - `logger.warning("Circuit breaker OPEN after \(consecutiveFailures) consecutive failures...")`
  - `logger.error("play() failed for WAV: \(wavPath)")`

**When to Log:**

- Startup/shutdown: service lifecycle events
- State transitions: circuit breaker open/close, audio hardware warm-up
- Errors: always log with context
- Performance: model load times, synthesis latency
- Do NOT log per-word: karaoke highlighting timestamp updates (high frequency)

## Comments

**When to Comment:**

- File-level comments for large classes: explain purpose, isolation model, ownership
- Method-level comments: document preconditions, async behavior, lifetime implications
- Inline comments: clarify non-obvious logic (e.g., "Pitfall 5: buffer unbuffering for launchd")
- Skip obvious comments: `let count = words.count` needs no explanation

**JSDoc/TSDoc:**

- Triple-slash comments used for public APIs: `/// Compute the number of characters to bold for a given word.`
- Multiline doc comments document parameters, return values, error cases
- Examples in code comments where algorithm is non-obvious
- Document why, not what: `/// Subclass AVAudioPlayer with weak timingDelegate...` (explains design intent)

**Spike/ADR References:**

- Comments cite spikes: `// FILE-SIZE-OK -- actor with HTTP client...` (references design decision)
- Comments cite external ADRs: `// (CJK-01)`, `// (D-01)`, `// (P1)` (sync with project CLAUDE.md)

## Function Design

**Size:**

- Typical range: 10-50 lines for public methods, 5-30 for helpers
- Larger functions (100+ lines) broken into sections with `// MARK: -` comments
- One responsibility per function: `recordFailure()` only manages failure count, not logging

**Parameters:**

- Named parameters required: `chunkIntoPages(text:fontSizeName:)` (clarity over brevity)
- Default values for optional settings: `fontSizeName: String = "medium"`
- Closures in trailing position: `completion: (() -> Void)? = nil`
- Inline documentation for parameters: `// Path aliases used` style comments before signature

**Return Values:**

- Explicit optional types when nil is meaningful: `AVAudioPlayer?` signals "may fail to load"
- Tuple returns for related values: `(sentences: [String], pages: [[SubtitlePage]], timings: [[TimeInterval]])`
- Structs preferred over tuples for public APIs: `TTSResult` bundles path, text, timings, duration

## Module Design

**Exports:**

- Classes/enums/structs marked `public` explicitly for library boundary (not internal default)
- Properties marked `private` or `private(set)` (default private in final classes)
- No namespace pollution: each module exports cohesive set of types

**Examples:**

- `public final class CircuitBreaker` (immutable lifecycle, sendable)
- `public enum DisplayMode: String, Codable, Sendable` (value type, encoding support)
- `public struct TTSResult: Sendable` (lightweight data container)

**Barrel Files:**

- Not observed; no `__init__.swift` or index exports
- Imports are granular (import specific types as needed)

**Sendable Conformance:**

- Value types conform automatically: `struct`, `enum` with `Sendable` members
- Classes require explicit conformance: `final class CircuitBreaker: @unchecked Sendable` (NSLock not Sendable)
- Comment rationale: `// Thread-safe via NSLock (matching TTSEngine pattern)` explains why @unchecked is safe

## Async/Await Patterns

**Task Wrapping:**

- Background work via `Task { await ... }` in initializers and lifecycle events
- No task cancellation tracking observed (fire-and-forget model)
- Example: `Task { await ttsEngine.checkPythonServerHealth() }` in CompanionApp.start()

**Async Functions:**

- Return types for async work: `async func synthesize(text:) async throws -> TTSResult`
- No backpressure/semaphore observed (Python server handles queuing)
- Timeout via URLSessionConfiguration: `config.timeoutIntervalForRequest`

**Actor Isolation:**

- Actor-isolated properties accessed via `await` from other actors
- Same-actor access is synchronous (no await needed)
- Cross-actor calls explicit: `await ttsEngine.synthesize(...)`

---

_Convention analysis: 2026-04-02_
