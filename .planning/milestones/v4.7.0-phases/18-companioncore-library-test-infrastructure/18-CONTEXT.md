# Phase 18: CompanionCore Library & Test Infrastructure - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract all business logic from the single executable target into a `CompanionCore` library target. Enable `swift test` with unit tests for pure types. After this phase, `main.swift` is the only file in the executable target — all logic lives in CompanionCore.

</domain>

<decisions>
## Implementation Decisions

### Library Extraction

- **D-01:** Ultra-thin main.swift — keeps ONLY NSApplication setup, SIGTERM handler, run loop (~50 lines). All wiring moves to a `CompanionApp` class in CompanionCore.
- **D-02:** Notification handling closure, `plannedRestart()`, `checkMemoryLifecycleRestart()`, and helper functions all move into CompanionCore (likely as methods on CompanionApp or a coordinator type).
- **D-03:** `nonisolated(unsafe)` keepAlive references stay in main.swift (they prevent ARC deallocation of the app-level coordinator).

### Access Control

- **D-04:** Public types, internal members. Mark `class`/`struct`/`enum` declarations as `public`. Keep methods and properties `internal` by default.
- **D-05:** Test target uses `@testable import CompanionCore` to access internal members.
- **D-06:** main.swift only needs the public `CompanionApp` facade (`.start()`, `.shutdown()`).

### Initial Test Coverage

- **D-07:** Write unit tests for four pure types: LanguageDetector, SubtitleChunker, TelegramFormatter, TranscriptParser.
- **D-08:** CircuitBreaker tests also included (state machine with time-based transitions — may need clock injection).
- **D-09:** These are proof-of-life tests beyond the minimum success criteria. Phase 20 adds comprehensive coverage for decomposed components.

### Claude's Discretion

- Whether to create a `CompanionApp` class vs a `bootstrap()` function for the coordinator pattern
- Internal organization of test files (one file per type vs grouped)
- Whether CircuitBreaker tests need a clock abstraction or can use short real-time intervals

</decisions>

<canonical_refs>

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Source Code (current state)

- `plugins/claude-tts-companion/Package.swift` — Current single-target SwiftPM manifest (must add library + test targets)
- `plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift` — Current 350-line entry point (extraction source)
- `plugins/claude-tts-companion/Sources/claude-tts-companion/LanguageDetector.swift` — Pure type, test target
- `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleChunker.swift` — Pure type, test target
- `plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramFormatter.swift` — Pure type, test target
- `plugins/claude-tts-companion/Sources/claude-tts-companion/TranscriptParser.swift` — Pure type, test target
- `plugins/claude-tts-companion/Sources/claude-tts-companion/CircuitBreaker.swift` — State machine, test target

### Project Context

- `.planning/ROADMAP.md` — Phase 18 success criteria (ARCH-01, TEST-01)
- `.planning/REQUIREMENTS.md` — ARCH-01, TEST-01 requirement definitions

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- 25 Swift files in `Sources/claude-tts-companion/` — all move to `Sources/CompanionCore/`
- `main.swift` stays in `Sources/claude-tts-companion/` (executable target)

### Established Patterns

- `nonisolated(unsafe)` for global state (Swift 6 strict concurrency)
- `DispatchQueue` for background work (not yet actors — that's Phase 19)
- Callback-based APIs (e.g., `TTSEngine.synthesizeWithTimestamps` takes completion handler)
- `Config` struct holds all constants (paths, ports, app name)

### Integration Points

- `Package.swift` needs: `.library(name: "CompanionCore", ...)` target + `.testTarget(name: "CompanionCoreTests", ...)`
- All dependencies (swift-telegram-sdk, swift-log, FlyingFox, kokoro-ios, MLX) move to the library target
- Executable target depends only on CompanionCore + AppKit + Foundation

</code_context>

<specifics>
## Specific Ideas

### main.swift Target Shape

```swift
// main.swift (~50 lines)
import CompanionCore
import AppKit

setbuf(stdout, nil)
setbuf(stderr, nil)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let companion = CompanionApp()
companion.start()

// SIGTERM handler
let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
sigSource.setEventHandler {
    companion.shutdown()
    app.stop(nil)
}
sigSource.resume()

app.run()
```

### File Move Plan

All 25 `.swift` files except `main.swift` move from `Sources/claude-tts-companion/` to `Sources/CompanionCore/`. No renames needed — just directory move + access control additions.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

_Phase: 18-companioncore-library-test-infrastructure_
_Context gathered: 2026-03-28_
