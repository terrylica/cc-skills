# Architecture Patterns

**Domain:** macOS background service / unified Swift TTS companion
**Researched:** 2026-03-25

## Recommended Architecture

**Single-binary accessory app** using `NSApplication.setActivationPolicy(.accessory)` -- no dock icon, no app switcher entry. This is the standard macOS pattern for background utilities that occasionally present UI (subtitle overlay). The binary runs as a launchd LaunchAgent, auto-starting at login and restarting on crash.

### Architecture Type: Event-Driven Coordinator

The application follows a **hub-and-spoke concurrency model** where multiple independent subsystems (spokes) communicate through a central `@MainActor` state coordinator (hub). Each spoke runs on its own thread/queue and dispatches state updates to the main thread via GCD or Swift concurrency.

```
                    ┌─────────────────────────────┐
                    │      Main Thread (Hub)       │
                    │                              │
                    │  NSApplication.run()         │
                    │  ├── SubtitlePanel (NSPanel)  │
                    │  └── AppState (@MainActor)   │
                    └──────────┬──────────────────┘
                               │
              DispatchQueue.main.async / MainActor.run
                               │
         ┌─────────────────────┼──────────────────────┐
         │                     │                       │
    ┌────┴─────┐    ┌─────────┴────────┐    ┌────────┴────────┐
    │Telegram  │    │   HTTP Server    │    │  File Watcher   │
    │Bot       │    │  (BSD sockets)   │    │ (DispatchSource) │
    │(Task.    │    │  DispatchQueue   │    │  .utility)       │
    │detached) │    │  .global(.util)  │    │                  │
    └────┬─────┘    └─────────┬────────┘    └────────┬────────┘
         │                     │                       │
         │              ┌──────┴──────┐                │
         └─────────────►│  TTSEngine  │◄───────────────┘
                        │ (serial DQ) │
                        │ @unchecked  │
                        │  Sendable   │
                        └─────────────┘
```

This architecture was **proven in Spike 10** with zero deadlocks and 82ms time-to-first-subtitle.

### Component Boundaries

| Component         | Responsibility                                                                                     | Thread/Queue                         | Communicates With                                                                       | Isolation                            |
| ----------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------ | --------------------------------------------------------------------------------------- | ------------------------------------ |
| **main.swift**    | Entry point: configures NSApp, launches all subsystems, calls `app.run()`                          | Main                                 | All components (setup only)                                                             | N/A                                  |
| **AppState**      | Central state coordinator: tracks bot status, TTS queue depth, subtitle visibility, health metrics | Main (@MainActor)                    | All components read/write via MainActor dispatch                                        | `@MainActor` serialization           |
| **SubtitlePanel** | NSPanel overlay: word-level karaoke highlighting, position/size/opacity control                    | Main (@MainActor)                    | AppState (reads config), TTSEngine (receives timestamps)                                | `@MainActor` (AppKit requirement)    |
| **TelegramBot**   | Long-polling Telegram updates, command dispatch (/tts, /subtitle, /session, /ping)                 | `Task.detached`                      | AppState (status updates), TTSEngine (synthesis requests), SubtitlePanel (show/dismiss) | Swift async/await                    |
| **HTTPServer**    | BSD socket server on port 8780: POST /subtitle, POST /tts, GET /health, POST /settings             | `DispatchQueue.global(.utility)`     | AppState (health reads), SubtitlePanel (show), TTSEngine (synthesis)                    | Blocking accept() loop               |
| **TTSEngine**     | sherpa-onnx Kokoro synthesis: text to WAV, lazy model loading, word timestamps                     | Dedicated serial `DispatchQueue`     | AppState (queue depth), SubtitlePanel (word timestamps for karaoke)                     | `@unchecked Sendable` + serial queue |
| **FileWatcher**   | Monitors `/tmp/claude-unified-watch/` for notification JSON files                                  | `DispatchSource` on `.utility` queue | AppState, SubtitlePanel, TTSEngine (triggers based on file content)                     | DispatchSource event handler         |
| **Config**        | Static configuration: paths, ports, token loading                                                  | N/A (value type)                     | Read by all components at startup                                                       | Immutable after init                 |
| **SignalHandler** | SIGTERM handling: graceful shutdown sequence                                                       | `DispatchSource` on `.main` queue    | All components (shutdown coordination)                                                  | GCD signal source                    |

### Data Flow

**Primary flow: Telegram message to subtitle + audio**

```
Telegram API ──(long poll)──► TelegramBot
                                  │
                    /tts "Hello world"
                                  │
                   ┌──────────────┴──────────────┐
                   ▼                              ▼
            MainActor.run {                 TTSEngine.synthesize()
              appState.ttsQueueDepth += 1     │ (serial DispatchQueue)
            }                                 │
                                              ▼
                                    sherpa-onnx generates:
                                    1. WAV audio data
                                    2. Word timestamps []
                                              │
                   ┌──────────────────────────┤
                   ▼                          ▼
            MainActor.run {            Process("afplay")
              subtitlePanel.show(        .launch()
                words: [...],            .waitUntilExit()
                timestamps: [...]      }
              )                              │
              appState.ttsQueueDepth -= 1    │
            }                                │
                   │                         │
                   ▼                         ▼
            Karaoke highlighting       Audio playback
            (6us per word update)      (real-time)
                   │                         │
                   └──────────┬──────────────┘
                              ▼
                       MainActor.run {
                         subtitlePanel.dismiss()
                       }
```

**Secondary flow: HTTP control API**

```
SwiftBar plugin ──(curl)──► HTTPServer (port 8780)
                                │
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
              GET /health  POST /settings  POST /subtitle
                    │           │           │
                    ▼           ▼           ▼
              DQ.main.sync  DQ.main.async  DQ.main.async
              { health() }  { update() }   { show() }
```

**Tertiary flow: File watcher notifications**

```
Claude hook writes ──► /tmp/claude-unified-watch/*.json
                              │
                    DispatchSource fires
                              │
                    Parse JSON notification
                              │
                    Route to SubtitlePanel or TTSEngine
```

## Patterns to Follow

### Pattern 1: @MainActor State Coordinator

**What:** All shared mutable state lives in a single `@MainActor` class. Background threads never mutate state directly -- they dispatch to main.

**When:** Always. This is the only safe pattern when AppKit UI and multiple background subsystems share state.

**Why:** Eliminates data races by design. No locks, no atomics, no manual synchronization. The main thread's RunLoop serializes all state mutations.

```swift
@MainActor
final class AppState {
    var ttsQueueDepth: Int = 0
    var lastBotUpdate: Date?
    let subtitlePanel = SubtitlePanel()

    func healthJSON() -> String { /* reads all state safely */ }
}

// From any background thread:
await MainActor.run { appState.ttsQueueDepth += 1 }
// Or from GCD:
DispatchQueue.main.async { appState.ttsQueueDepth += 1 }
```

### Pattern 2: @unchecked Sendable + Serial DispatchQueue for CPU-Heavy Work

**What:** Wrap CPU-bound work (TTS synthesis) in a non-isolated class with a private serial DispatchQueue, marked `@unchecked Sendable`.

**When:** When work takes seconds (7s for 99-word synthesis) and would block an actor's cooperative executor.

**Why:** Swift actors use cooperative thread pools. A 7-second synthesis would starve other actors. A dedicated serial DispatchQueue isolates the heavy work while `withCheckedContinuation` bridges back to async/await.

```swift
final class TTSEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tts-synthesis", qos: .userInitiated)

    func synthesize(text: String) async -> URL? {
        await withCheckedContinuation { cont in
            queue.async {
                let result = self.heavySynthesis(text)
                cont.resume(returning: result)
            }
        }
    }
}
```

### Pattern 3: Task.detached for Long-Running Network Loops

**What:** Use `Task.detached` (not `Task { }`) for the Telegram bot's infinite polling loop.

**When:** For long-running loops that must not inherit the caller's actor context (which would be `@MainActor` since launched from `main.swift`).

**Why:** A bare `Task { }` created on the main thread inherits `@MainActor` context, meaning the polling loop would run on the main thread and block UI. `Task.detached` explicitly opts out of actor inheritance.

```swift
Task.detached {
    try await startBot(token: token, state: state)
    // This runs on a background cooperative thread, not main
}
```

### Pattern 4: Lazy Model Loading

**What:** Defer sherpa-onnx model loading until first TTS request, not at startup.

**When:** Always for the TTS engine. Model loading takes 0.56s and allocates 561MB.

**Why:** The binary should start in <100ms for launchd. Most sessions may never use TTS. Loading 561MB of model data at boot wastes memory for idle sessions.

```swift
func ensureTTSEngine() -> TTSEngine {
    if let engine = ttsEngine { return engine }
    let engine = TTSEngine(modelDir: Config.kokoroModelDir)
    ttsEngine = engine
    return engine
}
```

### Pattern 5: BSD Socket HTTP Server (No Framework)

**What:** Raw POSIX socket-based HTTP server for the control API, no SwiftNIO/Vapor/Hummingbird.

**When:** Low-traffic localhost-only HTTP serving (SwiftBar health checks, settings control).

**Why:** Adding SwiftNIO would pull in a large dependency tree and its own event loop that could conflict with NSApplication's RunLoop. BSD sockets are 50 lines of code, zero dependencies, and adequate for <10 req/s localhost traffic.

### Pattern 6: DispatchSource for File System + Signal Monitoring

**What:** Use `DispatchSource.makeFileSystemObjectSource` for file watching and `DispatchSource.makeSignalSource` for SIGTERM handling.

**When:** Any OS-level event monitoring (file changes, signals).

**Why critical gotcha:** DispatchSource objects are reference-counted. If not stored in a global/long-lived variable, ARC silently deallocates them and event handling stops with no error. This was discovered in Spike 04.

```swift
// MUST store globally -- ARC will deallocate otherwise
nonisolated(unsafe) var fileWatcherSource: (any DispatchSourceFileSystemObject)?

func startFileWatcher(directory: String) {
    let source = DispatchSource.makeFileSystemObjectSource(...)
    source.resume()
    fileWatcherSource = source  // prevents deallocation
}
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Custom Actor for CPU-Heavy Work

**What:** Using a Swift actor to wrap TTS synthesis.

**Why bad:** Actors share a cooperative thread pool. A 7-second synthesis blocks one of the limited cooperative threads, potentially starving other async work (bot polling, HTTP handling). The cooperative executor has no priority system -- all actors are equal.

**Instead:** Use `@unchecked Sendable` + dedicated serial `DispatchQueue` (Pattern 2).

### Anti-Pattern 2: DispatchQueue.main.sync from Unknown Context

**What:** Calling `DispatchQueue.main.sync` when the calling thread might already be main.

**Why bad:** Instant deadlock. `sync` blocks the calling thread waiting for main, but main IS the calling thread.

**Instead:** Use `DispatchQueue.main.async` when the calling context is uncertain. Use `.sync` only from guaranteed background threads (e.g., the HTTP server's socket handler thread). The HTTP health endpoint uses `.sync` safely because `accept()` always runs on a background GCD thread.

### Anti-Pattern 3: SwiftUI for Background Service UI

**What:** Using SwiftUI `App` protocol and `@main` for a background service with occasional overlay UI.

**Why bad:** SwiftUI's `App` lifecycle takes control of `NSApplication`, making it difficult to run background subsystems before the event loop starts. The `@main` attribute conflicts with custom entry points. SwiftUI windows are harder to configure as always-on-top transparent overlays than raw NSPanel.

**Instead:** Use `main.swift` with manual `NSApplication` setup. Launch all background work before `app.run()`. Use AppKit's NSPanel directly for the overlay.

### Anti-Pattern 4: Vapor/Hummingbird for Internal HTTP

**What:** Adding a web framework for the localhost control API.

**Why bad:** Vapor pulls in SwiftNIO (event loop conflict with NSApplication RunLoop), adds 20+ transitive dependencies, increases binary size by 10MB+, and is massive overkill for 4 HTTP endpoints serving localhost.

**Instead:** 50 lines of BSD socket code (Pattern 5).

### Anti-Pattern 5: Multiple Processes Communicating via IPC

**What:** Keeping separate binaries for bot, TTS, and subtitle, coordinating via XPC/pipes/sockets.

**Why bad:** 3x process overhead (225MB vs 27MB idle RSS), complex lifecycle management, failure modes multiply, debugging requires correlating across processes.

**Instead:** Single binary, in-process communication via `@MainActor` state coordinator.

## Component Dependencies and Build Order

The build order is dictated by which components depend on which.

```
Layer 0 (no deps):     Config
Layer 1 (Foundation):  FileWatcher, SignalHandler, URLSessionTGClient
Layer 2 (C libs):      TTSEngine (depends on sherpa-onnx static libs)
Layer 3 (AppKit):      SubtitlePanel (depends on NSPanel, NSAttributedString)
Layer 4 (state):       AppState (depends on SubtitlePanel, TTSEngine interface)
Layer 5 (integration): TelegramBot (depends on AppState, TTSEngine, SubtitlePanel)
                        HTTPServer (depends on AppState, SubtitlePanel, TTSEngine)
Layer 6 (entry):       main.swift (depends on everything)
```

### Suggested Build Order (phases)

1. **Foundation layer** -- Config, CSherpaOnnx module map, Package.swift with all dependencies resolving. Proves the build system works with sherpa-onnx static libs + swift-telegram-sdk coexisting.

2. **Subtitle overlay** -- SubtitlePanel (NSPanel) with word-level karaoke. This is the core differentiator and the reason the binary needs NSApplication at all. Build and test independently with the HTTP /subtitle endpoint.

3. **TTS engine** -- TTSEngine wrapping sherpa-onnx with lazy loading, async synthesis, and word timestamp extraction. Test independently with a CLI harness.

4. **Telegram bot** -- TelegramBot with command handlers routing to TTSEngine and SubtitlePanel. Requires stopping the existing Bun bot (token conflict).

5. **Integration** -- Wire everything through AppState. Add HTTP server endpoints, file watcher, signal handling, health reporting. This is where Spike 10's proven concurrency model gets replicated at full scale.

6. **Deployment** -- launchd plist, SwiftBar plugin update (claude-hq v3.0.0), rollout (stop old services, start unified).

### Why This Order

- Subtitle first because it is the novel feature and validates that NSApplication.run() + background work coexistence works in the real codebase (not just spikes).
- TTS before bot because the bot's /tts command depends on TTSEngine.
- Bot after TTS because testing the bot requires the TTS engine and subtitle panel to be functional.
- Integration last because it wires components that must each work independently first.

## Source File Layout

```
claude-tts-companion/
├── Package.swift                    <- SwiftPM manifest
├── Sources/
│   ├── main.swift                   <- Entry point (NSApp + component launch)
│   ├── Config.swift                 <- Paths, ports, token loading
│   ├── AppState.swift               <- @MainActor shared state
│   ├── SubtitlePanel.swift          <- NSPanel karaoke overlay
│   ├── KaraokeRenderer.swift        <- Word-level gold highlighting
│   ├── TTSEngine.swift              <- sherpa-onnx synthesis wrapper
│   ├── AudioPlayer.swift            <- afplay subprocess management
│   ├── HTTPServer.swift             <- BSD socket control API
│   ├── FileWatcher.swift            <- DispatchSource file monitor
│   ├── TelegramBot.swift            <- Bot setup + command handlers
│   ├── URLSessionTGClient.swift     <- TGClientPrtcl implementation
│   ├── TranscriptParser.swift       <- JSONL streaming parser
│   ├── MiniMaxClient.swift          <- AI summary API client
│   ├── SherpaOnnx.swift             <- Swift wrapper (from upstream)
│   └── CSherpaOnnx/
│       ├── module.modulemap         <- C module map for sherpa-onnx headers
│       └── shim.h                   <- Umbrella header
├── com.terryli.claude-tts-companion.plist
└── Makefile                         <- build, install, test targets
```

## Scalability Considerations

This is a single-user desktop utility. "Scale" means handling edge cases gracefully, not horizontal scaling.

| Concern            | Normal Operation         | Stress Case                     | Mitigation                                                                                |
| ------------------ | ------------------------ | ------------------------------- | ----------------------------------------------------------------------------------------- |
| TTS queue depth    | 1 request at a time      | Rapid /tts commands (5+ queued) | Serial DispatchQueue naturally queues. Report depth via /health. Reject above 10.         |
| Memory (idle)      | 27 MB                    | N/A                             | No concern -- less than a single Chrome tab                                               |
| Memory (synthesis) | 561 MB peak              | Multiple rapid syntheses        | Serial queue prevents concurrent model use. RSS stays at 561MB regardless of queue depth. |
| Subtitle updates   | 6us per word             | 100+ word sentences             | 37x headroom. Word-wrap handles overflow. No performance concern.                         |
| Telegram polling   | 1 long-poll connection   | Network dropout                 | swift-telegram-sdk retries with backoff automatically                                     |
| HTTP requests      | <10/min (SwiftBar polls) | N/A                             | BSD socket with backlog of 5 is adequate                                                  |
| Log file growth    | ~1KB/hour                | Extended uptime (months)        | launchd log rotation via `newsyslog` or manual truncation                                 |

## Sources

- [Spike 08: Integration Architecture](~/tmp/subtitle-spikes-7aqa/SPIKE-08-INTEGRATION-ARCH.md) -- PRIMARY source, contains full dependency analysis, Package.swift, concurrency model, launchd plist design (HIGH confidence)
- [Spike 10: E2E Flow Report](~/tmp/subtitle-spikes-7aqa/10-e2e-flow/SPIKE-10-E2E-REPORT.md) -- Proves zero-deadlock concurrency model with measured timings (HIGH confidence)
- [Spike Overview](~/tmp/subtitle-spikes-7aqa/SPIKE-OVERVIEW.md) -- 23 spikes summarized with RSS measurements (HIGH confidence)
- [macOS menu bar app with AppKit](https://www.polpiella.dev/a-menu-bar-only-macos-app-using-appkit/) -- Standard accessory app pattern reference
- [Understanding agent-based macOS apps](https://rderik.com/blog/understanding-a-few-concepts-of-macos-applications-by-building-an-agent-based-menu-bar-app/) -- LaunchAgent + NSApplication.accessory pattern
- [NSApplication.setActivationPolicy](https://developer.apple.com/documentation/appkit/nsapplication/1428621-setactivationpolicy) -- Apple docs for activation policies
- [MainActor dispatch patterns](https://www.avanderlee.com/swift/mainactor-dispatch-main-thread/) -- @MainActor as modern replacement for DispatchQueue.main
- [Task execution and actor context](https://blog.jacobstechtavern.com/p/why-is-task-running-on-main-thread) -- Why Task.detached is needed to avoid main thread inheritance
- [Peter Steinberger: Menu bar settings window challenges](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) -- 2025 macOS accessory app quirks
