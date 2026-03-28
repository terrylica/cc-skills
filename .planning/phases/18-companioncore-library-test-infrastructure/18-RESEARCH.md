# Phase 18: CompanionCore Library & Test Infrastructure - Research

**Researched:** 2026-03-28
**Domain:** SwiftPM library target extraction, Swift 6 access control, XCTest / Swift Testing
**Confidence:** HIGH

## Summary

This phase extracts all business logic from a single executable target into a `CompanionCore` library target, enabling `swift test`. The codebase has 27 Swift files (26 business logic + 1 main.swift) in `Sources/claude-tts-companion/`. All 26 non-main files move to `Sources/CompanionCore/`. The executable target keeps only `main.swift` which imports CompanionCore.

The key technical challenges are: (1) SwiftPM Package.swift restructuring with correct dependency assignment, (2) adding `public` access modifiers to types that main.swift needs, (3) handling `@MainActor`-annotated types (SubtitleChunker, SubtitlePanel, SubtitleSyncDriver, SubtitleStyle) in tests, and (4) choosing between XCTest and Swift Testing framework.

**Primary recommendation:** Use Swift Testing (`@Test` macro) instead of XCTest. It ships with Swift 6 toolchain (no dependency needed), handles `@MainActor` natively on `@Suite`, and has cleaner syntax. Write tests for LanguageDetector, SubtitleChunker, TelegramFormatter, TranscriptParser, and CircuitBreaker.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Ultra-thin main.swift -- keeps ONLY NSApplication setup, SIGTERM handler, run loop (~50 lines). All wiring moves to a `CompanionApp` class in CompanionCore.
- **D-02:** Notification handling closure, `plannedRestart()`, `checkMemoryLifecycleRestart()`, and helper functions all move into CompanionCore (likely as methods on CompanionApp or a coordinator type).
- **D-03:** `nonisolated(unsafe)` keepAlive references stay in main.swift (they prevent ARC deallocation of the app-level coordinator).
- **D-04:** Public types, internal members. Mark `class`/`struct`/`enum` declarations as `public`. Keep methods and properties `internal` by default.
- **D-05:** Test target uses `@testable import CompanionCore` to access internal members.
- **D-06:** main.swift only needs the public `CompanionApp` facade (`.start()`, `.shutdown()`).
- **D-07:** Write unit tests for four pure types: LanguageDetector, SubtitleChunker, TelegramFormatter, TranscriptParser.
- **D-08:** CircuitBreaker tests also included (state machine with time-based transitions -- may need clock injection).
- **D-09:** These are proof-of-life tests beyond the minimum success criteria. Phase 20 adds comprehensive coverage for decomposed components.

### Claude's Discretion

- Whether to create a `CompanionApp` class vs a `bootstrap()` function for the coordinator pattern
- Internal organization of test files (one file per type vs grouped)
- Whether CircuitBreaker tests need a clock abstraction or can use short real-time intervals

### Deferred Ideas (OUT OF SCOPE)

None -- discussion stayed within phase scope.

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID      | Description                                                                                                | Research Support                                                                                       |
| ------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| ARCH-01 | CompanionCore library target extracts all business logic from executable, leaving main.swift as thin shell | Package.swift restructuring pattern, file move plan, access control strategy documented below          |
| TEST-01 | XCTest target for CompanionCore library with SwiftPM `swift test`                                          | Swift Testing framework analysis, test target configuration, @MainActor test patterns documented below |

</phase_requirements>

## Standard Stack

### Core

| Library       | Version              | Purpose                 | Why Standard                                                                                                                     |
| ------------- | -------------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Swift Testing | Built-in (Swift 6.2) | Unit test framework     | Ships with Swift 6 toolchain, no dependency needed. `@Test` macro, `#expect` assertions, native `@MainActor` support on `@Suite` |
| XCTest        | Built-in             | Fallback test framework | Available as alternative; Swift Testing preferred for new code                                                                   |

### Supporting

No additional libraries needed. The test target uses only `@testable import CompanionCore` plus system frameworks.

### Alternatives Considered

| Instead of    | Could Use | Tradeoff                                                                                                                                                                    |
| ------------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Swift Testing | XCTest    | XCTest cannot annotate `XCTestCase` subclass with `@MainActor` in Swift 6 (compiler error). Individual test methods need `@MainActor`. Swift Testing handles this natively. |

## Architecture Patterns

### Recommended Project Structure

```
plugins/claude-tts-companion/
├── Package.swift                          # Updated: library + executable + test targets
├── Sources/
│   ├── CompanionCore/                     # NEW: 26 files (all business logic)
│   │   ├── AudioStreamPlayer.swift
│   │   ├── AutoContinue.swift
│   │   ├── CaptionHistory.swift
│   │   ├── CircuitBreaker.swift
│   │   ├── ClaudeProcess.swift
│   │   ├── CompanionApp.swift             # NEW: coordinator extracted from main.swift
│   │   ├── Config.swift
│   │   ├── FeatureGates.swift
│   │   ├── FileWatcher.swift
│   │   ├── HTTPControlServer.swift
│   │   ├── InlineButtonManager.swift
│   │   ├── LanguageDetector.swift
│   │   ├── MiniMaxClient.swift
│   │   ├── NotificationProcessor.swift
│   │   ├── PromptExecutor.swift
│   │   ├── SettingsStore.swift
│   │   ├── SubtitleChunker.swift
│   │   ├── SubtitlePanel.swift
│   │   ├── SubtitleStyle.swift
│   │   ├── SubtitleSyncDriver.swift
│   │   ├── SummaryEngine.swift
│   │   ├── TelegramBot.swift
│   │   ├── TelegramFormatter.swift
│   │   ├── ThinkingWatcher.swift
│   │   ├── TranscriptParser.swift
│   │   └── TTSEngine.swift
│   └── claude-tts-companion/
│       └── main.swift                     # ONLY file here (~50 lines)
└── Tests/
    └── CompanionCoreTests/                # NEW: test target
        ├── LanguageDetectorTests.swift
        ├── SubtitleChunkerTests.swift
        ├── TelegramFormatterTests.swift
        ├── TranscriptParserTests.swift
        └── CircuitBreakerTests.swift
```

### Pattern 1: Package.swift Library + Executable + Test Target

**What:** SwiftPM manifest with three targets: library, executable (depends on library), test (depends on library).
**When to use:** Always for this phase -- it's the core deliverable.
**Example:**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "claude-tts-companion",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/nerzh/swift-telegram-sdk", from: "4.5.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/swhitty/FlyingFox", from: "0.26.0"),
        .package(url: "https://github.com/terrylica/kokoro-ios.git", exact: "1.0.14"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
    ],
    targets: [
        .target(
            name: "CompanionCore",
            dependencies: [
                .product(name: "SwiftTelegramBot", package: "swift-telegram-sdk"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "FlyingFox", package: "FlyingFox"),
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
                .product(name: "MLX", package: "mlx-swift"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .executableTarget(
            name: "claude-tts-companion",
            dependencies: ["CompanionCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "CompanionCoreTests",
            dependencies: ["CompanionCore"]
        ),
    ]
)
```

### Pattern 2: @testable import for Internal Access

**What:** Test target uses `@testable import CompanionCore` to access internal members without making everything public.
**When to use:** All test files.
**Example:**

```swift
@testable import CompanionCore
import Testing

@Suite struct LanguageDetectorTests {
    @Test func detectsEnglishText() {
        let result = LanguageDetector.detect(text: "Hello world, this is a test")
        #expect(result.lang == "en-us")
    }

    @Test func detectsCJKText() {
        let result = LanguageDetector.detect(text: "你好世界，这是一个测试")
        #expect(result.lang == "cmn")
    }
}
```

### Pattern 3: @MainActor Tests with Swift Testing

**What:** SubtitleChunker is `@MainActor` -- tests for it need main actor isolation.
**When to use:** Testing SubtitleChunker (and eventually SubtitlePanel, SubtitleSyncDriver, SubtitleStyle).
**Example:**

```swift
@testable import CompanionCore
import Testing

@Suite(.serialized)
@MainActor
struct SubtitleChunkerTests {
    @Test func chunksShortTextIntoSinglePage() {
        let pages = SubtitleChunker.chunkIntoPages(text: "Hello world")
        #expect(pages.count == 1)
        #expect(pages[0].words == ["Hello", "world"])
    }
}
```

**Key insight:** Swift Testing allows `@MainActor` on `@Suite` directly. XCTest does NOT allow `@MainActor` on the class (Swift 6 compiler error). This is a primary reason to prefer Swift Testing.

### Pattern 4: CircuitBreaker Tests with Short Intervals

**What:** CircuitBreaker uses `Date()` comparisons for cooldown. Tests can use short real intervals (0.1s) instead of injecting a clock.
**When to use:** CircuitBreaker state machine tests.
**Example:**

```swift
@testable import CompanionCore
import Testing

@Suite struct CircuitBreakerTests {
    @Test func startsInClosedState() {
        let cb = CircuitBreaker(maxFailures: 3, cooldownSeconds: 0.1)
        #expect(!cb.isOpen)
    }

    @Test func opensAfterMaxFailures() {
        let cb = CircuitBreaker(maxFailures: 2, cooldownSeconds: 60)
        cb.recordFailure()
        cb.recordFailure()
        #expect(cb.isOpen)
    }

    @Test func closesAfterCooldown() async throws {
        let cb = CircuitBreaker(maxFailures: 1, cooldownSeconds: 0.1)
        cb.recordFailure()
        #expect(cb.isOpen)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!cb.isOpen)
    }
}
```

**Discretion note:** Short real-time intervals (0.1s) are acceptable for proof-of-life tests. Clock injection is overkill at this stage -- add it in Phase 20 if needed for deterministic CI.

### Pattern 5: CompanionApp Coordinator

**What:** A class in CompanionCore that encapsulates all the wiring currently in main.swift.
**When to use:** This is the facade that main.swift calls.
**Example:**

```swift
import AppKit
import Foundation
import Logging

public final class CompanionApp: @unchecked Sendable {
    private let logger = Logger(label: Config.appName)
    // All subsystems as properties...
    private let settingsStore: SettingsStore
    private let subtitlePanel: SubtitlePanel
    private let ttsEngine: TTSEngine
    // ... etc

    public init() {
        // Wire up all subsystems (moved from main.swift)
    }

    public func start() {
        // Start HTTP server, Telegram bot, notification watcher, etc.
    }

    public func shutdown() {
        // Clean shutdown of all subsystems
    }
}
```

**Discretion recommendation:** Use a `CompanionApp` class (not a `bootstrap()` function) because it naturally owns the subsystem references, replacing the `nonisolated(unsafe) var keepAlive` pattern for everything except the CompanionApp instance itself. main.swift only needs one keepAlive for the CompanionApp.

### Anti-Patterns to Avoid

- **Circular target dependencies:** CompanionCore must NOT import the executable target. All shared types live in CompanionCore.
- **Making everything public:** Only type declarations get `public`. Methods and properties stay `internal` (accessed via `@testable import` in tests).
- **Putting tests in the Sources directory:** Tests must go in `Tests/CompanionCoreTests/`, not in `Sources/`.
- **Importing AppKit in tests unnecessarily:** Tests for pure types (LanguageDetector, TelegramFormatter, TranscriptParser) don't need AppKit. Only SubtitleChunker tests need it (via `@MainActor` isolation).

## Don't Hand-Roll

| Problem                   | Don't Build                                | Use Instead                          | Why                                                        |
| ------------------------- | ------------------------------------------ | ------------------------------------ | ---------------------------------------------------------- |
| Test framework            | Custom assertion helpers                   | Swift Testing `#expect` / `#require` | Built-in, expressive failure messages, parameterized tests |
| Main actor test isolation | Manual `DispatchQueue.main.async` in tests | `@MainActor` on `@Suite`             | Swift Testing handles this correctly                       |
| Test discovery            | Manual test registration                   | SwiftPM automatic test discovery     | `swift test` finds all `@Test` functions automatically     |

## Common Pitfalls

### Pitfall 1: main.swift Cannot Live in Library Target

**What goes wrong:** SwiftPM treats any file named `main.swift` as the entry point for an executable target. If `main.swift` is in the library target, the build fails.
**Why it happens:** SwiftPM has special handling for `main.swift` -- it generates an implicit `@main` entry point.
**How to avoid:** Keep `main.swift` in `Sources/claude-tts-companion/` (the executable target). All other files go to `Sources/CompanionCore/`.
**Warning signs:** Build error about "multiple entry points" or "main attribute".

### Pitfall 2: Missing Public Access on Types

**What goes wrong:** After moving files to CompanionCore, main.swift can't see any types -- they're all `internal` by default.
**Why it happens:** Swift default access level is `internal` (visible within the same module only).
**How to avoid:** Add `public` to every `class`, `struct`, `enum`, and `protocol` declaration. Add `public` to initializers and methods that main.swift calls directly. Keep the rest `internal` (test target uses `@testable import`).
**Warning signs:** "Cannot find type 'X' in scope" errors when building the executable target.

### Pitfall 3: Dependencies Must Move to Library Target

**What goes wrong:** Test or executable target fails to build because dependencies are on the wrong target.
**Why it happens:** All third-party dependencies (swift-telegram-sdk, swift-log, FlyingFox, kokoro-ios, MLX) are used by CompanionCore source files. They must be dependencies of the library target, not the executable.
**How to avoid:** Move all `.product(name:package:)` dependencies to the CompanionCore `.target()` in Package.swift. The executable target depends only on `"CompanionCore"`.
**Warning signs:** "No such module" errors for Logging, FlyingFox, etc.

### Pitfall 4: @MainActor Types in Tests

**What goes wrong:** Tests for SubtitleChunker fail to compile because its static methods are `@MainActor`-isolated.
**Why it happens:** SubtitleChunker uses `NSAttributedString.size()` with `NSFont`, which requires main thread.
**How to avoid:** Use Swift Testing with `@MainActor @Suite` annotation. If using XCTest, mark individual test methods as `@MainActor`.
**Warning signs:** "Expression is 'async' but is not marked with 'await'" or "Call to main actor-isolated static method in a synchronous nonisolated context".

### Pitfall 5: Framework Linker Settings Scope

**What goes wrong:** Build fails with "framework not found" because linker settings are on the wrong target.
**Why it happens:** AppKit and AVFoundation are used by CompanionCore types (SubtitlePanel, TTSEngine, AudioStreamPlayer). The `.linkedFramework` settings must be on the library target.
**How to avoid:** Add `.linkedFramework("AppKit")`, `.linkedFramework("AVFoundation")`, and `.linkedFramework("Foundation")` to the CompanionCore target's `linkerSettings`.
**Warning signs:** Linker errors about missing symbols from AppKit or AVFoundation.

### Pitfall 6: Helper Functions in main.swift

**What goes wrong:** After moving files, `extractGitBranch()`, `extractFirstTimestamp()`, `extractLastTimestamp()` are still referenced by the notification closure but live in main.swift.
**Why it happens:** These are free functions defined at the top level of main.swift. They must move into CompanionCore (either as static methods on a helper type or as methods on CompanionApp).
**How to avoid:** Per D-02, these helper functions move into CompanionCore. The notification closure itself also moves.
**Warning signs:** "Use of unresolved identifier" errors.

### Pitfall 7: Swift Testing Requires `import Testing` Not `import XCTest`

**What goes wrong:** Mix of XCTest and Swift Testing imports causes confusion.
**Why it happens:** Both frameworks can coexist but use different APIs.
**How to avoid:** Use `import Testing` consistently across all new test files. Do not mix `XCTAssertEqual` with `#expect` in the same file.
**Warning signs:** Compiler errors about unknown macros or missing types.

## Code Examples

### File Move Command

```bash
cd plugins/claude-tts-companion
mkdir -p Sources/CompanionCore
# Move all files except main.swift
for f in Sources/claude-tts-companion/*.swift; do
    [ "$(basename "$f")" = "main.swift" ] && continue
    mv "$f" Sources/CompanionCore/
done
mkdir -p Tests/CompanionCoreTests
```

### Access Control Pattern (Applied to Existing Types)

```swift
// Before (in executable target):
enum LanguageDetector {
    static func detect(text: String) -> LanguageResult { ... }
}

// After (in CompanionCore library):
public enum LanguageDetector {
    static func detect(text: String) -> LanguageResult { ... }
    // static func stays internal -- tests use @testable import
}
```

### Minimal Test for Success Criteria Verification

```swift
// Tests/CompanionCoreTests/LanguageDetectorTests.swift
@testable import CompanionCore
import Testing

@Suite struct LanguageDetectorTests {
    @Test func detectsEnglishByDefault() {
        let result = LanguageDetector.detect(text: "Hello world")
        #expect(result.lang == "en-us")
        #expect(result.voiceName == "af_heart")
    }
}
```

Running: `swift test --filter CompanionCoreTests` from the `plugins/claude-tts-companion` directory.

## Validation Architecture

### Test Framework

| Property           | Value                                                              |
| ------------------ | ------------------------------------------------------------------ |
| Framework          | Swift Testing (built into Swift 6.2 toolchain)                     |
| Config file        | None needed -- SwiftPM discovers tests automatically from `Tests/` |
| Quick run command  | `cd plugins/claude-tts-companion && swift test`                    |
| Full suite command | `cd plugins/claude-tts-companion && swift test`                    |

### Phase Requirements to Test Map

| Req ID  | Behavior                                     | Test Type  | Automated Command                                                           | File Exists?      |
| ------- | -------------------------------------------- | ---------- | --------------------------------------------------------------------------- | ----------------- |
| ARCH-01 | Library target exists and builds             | build      | `cd plugins/claude-tts-companion && swift build`                            | N/A (build check) |
| ARCH-01 | main.swift is only file in executable target | structural | `ls Sources/claude-tts-companion/` (verify only main.swift)                 | N/A (file check)  |
| TEST-01 | swift test runs and passes                   | unit       | `cd plugins/claude-tts-companion && swift test`                             | Wave 0            |
| TEST-01 | @testable import CompanionCore works         | unit       | `cd plugins/claude-tts-companion && swift test --filter CompanionCoreTests` | Wave 0            |

### Sampling Rate

- **Per task commit:** `cd plugins/claude-tts-companion && swift build && swift test`
- **Per wave merge:** Same (single test suite)
- **Phase gate:** `swift test` green + verify `main.swift` is only file in executable target

### Wave 0 Gaps

- [ ] `Tests/CompanionCoreTests/` directory -- does not exist yet
- [ ] `LanguageDetectorTests.swift` -- covers TEST-01 (proof-of-life)
- [ ] `SubtitleChunkerTests.swift` -- covers D-07
- [ ] `TelegramFormatterTests.swift` -- covers D-07
- [ ] `TranscriptParserTests.swift` -- covers D-07
- [ ] `CircuitBreakerTests.swift` -- covers D-08

## Codebase Inventory

### Files to Move (26 files)

All files in `Sources/claude-tts-companion/` except `main.swift`:

| File                        | Size | Dependencies                   | @MainActor | Test Target   |
| --------------------------- | ---- | ------------------------------ | ---------- | ------------- |
| AudioStreamPlayer.swift     | 9KB  | AVFoundation                   | No         | No (Phase 20) |
| AutoContinue.swift          | 51KB | Foundation, Logging            | No         | No (Phase 20) |
| CaptionHistory.swift        | 4KB  | Foundation                     | No         | No (Phase 20) |
| CircuitBreaker.swift        | 4KB  | Foundation, Logging            | No         | Yes (D-08)    |
| ClaudeProcess.swift         | 10KB | Foundation                     | No         | No            |
| Config.swift                | 6KB  | Foundation                     | No         | No            |
| FeatureGates.swift          | 2KB  | Foundation                     | No         | No            |
| FileWatcher.swift           | 9KB  | Foundation, Logging            | No         | No            |
| HTTPControlServer.swift     | 14KB | FlyingFox, Foundation          | Partial    | No            |
| InlineButtonManager.swift   | 6KB  | Foundation                     | No         | No            |
| LanguageDetector.swift      | 2KB  | Foundation                     | No         | Yes (D-07)    |
| MiniMaxClient.swift         | 6KB  | Foundation, Logging            | No         | No            |
| NotificationProcessor.swift | 7KB  | Foundation, Logging            | No         | No            |
| PromptExecutor.swift        | 15KB | Foundation                     | No         | No            |
| SettingsStore.swift         | 4KB  | Foundation                     | No         | No            |
| SubtitleChunker.swift       | 7KB  | AppKit                         | Yes        | Yes (D-07)    |
| SubtitlePanel.swift         | 22KB | AppKit                         | Yes        | No (Phase 20) |
| SubtitleStyle.swift         | 4KB  | AppKit                         | Yes        | No            |
| SubtitleSyncDriver.swift    | 23KB | AppKit, AVFoundation           | Yes        | No            |
| SummaryEngine.swift         | 19KB | Foundation, Logging            | No         | No            |
| TelegramBot.swift           | 44KB | SwiftTelegramBot, Logging      | No         | No            |
| TelegramFormatter.swift     | 36KB | Foundation                     | No         | Yes (D-07)    |
| ThinkingWatcher.swift       | 6KB  | Foundation, Logging            | No         | No            |
| TranscriptParser.swift      | 20KB | Foundation, Logging            | No         | Yes (D-07)    |
| TTSEngine.swift             | 51KB | KokoroSwift, MLX, AVFoundation | No         | No            |

### main.swift Extraction Plan

Current main.swift is 350 lines. After extraction:

**Stays in main.swift (~50 lines):**

- `setbuf(stdout, nil)` / `setbuf(stderr, nil)`
- `LoggingSystem.bootstrap`
- `NSApplication.shared` setup
- `CompanionApp()` creation and `.start()`
- SIGTERM handler (DispatchSource)
- `nonisolated(unsafe) var keepAlive` for CompanionApp and sigSource
- `app.run()`

**Moves to CompanionApp in CompanionCore (~300 lines):**

- All subsystem creation (settingsStore, subtitlePanel, ttsEngine, etc.)
- HTTP server start
- Telegram bot start
- Notification watcher creation and callback
- `plannedRestart()` and `checkMemoryLifecycleRestart()`
- `extractGitBranch()`, `extractFirstTimestamp()`, `extractLastTimestamp()`
- Demo TTS code

### Types Needing `public` Modifier

**Required by main.swift (public type + public init + public methods):**

- `CompanionApp` -- `init()`, `start()`, `shutdown()`
- `Config` -- `appName` (used by logger label)

**Required for `@testable import` only (public type, internal members):**

- `LanguageDetector`, `LanguageResult`
- `SubtitleChunker`, `SubtitlePage`
- `TelegramFormatter`, `SessionNotificationData`
- `TranscriptParser`, `TranscriptEntry`, `TranscriptSummary`
- `CircuitBreaker`

All other types: add `public` to type declaration only (D-04). The `@testable import` grants test access to internal members.

## Open Questions

1. **SubtitleChunker test on headless CI**
   - What we know: SubtitleChunker uses `NSAttributedString.size()` with `NSFont` which needs AppKit display context. Works on macOS with display.
   - What's unclear: Whether `swift test` on a headless macOS CI (no display) would fail. Not relevant now since tests run locally.
   - Recommendation: Not a concern for this phase. Tests run on the developer's Mac.

2. **CompanionApp init vs start separation**
   - What we know: D-01 specifies `.start()` and `.shutdown()` as the public API.
   - What's unclear: Whether init should do zero work (just store config) or partial setup.
   - Recommendation: init creates subsystems but does not start any async work. `start()` kicks off HTTP server, bot, watchers. This is cleaner and matches the CONTEXT.md example.

## Sources

### Primary (HIGH confidence)

- Swift 6 toolchain (verified locally: Swift 6.2.4 installed)
- [Swift Testing documentation](https://developer.apple.com/documentation/testing) -- `@Test` macro, `#expect`, `@Suite`, `@MainActor` support
- [SwiftPM documentation](https://www.swift.org/documentation/server/guides/testing.html) -- test target configuration
- Codebase audit: 27 files in `Sources/claude-tts-companion/`, Package.swift with swift-tools-version 6.0

### Secondary (MEDIUM confidence)

- [Swift Forums: XCTest @MainActor issues](https://github.com/pointfreeco/swift-composable-architecture/discussions/2739) -- confirms XCTest + `@MainActor` class-level annotation is broken in Swift 6
- [XCTest Meets @MainActor](https://qualitycoding.org/xctest-mainactor/) -- workaround documentation for XCTest limitations

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH -- Swift Testing is built into the toolchain, verified locally
- Architecture: HIGH -- SwiftPM library/executable/test target pattern is well-documented and standard
- Pitfalls: HIGH -- derived from direct codebase analysis (26 files, dependency graph, @MainActor annotations)

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable -- SwiftPM patterns don't change frequently)
