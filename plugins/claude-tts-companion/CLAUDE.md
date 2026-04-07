# claude-tts-companion

Unified macOS accessory app for real-time karaoke subtitles synced with TTS playback. Replaces three separate processes (TypeScript Telegram bot + Python TTS server + Swift subtitle prototype) with a single Swift binary.

**Hub:** [CLAUDE.md](../../CLAUDE.md) | **Sibling:** [plugins/CLAUDE.md](../CLAUDE.md)

## Build

```bash
cd plugins/claude-tts-companion
swift build -c release
```

Release binary at `.build/release/claude-tts-companion` (~18MB stripped).

## Critical Invariants (DO NOT VIOLATE)

These are load-bearing decisions from prior incidents. Future changes MUST respect them.

### 1. Audio playback uses `afplay` subprocess — NOT AVAudioPlayer

**`AfplayPlayer.swift` chains `posix_spawn(afplay)` subprocesses for pipelined per-segment playback. This is intentional structural isolation, not convenience.**

- **What not to do**: "simplify" by replacing the subprocess chain with `AVAudioPlayer.init(data:)` or `AVAudioEngine + AVAudioPlayerNode`.
- **Why**: AVAudioPlayer/AVAudioEngine was the _previous_ implementation. It was abandoned because even **initializing** `AVAudioEngine` in the same process polluted CoreAudio hardware state enough to cause audio jitter under CPU contention (concurrent Swift compilation, MLX/Metal spikes). Subprocess isolation via `afplay` makes the audio path unaffected by in-process GPU/CPU pressure.
- **Evidence**: Git commits `e2e80e1e`, `2be60672`, `c3525c2e`, `815844e2` — search `git log --oneline -- plugins/claude-tts-companion/Sources/CompanionCore/AfplayPlayer.swift` for the retreat from AVFoundation.
- **Canonical research doc**: `.planning/quick/260407-h07-antifragile-fix-for-afplayplayer-wav-wri/260407-h07-RESEARCH.md` — the 2026-04-07 research that re-validated this decision.

### 2. Filesystem side-effects use self-healing fallback chains — NOT silent `try?`

**`AfplayPlayer.ensureWritableWavDirectory()` walks a three-tier chain on every write: primary (`~/.local/share/tts-debug-wav/`) → `NSTemporaryDirectory() + "claude-tts-wav/"` → `mkstemp(3)` ultimate fallback. Failure-class telemetry collapses identical errors to ≤1 log per class per 60s with recovery events.**

- **What not to do**: write `try? FileManager.default.createDirectory(...)` anywhere in `Sources/`. A codebase-wide grep must return zero hits.
- **Why**: On 2026-04-06 the primary WAV directory disappeared (cause still unknown) and every TTS request silently failed at the WAV-write stage for 50+ minutes — 25+ identical `NSPOSIXErrorDomain Code=2` log lines, zero recovery. The subtitles still rendered (in-memory samples) but no audio played. The failure was a `try? createDirectory` at init-time swallowing the error, then no re-check on subsequent writes.
- **Pattern to follow**: `AfplayPlayer.ensureWritableWavDirectory()` + `AfplayPlayer.recordFailure(classify:)` + `/health.afplay` snapshot. This is the canonical antifragile pattern for filesystem side-effects in this codebase. Copy it when adding new side-effect-producing code.
- **Chaos test**: `Tests/CompanionCoreTests/AfplayPlayerChaosTests.swift` — rm-the-dir-mid-playback tests. Any new filesystem side-effect should add a similar chaos test.
- **Original incident**: `.planning/debug/tts-no-audio-260406.md`
- **Fix rationale + pattern docs**: `.planning/quick/260407-h07-antifragile-fix-for-afplayplayer-wav-wri/` (RESEARCH.md, PLAN.md, SUMMARY.md, VERIFICATION.md)

### 3. PythonTimestampResponse uses explicit CodingKeys — NOT `.convertFromSnakeCase`

**The JSON decoder for the Kokoro Python HTTP response uses an explicit `CodingKeys` enum mapping camelCase Swift properties to snake_case JSON keys.**

- **What not to do**: set `decoder.keyDecodingStrategy = .convertFromSnakeCase` on any shared `JSONDecoder`. It would silently affect other Codable types in ways that are hard to audit.
- **Why**: Explicit mapping is self-documenting and scoped. Changed on 2026-04-06 (commit `af9698be`) to eliminate the `audio_b64`/`audioDuration` dual-naming drift.
- **File**: `Sources/CompanionCore/TTSEngine.swift`, struct `PythonTimestampResponse`

## Architecture

- **CSherpaOnnx** -- C module target wrapping sherpa-onnx headers via `module.modulemap`. Vendored `c-api.h` header enables `import CSherpaOnnx` from Swift without system-level pkg-config.
- **NSApp Accessory** -- `NSApplication.shared` with `.accessory` activation policy (no dock icon, no app switcher). Runs as a background service under launchd.
- **SIGTERM Handling** -- `DispatchSource.makeSignalSource` for clean shutdown. Dummy `NSEvent.otherEvent` posted to unblock the run loop after `app.stop()`.
- **swift-telegram-sdk** -- Long-polling Telegram bot via `TGClientPrtcl` (URLSession, no Vapor/SwiftNIO).
- **Logging** -- `swift-log` with `StreamLogHandler.standardError` for launchd stderr capture.
- **Audio Playback** -- `AfplayPlayer` chains `posix_spawn(afplay)` subprocesses for pipelined per-segment playback (not AVAudioPlayer — see Critical Invariant 1). Self-healing WAV directory fallback chain + collapsed failure telemetry (Critical Invariant 2).

## Dependencies

| Package            | Version     | Purpose              |
| ------------------ | ----------- | -------------------- |
| swift-telegram-sdk | 4.5.0       | Telegram Bot API     |
| swift-log          | 1.6.0+      | Structured logging   |
| sherpa-onnx        | static libs | Kokoro TTS synthesis |

## Key Files

| File                                        | Purpose                                                    |
| ------------------------------------------- | ---------------------------------------------------------- |
| `Package.swift`                             | SwiftPM manifest with all dependencies and linker settings |
| `Sources/CSherpaOnnx/`                      | C module target for sherpa-onnx header interop             |
| `Sources/claude-tts-companion/main.swift`   | NSApplication accessory entry point with SIGTERM handling  |
| `Sources/claude-tts-companion/Config.swift` | Centralized path and configuration constants               |

<!-- GSD:project-start source:PROJECT.md -->

## Project

**claude-tts-companion — Notification Intelligence Milestone**

A unified macOS accessory app that monitors Claude Code sessions and delivers real-time summaries via Telegram, TTS audio, and karaoke subtitles. Replaces three separate processes (Swift runner + Bun/TypeScript bot + Python TTS server) with a single ~18MB binary running under launchd. The companion watches session transcript files, summarizes them via MiniMax, and delivers through multiple "Outlets" (Telegram, TTS, subtitles).

**Core Value:** **Every session end produces an accurate, self-explanatory notification** — the user should understand what happened without opening Claude Code. Summaries must reflect the _actual last work done_, not stale intermediate state.

### Constraints

- **Platform**: macOS Apple Silicon only (sherpa-onnx requires ARM64)
- **macOS version**: 14+ (swift-telegram-sdk requirement)
- **Build**: `swift build` via SwiftPM, NOT Xcode
- **Binary**: Single binary at `~/.local/bin/claude-tts-companion`
- **Deploy**: `make` handles build + deploy + restart
- **Python dependency**: Kokoro TTS server on port 8779 must remain (companion delegates English TTS)
- **No breaking changes**: Telegram message format must stay compatible (users have muscle memory for buttons)
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->

## Technology Stack

## Languages

- **Swift** 6.0+ - Main language for the entire application; unified single binary replacing three separate runtimes (TypeScript bot + Python TTS + Swift prototype)
- **C/C++** - sherpa-onnx library integration via static C API bindings
- **Objective-C** - macOS AppKit framework interaction (NSPanel, NSApplication, AVFoundation)

## Runtime

- **macOS** 14+ (Apple Silicon)
- **SwiftPM** (swift-tools-version: 6.0)
- **Swift Compiler** 6.0+
- Run command: `swift build -c release`
- Release binary: `.build/release/claude-tts-companion` (~18-25 MB stripped)

## Frameworks

- **AppKit** (linked) - NSApplication (accessory activation policy), NSPanel (always-on-top subtitle overlay), NSAttributedString (karaoke highlighting)
- **AVFoundation** (linked) - AVAudioPlayer is linked but used only for non-pipelined hardware warm-up / silent audio; primary playback path is `posix_spawn(afplay)` subprocess chain via `AfplayPlayer.swift` (see Critical Invariant 1)
- **Foundation** (linked) - Core Networking, File I/O, Logging, Concurrency
- **swift-telegram-sdk** 4.5.0 - Telegram Bot API wrapper (long polling, message sending, inline buttons)
- **FlyingFox** 0.26.2 - Lightweight async/await HTTP server (zero dependencies, BSD sockets wrapper)
- **swift-log** 1.10.1 - Apple's standard logging facade
- **swift-testing** 0.99.0 - Modern Swift testing framework

## Key Dependencies

- **sherpa-onnx** 1.12.33 (static linking)
- **swift-custom-logger** 1.1.1
- **swift-regular-expression** 0.2.4
- **swift-syntax** 600.0.1 (macro expansion, not used directly)

## Configuration

- launchd plist: `launchd/com.terryli.claude-tts-companion.plist`
- Service label: `com.terryli.claude-tts-companion`
- Install path: `$HOME/.local/bin/claude-tts-companion`
- Logs: `$HOME/.local/state/launchd-logs/claude-tts-companion/stderr.log`
- `HOME` - User home directory
- `PATH` - Shim PATH for mise + Homebrew + system bins
- `SHERPA_ONNX_PATH` - sherpa-onnx build install directory (for .dylib discovery if not static)
- `KOKORO_MODEL_PATH` - Model directory (default: `$HOME/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0`)
- `TELEGRAM_BOT_TOKEN` - Bot token (empty in plist, populated via launchctl setenv)
- `TELEGRAM_CHAT_ID` - Notification target chat ID
- `MINIMAX_API_KEY` - API key for summary generation
- `STREAMING_TTS` - Streaming sentence-chunked TTS (default: true)
- `KOKORO_TTS_SERVER_URL` - Python Kokoro MLX server (default: `http://127.0.0.1:8779`)
- `CLAUDE_NOTIFICATION_DIR` - Claude Code notification JSON files (default: `$HOME/.claude/notifications`)
- `CLAUDE_PROJECTS_DIR` - Transcript JSONL files (default: `$HOME/.claude/projects`)
- Model-specific env overrides: `KOKORO_MLX_MODEL_PATH`, `KOKORO_VOICES_PATH`, `MLX_METALLIB_PATH`, `KOKORO_MODEL_PATH`
- SwiftPM manifest: `Package.swift` (swift-tools-version 6.0)
- Dependencies resolved: `Package.resolved` (locked versions)
- Linker flags: unsafe C library linking (14 static libs) in CompanionCore target
- No `.swiftformat`, `.swiftlint`, or other formatters configured (architecture pre-Swift 5.8 lint)

## Platform Requirements

- macOS 14+ with Apple Silicon (arm64)
- Swift 6.0+ toolchain
- sherpa-onnx fork built locally (`/Users/terryli/fork-tools/sherpa-onnx/build-swift-macos/install/`)
- Kokoro int8 model at `~/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0/` (~260MB)
- macOS 15+ (actual deployment target)
- Process type: Adaptive (auto-suspend when idle)
- Memory limit: 8 GB soft limit (plist line 46)
- Exit timeout: 15 seconds for clean shutdown (plist line 23)
- Restart behavior: KeepAlive with NetworkState true, SuccessfulExit false (respawn on crash, not on clean exit)
- Stderr logging: ASL/Console.app via launchd
- Network dependency: Requires internet for Telegram long polling + MiniMax API
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

## Naming Patterns

- CamelCase with descriptive names: `CircuitBreaker.swift`, `SubtitleChunker.swift`, `TTSPipelineCoordinator.swift`
- Postfix-descriptive for supporting modules: `TelegramBotCallbacks.swift`, `TelegramBotCommands.swift`, `TelegramFormatterFencing.swift`
- Functional modules (not types) use simple lowercase: `main.swift`, `module.modulemap` (C interop)
- camelCase starting with lowercase: `chunkIntoPages()`, `recordFailure()`, `play()`, `splitIntoSentences()`
- Verb-first for actions: `checkPythonServerHealth()`, `recordSuccess()`, `auditAudioRouting()`
- Property accessors use descriptive names: `isOpen`, `audioRoutingClean`, `isTTSCircuitBreakerOpen`
- Static factory functions: `from(string:)` returns enum instances
- camelCase: `logger`, `urlSession`, `playbackManager`, `wavPath`, `wordTimings`
- Private properties use `_` prefix where semantics matter (rare; mostly avoided)
- Module references: `settingsStore`, `subtitlePanel`, `sherpaOnnxEngine` (noun-based)
- Classes: `CircuitBreaker`, `TTSEngine`, `PlaybackManager` (final classes marked explicitly)
- Enums: `DisplayMode`, `TTSError`, `SummaryError` (PascalCase, concise names)
- Structs: `SynthesisResult`, `TTSResult`, `SubtitlePage` (noun-based, no "Result" suffix for most)
- Protocols: Use action/interface names (e.g., `Sendable`, `CustomStringConvertible`)

## Code Style

- No external formatter (SwiftFormat/Prettier not configured)
- 2-space indentation (inferred from standard Swift)
- Line length: no hard limit observed; pragmatic wrapping at logical boundaries (parameters, closures)
- Trailing commas in multiline collections observed but inconsistent
- No linter configuration found (no .swiftlint.yml, eslint, biome.json)
- Code quality enforced via code review and Swift 6 strict concurrency checking
- MARK comments used liberally to organize large files: `// MARK: - Lifecycle`, `// MARK: - Public API`, `// MARK: - TTS Circuit Breaker`
- Swift 6 strict concurrency with actor isolation (not @unchecked Sendable carelessly)
- `@MainActor` for UI-bound classes: `SubtitlePanel`, `BionicRenderer.render()`, `PlaybackManager`
- Actor-isolated classes for background work: `TTSEngine`, `SummaryEngine`, `MiniMaxClient`
- `@unchecked Sendable` used sparingly with clear comments: `CompanionApp: @unchecked Sendable` with lifetime management for SIGTERM handler
- `nonisolated(unsafe)` for global keepAlive references in main.swift (documented as anti-pattern with fallback reason)

## Import Organization

- Not observed; no target aliases or custom import paths used

## Error Handling

- Explicit error enums with `CustomStringConvertible`: `TTSError`, `SummaryError`
- Associated values for context: `.apiError(statusCode: Int, body: String)`
- Human-readable descriptions in switch cases (no generic "Unknown error")
- Errors propagated via `throws`, caught with `do/catch`, logged with `logger.warning()` or `logger.error()`
- Circuit breaker pattern for API failures (TTSEngine, SummaryEngine): fail fast after N consecutive failures, cooldown before retry
- Async tasks wrapped with `Task { do { ... } catch { logger.error(...) } }` (fire-and-forget patterns used sparingly)
- `TTSError`: synthesis, server unavailability, circuit breaker state
- `SummaryError`: circuit breaker, missing API key, decoding failures
- URLError: network transport errors (wrapped in higher-level errors)

## Logging

- Logger created per class: `private let logger = Logger(label: "module-name")`
- Structured logging: `logger.info("Message")`, `logger.warning(...)`, `logger.error(...)`
- Context-rich messages: include affected resource names, counts, paths
- Examples:
- Startup/shutdown: service lifecycle events
- State transitions: circuit breaker open/close, audio hardware warm-up
- Errors: always log with context
- Performance: model load times, synthesis latency
- Do NOT log per-word: karaoke highlighting timestamp updates (high frequency)

## Comments

- File-level comments for large classes: explain purpose, isolation model, ownership
- Method-level comments: document preconditions, async behavior, lifetime implications
- Inline comments: clarify non-obvious logic (e.g., "Pitfall 5: buffer unbuffering for launchd")
- Skip obvious comments: `let count = words.count` needs no explanation
- Triple-slash comments used for public APIs: `/// Compute the number of characters to bold for a given word.`
- Multiline doc comments document parameters, return values, error cases
- Examples in code comments where algorithm is non-obvious
- Document why, not what: `/// Subclass AVAudioPlayer with weak timingDelegate...` (explains design intent)
- Comments cite spikes: `// FILE-SIZE-OK -- actor with HTTP client...` (references design decision)
- Comments cite external ADRs: `// (CJK-01)`, `// (D-01)`, `// (P1)` (sync with project CLAUDE.md)

## Function Design

- Typical range: 10-50 lines for public methods, 5-30 for helpers
- Larger functions (100+ lines) broken into sections with `// MARK: -` comments
- One responsibility per function: `recordFailure()` only manages failure count, not logging
- Named parameters required: `chunkIntoPages(text:fontSizeName:)` (clarity over brevity)
- Default values for optional settings: `fontSizeName: String = "medium"`
- Closures in trailing position: `completion: (() -> Void)? = nil`
- Inline documentation for parameters: `// Path aliases used` style comments before signature
- Explicit optional types when nil is meaningful: `AVAudioPlayer?` signals "may fail to load"
- Tuple returns for related values: `(sentences: [String], pages: [[SubtitlePage]], timings: [[TimeInterval]])`
- Structs preferred over tuples for public APIs: `TTSResult` bundles path, text, timings, duration

## Module Design

- Classes/enums/structs marked `public` explicitly for library boundary (not internal default)
- Properties marked `private` or `private(set)` (default private in final classes)
- No namespace pollution: each module exports cohesive set of types
- `public final class CircuitBreaker` (immutable lifecycle, sendable)
- `public enum DisplayMode: String, Codable, Sendable` (value type, encoding support)
- `public struct TTSResult: Sendable` (lightweight data container)
- Not observed; no `__init__.swift` or index exports
- Imports are granular (import specific types as needed)
- Value types conform automatically: `struct`, `enum` with `Sendable` members
- Classes require explicit conformance: `final class CircuitBreaker: @unchecked Sendable` (NSLock not Sendable)
- Comment rationale: `// Thread-safe via NSLock (matching TTSEngine pattern)` explains why @unchecked is safe

## Async/Await Patterns

- Background work via `Task { await ... }` in initializers and lifecycle events
- No task cancellation tracking observed (fire-and-forget model)
- Example: `Task { await ttsEngine.checkPythonServerHealth() }` in CompanionApp.start()
- Return types for async work: `async func synthesize(text:) async throws -> TTSResult`
- No backpressure/semaphore observed (Python server handles queuing)
- Timeout via URLSessionConfiguration: `config.timeoutIntervalForRequest`
- Actor-isolated properties accessed via `await` from other actors
- Same-actor access is synchronous (no await needed)
- Cross-actor calls explicit: `await ttsEngine.synthesize(...)`
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

## Pattern Overview

- Single Swift binary runs as macOS background service (launchd) with no UI chrome
- Multi-actor concurrency model using Swift's strict concurrency checking (Swift 6)
- Unified interface between Telegram bot, Python TTS server, and subtitle overlay
- File-system-driven notification processing with dedup and rate limiting
- HTTP control plane (FlyingFox) for remote configuration and diagnostics

## Layers

- Purpose: NSApplication lifecycle management with SIGTERM handler for clean shutdown
- Location: `Sources/claude-tts-companion/main.swift`
- Contains: NSApplication initialization, signal handling, run loop execution
- Depends on: CompanionApp (core coordinator)
- Used by: launchd via installed binary at `~/.local/bin/claude-tts-companion`
- Purpose: Owns and wires all subsystems; single source of truth for component lifetimes
- Location: `Sources/CompanionCore/CompanionApp.swift`
- Contains: Subsystem initialization order, start/shutdown orchestration, notification dispatch
- Depends on: All lower layers (SettingsStore, SubtitlePanel, PlaybackManager, TTSEngine, etc.)
- Used by: main.swift (entry point receives CompanionApp instance)
- Purpose: Ingest events from Claude Code sessions (JSONL files) and Telegram commands
- Location: `NotificationWatcher.swift`, `TelegramBot.swift`, `NotificationProcessor.swift`
- Contains: Directory polling (2s interval), JSON file parsing, Telegram long-polling, dedup/rate-limit gates
- Depends on: CompanionApp (for callback dispatch), TelegramBot (for command handling)
- Used by: CompanionApp.start() to monitor incoming notifications
- Purpose: Orchestrate text→audio conversion via Python Kokoro server and sherpa-onnx
- Location: `TTSEngine.swift`, `SherpaOnnxEngine.swift`, `TTSQueue.swift`, `TTSPipelineCoordinator.swift`
- Contains: HTTP client for Python server, circuit breaker, sentence-chunked streaming, priority-aware queuing, language detection
- Depends on: PlaybackManager (for audio hardware), Config (for paths and URLs)
- Used by: TTSQueue (serializes work), CompanionApp (init), TelegramBot (Telegram TTS commands)
- Purpose: Low-level audio playback using AVAudioPlayer and afplay subprocess
- Location: `PlaybackManager.swift`, `AfplayPlayer.swift`, `AudioStreamPlayer.swift`, `PlaybackDelegate.swift`
- Contains: Player lifecycle, hardware warm-up, WAV file cleanup, afplay subprocess management
- Depends on: Config (for silent audio generation)
- Used by: TTSEngine, TTSQueue, SubtitleSyncDriver (for sync timing)
- Purpose: Always-on-top floating panel with word-level karaoke highlighting
- Location: `SubtitlePanel.swift`, `SubtitleStyle.swift`, `SubtitleBorder.swift`, `SubtitleClipboard.swift`, `SubtitlePosition.swift`, `DisplayMode.swift`
- Contains: NSPanel with karaoke state machine, word highlighting, bionic rendering, position/opacity/font settings
- Depends on: SettingsStore (for user preferences), PlaybackManager (for sync timing via currentTime polling)
- Used by: CompanionApp (positionOnScreen), HTTPControlServer (show/hide), TelegramBot (display formatted messages)
- Purpose: REST API for configuration, diagnostics, and remote TTS triggering
- Location: `HTTPControlServer.swift`
- Contains: Health endpoint (uptime, RSS, subsystem status), PATCH endpoints for settings, POST endpoints for TTS/subtitle control
- Depends on: All subsystems (for state query and control)
- Used by: External clients (SwiftBar, curl, etc.) on localhost:8780
- Purpose: Command parsing, inline button callbacks, Markdown formatting for session output
- Location: `TelegramBotCommands.swift`, `TelegramBotCallbacks.swift`, `TelegramBotNotifications.swift`, `TelegramFormatter.swift`, `TelegramFormatterFencing.swift`, `TelegramFormatterFileRefs.swift`
- Contains: /start, /stop, /status, /prompt handlers; fenced code block formatting; file reference extraction
- Depends on: TelegramBot (actor-isolated bot reference), PromptExecutor (for /prompt commands)
- Used by: TelegramBot via dispatcher pattern (BotDispatcher)
- Purpose: Third-party API clients and adapters
- Location: `MiniMaxClient.swift`, `SummaryEngine.swift`, `AutoContinue*.swift`, `ClaudeProcess.swift`
- Contains: MiniMax API client for summaries, extended thinking integration, Claude CLI subprocess wrapper
- Depends on: URLSession (for HTTP), Foundation (for subprocess)
- Used by: CompanionApp (initialize), NotificationProcessor (route to summaries)

## Data Flow

- **SettingsStore:** Persisted to `~/.config/claude-tts-companion/settings.json`, queried by SubtitlePanel and HTTPControlServer on every change
- **CaptionHistory:** In-memory circular buffer (max 500 entries), populated by TTSQueue on synthesis completion
- **Karaoke State:** SubtitlePanel holds `words: [String]`, `wordTimings: [TimeInterval]`, `generation: Int` (generation counter to cancel stale scheduling)
- **Audio Hardware State:** PlaybackManager tracks `lastPlaybackTime` and `audioHardwareWarmed` for idle re-warm
- **Dedup/Rate-Limit State:** NotificationProcessor holds `processedSessions: [sessionId: (processedAt, transcriptSize)]`

## Key Abstractions

- Purpose: Encapsulates synthesis output (WAV path, text, word timings, audio duration)
- Examples: `Sources/CompanionCore/TTSEngine.swift` (line 21), returned by TTSEngine.synthesize()
- Pattern: Immutable Sendable struct for cross-actor communication
- Purpose: Priority-aware FIFO queue that serializes GPU access (single worker)
- Examples: `Sources/CompanionCore/TTSQueue.swift`
- Pattern: Actor enforces serial access; cooperative cancellation tokens for in-flight work
- Purpose: Immutable snapshot of a displayed caption (text, timestamp, speaker, duration)
- Examples: `Sources/CompanionCore/CaptionHistory.swift`
- Pattern: Used by CaptionHistory for circular buffer; exposed via HTTP /captions endpoint
- Purpose: Thread-safe persistent key-value store for user preferences
- Examples: `Sources/CompanionCore/SettingsStore.swift` (subtitle position, font size, opacity, TTS voice/speed)
- Pattern: Read-through cache with on-change callbacks; Codable JSON serialization
- Purpose: Tracks consecutive failures and disables operation under load
- Examples: `Sources/CompanionCore/CircuitBreaker.swift`, used by TTSEngine
- Pattern: Half-open state resets on successful operation; exponential backoff cooldown
- Purpose: Copies displayed text + UUID to pasteboard for SwiftBar integration
- Examples: `Sources/CompanionCore/SubtitleClipboard.swift`
- Pattern: Called by SubtitlePanel.show(); integrates with SwiftBar via environment variable injection
- Purpose: Gates session notifications with transcript-size-based dedup and 5s rate limiting
- Examples: `Sources/CompanionCore/NotificationProcessor.swift` (REL-01, REL-02)
- Pattern: Stateful gate with locking; pending file retry via DispatchSourceTimer
- Purpose: Bionic reading format (bold first half of words for faster scanning)
- Examples: `Sources/CompanionCore/BionicRenderer.swift`, triggered by DisplayMode.bionic
- Pattern: Converts word list to NSAttributedString with opacity-based emphasis

## Entry Points

- Location: `Sources/claude-tts-companion/main.swift`
- Triggers: `launchctl bootstrap` or `swift build -c release && ./.build/release/claude-tts-companion`
- Responsibilities: Configure logging, create NSApplication, initialize CompanionApp, handle SIGTERM, run event loop
- Location: `Sources/CompanionCore/CompanionApp.swift` → start()
- Triggers: Called from main.swift after app.run() begins
- Responsibilities: Audit audio routing, health-check Python server, start HTTP server, start Telegram bot, start NotificationWatcher, position SubtitlePanel
- Location: `Sources/CompanionCore/CompanionApp.swift` → handleNotification(filePath)
- Triggers: NotificationWatcher finds new .json in ~/.claude/notifications/
- Responsibilities: Parse notification, check dedup, rate-limit, route to appropriate handler (session TTS, thinking summary, etc.)
- Location: `Sources/CompanionCore/HTTPControlServer.swift`
- Triggers: External HTTP requests on localhost:8780
- Responsibilities: Query state, modify settings, control playback, return diagnostics
- Location: `Sources/CompanionCore/TelegramBotCommands.swift`
- Triggers: User sends /start, /stop, /status, /health, /prompt, /done, /sessions, /commands
- Responsibilities: Execute command logic, format response, send via bot.sendMessage()

## Error Handling

- **Circuit Breaker (TTS):** TTSEngine tracks 3 consecutive failures; disables synthesis for 30s cooldown, then retries. Failures logged but don't crash service. Subsequent synthesis requests fail fast until cooldown expires.
- **Python Server Unavailability:** TTSEngine.checkPythonServerHealth() retries 6 times (30s total) at startup. If unreachable, logs warning and sets `pythonServerWarning = true`. Synthesis requests still attempted (server could come up), but caller informed via health endpoint.
- **Telegram Connection Loss:** TelegramBot.start() wrapped in try/catch; failure logged as warning. Service continues without bot. HTTPControlServer still functional. User can restart bot via HTTP endpoint or check status.
- **Audio Hardware Failure:** PlaybackManager.play() catches AVAudioPlayer init errors; logs warning and returns nil. Playback skipped but TTS synthesis still completed (file written). Caller sees no audio but captions still displayed.
- **Notification File I/O:** CompanionApp.handleNotification() catches JSON decode, file read, transcript parse errors. Each error logged at appropriate level (debug, info, warning). Notification skipped, process continues.
- **Subprocess Timeouts:** PromptExecutor /prompt commands timeout after 120s. Response formatted as "Command timed out". ClaudeProcess.run() catches subprocess errors.
- **Memory Pressure:** TTSPipelineCoordinator monitors memory warnings via DispatchSource; triggers early unload of sherpa-onnx model if RSS > 1GB.

## Cross-Cutting Concerns

- Framework: `swift-log` with `StreamLogHandler.standardError`
- Configuration: `LoggingSystem.bootstrap()` in main.swift
- Pattern: Each subsystem creates `Logger(label: "subsystem-name")`; all logs go to stderr (captured by launchd)
- Structured logging: Use logger.info/warning/error with contextual messages
- TTSQueue validates text length before enqueuing
- SentenceSplitter validates sentence boundaries
- LanguageDetector validates CJK character ratios (REL-03)
- TranscriptParser validates JSONL format (each line is valid JSON)
- HTTPControlServer validates request bodies (Codable deserialization)
- HTTP API: localhost-only binding (no credentials required)
- Telegram: Bot token from Config.telegramBotToken environment variable
- Python TTS server: localhost-only, token-less
- MiniMax API: API key from Config.miniMaxApiKey environment variable
- CompanionApp @MainActor ensures single-threaded subsystem initialization
- PlaybackManager @MainActor (AVAudioPlayer callbacks fire on main thread)
- SubtitlePanel @MainActor (NSPanel AppKit APIs)
- TTSQueue actor (isolates synthesis queue state)
- TTSEngine actor (isolates HTTP client and circuit breaker)
- TelegramBot @unchecked Sendable with internal NSLock for mutable state
- All subsystems use Sendable types for cross-isolation data (TTSResult, SettingsStore.settings, etc.)
- WAV files deleted by PlaybackDelegate after playback or timeout
- sherpa-onnx model unloaded after 30s idle (Config.sherpaOnnxIdleTimeoutSeconds)
- NotificationProcessor.pruneExpiredEntries() called periodically to unbind dedup entries older than 30 minutes
- HTTP server gracefully stops on shutdown via httpServer.stop()
- Telegram bot stops via TelegramBot.stop()
- All DispatchSource and timers canceled in shutdown flow
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.

<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.

<!-- GSD:profile-end -->
