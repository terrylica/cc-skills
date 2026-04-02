# Testing Patterns

**Analysis Date:** 2026-04-02

## Test Framework

**Runner:**

- [Apple Swift Testing](https://github.com/swiftlang/swift-testing) 0.12.0+
- Config: No separate config file; all configuration via `Package.swift` and source attributes
- Integrated with SwiftPM (`swift test` command)

**Assertion Library:**

- Swift Testing's `#expect()` macro (native to framework, no separate library)
- No external assertion libraries (XCTest deprecated in favor of swift-testing)

**Run Commands:**

```bash
swift test                    # Run all tests
swift test -v                 # Verbose output
swift test --filter "CircuitBreakerTests"  # Run specific suite
```

## Test File Organization

**Location:**

- Path: `Tests/CompanionCoreTests/` (co-located with source in `Sources/CompanionCore/`)
- Pattern: One test file per module under test: `CircuitBreakerTests.swift` tests `CircuitBreaker.swift`

**Naming:**

- Suffix `Tests`: `CircuitBreakerTests`, `BionicRendererTests`, `SentenceSplitterTests`
- Struct-based (not class): `struct CircuitBreakerTests`
- Import pattern: `@testable import CompanionCore` for internal access

**Structure:**

```
Tests/
├── CompanionCoreTests/
│   ├── CircuitBreakerTests.swift
│   ├── SentenceSplitterTests.swift
│   ├── BionicRendererTests.swift
│   ├── StreamingPipelineTests.swift
│   └── ... (10 test files total)
```

## Test Structure

**Suite Organization:**

```swift
@testable import CompanionCore
import Testing

@Suite struct CircuitBreakerTests {
    @Test func startsInClosedState() {
        let cb = CircuitBreaker(maxFailures: 3, cooldownSeconds: 60)
        #expect(!cb.isOpen)
    }

    @Test func opensAfterMaxFailures() {
        let cb = CircuitBreaker(maxFailures: 2, cooldownSeconds: 60)
        cb.recordFailure()
        cb.recordFailure()
        #expect(cb.isOpen)
    }
}
```

**Patterns:**

- Setup: Inline in each test (no shared setUp method observed; DRY via helper functions)
- Teardown: Minimal cleanup needed; Swift testing framework handles test isolation
- Assertion: Single `#expect()` per test typically, or multiple for related checks within one scenario

**Helper Functions:**

```swift
// From StreamingPipelineTests
private func runPipeline(
    text: String,
    durationPerSentence: TimeInterval
) -> (sentences: [String], pages: [[SubtitlePage]], timings: [[TimeInterval]]) {
    let sentences = SentenceSplitter.splitIntoSentences(text)
    var allPages: [[SubtitlePage]] = []
    var allTimings: [[TimeInterval]] = []

    for sentence in sentences {
        let pages = SubtitleChunker.chunkIntoPages(text: sentence)
        let timings = WordTimingAligner.extractWordTimings(
            text: sentence, audioDuration: durationPerSentence
        )
        allPages.append(pages)
        allTimings.append(timings)
    }

    return (sentences, allPages, allTimings)
}
```

## Mocking

**Framework:**

- No external mocking library (Mockito, Mocker, etc.) observed
- Manual mocks via in-place test doubles and dependency injection

**Patterns:**

- Dependency injection: Pass real objects (or minimal test stubs) to units under test
- Example: `CircuitBreaker(maxFailures: 2, cooldownSeconds: 60)` uses real constructor with test-specific params
- No protocol-based mocking: tests instantiate real types with controlled constructor arguments

**What to Mock:**

- Python TTS server responses: Not mocked in unit tests (Python server not a dependency of CompanionCore tests)
- Audio playback: Not mocked; tests avoid audio hardware calls
- Settings/configuration: Not mocked; tests use real `Config` values or helpers

**What NOT to Mock:**

- Core domain objects: Always use real `CircuitBreaker`, `SentenceSplitter`, `BionicRenderer` classes
- Logic classes: Real implementation tested, not stubbed
- AVFoundation/AppKit: Tests marked `@MainActor` or avoid UI classes entirely (SentenceSplitter is pure logic)

## Fixtures and Factories

**Test Data:**

- Inline strings in tests (no separate fixture files)
- Example from `SentenceSplitterTests`:

```swift
@Test func splitsOnPeriod() {
    let result = SentenceSplitter.splitIntoSentences("Hello world. Goodbye world.")
    #expect(result == ["Hello world.", "Goodbye world."])
}
```

- Example from `WordTimingAlignerTests`:

```swift
@Test func extractWordTimingsSumEqualsDuration() {
    let timings = WordTimingAligner.extractWordTimings(
        text: "The quick brown fox jumps", audioDuration: 5.0)
    let sum = timings.reduce(0, +)
    #expect(abs(sum - 5.0) < 0.0001)
}
```

**Location:**

- No separate factory files; test data created inline or via helper functions
- Builder pattern not observed (simple literals preferred)

**Test Doubles:**

- Minimal custom doubles: tests prefer real objects with controlled parameters
- Example: `CircuitBreaker` with `maxFailures: 1, cooldownSeconds: 0.1` for fast cooldown tests

## Coverage

**Requirements:**

- No hard coverage target (no CI gate, no code coverage enforced)
- Tests focus on domain logic: sentence splitting, bionic rendering, circuit breaker state
- Async/await and Actor patterns not extensively tested (infrastructure assumed correct)

**View Coverage:**

```bash
# No built-in coverage reporting observed
# Would require external tool (e.g., codecov, Swift Coverage plugin)
```

## Test Types

**Unit Tests:**

- Scope: Single class or function in isolation
- Approach: No external dependencies (network, filesystem, audio)
- Examples:
  - `CircuitBreakerTests`: State machine logic (open/close/reset)
  - `SentenceSplitterTests`: Text segmentation rules (punctuation, abbreviations)
  - `BionicRendererTests`: Bold prefix computation and NSAttributedString construction
  - `LanguageDetectorTests`: CJK character ratio detection
  - `PronunciationProcessorTests`: Phoneme insertion logic

**Integration Tests:**

- Scope: Multiple components working together
- Approach: Real objects (no mocks), minimal fixtures
- Examples:
  - `StreamingPipelineTests`: Full pipeline with SentenceSplitter + SubtitleChunker + WordTimingAligner
  - `TelegramFormatterTests`: Formatter chains (fencing, file refs)
  - `TranscriptParserTests`: Parsing + format conversion

**E2E Tests:**

- Framework: Not used
- Rationale: Would require Python TTS server, audio playback, network access
- Integration tests serve as "smoke tests" for core paths

## Common Patterns

**Async Testing:**

```swift
// From CircuitBreakerTests
@Test func closesAfterCooldown() async throws {
    let cb = CircuitBreaker(maxFailures: 1, cooldownSeconds: 0.1)
    cb.recordFailure()
    #expect(cb.isOpen)
    try await Task.sleep(for: .milliseconds(150))
    #expect(!cb.isOpen) // Cooldown expired
}
```

**Serialized Tests (Async + MainActor):**

```swift
// From StreamingPipelineTests
@Suite(.serialized)
@MainActor
struct StreamingPipelineTests {
    @Test func multiSentenceProducesSequencedChunks() {
        // Real SubtitlePanel sizing requires MainActor
        let pages = SubtitleChunker.chunkIntoPages(text: sentence)
        #expect(!pages.isEmpty)
    }
}
```

**Error Testing:**

```swift
// Implicit via state checks (no exception assertions observed)
@Test func circuitBreakerOpenBlocksOperations() {
    let cb = CircuitBreaker(maxFailures: 1, cooldownSeconds: 60)
    cb.recordFailure()
    #expect(cb.isOpen)  // Asserts state, not thrown error
}
```

**Floating-Point Tolerance:**

```swift
// From WordTimingAlignerTests
#expect(abs(timings[0] - 1.0) < 0.001)
#expect(abs(sum - 5.0) < 0.0001)
```

## Test Isolation & Cleanup

**Per-Test Isolation:**

- Each test method creates its own instances (no shared state)
- No setUp/tearDown methods observed
- Swift Testing framework isolates tests automatically

**Resource Cleanup:**

- Minimal: Most tests operate on strings and value types (auto-freed)
- TimeInterval-based async tests use `Task.sleep()` with cleanup via test framework

## Line-by-Line Test Examples

**CircuitBreakerTests (State Machine Logic):**

```swift
@Suite struct CircuitBreakerTests {
    @Test func startsInClosedState() {
        let cb = CircuitBreaker(maxFailures: 3, cooldownSeconds: 60)
        #expect(!cb.isOpen)
    }

    @Test func opensAfterMaxFailures() {
        let cb = CircuitBreaker(maxFailures: 2, cooldownSeconds: 60)
        cb.recordFailure()
        cb.recordFailure()
        #expect(cb.isOpen)
    }

    @Test func resetsOnSuccess() {
        let cb = CircuitBreaker(maxFailures: 2, cooldownSeconds: 60)
        cb.recordFailure()
        cb.recordSuccess()
        cb.recordFailure()
        #expect(!cb.isOpen) // Only 1 consecutive failure after reset
    }
}
```

**BionicRendererTests (Computation + NSAttributedString):**

```swift
@Test func renderProducesBoldPrefixAndRegularSuffix() {
    let result = BionicRenderer.render(words: ["Hello"], fontSizeName: "medium")
    let str = result.string
    #expect(str == "Hello")

    // First 2 chars ("He") should be bold
    var boldRange = NSRange(location: 0, length: 0)
    let boldFont = result.attribute(.font, at: 0, effectiveRange: &boldRange) as? NSFont
    #expect(boldFont != nil)
    #expect(boldRange.length >= 2)

    // Chars at index 2 ("l") should be regular
    var regularRange = NSRange(location: 0, length: 0)
    let regularFont = result.attribute(.font, at: 2, effectiveRange: &regularRange) as? NSFont
    #expect(regularFont != nil)

    // Bold and regular should use different weights
    #expect(boldFont != regularFont)
}
```

**StreamingPipelineTests (Integration with Helper):**

```swift
@Suite(.serialized)
@MainActor
struct StreamingPipelineTests {
    private func runPipeline(
        text: String,
        durationPerSentence: TimeInterval
    ) -> (sentences: [String], pages: [[SubtitlePage]], timings: [[TimeInterval]]) {
        let sentences = SentenceSplitter.splitIntoSentences(text)
        var allPages: [[SubtitlePage]] = []
        var allTimings: [[TimeInterval]] = []

        for sentence in sentences {
            let pages = SubtitleChunker.chunkIntoPages(text: sentence)
            let timings = WordTimingAligner.extractWordTimings(
                text: sentence, audioDuration: durationPerSentence
            )
            allPages.append(pages)
            allTimings.append(timings)
        }

        return (sentences, allPages, allTimings)
    }

    @Test func multiSentenceProducesSequencedChunks() {
        let text = "The quick brown fox jumped over the lazy dog. It was a sunny day in the park. Birds were singing loudly."
        let result = runPipeline(text: text, durationPerSentence: 2.0)

        #expect(result.sentences.count == 3)

        for (i, pages) in result.pages.enumerated() {
            #expect(!pages.isEmpty, "Sentence \(i) should have pages")
        }

        for (i, timings) in result.timings.enumerated() {
            let sum = timings.reduce(0, +)
            #expect(abs(sum - 2.0) < 0.001,
                    "Sentence \(i) timings sum \(sum) should equal 2.0")
        }
    }
}
```

## Coverage Gaps (Untested Areas)

| Area            | What's Not Tested                           | Files                                             | Risk                                       | Priority |
| --------------- | ------------------------------------------- | ------------------------------------------------- | ------------------------------------------ | -------- |
| Audio playback  | AVAudioPlayer delegation, afplay subprocess | `PlaybackManager.swift`, `AfplayPlayer.swift`     | Playback failures undetected until runtime | High     |
| HTTP API        | Request routing, JSON encoding/decoding     | `HTTPControlServer.swift`                         | Broken API endpoints                       | High     |
| Telegram bot    | Message handling, callback chains           | `TelegramBot.swift`, `TelegramBotCallbacks.swift` | Silent bot failures                        | Medium   |
| Actor isolation | Cross-actor task scheduling, reentrancy     | `TTSEngine.swift`, `CompanionApp.swift`           | Data races under concurrency               | Medium   |
| Configuration   | Settings persistence, env var loading       | `Config.swift`, `SettingsStore.swift`             | Config corruption on upgrade               | Medium   |
| Error paths     | Exception handling in async contexts        | Throughout                                        | Unhandled errors, hangs                    | Medium   |

---

_Testing analysis: 2026-04-02_
