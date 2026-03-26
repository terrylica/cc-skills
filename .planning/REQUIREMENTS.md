# Requirements: claude-tts-companion

**Defined:** 2026-03-25
**Core Value:** See what Claude says, anywhere — real-time karaoke subtitles synced with TTS playback

## v1 Requirements

### Build System

- [x] **BUILD-01**: User can compile the binary with `swift build -c release` (no Xcode required)
- [x] **BUILD-02**: Package.swift includes swift-telegram-sdk v4.5.0 and sherpa-onnx static lib linker settings
- [x] **BUILD-03**: Bridging header correctly imports sherpa-onnx C API and ONNX Runtime C API
- [x] **BUILD-04**: Release binary is a single file under 30MB (excluding model files)

### Subtitle Overlay

- [x] **SUB-01**: User sees floating subtitle text overlaid on their macOS screen via NSPanel
- [x] **SUB-02**: Subtitle panel appears on MacBook built-in display by default
- [x] **SUB-03**: Current word is highlighted in warm gold (bold) as audio plays (karaoke style)
- [x] **SUB-04**: Past words dim to silver-grey, future words are white
- [x] **SUB-05**: NSAttributedString updates complete in under 1ms per word (no frame drops)
- [x] **SUB-06**: Panel has dark semi-transparent background at 30% opacity with 10px corner radius
- [x] **SUB-07**: Long text word-wraps to 2 lines (no auto-shrink)
- [x] **SUB-08**: Panel is invisible to screen sharing and screen capture (sharingType = .none)
- [x] **SUB-09**: Panel does not steal focus from the active application (nonactivatingPanel)
- [x] **SUB-10**: Panel is click-through (ignoresMouseEvents = true)
- [x] **SUB-11**: Panel is visible on all Spaces and in fullscreen apps

### TTS Engine

- [x] **TTS-01**: User hears synthesized speech from text via Kokoro int8 model through afplay
- [x] **TTS-02**: Synthesis runs on a dedicated serial DispatchQueue (does not block UI)
- [x] **TTS-03**: Model loads lazily on first synthesis request (not at startup)
- [x] **TTS-04**: Peak RSS during synthesis stays under 700MB with int8 model
- [x] **TTS-05**: Synthesis speed is at least 1.5x real-time (audio plays without gaps)
- [ ] **TTS-06**: Duration tensor is extracted from patched sherpa-onnx for word timestamps
- [ ] **TTS-07**: Word timestamps have zero accumulated drift over the full audio duration
- [x] **TTS-08**: Audio output is 24kHz mono 16-bit WAV played via afplay subprocess

### Telegram Bot

- [ ] **BOT-01**: Bot connects to Telegram via long polling using swift-telegram-sdk
- [ ] **BOT-02**: Bot responds to /start, /stop, /status, /health, /prompt, /sessions, /done, /commands
- [ ] **BOT-03**: Bot sends session notifications (Arc Summary + Tail Brief) when sessions end
- [ ] **BOT-04**: Bot dispatches TTS for Tail Brief text with subtitle overlay
- [x] **BOT-05**: Bot supports model selection (/prompt --haiku, --sonnet, --opus)
- [x] **BOT-06**: Bot resumes existing Claude Code sessions via Agent SDK subprocess
- [x] **BOT-07**: Bot parses JSONL transcripts to extract prompts, responses, and tool counts
- [ ] **BOT-08**: Bot sends messages with HTML formatting, fence-aware chunking (4096 char limit)

### AI Summaries

- [ ] **SUM-01**: Arc Summary generates full-session narrative via MiniMax API
- [ ] **SUM-02**: Tail Brief generates end-weighted narrative (20% context, 80% final turn)
- [ ] **SUM-03**: Single-turn summary generates "you prompted me X ago to..." narrative
- [ ] **SUM-04**: Circuit breaker disables summaries after 3 consecutive API failures (5 min cooldown)

### File Watching

- [x] **WATCH-01**: Notification file watcher detects new .json files in the notification directory
- [x] **WATCH-02**: JSONL file tailer reads new bytes from growing transcript files via offset tracking
- [x] **WATCH-03**: DispatchSource watchers are stored as strong references (no silent ARC deallocation)
- [x] **WATCH-04**: File watcher latency is under 100ms from write to detection

### Claude CLI Integration

- [x] **CLI-01**: /prompt command spawns claude CLI as subprocess via Foundation Process + Pipe
- [x] **CLI-02**: Streaming NDJSON response is parsed and forwarded to Telegram as edit-in-place updates
- [x] **CLI-03**: CLAUDECODE env var is unset before spawning subprocess

### Auto-Continue

- [x] **AUTO-01**: Stop hook evaluates session completion via MiniMax (CONTINUE/SWEEP/REDIRECT/DONE)
- [x] **AUTO-02**: Plan file discovery scans transcript for .claude/plans/\*.md references
- [x] **AUTO-03**: SWEEP mode injects 5-step review pipeline

### HTTP Control API

- [x] **API-01**: GET /health returns subsystem status (bot, TTS, subtitle) with RSS and uptime
- [x] **API-02**: GET /settings returns all current settings as JSON
- [x] **API-03**: POST /settings/subtitle accepts fontSize, position, screen, opacity, karaoke toggle
- [x] **API-04**: POST /settings/tts accepts enabled, voice, speed toggles
- [x] **API-05**: POST /subtitle/show displays subtitle text with optional duration
- [x] **API-06**: POST /subtitle/hide dismisses current subtitle
- [x] **API-07**: Settings persist to disk and survive binary restart

### SwiftBar Integration

- [ ] **BAR-01**: Updated claude-hq v3.0.0 plugin monitors single unified service (com.terryli.claude-tts-companion)
- [ ] **BAR-02**: SwiftBar menu shows subtitle controls (font S/M/L, position, karaoke toggle)
- [ ] **BAR-03**: SwiftBar menu shows TTS controls (enable/disable, test TTS)
- [ ] **BAR-04**: SwiftBar actions call HTTP API endpoints (response under 200ms)
- [ ] **BAR-05**: SwiftBar shows per-subsystem health status from /health endpoint

### Deployment

- [ ] **DEP-01**: Single launchd plist (com.terryli.claude-tts-companion) manages the unified binary
- [ ] **DEP-02**: Existing services (telegram-bot, kokoro-tts-server) are stopped but plists preserved
- [ ] **DEP-03**: Rollback script can re-enable old services if unified binary fails
- [ ] **DEP-04**: Kokoro int8 model is at ~/.local/share/kokoro/models/kokoro-int8-en-v0_19/

### Extras

- [ ] **EXT-01**: User can view scrollable caption history (last N subtitle entries)
- [ ] **EXT-02**: User can copy subtitle text to clipboard
- [ ] **EXT-03**: User can switch subtitle display to external monitor via SwiftBar
- [ ] **EXT-04**: Thinking watcher summarizes Claude's thinking via MiniMax

## v2 Requirements

### Deferred

- Bionic reading mode (bold first letters for ADHD users) — interesting but unvalidated need
- Multi-language TTS — English-only for v1
- GUI preferences window — SwiftBar + HTTP API is sufficient
- Focus mode / DND integration — no public macOS API

## Out of Scope

- CoreML/FluidAudio TTS — 3.9GB models, overkill (Spike 05)
- Speech recognition / STT — this is a TTS product
- Sidecar iPad display — desktop-native only
- Rewriting SwiftBar in Swift — 244 lines Python, working fine
- Xcode project — SwiftPM only

## Traceability

| Requirement | Phase    | Status  |
| ----------- | -------- | ------- |
| BUILD-01    | Phase 1  | Complete |
| BUILD-02    | Phase 1  | Complete |
| BUILD-03    | Phase 1  | Complete |
| BUILD-04    | Phase 1  | Complete |
| SUB-01      | Phase 2  | Complete |
| SUB-02      | Phase 2  | Complete |
| SUB-03      | Phase 2  | Complete |
| SUB-04      | Phase 2  | Complete |
| SUB-05      | Phase 2  | Complete |
| SUB-06      | Phase 2  | Complete |
| SUB-07      | Phase 2  | Complete |
| SUB-08      | Phase 2  | Complete |
| SUB-09      | Phase 2  | Complete |
| SUB-10      | Phase 2  | Complete |
| SUB-11      | Phase 2  | Complete |
| TTS-01      | Phase 3  | Complete |
| TTS-02      | Phase 3  | Complete |
| TTS-03      | Phase 3  | Complete |
| TTS-04      | Phase 3  | Complete |
| TTS-05      | Phase 3  | Complete |
| TTS-06      | Phase 3  | Pending |
| TTS-07      | Phase 3  | Pending |
| TTS-08      | Phase 3  | Complete |
| SUM-01      | Phase 4  | Pending |
| SUM-02      | Phase 4  | Pending |
| SUM-03      | Phase 4  | Pending |
| SUM-04      | Phase 4  | Pending |
| BOT-01      | Phase 5  | Pending |
| BOT-02      | Phase 5  | Pending |
| BOT-03      | Phase 5  | Pending |
| BOT-04      | Phase 5  | Pending |
| BOT-08      | Phase 5  | Pending |
| BOT-05      | Phase 6  | Complete |
| BOT-06      | Phase 6  | Complete |
| BOT-07      | Phase 6  | Complete |
| CLI-01      | Phase 6  | Complete |
| CLI-02      | Phase 6  | Complete |
| CLI-03      | Phase 6  | Complete |
| WATCH-01    | Phase 7  | Complete |
| WATCH-02    | Phase 7  | Complete |
| WATCH-03    | Phase 7  | Complete |
| WATCH-04    | Phase 7  | Complete |
| AUTO-01     | Phase 7  | Complete |
| AUTO-02     | Phase 7  | Complete |
| AUTO-03     | Phase 7  | Complete |
| API-01      | Phase 8  | Complete |
| API-02      | Phase 8  | Complete |
| API-03      | Phase 8  | Complete |
| API-04      | Phase 8  | Complete |
| API-05      | Phase 8  | Complete |
| API-06      | Phase 8  | Complete |
| API-07      | Phase 8  | Complete |
| BAR-01      | Phase 9  | Pending |
| BAR-02      | Phase 9  | Pending |
| BAR-03      | Phase 9  | Pending |
| BAR-04      | Phase 9  | Pending |
| BAR-05      | Phase 9  | Pending |
| EXT-03      | Phase 9  | Pending |
| DEP-01      | Phase 10 | Pending |
| DEP-02      | Phase 10 | Pending |
| DEP-03      | Phase 10 | Pending |
| DEP-04      | Phase 10 | Pending |
| EXT-01      | Phase 10 | Pending |
| EXT-02      | Phase 10 | Pending |
| EXT-04      | Phase 10 | Pending |
