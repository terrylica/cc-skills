# claude-tts-companion

Unified macOS accessory app for real-time karaoke subtitles synced with TTS playback. Replaces three separate processes (TypeScript Telegram bot + Python TTS server + Swift subtitle prototype) with a single Swift binary.

**Hub:** [CLAUDE.md](../../CLAUDE.md) | **Sibling:** [plugins/CLAUDE.md](../CLAUDE.md)

## Build

```bash
cd plugins/claude-tts-companion
swift build -c release
```

Release binary at `.build/release/claude-tts-companion` (~18MB stripped).

## Architecture

- **CSherpaOnnx** -- C module target wrapping sherpa-onnx headers via `module.modulemap`. Vendored `c-api.h` header enables `import CSherpaOnnx` from Swift without system-level pkg-config.
- **NSApp Accessory** -- `NSApplication.shared` with `.accessory` activation policy (no dock icon, no app switcher). Runs as a background service under launchd.
- **SIGTERM Handling** -- `DispatchSource.makeSignalSource` for clean shutdown. Dummy `NSEvent.otherEvent` posted to unblock the run loop after `app.stop()`.
- **swift-telegram-sdk** -- Long-polling Telegram bot via `TGClientPrtcl` (URLSession, no Vapor/SwiftNIO).
- **Logging** -- `swift-log` with `StreamLogHandler.standardError` for launchd stderr capture.

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
