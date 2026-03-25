# Feature Landscape

**Domain:** macOS TTS companion with subtitle overlay for developer session monitoring
**Researched:** 2026-03-25

## Reference Products

The feature landscape is informed by these existing products and capabilities:

| Product                           | Relevance                                                     | Key Insight                                                                                                                |
| --------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **macOS Live Captions**           | Direct comparable for subtitle overlay UX                     | Font/color customization, position dragging, scroll-back history, auto-hide when silent, hidden during screen recording    |
| **Textream**                      | Closest open-source comparable (teleprompter + word tracking) | Word-level highlighting, Dynamic Island overlay, floating window with opacity, Sidecar iPad support, WebSocket remote sync |
| **GhostLayer**                    | Privacy-focused overlay                                       | `sharingType = .none` pattern for screen sharing privacy — identical approach validated in Spike 21                        |
| **SwiftBar / menubar companions** | Control surface pattern                                       | Menu bar popover for quick settings, status indicators, multi-monitor awareness                                            |

## Table Stakes

Features users expect. Missing = product feels incomplete.

| Feature                              | Why Expected                                                                                                                        | Complexity | Notes                                                                             |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------- |
| TTS playback of session content      | Core value prop — "hear what Claude says"                                                                                           | High       | Kokoro via sherpa-onnx, validated in Spikes 03/09/10                              |
| Subtitle overlay on screen           | Core value prop — "see what Claude says"                                                                                            | Med        | NSPanel, validated in Spike 02 (88KB, 19MB RSS)                                   |
| Word-level karaoke highlighting      | Users expect sync between audio and text; anything less feels broken                                                                | Med        | Gold highlight, 6us/update (Spike 19), timestamps from duration model (Spike 13b) |
| Telegram bot integration             | Replaces existing bot — users depend on session notifications                                                                       | Med        | swift-telegram-sdk long polling (Spike 04)                                        |
| AI session summaries                 | Replaces existing MiniMax summarization pipeline                                                                                    | Med        | URLSession to MiniMax API, direct port of existing logic                          |
| Font size presets (S/M/L)            | Apple Live Captions has font size; Textream has XS-XL; users expect text sizing                                                     | Low        | User-confirmed in Spike 23                                                        |
| Position control (top/center/bottom) | Apple Live Captions supports dragging; Textream has pinned/floating; basic expectation                                              | Low        | User-confirmed in Spike 23                                                        |
| Dark semi-transparent background     | Every subtitle/caption overlay has this; 30% opacity is user-approved                                                               | Low        | User-confirmed in Spike 22                                                        |
| Word-wrap (no auto-shrink)           | Text must remain readable; shrinking defeats font size selection                                                                    | Low        | User-confirmed in Spike 22                                                        |
| Screen sharing privacy (auto-hide)   | GhostLayer, Apple Live Captions both hide during screen capture; showing private session content in a meeting is a critical failure | Low        | `NSWindow.sharingType = .none` (Spike 21)                                         |
| File watcher for notifications       | Replaces existing DispatchSource/FSEvents watcher                                                                                   | Low        | Direct port, well-understood pattern                                              |
| Single launchd service               | Replacing 3 processes with 1 is the architectural value prop                                                                        | Med        | Integration architecture validated (Spike 08)                                     |
| JSONL transcript parsing             | Required for feeding content to TTS and summaries                                                                                   | Low        | Foundation line-by-line streaming at 67 MB/s                                      |

## Differentiators

Features that set product apart. Not expected by the market, but valuable for this use case.

| Feature                                 | Value Proposition                                                                                                           | Complexity | Notes                                                                                                 |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------- |
| Scrollable caption history              | Apple Live Captions has scroll-back; most subtitle tools don't. Lets you catch up on missed content without rewinding audio | Med        | Spike 17 research identified this; requires maintaining a text buffer and scroll state in the overlay |
| Copy-to-clipboard                       | Grab a specific subtitle line for pasting into notes/chat — no comparable in caption tools                                  | Low        | Spike 17 research; keyboard shortcut or right-click on overlay text                                   |
| HTTP control API                        | Programmatic control from scripts, SwiftBar, other tools — unique to developer-focused companion                            | Med        | Settings, health, subtitle, TTS endpoints; enables automation ecosystem                               |
| SwiftBar integration (claude-hq v3.0.0) | Unified control surface in menu bar for all companion features — font, position, screen, service status                     | Med        | Leverages existing SwiftBar plugin architecture; Python plugin talks to HTTP API                      |
| Multi-monitor with display selection    | Default to MacBook built-in, configurable to external — most overlay tools pick one and stick                               | Low        | User requirement; SwiftBar dropdown for screen selection                                              |
| Auto-continue hook with MiniMax eval    | AI decides whether to continue a Claude session — no comparable product does this                                           | High       | Unique to this use case; MiniMax evaluates session state                                              |
| JSONL file tailing (thinking watcher)   | Real-time thinking indicator from Claude's NDJSON output — developer-specific feature                                       | Low        | Offset-based, 0.34ms P95 (validated)                                                                  |
| Claude CLI subprocess integration       | Direct Process + Pipe to Claude CLI — unique integration point                                                              | Med        | Streaming NDJSON parsing                                                                              |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature                       | Why Avoid                                                                                        | What to Do Instead                                                      |
| ---------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| CoreML / FluidAudio TTS path       | 3.9GB models are overkill; sherpa-onnx proven across 5 spikes with 561MB peak RSS (Spike 05)     | Use sherpa-onnx with int8 quantized Kokoro model                        |
| Bionic reading mode                | Interesting typography experiment but unvalidated user need; adds complexity to text rendering   | Defer indefinitely; standard word highlighting is sufficient (Spike 17) |
| Focus mode / DND integration       | No public macOS API for Do Not Disturb state detection (Spike 21)                                | Use screen sharing detection instead, which has a real API              |
| Rewriting SwiftBar plugin in Swift | 244 lines of Python, working fine, SwiftBar is a Python/shell ecosystem (Spike 06)               | Keep Python plugin, have it call HTTP API of the new companion          |
| Speech recognition / STT           | Textream and Apple Live Captions do STT; this product does TTS. Adding STT conflates the purpose | Stay focused on TTS output + subtitle display of Claude content         |
| Multi-language TTS                 | Kokoro int8 English model is the validated path; multi-language adds model management complexity | English only; user's primary language                                   |
| GUI preferences window             | SwiftUI preferences panel adds binary size and maintenance burden for rarely-changed settings    | SwiftBar menu + HTTP API + config file is sufficient                    |
| Xcode project / .xcodeproj         | SwiftPM builds are simpler, CI-friendly, and the validated path (Spike 08)                       | `swift build` only                                                      |
| Sidecar iPad display               | Textream supports this but it's a teleprompter use case; this product is desktop-native          | MacBook + external monitor only                                         |
| Remote control / WebSocket sync    | Textream has director mode; unnecessary for single-user developer tool                           | Local HTTP API is sufficient                                            |

## Feature Dependencies

```
JSONL Transcript Parsing ─────┬──→ TTS Playback (needs text to synthesize)
                               ├──→ Subtitle Overlay (needs text to display)
                               └──→ AI Session Summaries (needs transcript content)

TTS Playback ─────────────────→ Word-Level Karaoke (needs audio timestamps for sync)

Subtitle Overlay ─────────────┬──→ Font Size Presets (overlay must exist first)
                               ├──→ Position Control (overlay must exist first)
                               ├──→ Dark Background (overlay must exist first)
                               ├──→ Word-Wrap (overlay must exist first)
                               ├──→ Screen Sharing Privacy (overlay must exist first)
                               ├──→ Scrollable Caption History (overlay must exist first)
                               ├──→ Copy-to-Clipboard (overlay must exist first)
                               └──→ Multi-Monitor Selection (overlay must exist first)

File Watcher ─────────────────→ Telegram Bot Notifications (watches for notification files)

HTTP Control API ─────────────→ SwiftBar Integration (SwiftBar calls HTTP endpoints)

Single launchd Service ───────→ Everything (architectural container for all features)
```

## MVP Recommendation

Prioritize (Phase 1 - "it works"):

1. **JSONL transcript parsing** — foundation for all content flow
2. **TTS playback via sherpa-onnx** — core audio value prop
3. **Subtitle overlay with word-level karaoke** — core visual value prop
4. **Dark background + word-wrap + font presets + position** — visual polish that makes the overlay usable
5. **Screen sharing privacy** — one line of code, prevents embarrassing failures
6. **Single launchd service** — the architectural goal

Prioritize (Phase 2 - "it's connected"): 7. **Telegram bot integration** — replaces existing service 8. **File watcher for notifications** — replaces existing service 9. **AI session summaries** — replaces existing pipeline 10. **HTTP control API** — enables external control

Prioritize (Phase 3 - "it's polished"): 11. **SwiftBar integration (v3.0.0)** — unified control surface 12. **Scrollable caption history** — catch-up capability 13. **Copy-to-clipboard** — utility feature 14. **Multi-monitor display selection** — flexibility 15. **Auto-continue hook** — advanced automation

Defer: **Bionic reading**, **CoreML path**, **multi-language**, **Sidecar** — all validated as out-of-scope.

## Sources

- [Apple Live Captions settings](https://support.apple.com/guide/mac-help/change-live-captions-settings-accessibility-mchla0b36db8/mac)
- [Textream - macOS teleprompter with word tracking](https://github.com/f/textream)
- [GhostLayer - privacy-focused overlay](https://github.com/HelithaSri/GhostLayer)
- [LiveKit screen sharing exclusion discussion](https://github.com/livekit/client-sdk-swift/issues/567)
- [Transync AI - Mac subtitle translation](https://www.transyncai.com/blog/mac-translation-app/)
- Project spikes 02-23 at `~/tmp/subtitle-spikes-7aqa/`
