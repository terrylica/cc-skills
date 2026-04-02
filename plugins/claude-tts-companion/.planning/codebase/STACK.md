# Technology Stack

**Analysis Date:** 2026-04-02

## Languages

**Primary:**

- **Swift** 6.0+ - Main language for the entire application; unified single binary replacing three separate runtimes (TypeScript bot + Python TTS + Swift prototype)
- **C/C++** - sherpa-onnx library integration via static C API bindings

**Secondary:**

- **Objective-C** - macOS AppKit framework interaction (NSPanel, NSApplication, AVFoundation)

## Runtime

**Environment:**

- **macOS** 14+ (Apple Silicon)
  - Minimum deployment target: `.macOS(.v15)` per `Package.swift` line 6
  - Platform: arm64 (Apple Silicon only; required for sherpa-onnx MLX support)

**Build System:**

- **SwiftPM** (swift-tools-version: 6.0)
- **Swift Compiler** 6.0+
- Run command: `swift build -c release`
- Release binary: `.build/release/claude-tts-companion` (~18-25 MB stripped)

## Frameworks

**Core Application:**

- **AppKit** (linked) - NSApplication (accessory activation policy), NSPanel (always-on-top subtitle overlay), NSAttributedString (karaoke highlighting)
- **AVFoundation** (linked) - AVAudioPlayer for WAV playback synchronized with TTS synthesis
- **Foundation** (linked) - Core Networking, File I/O, Logging, Concurrency

**Telegram Integration:**

- **swift-telegram-sdk** 4.5.0 - Telegram Bot API wrapper (long polling, message sending, inline buttons)
  - No Vapor/SwiftNIO required; uses URLSession directly
  - Imports: `SwiftTelegramBot` product
  - See `Sources/CompanionCore/TelegramBot.swift` for bot lifecycle

**HTTP Control API:**

- **FlyingFox** 0.26.2 - Lightweight async/await HTTP server (zero dependencies, BSD sockets wrapper)
  - Binds to localhost only for security
  - Control port: 8780 (per `Config.httpPort`)
  - See `Sources/CompanionCore/HTTPControlServer.swift` for REST endpoints

**Structured Logging:**

- **swift-log** 1.10.1 - Apple's standard logging facade
  - Configured with `StreamLogHandler.standardError` for launchd stderr capture
  - Used by: TelegramBot, HTTPControlServer, MiniMaxClient, TTSEngine, all core subsystems

**Testing:**

- **swift-testing** 0.99.0 - Modern Swift testing framework
  - Test target: `CompanionCoreTests`
  - Config file: `Package.swift` lines 58-64

## Key Dependencies

**Critical Runtime:**

- **sherpa-onnx** 1.12.33 (static linking)
  - Kokoro int8 quantized TTS synthesis
  - Linked libraries: `libsherpa-onnx-c-api`, `libsherpa-onnx-core`, `libsherpa-onnx`, `libonnxruntime`
  - Additional: `libespeak-ng`, `libpiper_phonemize`, `libssentencepiece_core`, `libucd`, `libkaldi-*`, `libkissfft-float`, `libc++`
  - Library path: `-L/Users/terryli/fork-tools/sherpa-onnx/build-swift-macos/install/lib` (Package.swift line 32)
  - Header location: `Sources/CSherpaOnnx/include/c-api.h` (C module target for Swift interop)

**Transitive (via swift-telegram-sdk):**

- **swift-custom-logger** 1.1.1
- **swift-regular-expression** 0.2.4
- **swift-syntax** 600.0.1 (macro expansion, not used directly)

## Configuration

**Environment:**

- launchd plist: `launchd/com.terryli.claude-tts-companion.plist`
- Service label: `com.terryli.claude-tts-companion`
- Install path: `$HOME/.local/bin/claude-tts-companion`
- Logs: `$HOME/.local/state/launchd-logs/claude-tts-companion/stderr.log`

**Key Environment Variables (plist EnvironmentVariables):**

- `HOME` - User home directory
- `PATH` - Shim PATH for mise + Homebrew + system bins
- `SHERPA_ONNX_PATH` - sherpa-onnx build install directory (for .dylib discovery if not static)
- `KOKORO_MODEL_PATH` - Model directory (default: `$HOME/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0`)
- `TELEGRAM_BOT_TOKEN` - Bot token (empty in plist, populated via launchctl setenv)
- `TELEGRAM_CHAT_ID` - Notification target chat ID
- `MINIMAX_API_KEY` - API key for summary generation

**Runtime Config (Config.swift):**

- `STREAMING_TTS` - Streaming sentence-chunked TTS (default: true)
- `KOKORO_TTS_SERVER_URL` - Python Kokoro MLX server (default: `http://127.0.0.1:8779`)
- `CLAUDE_NOTIFICATION_DIR` - Claude Code notification JSON files (default: `$HOME/.claude/notifications`)
- `CLAUDE_PROJECTS_DIR` - Transcript JSONL files (default: `$HOME/.claude/projects`)
- Model-specific env overrides: `KOKORO_MLX_MODEL_PATH`, `KOKORO_VOICES_PATH`, `MLX_METALLIB_PATH`, `KOKORO_MODEL_PATH`

**Build Configuration:**

- SwiftPM manifest: `Package.swift` (swift-tools-version 6.0)
- Dependencies resolved: `Package.resolved` (locked versions)
- Linker flags: unsafe C library linking (14 static libs) in CompanionCore target
- No `.swiftformat`, `.swiftlint`, or other formatters configured (architecture pre-Swift 5.8 lint)

## Platform Requirements

**Development:**

- macOS 14+ with Apple Silicon (arm64)
- Swift 6.0+ toolchain
- sherpa-onnx fork built locally (`/Users/terryli/fork-tools/sherpa-onnx/build-swift-macos/install/`)
- Kokoro int8 model at `~/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0/` (~260MB)

**Production (launchd):**

- macOS 15+ (actual deployment target)
- Process type: Adaptive (auto-suspend when idle)
- Memory limit: 8 GB soft limit (plist line 46)
- Exit timeout: 15 seconds for clean shutdown (plist line 23)
- Restart behavior: KeepAlive with NetworkState true, SuccessfulExit false (respawn on crash, not on clean exit)
- Stderr logging: ASL/Console.app via launchd
- Network dependency: Requires internet for Telegram long polling + MiniMax API

---

_Stack analysis: 2026-04-02_
