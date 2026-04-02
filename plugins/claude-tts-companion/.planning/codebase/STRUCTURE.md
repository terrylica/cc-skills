# Codebase Structure

**Analysis Date:** 2026-04-02

## Directory Layout

```
plugins/claude-tts-companion/
├── .planning/                           # GSD planning artifacts
│   └── codebase/                        # This documentation (ARCHITECTURE.md, STRUCTURE.md)
├── Sources/                             # All Swift source code
│   ├── claude-tts-companion/            # Executable target (entry point)
│   │   └── main.swift                   # NSApplication init, SIGTERM handler, run loop
│   └── CompanionCore/                   # Library target (all business logic)
│       ├── CompanionApp.swift           # Top-level coordinator, subsystem wiring
│       ├── Config.swift                 # Centralized config (paths, URLs, constants)
│       ├── main subsystems/             # Core services (TTS, playback, UI, messaging)
│       ├── telegram support/            # Bot commands, formatting, callbacks
│       ├── text processing/             # Parsing, chunking, language detection
│       ├── audio layer/                 # Playback, subtitle sync, audio hardware
│       └── integration/                 # External APIs (MiniMax, Claude CLI)
├── Sources/CSherpaOnnx/                 # C module for sherpa-onnx header interop
│   ├── include/                         # Public C headers
│   └── module.modulemap                 # Maps C headers to Swift import CSherpaOnnx
├── Tests/                               # Swift Testing test suite
│   └── CompanionCoreTests/              # Unit tests for all major components
├── launchd/                             # Service configuration
│   └── com.terryli.claude-tts-companion.plist
├── scripts/                             # Utility scripts
├── Package.swift                        # SwiftPM manifest (dependencies, targets, linker flags)
├── Package.resolved                     # Locked dependency versions
├── Makefile                             # Build, deploy, restart automation
└── CLAUDE.md                            # Plugin-level documentation

```

## Directory Purposes

**Sources/claude-tts-companion/:**

- Purpose: Executable target — produces the `claude-tts-companion` binary
- Contains: Only `main.swift` (ultra-thin entry point)
- Key files: `main.swift` (43 lines: NSApp init, signal handling, run loop)

**Sources/CompanionCore/:**

- Purpose: Library target — contains all business logic and subsystems
- Contains: 53 .swift files organized by functional domain
- Key files: See "Key File Locations" section below

**Sources/CSherpaOnnx/:**

- Purpose: C module target for sherpa-onnx interop (C headers → Swift)
- Contains: `include/` subdirectory with vendored C header files
- Key files: `module.modulemap` (tells compiler how to map C headers)
- Note: Actual sherpa-onnx libraries (.a files) linked via `linkerSettings` in Package.swift

**Tests/CompanionCoreTests/:**

- Purpose: Unit tests using Swift Testing framework (@Test macro)
- Contains: 10 test files covering parsers, formatters, renderers, algorithms
- Files: `TranscriptParserTests.swift`, `SentenceSplitterTests.swift`, `TelegramFormatterTests.swift`, etc.

**launchd/:**

- Purpose: macOS launchd service configuration
- Contains: Single plist file defining service behavior
- Key file: `com.terryli.claude-tts-companion.plist` (KeepAlive, ProcessType, environment vars)

**scripts/:**

- Purpose: Build and deployment utilities
- Contains: Shell scripts for pre-build setup, validation, etc.

## Key File Locations

**Entry Points:**

- `Sources/claude-tts-companion/main.swift`: NSApplication lifecycle, SIGTERM handler, event loop. Called by launchd via `~/.local/bin/claude-tts-companion`.
- `Sources/CompanionCore/CompanionApp.swift`: Core coordinator. Called from main.swift; owns all subsystems and orchestrates start/shutdown.

**Configuration:**

- `Sources/CompanionCore/Config.swift`: Centralized constants (paths, URLs, timeouts, model IDs, API keys). All subsystems read from Config enum; environment variables override defaults.
- `launchd/com.terryli.claude-tts-companion.plist`: launchd service manifest. Defines binary path, environment variables, log file paths, resource limits. Managed by `launchctl bootstrap/bootout`.
- `Package.swift`: SwiftPM manifest. Declares dependencies (swift-telegram-sdk, swift-log, FlyingFox), targets (CSherpaOnnx, CompanionCore, executable), linker flags for sherpa-onnx libraries.

**Core Logic (TTS Pipeline):**

- `Sources/CompanionCore/TTSEngine.swift`: HTTP client for Python Kokoro server. Routes English to Python, CJK to sherpa-onnx. Implements circuit breaker, word timing parsing.
- `Sources/CompanionCore/TTSQueue.swift`: Priority-aware FIFO queue. Serializes synthesis/playback. Cancels in-flight work on userInitiated requests.
- `Sources/CompanionCore/SherpaOnnxEngine.swift`: Sherpa-onnx C API wrapper. On-demand model loading with 30s idle unload.
- `Sources/CompanionCore/SentenceSplitter.swift`: Splits text into synthesis-sized sentences (balanced for latency vs. natural chunking).
- `Sources/CompanionCore/TTSPipelineCoordinator.swift`: Orchestrates playback + karaoke sync. Monitors memory pressure, audio hardware health.

**Audio & Playback:**

- `Sources/CompanionCore/PlaybackManager.swift`: Owns AVAudioPlayer lifecycle. Delegates afplay for actual playback (avoids jitter). Warm-up logic, idle timeout.
- `Sources/CompanionCore/AfplayPlayer.swift`: Spawns afplay subprocess for jitter-free playback (used instead of AVAudioEngine).
- `Sources/CompanionCore/AudioStreamPlayer.swift`: AVAudioEngine-based gapless streaming (not currently used for TTS; kept for future use).
- `Sources/CompanionCore/PlaybackDelegate.swift`: Delegate for AVAudioPlayer completion callbacks. Cleans up WAV files after playback or timeout.
- `Sources/CompanionCore/SubtitleSyncDriver.swift`: Polls AVAudioPlayer.currentTime at 6ms interval; drives karaoke highlighting in SubtitlePanel.

**Subtitle Display:**

- `Sources/CompanionCore/SubtitlePanel.swift`: NSPanel floating overlay. Owns karaoke state machine (words, timings, generation counter). Renders text or attributed string (bionic mode).
- `Sources/CompanionCore/SubtitleStyle.swift`: Constants for fonts, colors, spacing, opacity, truncation behavior.
- `Sources/CompanionCore/SubtitleBorder.swift`: Animated rainbow gradient border for the panel.
- `Sources/CompanionCore/SubtitleClipboard.swift`: Copies displayed text + UUID to pasteboard for SwiftBar relay.
- `Sources/CompanionCore/SubtitlePosition.swift`: Maps position setting ("top", "bottom", "center") to NSRect on current screen.
- `Sources/CompanionCore/DisplayMode.swift`: Enum for display modes (karaoke, bionic, static). Controls rendering logic.

**Input: File Watching & Notifications:**

- `Sources/CompanionCore/NotificationWatcher.swift`: Polls `~/.claude/notifications/` every 2s for new .json files. Deduplicates via filename+mtime tracking.
- `Sources/CompanionCore/NotificationProcessor.swift`: Dedup gate (session ID + transcript size) and rate limiter (5s minimum between processing).
- `Sources/CompanionCore/JSONLTailer.swift`: Reads JSONL transcript files with offset-based tailing (avoids re-reading entire file).

**Input: Telegram Bot:**

- `Sources/CompanionCore/TelegramBot.swift`: Bot lifecycle (start, stop, message sending). Wraps swift-telegram-sdk TGBot actor.
- `Sources/CompanionCore/TelegramBotCommands.swift`: Handlers for /start, /stop, /status, /health, /prompt, /done, /sessions, /commands.
- `Sources/CompanionCore/TelegramBotNotifications.swift`: Routes session notifications to Telegram, including TTS playback of responses.
- `Sources/CompanionCore/TelegramBotCallbacks.swift`: Inline button callback handlers (e.g., "Copy to pasteboard" button).

**Message Formatting:**

- `Sources/CompanionCore/TelegramFormatter.swift`: Converts plaintext to HTML with Markdown-style emphasis, code block fencing.
- `Sources/CompanionCore/TelegramFormatterFencing.swift`: Code fence generation (`lang\ncode\n`).
- `Sources/CompanionCore/TelegramFormatterFileRefs.swift`: Extracts and formats file references (paths, line numbers).

**Text Processing:**

- `Sources/CompanionCore/TranscriptParser.swift`: Parses Claude Code session JSONL (extracts text, tool calls, thinking spans).
- `Sources/CompanionCore/LanguageDetector.swift`: Detects CJK text via character ratio threshold (Config.cjkDetectionThreshold = 20%).
- `Sources/CompanionCore/PronunciationProcessor.swift`: Handles pronunciation hints (e.g., "[ˈmeɪn]" phonemes for sherpa-onnx).
- `Sources/CompanionCore/WordTimingAligner.swift`: Maps word-level timings from Python server to word list for karaoke sync.
- `Sources/CompanionCore/SubtitleChunker.swift`: Breaks long text into visually-balanced lines for display (respects font width).

**Rendering:**

- `Sources/CompanionCore/BionicRenderer.swift`: Renders bionic reading format (bold first half of words for faster scanning).

**Control Plane:**

- `Sources/CompanionCore/HTTPControlServer.swift`: REST API on localhost:8780. Health, settings, TTS/subtitle control, caption history.

**Extended Thinking & Summaries:**

- `Sources/CompanionCore/ThinkingWatcher.swift`: Monitors thinking spans in transcripts. Calls SummaryEngine when complete.
- `Sources/CompanionCore/SummaryEngine.swift`: Calls MiniMax API for summary generation (extended thinking condensed into readable text).
- `Sources/CompanionCore/AutoContinue*.swift`: Auto-continue logic (re-prompt Claude if thinking is incomplete).

**External Integrations:**

- `Sources/CompanionCore/MiniMaxClient.swift`: HTTP client for MiniMax API (Anthropic-compatible endpoint).
- `Sources/CompanionCore/PromptExecutor.swift`: Spawns Claude CLI subprocess for /prompt commands.
- `Sources/CompanionCore/ClaudeProcess.swift`: Manages Claude CLI subprocess lifecycle.

**State & Settings:**

- `Sources/CompanionCore/SettingsStore.swift`: Persistent key-value store (JSON → `~/.config/claude-tts-companion/settings.json`). Subtitle settings, TTS settings, etc.
- `Sources/CompanionCore/CaptionHistory.swift`: In-memory circular buffer for caption display history. Exposed via HTTP /captions endpoint.
- `Sources/CompanionCore/CaptionHistoryPanel.swift`: UI panel for browsing caption history.

**Resilience:**

- `Sources/CompanionCore/CircuitBreaker.swift`: Tracks consecutive failures; disables operation with exponential backoff cooldown.

**Error Types:**

- `Sources/CompanionCore/TTSError.swift`: Custom error enum for TTS-specific failures.

**Testing:**

- `Tests/CompanionCoreTests/TranscriptParserTests.swift`: Tests JSONL parsing with mock data.
- `Tests/CompanionCoreTests/SentenceSplitterTests.swift`: Tests sentence boundary detection in various languages.
- `Tests/CompanionCoreTests/TelegramFormatterTests.swift`: Tests Markdown-to-HTML conversion and fencing.
- `Tests/CompanionCoreTests/BionicRendererTests.swift`: Tests bionic reading format generation.
- `Tests/CompanionCoreTests/CircuitBreakerTests.swift`: Tests failure tracking and cooldown behavior.
- `Tests/CompanionCoreTests/LanguageDetectorTests.swift`: Tests CJK detection threshold.
- `Tests/CompanionCoreTests/PronunciationProcessorTests.swift`: Tests phoneme parsing.
- `Tests/CompanionCoreTests/WordTimingAlignerTests.swift`: Tests alignment of word timings to word list.
- `Tests/CompanionCoreTests/StreamingPipelineTests.swift`: End-to-end synthesis + playback + sync tests.
- `Tests/CompanionCoreTests/SubtitleChunkerTests.swift`: Tests line breaking for subtitle display.

## Naming Conventions

**Files:**

- PascalCase: All Swift files use PascalCase (e.g., `TTSEngine.swift`, `SubtitlePanel.swift`).
- Suffix pattern: Test files suffix with "Tests" (e.g., `SentenceSplitterTests.swift`).
- No separators: Use concatenated words, not hyphens or underscores (CamelCase throughout).

**Directories:**

- No prefixes: Directories follow file names directly (all under `CompanionCore/`, no subdirectories).
- Functional grouping: Files organized mentally by domain (TTS, playback, UI, bot), not by type.

**Classes & Types:**

- PascalCase: `SubtitlePanel`, `TTSEngine`, `PlaybackManager`, `CircuitBreaker`.
- Enums: `Config` (configuration), `DisplayMode`, `TTSPriority`, `TTSError`.
- Protocols: Implicit naming (no Protocol suffix used; e.g., `PlaybackDelegate` despite being a delegate).

**Functions & Methods:**

- camelCase: `start()`, `synthesize()`, `showUtterance()`, `shouldSkipDedup()`.
- Query methods: Prefix with "is" or "can" (e.g., `isCancelled`, `canBecomeKey`).
- Action methods: Start with verb (e.g., `play()`, `enqueue()`, `dispatch()`).

**Properties:**

- camelCase: `audioStreamPlayer`, `wordTimings`, `lastPlaybackTime`, `knownFiles`.
- Boolean properties: Prefix with "is", "has", "can" (e.g., `isPlaying`, `hasAudio`, `canBecomeKey`).
- Private/internal: Prefix with underscore (e.g., `_cancelled`, `_processing`).

**Constants:**

- UPPER_CASE in enums (legacy C style) or PascalCase for static let in structs/classes.
- Example: `Config.appName`, `Config.httpPort`, `SubtitleStyle.maxLines`.

## Where to Add New Code

**New Feature (e.g., add voice selection):**

- Primary code: `Sources/CompanionCore/` — add feature-specific file if >200 lines
  - Example: If adding voice profiles, create `VoiceProfiles.swift`
  - Integrate with `SettingsStore.swift` for persistence
  - Add HTTP endpoint in `HTTPControlServer.swift` for remote control
- Tests: `Tests/CompanionCoreTests/` — add parallel test file
  - Example: `VoiceProfilesTests.swift` testing voice selection logic

**New Component/Module (e.g., add transcription engine):**

- Implementation: `Sources/CompanionCore/{FeatureName}.swift`
  - Declare as actor or @MainActor if isolating mutable state
  - Use Sendable types for cross-isolation communication
- Integration: Wire into `CompanionApp.__init__()` alongside other subsystems
  - Pass required subsystem references (e.g., playbackManager, ttsEngine) in constructor
  - Store as property in CompanionApp
  - Call start()/stop() in CompanionApp.start() and shutdown()
- Tests: Add to `Tests/CompanionCoreTests/{FeatureName}Tests.swift`

**New HTTP Endpoint:**

- Location: `Sources/CompanionCore/HTTPControlServer.swift`
- Pattern: Add new Route handler in HTTPControlServer.start() function
  - Define request/response Codable structs near top of file
  - Add validation before processing
  - Return error response with appropriate HTTP status if validation fails
  - Reference subsystem state via properties (e.g., settingsStore, ttsQueue)

**New Telegram Command:**

- Location: `Sources/CompanionCore/TelegramBotCommands.swift`
- Pattern: Add handler function in TelegramBotCommands extension
  - Use existing helpers (formatMessage, sendNotification) for consistency
  - Route from BotDispatcher in same file
  - Document command in TelegramBot.start() command registration list

**Utilities (e.g., text parsing, math, formatting):**

- Shared helpers: `Sources/CompanionCore/{UtilityName}.swift`
  - No tests required unless >100 lines
  - Used by multiple subsystems (justifies extraction)
- Example: `SentenceSplitter.swift` (used by TTSEngine and PromptExecutor)

**Settings or Constants:**

- Centralized in `Sources/CompanionCore/Config.swift`
- Never hardcode values in subsystems
- Use environment variable overrides for deployment flexibility

## Special Directories

**Sources/CSherpaOnnx/:**

- Purpose: C module target enabling `import CSherpaOnnx` from Swift
- Generated: No (manually maintained)
- Committed: Yes
- Details: Vendored C headers in `include/` directory. Module.modulemap tells compiler which headers to expose. Actual sherpa-onnx libraries linked via Package.swift linkerSettings.

**.planning/:**

- Purpose: GSD-generated planning artifacts (this documentation, debug logs, quick fixes)
- Generated: Yes (by GSD commands `/gsd:map-codebase`, `/gsd:debug`, `/gsd:quick`)
- Committed: No (listed in .gitignore unless explicitly committed)

**.build/:**

- Purpose: SwiftPM build artifacts
- Generated: Yes (by `swift build`)
- Committed: No
- Cleaned by: `swift build --clean`

---

_Structure analysis: 2026-04-02_
