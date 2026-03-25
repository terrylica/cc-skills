# Technology Stack

**Project:** claude-tts-companion
**Researched:** 2026-03-25

## Recommended Stack

### Core Language & Runtime

| Technology | Version                          | Purpose          | Why                                                                                                                                                                                                                                | Confidence |
| ---------- | -------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| Swift      | 6.0+                             | Primary language | Unifies all three replaced runtimes (Swift/TypeScript/Python) into one binary. Swift 6 gives strict concurrency checking, which prevents data races in our multi-threaded architecture (main thread UI + background bot/TTS/HTTP). | HIGH       |
| SwiftPM    | swift-tools-version: 6.0         | Build system     | Spike 08 validated this. No Xcode project needed. `swift build` produces the binary directly.                                                                                                                                      | HIGH       |
| macOS 14+  | Deployment target `.macOS(.v14)` | Minimum OS       | Required by swift-telegram-sdk (Swift 6 concurrency runtime). Spike 08 confirmed macOS 14 as the correct floor. Your machine runs macOS 14+. No reason to support older.                                                           | HIGH       |

### Telegram Bot

| Technology                                                        | Version               | Purpose                  | Why                                                                                                                                                                                                                                                               | Confidence |
| ----------------------------------------------------------------- | --------------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| [swift-telegram-sdk](https://github.com/nerzh/swift-telegram-sdk) | 4.5.0 (from: "4.5.0") | Telegram Bot API wrapper | Spike 04 validated: 4.5MB binary, 8.6MB RSS. Long polling works without Vapor/SwiftNIO. Only dependency is swift-log + swift-regular-expression. Implements Telegram Bot API 9.5. The `TGClientPrtcl` approach lets you use pure URLSession (88 lines, spike 04). | HIGH       |

**Note on version:** Spike 08 referenced v3.10.0, but the latest release is v4.5.0 (March 2026). The v4.x series added Swift 6 strict concurrency support. Use 4.5.0.

### TTS Engine

| Technology                                           | Version                           | Purpose                               | Why                                                                                                                                                                                                                                               | Confidence |
| ---------------------------------------------------- | --------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | 1.12.33 (built from source)       | Kokoro TTS synthesis via ONNX Runtime | Validated across spikes 03, 09, 10, 13b, 16, 19. Int8 quantized model cuts peak RSS to 561MB. Static linking avoids dylib hell. The ~50-line C++ patch (spike 16) enables word-level timestamps from the duration model -- zero-drift, zero-cost. | HIGH       |
| ONNX Runtime                                         | Bundled with sherpa-onnx (static) | ML inference backend                  | Comes as `libonnxruntime.a` in the sherpa-onnx build. Do NOT add the separate `onnxruntime-swift-package-manager` SPM package -- it would conflict with sherpa-onnx's bundled copy.                                                               | HIGH       |

**Build approach:** Pre-build sherpa-onnx from source (`~/fork-tools/sherpa-onnx/build-swift-macos/install/`). Link the static archives via Package.swift `linkerSettings`. Do NOT use CocoaPods or the xcframework distribution -- static libs give you full control over the C++ patch.

**Model:** Kokoro int8 English v0.19 at `~/.local/share/kokoro/models/kokoro-int8-en-v0_19/` (129MB on disk). Already validated.

### Subtitle Overlay

| Technology         | Version                | Purpose                         | Why                                                                                                                                                                                                                                | Confidence |
| ------------------ | ---------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| AppKit NSPanel     | macOS system framework | Always-on-top subtitle window   | Spike 02: 88KB binary, 19MB RSS. NSPanel with `.floating` level + `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]` gives always-visible overlay. `sharingType = .none` auto-hides during screen sharing (spike 21). | HIGH       |
| NSAttributedString | macOS system framework | Word-level karaoke highlighting | Spike 19: gold highlighting at 6us per word update (37x headroom). NSAttributedString range-based styling is the right abstraction for karaoke.                                                                                    | HIGH       |

**Not SwiftUI.** The overlay is a single NSPanel with an NSTextField. SwiftUI would add complexity without benefit -- no layout system needed, no data binding needed. Pure AppKit is the correct choice for a text overlay.

### HTTP Control API

| Technology                                        | Version                 | Purpose                 | Why                                                                                                                                                                                                                                    | Confidence |
| ------------------------------------------------- | ----------------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| [FlyingFox](https://github.com/swhitty/FlyingFox) | 0.26.2 (from: "0.26.0") | Lightweight HTTP server | Pure BSD sockets + Swift Concurrency. Zero dependencies (no SwiftNIO, no Vapor). Spike 08 designed for raw BSD sockets; FlyingFox wraps them with a clean async/await API while adding zero framework overhead. Supports macOS 10.15+. | MEDIUM     |

**Alternative considered: raw BSD sockets.** Spike 08 designed for hand-rolled BSD sockets. FlyingFox provides the same thing with routing, JSON parsing, and proper error handling -- without pulling in a web framework. If you want zero dependencies, raw BSD sockets work (spike 02 proved it), but FlyingFox saves ~200 lines of boilerplate.

**Decision point:** Start with raw BSD sockets (spike 02's approach) for the first milestone. Evaluate FlyingFox if the HTTP API grows beyond 4-5 endpoints.

### File Watching

| Technology                | Version                | Purpose                                 | Why                                                                                                                                                                 | Confidence |
| ------------------------- | ---------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| DispatchSource + FSEvents | macOS system framework | Watch notification files, JSONL tailing | Spike 15 validated offset-based JSONL tailing at 0.34ms P95. `DispatchSource.makeFileSystemObjectSource(.write)` is the correct API. No third-party library needed. | HIGH       |

### Logging

| Technology                                      | Version                | Purpose                   | Why                                                                                                                                                                                                                                                                 | Confidence |
| ----------------------------------------------- | ---------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| [swift-log](https://github.com/apple/swift-log) | 1.10.1 (from: "1.6.0") | Structured logging facade | Already a transitive dependency of swift-telegram-sdk. Use it directly rather than adding a second logging system. Apple's standard logging API for server/CLI Swift. Configure with `StreamLogHandler.standardError` for launchd (stderr goes to ASL/Console.app). | HIGH       |

### Audio Playback

| Technology                   | Version                | Purpose      | Why                                                                                                                                                                                                 | Confidence |
| ---------------------------- | ---------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| AVFoundation (AVAudioPlayer) | macOS system framework | WAV playback | Spike 10 validated: plays 24kHz mono 16-bit WAV from sherpa-onnx output. Alternative `afplay` subprocess works but AVAudioPlayer gives programmatic control (pause, current time for karaoke sync). | HIGH       |

### AI / MiniMax API

| Technology | Version                | Purpose                              | Why                                                                                                                                              | Confidence |
| ---------- | ---------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| URLSession | macOS system framework | MiniMax API calls, session summaries | Spike 11 validated MiniMax integration from Swift. URLSession handles HTTPS, JSON encoding/decoding, async/await. No HTTP client library needed. | HIGH       |

### CLI Arguments (Optional)

| Technology                                                              | Version               | Purpose                    | Why                                                                                                                                                                                      | Confidence |
| ----------------------------------------------------------------------- | --------------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.7.1 (from: "1.5.0") | CLI flags for debug/config | Only needed if you want `claude-tts-companion --port 8780 --model-path /path`. For a launchd service that reads config from a plist or JSON file, this is optional. Add later if needed. | MEDIUM     |

## Stack NOT to Use

| Technology          | Why Not                                                                                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Vapor / Hummingbird | Pulls in SwiftNIO + massive dependency tree. The HTTP API is 4-5 endpoints, not a web application. Overkill.                                                              |
| SwiftNIO            | Adds complexity without benefit. BSD sockets (or FlyingFox) handle the load. You're serving ~1 req/sec from SwiftBar, not thousands.                                      |
| CoreML / FluidAudio | Spike 05 evaluated and rejected. CoreML models are 3.9GB vs 129MB for sherpa-onnx int8. FluidAudio has no Swift API.                                                      |
| Electron / Tauri    | Native AppKit NSPanel is 88KB vs hundreds of MB. No web runtime needed for a text overlay.                                                                                |
| SwiftUI             | No benefit for the overlay (single NSPanel + NSTextField). SwiftUI's layout system adds overhead for zero gain. AppKit is simpler here.                                   |
| Telegrammer         | Abandoned (last commit 2021). swift-telegram-sdk is the only actively maintained option.                                                                                  |
| TDLibKit            | Full Telegram client library (TDLib C++). Overkill -- you need Bot API, not client API.                                                                                   |
| os.log / OSLog      | Good for app debugging, but launchd services benefit from swift-log's StreamLogHandler which writes to stderr (captured by launchd). os.log requires Console.app to read. |

## Package.swift Structure

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "claude-tts-companion",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/nerzh/swift-telegram-sdk", from: "4.5.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        // FlyingFox: add later if raw BSD sockets become unwieldy
        // .package(url: "https://github.com/swhitty/FlyingFox", from: "0.26.0"),
    ],
    targets: [
        .executableTarget(
            name: "claude-tts-companion",
            dependencies: [
                .product(name: "SwiftTelegramSdk", package: "swift-telegram-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ],
            linkerSettings: [
                // sherpa-onnx static libraries (pre-built from source)
                .unsafeFlags([
                    "-L", "path/to/sherpa-onnx/install/lib",
                    "-lsherpa-onnx-c-api",
                    "-lsherpa-onnx-core",
                    "-lonnxruntime",
                    "-lkaldi-native-fbank-core",
                    "-lkissfft-float",
                    "-lpiper_phonemize",
                    "-lespeak-ng",
                    "-lssentencepiece_core",
                    "-lucd",
                ]),
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
            ]
        ),
    ]
)
```

**Note:** The exact linker flags come from spike 08. The `-lsherpa-onnx` combined archive may simplify this to a single `-lsherpa-onnx` flag -- verify during Phase 1 build setup.

## Dependency Tree (Total)

```
claude-tts-companion
├── swift-telegram-sdk v4.5.0
│   ├── swift-regular-expression v0.2.x  (pure Swift, zero deps)
│   └── swift-custom-logger v1.1.x
│       └── swift-log v1.10.x  (Apple standard)
├── swift-log v1.10.x  (shared with above)
├── sherpa-onnx (static libs, not an SPM package)
│   └── onnxruntime (static, bundled)
└── System frameworks: AppKit, AVFoundation, Foundation, Accelerate
```

**Total SwiftPM dependencies: 3** (swift-telegram-sdk, swift-log, swift-regular-expression). Everything else is system frameworks or pre-built static libraries.

## Build & Run

```bash
# Build (debug)
swift build

# Build (release, stripped)
swift build -c release
strip .build/release/claude-tts-companion

# Run
.build/release/claude-tts-companion

# Install as launchd service
cp .build/release/claude-tts-companion /usr/local/bin/
# Use existing plist pattern from com.terryli.telegram-bot
```

## Binary Size & Memory Targets

| Metric                 | Target    | Source                                                        |
| ---------------------- | --------- | ------------------------------------------------------------- |
| Binary size (stripped) | ~19-25 MB | Spike 03: 19MB for TTS alone                                  |
| Idle RSS               | ~27 MB    | Spike 02 (19MB subtitle) + spike 04 (8.6MB bot) share runtime |
| Peak RSS (synthesis)   | ~561 MB   | Spike 09: int8 quantized model                                |
| Model load time        | ~0.56s    | Spike 03 (lazy, on first TTS request)                         |

## Sources

- [sherpa-onnx v1.12.33](https://github.com/k2-fsa/sherpa-onnx/releases) -- verified March 24, 2026
- [swift-telegram-sdk v4.5.0](https://github.com/nerzh/swift-telegram-sdk/releases) -- verified March 1, 2026
- [swift-log v1.10.1](https://github.com/apple/swift-log/releases) -- verified February 16, 2025
- [swift-argument-parser v1.7.1](https://github.com/apple/swift-argument-parser/releases) -- verified March 20, 2025
- [FlyingFox v0.26.2](https://github.com/swhitty/FlyingFox) -- verified January 17, 2025
- [ONNX Runtime SPM v1.24.2](https://github.com/microsoft/onnxruntime-swift-package-manager/releases) -- NOT recommended (conflicts with sherpa-onnx bundled copy)
- Spike 08: Integration Architecture -- validated dependency conflicts, Package.swift design
- Spike 04: Swift Telegram Bot -- validated long polling without Vapor
- Spike 02: Swift Subtitle Overlay -- validated NSPanel approach
- Spike 03/09: sherpa-onnx TTS -- validated synthesis and int8 quantization
