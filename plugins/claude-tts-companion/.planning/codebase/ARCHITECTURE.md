# Architecture

**Analysis Date:** 2026-04-02

## Pattern Overview

**Overall:** Layered actor-based service architecture (NSApplication accessory mode) with event-driven subsystems.

**Key Characteristics:**

- Single Swift binary runs as macOS background service (launchd) with no UI chrome
- Multi-actor concurrency model using Swift's strict concurrency checking (Swift 6)
- Unified interface between Telegram bot, Python TTS server, and subtitle overlay
- File-system-driven notification processing with dedup and rate limiting
- HTTP control plane (FlyingFox) for remote configuration and diagnostics

## Layers

**Application (Accessory NSApplication):**

- Purpose: NSApplication lifecycle management with SIGTERM handler for clean shutdown
- Location: `Sources/claude-tts-companion/main.swift`
- Contains: NSApplication initialization, signal handling, run loop execution
- Depends on: CompanionApp (core coordinator)
- Used by: launchd via installed binary at `~/.local/bin/claude-tts-companion`

**Core Coordinator (CompanionApp):**

- Purpose: Owns and wires all subsystems; single source of truth for component lifetimes
- Location: `Sources/CompanionCore/CompanionApp.swift`
- Contains: Subsystem initialization order, start/shutdown orchestration, notification dispatch
- Depends on: All lower layers (SettingsStore, SubtitlePanel, PlaybackManager, TTSEngine, etc.)
- Used by: main.swift (entry point receives CompanionApp instance)

**Input Layer (File Watching + Telegram):**

- Purpose: Ingest events from Claude Code sessions (JSONL files) and Telegram commands
- Location: `NotificationWatcher.swift`, `TelegramBot.swift`, `NotificationProcessor.swift`
- Contains: Directory polling (2s interval), JSON file parsing, Telegram long-polling, dedup/rate-limit gates
- Depends on: CompanionApp (for callback dispatch), TelegramBot (for command handling)
- Used by: CompanionApp.start() to monitor incoming notifications

**Synthesis Layer (TTS):**

- Purpose: Orchestrate text→audio conversion via Python Kokoro server and sherpa-onnx
- Location: `TTSEngine.swift`, `SherpaOnnxEngine.swift`, `TTSQueue.swift`, `TTSPipelineCoordinator.swift`
- Contains: HTTP client for Python server, circuit breaker, sentence-chunked streaming, priority-aware queuing, language detection
- Depends on: PlaybackManager (for audio hardware), Config (for paths and URLs)
- Used by: TTSQueue (serializes work), CompanionApp (init), TelegramBot (Telegram TTS commands)

**Playback Layer (Audio):**

- Purpose: Low-level audio playback using AVAudioPlayer and afplay subprocess
- Location: `PlaybackManager.swift`, `AfplayPlayer.swift`, `AudioStreamPlayer.swift`, `PlaybackDelegate.swift`
- Contains: Player lifecycle, hardware warm-up, WAV file cleanup, afplay subprocess management
- Depends on: Config (for silent audio generation)
- Used by: TTSEngine, TTSQueue, SubtitleSyncDriver (for sync timing)

**Subtitle Display (UI):**

- Purpose: Always-on-top floating panel with word-level karaoke highlighting
- Location: `SubtitlePanel.swift`, `SubtitleStyle.swift`, `SubtitleBorder.swift`, `SubtitleClipboard.swift`, `SubtitlePosition.swift`, `DisplayMode.swift`
- Contains: NSPanel with karaoke state machine, word highlighting, bionic rendering, position/opacity/font settings
- Depends on: SettingsStore (for user preferences), PlaybackManager (for sync timing via currentTime polling)
- Used by: CompanionApp (positionOnScreen), HTTPControlServer (show/hide), TelegramBot (display formatted messages)

**Control Plane (HTTP API):**

- Purpose: REST API for configuration, diagnostics, and remote TTS triggering
- Location: `HTTPControlServer.swift`
- Contains: Health endpoint (uptime, RSS, subsystem status), PATCH endpoints for settings, POST endpoints for TTS/subtitle control
- Depends on: All subsystems (for state query and control)
- Used by: External clients (SwiftBar, curl, etc.) on localhost:8780

**Message Processing (Telegram):**

- Purpose: Command parsing, inline button callbacks, Markdown formatting for session output
- Location: `TelegramBotCommands.swift`, `TelegramBotCallbacks.swift`, `TelegramBotNotifications.swift`, `TelegramFormatter.swift`, `TelegramFormatterFencing.swift`, `TelegramFormatterFileRefs.swift`
- Contains: /start, /stop, /status, /prompt handlers; fenced code block formatting; file reference extraction
- Depends on: TelegramBot (actor-isolated bot reference), PromptExecutor (for /prompt commands)
- Used by: TelegramBot via dispatcher pattern (BotDispatcher)

**External Integrations:**

- Purpose: Third-party API clients and adapters
- Location: `MiniMaxClient.swift`, `SummaryEngine.swift`, `AutoContinue*.swift`, `ClaudeProcess.swift`
- Contains: MiniMax API client for summaries, extended thinking integration, Claude CLI subprocess wrapper
- Depends on: URLSession (for HTTP), Foundation (for subprocess)
- Used by: CompanionApp (initialize), NotificationProcessor (route to summaries)

## Data Flow

**Session Notification → TTS → Subtitles:**

1. NotificationWatcher polls `~/.claude/notifications/` every 2s
2. Finds new `.json` file → calls CompanionApp.handleNotification(filePath)
3. NotificationProcessor dedup/rate-limit gates the request
4. TranscriptParser extracts JSONL from session transcript file
5. AutoContinueEvaluator determines if session should auto-continue (extended thinking)
6. Text sent to TTSQueue (userInitiated priority)
7. TTSQueue serializes: cancel in-flight, drain queue, start new synthesis
8. TTSEngine sends text to Python Kokoro server (localhost:8779) via HTTP
9. Python server returns WAV file + word timing JSON
10. TTSEngine returns SynthesisResult to TTSQueue
11. TTSQueue calls TTSPipelineCoordinator.playAndSync()
12. TTSPipelineCoordinator delegates to PlaybackManager.play(wavPath)
13. PlaybackManager spawns afplay subprocess to play audio
14. SubtitleSyncDriver polls AVAudioPlayer.currentTime, drives karaoke highlighting in SubtitlePanel
15. Playback complete → PlaybackDelegate fires completion → SubtitlePanel hidden
16. Caption recorded in CaptionHistory (for /history Telegram endpoint)

**Telegram Command → Execution → Response:**

1. TelegramBot.start() begins long-polling via swift-telegram-sdk
2. User sends /status, /health, /prompt, etc.
3. BotDispatcher routes to TelegramBotCommands handler
4. Handler queries subsystem state (PlaybackManager.isPlaying, TTSQueue.queueSize, etc.)
5. PromptExecutor subprocess-spawns `claude run` for /prompt commands (with timeout 120s)
6. Response formatted via TelegramFormatter (HTML with code fencing, file refs)
7. Sent back via bot.sendMessage() → Telegram

**HTTP API Request:**

1. HTTPControlServer listens on localhost:8780
2. GET /health → queryies CompanionApp health state, returns JSON
3. PATCH /subtitle/settings → updates SettingsStore, SubtitlePanel re-renders
4. POST /tts/speak → enqueues text as userInitiated priority → goes through TTSQueue
5. GET /captions → returns CaptionHistory.recent(limit) as JSON array

**State Management:**

- **SettingsStore:** Persisted to `~/.config/claude-tts-companion/settings.json`, queried by SubtitlePanel and HTTPControlServer on every change
- **CaptionHistory:** In-memory circular buffer (max 500 entries), populated by TTSQueue on synthesis completion
- **Karaoke State:** SubtitlePanel holds `words: [String]`, `wordTimings: [TimeInterval]`, `generation: Int` (generation counter to cancel stale scheduling)
- **Audio Hardware State:** PlaybackManager tracks `lastPlaybackTime` and `audioHardwareWarmed` for idle re-warm
- **Dedup/Rate-Limit State:** NotificationProcessor holds `processedSessions: [sessionId: (processedAt, transcriptSize)]`

## Key Abstractions

**TTSResult:**

- Purpose: Encapsulates synthesis output (WAV path, text, word timings, audio duration)
- Examples: `Sources/CompanionCore/TTSEngine.swift` (line 21), returned by TTSEngine.synthesize()
- Pattern: Immutable Sendable struct for cross-actor communication

**TTSQueue (Actor):**

- Purpose: Priority-aware FIFO queue that serializes GPU access (single worker)
- Examples: `Sources/CompanionCore/TTSQueue.swift`
- Pattern: Actor enforces serial access; cooperative cancellation tokens for in-flight work

**CaptionEntry:**

- Purpose: Immutable snapshot of a displayed caption (text, timestamp, speaker, duration)
- Examples: `Sources/CompanionCore/CaptionHistory.swift`
- Pattern: Used by CaptionHistory for circular buffer; exposed via HTTP /captions endpoint

**SettingsStore:**

- Purpose: Thread-safe persistent key-value store for user preferences
- Examples: `Sources/CompanionCore/SettingsStore.swift` (subtitle position, font size, opacity, TTS voice/speed)
- Pattern: Read-through cache with on-change callbacks; Codable JSON serialization

**CircuitBreaker:**

- Purpose: Tracks consecutive failures and disables operation under load
- Examples: `Sources/CompanionCore/CircuitBreaker.swift`, used by TTSEngine
- Pattern: Half-open state resets on successful operation; exponential backoff cooldown

**SubtitleClipboard:**

- Purpose: Copies displayed text + UUID to pasteboard for SwiftBar integration
- Examples: `Sources/CompanionCore/SubtitleClipboard.swift`
- Pattern: Called by SubtitlePanel.show(); integrates with SwiftBar via environment variable injection

**NotificationProcessor (Dedup/Rate-Limit):**

- Purpose: Gates session notifications with transcript-size-based dedup and 5s rate limiting
- Examples: `Sources/CompanionCore/NotificationProcessor.swift` (REL-01, REL-02)
- Pattern: Stateful gate with locking; pending file retry via DispatchSourceTimer

**BionicRenderer:**

- Purpose: Bionic reading format (bold first half of words for faster scanning)
- Examples: `Sources/CompanionCore/BionicRenderer.swift`, triggered by DisplayMode.bionic
- Pattern: Converts word list to NSAttributedString with opacity-based emphasis

## Entry Points

**Application Entry (NSApplication):**

- Location: `Sources/claude-tts-companion/main.swift`
- Triggers: `launchctl bootstrap` or `swift build -c release && ./.build/release/claude-tts-companion`
- Responsibilities: Configure logging, create NSApplication, initialize CompanionApp, handle SIGTERM, run event loop

**Service Start (CompanionApp):**

- Location: `Sources/CompanionCore/CompanionApp.swift` → start()
- Triggers: Called from main.swift after app.run() begins
- Responsibilities: Audit audio routing, health-check Python server, start HTTP server, start Telegram bot, start NotificationWatcher, position SubtitlePanel

**Notification Intake:**

- Location: `Sources/CompanionCore/CompanionApp.swift` → handleNotification(filePath)
- Triggers: NotificationWatcher finds new .json in ~/.claude/notifications/
- Responsibilities: Parse notification, check dedup, rate-limit, route to appropriate handler (session TTS, thinking summary, etc.)

**HTTP API Endpoints:**

- Location: `Sources/CompanionCore/HTTPControlServer.swift`
- Triggers: External HTTP requests on localhost:8780
- Responsibilities: Query state, modify settings, control playback, return diagnostics

**Telegram Commands:**

- Location: `Sources/CompanionCore/TelegramBotCommands.swift`
- Triggers: User sends /start, /stop, /status, /health, /prompt, /done, /sessions, /commands
- Responsibilities: Execute command logic, format response, send via bot.sendMessage()

## Error Handling

**Strategy:** Graceful degradation with circuit breaker protection and per-subsystem fallbacks.

**Patterns:**

- **Circuit Breaker (TTS):** TTSEngine tracks 3 consecutive failures; disables synthesis for 30s cooldown, then retries. Failures logged but don't crash service. Subsequent synthesis requests fail fast until cooldown expires.

- **Python Server Unavailability:** TTSEngine.checkPythonServerHealth() retries 6 times (30s total) at startup. If unreachable, logs warning and sets `pythonServerWarning = true`. Synthesis requests still attempted (server could come up), but caller informed via health endpoint.

- **Telegram Connection Loss:** TelegramBot.start() wrapped in try/catch; failure logged as warning. Service continues without bot. HTTPControlServer still functional. User can restart bot via HTTP endpoint or check status.

- **Audio Hardware Failure:** PlaybackManager.play() catches AVAudioPlayer init errors; logs warning and returns nil. Playback skipped but TTS synthesis still completed (file written). Caller sees no audio but captions still displayed.

- **Notification File I/O:** CompanionApp.handleNotification() catches JSON decode, file read, transcript parse errors. Each error logged at appropriate level (debug, info, warning). Notification skipped, process continues.

- **Subprocess Timeouts:** PromptExecutor /prompt commands timeout after 120s. Response formatted as "Command timed out". ClaudeProcess.run() catches subprocess errors.

- **Memory Pressure:** TTSPipelineCoordinator monitors memory warnings via DispatchSource; triggers early unload of sherpa-onnx model if RSS > 1GB.

## Cross-Cutting Concerns

**Logging:**

- Framework: `swift-log` with `StreamLogHandler.standardError`
- Configuration: `LoggingSystem.bootstrap()` in main.swift
- Pattern: Each subsystem creates `Logger(label: "subsystem-name")`; all logs go to stderr (captured by launchd)
- Structured logging: Use logger.info/warning/error with contextual messages

**Validation:**

- TTSQueue validates text length before enqueuing
- SentenceSplitter validates sentence boundaries
- LanguageDetector validates CJK character ratios (REL-03)
- TranscriptParser validates JSONL format (each line is valid JSON)
- HTTPControlServer validates request bodies (Codable deserialization)

**Authentication:**

- HTTP API: localhost-only binding (no credentials required)
- Telegram: Bot token from Config.telegramBotToken environment variable
- Python TTS server: localhost-only, token-less
- MiniMax API: API key from Config.miniMaxApiKey environment variable

**Concurrency:**

- CompanionApp @MainActor ensures single-threaded subsystem initialization
- PlaybackManager @MainActor (AVAudioPlayer callbacks fire on main thread)
- SubtitlePanel @MainActor (NSPanel AppKit APIs)
- TTSQueue actor (isolates synthesis queue state)
- TTSEngine actor (isolates HTTP client and circuit breaker)
- TelegramBot @unchecked Sendable with internal NSLock for mutable state
- All subsystems use Sendable types for cross-isolation data (TTSResult, SettingsStore.settings, etc.)

**Resource Cleanup:**

- WAV files deleted by PlaybackDelegate after playback or timeout
- sherpa-onnx model unloaded after 30s idle (Config.sherpaOnnxIdleTimeoutSeconds)
- NotificationProcessor.pruneExpiredEntries() called periodically to unbind dedup entries older than 30 minutes
- HTTP server gracefully stops on shutdown via httpServer.stop()
- Telegram bot stops via TelegramBot.stop()
- All DispatchSource and timers canceled in shutdown flow

---

_Architecture analysis: 2026-04-02_
