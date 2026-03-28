# Milestones

## v4.8.0 Python MLX TTS Consolidation (Shipped: 2026-03-28)

**Phases completed:** 25 phases, 48 plans, 91 tasks

**Key accomplishments:**

- SwiftPM project scaffold with CSherpaOnnx C module map, swift-telegram-sdk v4.5.0 dependency, and centralized Config.swift path constants
- NSApp accessory entry point with SIGTERM handling, sherpa-onnx C interop verification, and 18.3MB stripped release binary
- Floating NSPanel overlay with dark 30% background, click-through, screen-sharing-invisible, bottom-center positioned with 2-line word-wrap and karaoke-ready API
- Word-level karaoke highlighting with gold/silver-grey/white NSAttributedString coloring, 200ms/word demo mode, and main.swift wiring with SIGTERM cleanup
- Patched sherpa-onnx C++ for duration tensors, rebuilt static libs, and created TTSEngine.swift with lazy-loaded Kokoro synthesis, serial queue execution, WAV output, and afplay playback
- URLSession-based MiniMax API client with Anthropic-compatible headers and circuit breaker (3 failures / 5-min cooldown)
- Three MiniMax prompt templates (arc, tail-brief, single-turn) ported from TypeScript with ||| delimiter parsing and safe fallbacks
- TelegramBot actor with swift-telegram-sdk long polling, 7 command handlers, and fence-aware HTML message chunking up to 4096 chars
- Session notification pipeline: TelegramBot -> concurrent arcSummary + tailBrief -> HTML message + TTS karaoke dispatch via SubtitlePanel
- 1. [Rule 1 - Bug] Swift 6 Sendable violation in stderr capture
- /prompt command with --haiku/--sonnet/--opus model flags, streaming edit-in-place to Telegram, circuit breaker + mutex safety
- DispatchSource-based NotificationWatcher for .json file detection and JSONLTailer for offset-based JSONL transcript tailing
- MiniMax-based session evaluation returning CONTINUE/SWEEP/REDIRECT/DONE with plan file discovery and 5-step sweep pipeline
- FlyingFox HTTP server with 6 REST endpoints (health, settings CRUD, subtitle control) plus SettingsStore with JSON disk persistence at ~/.config/claude-tts-companion/settings.json
- HTTPControlServer wired into main.swift with background Task startup on port 8780, ARC retention, and graceful fallback on bind failure
- SwiftBar plugin rewritten from dual-service TOML monitoring to single HTTP API control surface with subtitle/TTS/health sections
- nc-action.sh rewritten from TOML config toggles to HTTP API curl calls for subtitle/TTS/service control
- Launchd plist with KeepAlive + env vars, install/rollback scripts using bootout/bootstrap, Config.swift canonical model path
- Ring buffer caption history with clipboard copy, thinking JSONL watcher with MiniMax summarization, and two new HTTP endpoints
- Full legacy TypeScript formatting pipeline ported to TelegramFormatter.swift with renderSessionNotification, meta-tag stripping, file-ref wrapping, and fence-aware chunking with close/reopen
- Session notification pipeline wired end-to-end: rich HTML header via renderSessionNotification, silent Tail Brief as separate message, git branch and timestamps extracted from JSONL transcripts
- Ported 18 legacy noise patterns + regex filters into TranscriptParser with longest-response turn extraction and tool count aggregation
- Ported exact legacy TypeScript prompt text into SummaryEngine with em dashes, right arrows, correct char budgets, and new summarizePromptForDisplay method
- Full legacy auto-continue evaluation engine ported from TypeScript with verbatim SYSTEM_PROMPT/SWEEP_PROMPT, per-session state tracking, sibling JSONL plan discovery, and deterministic sweep fallback
- Rich Telegram decision notifications with icon, reason, progress bar, tool breakdown, and timing ported from legacy TypeScript formatDecisionMessage/sendExitNotification
- CJK language detection across 3 Unicode ranges with per-outlet feature gates reading 5 legacy env vars
- Feature-gated notification pipeline with CJK language detection routing English to af_heart (3) and Chinese to zf_xiaobei (45)
- Inline keyboard with Focus Tab/Follow Up/Transcript buttons on Arc Summary, callback handlers with AppleScript iTerm2 switching and FIFO-bounded state maps
- Verified itermSessionId and transcriptPath already wired from notification JSON to sendSessionNotification -- Plan 01 completed all code changes
- NotificationProcessor with session dedup (15-min TTL, transcript size tracking) and 5s rate limiting ported from legacy TypeScript
- Pixel-width SubtitleChunker splits text into 2-line pages with clause-priority line breaking; SubtitlePanel.showPages() drives sequential page-flip karaoke with generation-counter interruption safety
- Replaced showUtterance() with SubtitleChunker.chunkIntoPages() + showPages() in dispatchTTS() for paged karaoke subtitles with continuous audio playback
- Extracted 25 business logic files into CompanionCore library target with CompanionApp coordinator, enabling @testable import for all testing
- 30 Swift Testing unit tests across 5 files validating LanguageDetector, TelegramFormatter, TranscriptParser, CircuitBreaker, and SubtitleChunker via @testable import CompanionCore
- Extracted 5 pure types from 1139-line TTSEngine.swift into standalone files, reducing it to 763 lines with zero behavior changes
- Extracted PlaybackManager as @MainActor class, migrated TTSEngine from class+NSLock to Swift actor with async methods and DispatchQueue bridge for blocking GPU synthesis
- 40 unit tests for WordTimingAligner (21), PronunciationProcessor (8), and SentenceSplitter (11) covering MToken timing extraction, onset alignment, pronunciation overrides, and sentence boundary detection
- Expanded SubtitleChunker to 14 tests (break priority, font sizes, page integrity, width measurement) and added 5 streaming pipeline integration tests verifying SentenceSplitter -> SubtitleChunker -> WordTimingAligner chain
- Synthesis counter triggers graceful exit(42) after 10 generateAudio() calls; kokoro-ios cache reduced to 20MB; launchd restarts within 5 seconds
- TTSPipelineCoordinator serializing AudioStreamPlayer access with subtitle-only fallback for busy-state notifications
- AVAudioEngine route change recovery for Bluetooth disconnect + DispatchSource memory pressure monitoring with subtitle-only degradation
- DisplayMode enum + BionicRenderer (40% bold-prefix) with SubtitlePanel integration and HTTP API toggle
- Bionic Reading toggle added to SwiftBar menu with nc-action.sh handler for displayMode cycling between karaoke and bionic
- Scrollable NSPanel with HH:mm timestamps, click-to-copy, auto-scroll with manual override, and HTTP show/hide endpoints
- SwiftBar menu button with :text.bubble: icon triggers caption history panel via POST /captions/panel/show
- CSherpaOnnx C module with vendored header and SherpaOnnxEngine for on-demand CJK TTS via sherpa-onnx kokoro-int8-multi-lang model
- CJK text auto-routes to sherpa-onnx engine while English stays on kokoro-ios MLX, with graceful subtitle-only fallback on failure

---

## v4.7.0 Architecture Hardening + Feature Expansion (Shipped: 2026-03-28)

**Phases completed:** 17 phases, 33 plans, 61 tasks

**Key accomplishments:**

- SwiftPM project scaffold with CSherpaOnnx C module map, swift-telegram-sdk v4.5.0 dependency, and centralized Config.swift path constants
- NSApp accessory entry point with SIGTERM handling, sherpa-onnx C interop verification, and 18.3MB stripped release binary
- Floating NSPanel overlay with dark 30% background, click-through, screen-sharing-invisible, bottom-center positioned with 2-line word-wrap and karaoke-ready API
- Word-level karaoke highlighting with gold/silver-grey/white NSAttributedString coloring, 200ms/word demo mode, and main.swift wiring with SIGTERM cleanup
- Patched sherpa-onnx C++ for duration tensors, rebuilt static libs, and created TTSEngine.swift with lazy-loaded Kokoro synthesis, serial queue execution, WAV output, and afplay playback
- URLSession-based MiniMax API client with Anthropic-compatible headers and circuit breaker (3 failures / 5-min cooldown)
- Three MiniMax prompt templates (arc, tail-brief, single-turn) ported from TypeScript with ||| delimiter parsing and safe fallbacks
- TelegramBot actor with swift-telegram-sdk long polling, 7 command handlers, and fence-aware HTML message chunking up to 4096 chars
- Session notification pipeline: TelegramBot -> concurrent arcSummary + tailBrief -> HTML message + TTS karaoke dispatch via SubtitlePanel
- 1. [Rule 1 - Bug] Swift 6 Sendable violation in stderr capture
- /prompt command with --haiku/--sonnet/--opus model flags, streaming edit-in-place to Telegram, circuit breaker + mutex safety
- DispatchSource-based NotificationWatcher for .json file detection and JSONLTailer for offset-based JSONL transcript tailing
- MiniMax-based session evaluation returning CONTINUE/SWEEP/REDIRECT/DONE with plan file discovery and 5-step sweep pipeline
- FlyingFox HTTP server with 6 REST endpoints (health, settings CRUD, subtitle control) plus SettingsStore with JSON disk persistence at ~/.config/claude-tts-companion/settings.json
- HTTPControlServer wired into main.swift with background Task startup on port 8780, ARC retention, and graceful fallback on bind failure
- SwiftBar plugin rewritten from dual-service TOML monitoring to single HTTP API control surface with subtitle/TTS/health sections
- nc-action.sh rewritten from TOML config toggles to HTTP API curl calls for subtitle/TTS/service control
- Launchd plist with KeepAlive + env vars, install/rollback scripts using bootout/bootstrap, Config.swift canonical model path
- Ring buffer caption history with clipboard copy, thinking JSONL watcher with MiniMax summarization, and two new HTTP endpoints
- Full legacy TypeScript formatting pipeline ported to TelegramFormatter.swift with renderSessionNotification, meta-tag stripping, file-ref wrapping, and fence-aware chunking with close/reopen
- Session notification pipeline wired end-to-end: rich HTML header via renderSessionNotification, silent Tail Brief as separate message, git branch and timestamps extracted from JSONL transcripts
- Ported 18 legacy noise patterns + regex filters into TranscriptParser with longest-response turn extraction and tool count aggregation
- Ported exact legacy TypeScript prompt text into SummaryEngine with em dashes, right arrows, correct char budgets, and new summarizePromptForDisplay method
- Full legacy auto-continue evaluation engine ported from TypeScript with verbatim SYSTEM_PROMPT/SWEEP_PROMPT, per-session state tracking, sibling JSONL plan discovery, and deterministic sweep fallback
- Rich Telegram decision notifications with icon, reason, progress bar, tool breakdown, and timing ported from legacy TypeScript formatDecisionMessage/sendExitNotification
- CJK language detection across 3 Unicode ranges with per-outlet feature gates reading 5 legacy env vars
- Feature-gated notification pipeline with CJK language detection routing English to af_heart (3) and Chinese to zf_xiaobei (45)
- Inline keyboard with Focus Tab/Follow Up/Transcript buttons on Arc Summary, callback handlers with AppleScript iTerm2 switching and FIFO-bounded state maps
- Verified itermSessionId and transcriptPath already wired from notification JSON to sendSessionNotification -- Plan 01 completed all code changes
- NotificationProcessor with session dedup (15-min TTL, transcript size tracking) and 5s rate limiting ported from legacy TypeScript
- Pixel-width SubtitleChunker splits text into 2-line pages with clause-priority line breaking; SubtitlePanel.showPages() drives sequential page-flip karaoke with generation-counter interruption safety
- Replaced showUtterance() with SubtitleChunker.chunkIntoPages() + showPages() in dispatchTTS() for paged karaoke subtitles with continuous audio playback

---

## v4.6.0 Legacy Pipeline Feature Parity (Shipped: 2026-03-27)

**Phases completed:** 7 phases, 13 plans, 21 tasks

**Key accomplishments:**

- Full legacy TypeScript formatting pipeline ported to TelegramFormatter.swift with renderSessionNotification, meta-tag stripping, file-ref wrapping, and fence-aware chunking with close/reopen
- Session notification pipeline wired end-to-end: rich HTML header via renderSessionNotification, silent Tail Brief as separate message, git branch and timestamps extracted from JSONL transcripts
- Ported 18 legacy noise patterns + regex filters into TranscriptParser with longest-response turn extraction and tool count aggregation
- Ported exact legacy TypeScript prompt text into SummaryEngine with em dashes, right arrows, correct char budgets, and new summarizePromptForDisplay method
- Full legacy auto-continue evaluation engine ported from TypeScript with verbatim SYSTEM_PROMPT/SWEEP_PROMPT, per-session state tracking, sibling JSONL plan discovery, and deterministic sweep fallback
- Rich Telegram decision notifications with icon, reason, progress bar, tool breakdown, and timing ported from legacy TypeScript formatDecisionMessage/sendExitNotification
- CJK language detection across 3 Unicode ranges with per-outlet feature gates reading 5 legacy env vars
- Feature-gated notification pipeline with CJK language detection routing English to af_heart (3) and Chinese to zf_xiaobei (45)
- Inline keyboard with Focus Tab/Follow Up/Transcript buttons on Arc Summary, callback handlers with AppleScript iTerm2 switching and FIFO-bounded state maps
- Verified itermSessionId and transcriptPath already wired from notification JSON to sendSessionNotification -- Plan 01 completed all code changes
- NotificationProcessor with session dedup (15-min TTL, transcript size tracking) and 5s rate limiting ported from legacy TypeScript
- Pixel-width SubtitleChunker splits text into 2-line pages with clause-priority line breaking; SubtitlePanel.showPages() drives sequential page-flip karaoke with generation-counter interruption safety
- Replaced showUtterance() with SubtitleChunker.chunkIntoPages() + showPages() in dispatchTTS() for paged karaoke subtitles with continuous audio playback

---
