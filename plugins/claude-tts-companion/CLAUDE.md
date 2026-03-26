# claude-tts-companion

Unified Swift binary: Telegram session bot + Kokoro TTS engine + karaoke subtitle overlay as one macOS launchd service.

**Hub:** [CLAUDE.md](../../CLAUDE.md) | **Sibling:** [tts-tg-sync](../tts-tg-sync/CLAUDE.md)

## Build

```bash
cd plugins/claude-tts-companion
swift build -c release
```

## Architecture

- **CSherpaOnnx** -- C module target wrapping sherpa-onnx headers via module.modulemap
- **claude-tts-companion** -- Main executable target (Swift)

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
| `Sources/claude-tts-companion/Config.swift` | Centralized path and configuration constants               |
