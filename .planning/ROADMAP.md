# Roadmap: claude-tts-companion

<!-- # SSoT-OK -->

## Milestones

- ✅ **v4.5.0 MVP** - Phases 1-10 (shipped)
- ✅ **v4.6.0 Legacy Pipeline Feature Parity** - Phases 11-17 (shipped 2026-03-27)
- ✅ **v4.7.0 Architecture Hardening + Feature Expansion** - Phases 18-24 (shipped 2026-03-28)
- 🚧 **v4.8.0 Python MLX TTS Consolidation** - Phases 25-28 (in progress)

## Overview

Replace three separate processes (TypeScript Telegram bot + Python TTS server + Swift subtitle prototype) with a single Swift binary running as a macOS LaunchAgent. The build follows dependency order: foundation first (everything depends on Package.swift), then the two core value props (subtitle overlay, TTS engine), then the bot ecosystem (summaries, core bot, advanced commands), then the event-driven subsystems (file watching, HTTP API), and finally the control surface and deployment (SwiftBar, launchd cutover). Ten phases, each delivering a coherent, testable capability.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

<details>
<summary>v4.5.0 MVP (Phases 1-10)</summary>

- [x] **Phase 1: Foundation & Build System** - Package.swift compiles with all dependencies, bridging header works, binary runs
- [x] **Phase 2: Subtitle Overlay** - Floating karaoke subtitle panel visible on screen with all visual properties
- [ ] **Phase 3: TTS Engine** - Kokoro int8 synthesis produces audio with word-level timestamps
- [ ] **Phase 4: AI Summaries** - MiniMax API generates session narratives with circuit breaker protection
- [ ] **Phase 5: Telegram Bot Core** - Bot connects, handles basic commands, sends session notifications
- [x] **Phase 6: Telegram Bot Commands** - Bot supports model selection, session resume, CLI subprocess integration (completed 2026-03-26)
- [x] **Phase 7: File Watching & Auto-Continue** - Event-driven file monitoring and MiniMax-evaluated auto-continue (completed 2026-03-26)
- [ ] **Phase 8: HTTP Control API** - External control surface for settings, health, subtitle, and TTS
- [ ] **Phase 9: SwiftBar Integration** - Menu bar plugin controls all subsystems via HTTP API
- [x] **Phase 10: Deployment & Extras** - Launchd service, rollback, caption history, clipboard, thinking watcher (completed 2026-03-26)

</details>

<details>
<summary>v4.6.0 Legacy Pipeline Feature Parity (Phases 11-17)</summary>

- [x] **Phase 11: Notification Formatting** - Rich HTML session notifications with fence-aware chunking and file reference wrapping
- [x] **Phase 12: AI Summary Prompts** - Exact legacy prompts ported for Arc Summary, Tail Brief, and single-exchange summarizer
- [x] **Phase 13: Auto-Continue Evaluation** - Full legacy evaluation logic with state tracking, rich notifications, and sweep fallback
- [x] **Phase 14: TTS Dispatch & Feature Gates** - Wire TTS to Tail Brief output with language detection and per-outlet feature gates
- [x] **Phase 15: Telegram Inline Buttons** - Interactive buttons on notifications for Focus Tab, Follow Up, and Transcript
- [x] **Phase 16: Integration & Reliability** - Deduplication, rate limiting, circuit breaker, stop hook, and tool breakdown
- [x] **Phase 17: TTS Streaming & Subtitle Chunking** - Paged karaoke subtitles with pixel-width chunking and streaming TTS

</details>

<details>
<summary>v4.7.0 Architecture Hardening + Feature Expansion (Phases 18-24)</summary>

- [x] **Phase 18: CompanionCore Library & Test Infrastructure** - Extract library target from executable, enable `swift test` with initial unit tests
- [x] **Phase 19: TTSEngine Decomposition & Actor Migration** - Decompose god object into isolated components, replace NSLock with actors
- [x] **Phase 20: Unit & Integration Tests** - Full test coverage for decomposed components and streaming pipeline
- [x] **Phase 20.1: MLX Metal Memory Lifecycle** - Aggressive cache clearing, synthesis-count auto-restart, IOAccelerator leak mitigation (INSERTED)
- [x] **Phase 21: Pipeline Hardening** - Edge-case resilience for rapid-fire, hardware disconnect, memory pressure, and race conditions
- [x] **Phase 22: Bionic Reading Mode** - Bold-prefix word splitting in subtitles with HTTP API and SwiftBar toggles
- [x] **Phase 23: Caption History Panel** - Scrollable past-captions panel with timestamps and copy-to-clipboard
- [x] **Phase 24: Chinese TTS Fallback** - CJK text routed to sherpa-onnx engine with on-demand model loading

</details>

### v4.8.0 Python MLX TTS Consolidation (Phases 25-28)

- [ ] **Phase 25: Python TTS Server Timestamp Endpoint** - Python MLX server exposes word-level timestamp API that Swift consumes via HTTP
- [ ] **Phase 26: Swift TTSEngine Python Integration** - TTSEngine delegates to Python server with native word onsets, replacing character-weighted fallback
- [ ] **Phase 27: MLX Dependency Removal** - kokoro-ios, mlx-swift, MLXUtilsLibrary stripped from Package.swift and all imports
- [ ] **Phase 28: Memory Lifecycle Cleanup** - Synthesis-count restart and IOAccelerator mitigation code removed (no MLX in Swift process)

## Phase Details

<details>
<summary>v4.5.0 MVP Phase Details (Phases 1-10)</summary>

### Phase 1: Foundation & Build System

**Goal**: The project compiles and runs as a macOS accessory app with all dependencies resolved
**Depends on**: Nothing (first phase)
**Requirements**: BUILD-01, BUILD-02, BUILD-03, BUILD-04
**Success Criteria** (what must be TRUE):

1. `swift build -c release` succeeds with zero errors and produces a single binary under 30MB
2. Package.swift resolves swift-telegram-sdk v4.5.0 and links sherpa-onnx static libraries without conflicts
3. Bridging header imports sherpa-onnx C API and ONNX Runtime C API; a trivial C function call succeeds
4. Binary launches as NSApplication accessory app, logs to stdout, and exits cleanly on SIGTERM
   **Plans**: 2 plans

Plans:

- [x] 01-01-PLAN.md -- SwiftPM scaffold: CSherpaOnnx module map + Package.swift + Config.swift
- [x] 01-02-PLAN.md -- App entry point (main.swift) + plugin registration + build verification

### Phase 2: Subtitle Overlay

**Goal**: Users see floating karaoke subtitles on their macOS screen with all visual and privacy properties
**Depends on**: Phase 1
**Requirements**: SUB-01, SUB-02, SUB-03, SUB-04, SUB-05, SUB-06, SUB-07, SUB-08, SUB-09, SUB-10, SUB-11
**Success Criteria** (what must be TRUE):

1. A floating subtitle panel appears on the MacBook built-in display showing text with dark 30% opacity background
2. Words highlight in warm gold as they are "spoken" (driven by test timings), with past words dimming to silver-grey
3. Panel is invisible to screen sharing, does not steal focus, is click-through, and appears on all Spaces
4. Long text word-wraps to 2 lines without shrinking font size
5. NSAttributedString updates complete in under 1ms per word transition
   **Plans**: 2 plans

Plans:

- [x] 02-01-PLAN.md -- SubtitleStyle constants + SubtitlePanel NSPanel with all window behaviors
- [x] 02-02-PLAN.md -- Karaoke highlighting engine + demo mode + main.swift wiring + visual checkpoint
      **UI hint**: yes

### Phase 3: TTS Engine

**Goal**: The binary synthesizes speech from text with word-level timestamps that drive the subtitle overlay
**Depends on**: Phase 2
**Requirements**: TTS-01, TTS-02, TTS-03, TTS-04, TTS-05, TTS-06, TTS-07, TTS-08
**Success Criteria** (what must be TRUE):

1. User hears synthesized speech played through afplay from text input
2. Synthesis runs on a background queue without blocking the subtitle UI
3. Word timestamps extracted from duration tensor drive karaoke highlighting with zero accumulated drift
4. Model loads lazily on first request; peak RSS stays under 700MB during synthesis
5. Synthesis speed is at least 1.5x real-time (no gaps during playback)
   **Plans**: 2 plans

Plans:

- [x] 03-01-PLAN.md -- Patch sherpa-onnx for duration tensor + TTSEngine with synthesis/WAV/afplay
- [ ] 03-02-PLAN.md -- Word timestamp extraction + karaoke integration + main.swift wiring + verification
      **UI hint**: yes

### Phase 4: AI Summaries

**Goal**: MiniMax API generates session narratives in three formats with failure resilience
**Depends on**: Phase 1
**Requirements**: SUM-01, SUM-02, SUM-03, SUM-04
**Success Criteria** (what must be TRUE):

1. Arc Summary produces a full-session narrative from a JSONL transcript via MiniMax API
2. Tail Brief produces an end-weighted narrative (20% context, 80% final turn)
3. Single-turn summary produces a "you prompted me X ago to..." narrative
4. After 3 consecutive MiniMax failures, summaries disable for 5 minutes (circuit breaker)
   **Plans**: 2 plans

Plans:

- [x] 21-01-PLAN.md -- TTSPipelineCoordinator: exclusive pipeline access, rapid-fire subtitle-only fallback, concurrent TTS test race elimination
- [x] 21-02-PLAN.md -- Audio route change recovery (AVAudioEngine config change) + memory pressure subtitle-only degradation

### Phase 5: Telegram Bot Core

**Goal**: Bot connects to Telegram, handles basic commands, and sends session notifications with TTS
**Depends on**: Phase 3, Phase 4
**Requirements**: BOT-01, BOT-02, BOT-03, BOT-04, BOT-08
**Success Criteria** (what must be TRUE):

1. Bot connects via long polling and responds to /start, /stop, /status, /health, /sessions, /done, /commands
2. Bot sends session-end notifications containing Arc Summary and Tail Brief
3. Bot dispatches TTS for Tail Brief text with karaoke subtitle overlay
4. Messages use HTML formatting with fence-aware chunking at 4096 char limit
   **Plans**: 2 plans

Plans:

- [x] 21-01-PLAN.md -- TTSPipelineCoordinator: exclusive pipeline access, rapid-fire subtitle-only fallback, concurrent TTS test race elimination
- [ ] 21-02-PLAN.md -- Audio route change recovery (AVAudioEngine config change) + memory pressure subtitle-only degradation

### Phase 6: Telegram Bot Commands

**Goal**: Bot supports model selection, session resume, and Claude CLI subprocess integration
**Depends on**: Phase 5
**Requirements**: BOT-05, BOT-06, BOT-07, CLI-01, CLI-02, CLI-03
**Success Criteria** (what must be TRUE):

1. /prompt command with --haiku, --sonnet, --opus flags spawns Claude CLI with the selected model
2. Claude CLI runs as subprocess via Process + Pipe with CLAUDECODE env var unset
3. Streaming NDJSON response is parsed and forwarded to Telegram as edit-in-place updates
4. Bot resumes existing sessions via Agent SDK subprocess
5. JSONL transcript parsing extracts prompts, responses, and tool counts accurately
   **Plans**: 2 plans

Plans:

- [x] 06-01-PLAN.md -- Model selection + session resume + CLI subprocess
- [x] 06-02-PLAN.md -- NDJSON streaming + edit-in-place + transcript parsing

### Phase 7: File Watching & Auto-Continue

**Goal**: Event-driven file monitoring triggers notifications; auto-continue evaluates session completion
**Depends on**: Phase 5
**Requirements**: WATCH-01, WATCH-02, WATCH-03, WATCH-04, AUTO-01, AUTO-02, AUTO-03
**Success Criteria** (what must be TRUE):

1. New .json files in the notification directory are detected within 100ms and trigger bot notifications
2. JSONL file tailer reads new bytes from growing transcripts via offset tracking
3. DispatchSource watchers persist as strong references (no silent ARC deallocation)
4. Stop hook evaluates session completion via MiniMax and returns CONTINUE/SWEEP/REDIRECT/DONE
5. SWEEP mode injects 5-step review pipeline; plan file discovery scans transcript for .claude/plans/\*.md
   **Plans**: 2 plans

Plans:

- [x] 07-01-PLAN.md -- FileWatcher: NotificationWatcher + JSONLTailer with DispatchSource
- [x] 07-02-PLAN.md -- AutoContinueEvaluator + main.swift wiring

### Phase 8: HTTP Control API

**Goal**: External programs can query health, read/write settings, and control subtitle/TTS via HTTP
**Depends on**: Phase 3
**Requirements**: API-01, API-02, API-03, API-04, API-05, API-06, API-07
**Success Criteria** (what must be TRUE):

1. GET /health returns subsystem status (bot, TTS, subtitle) with RSS and uptime
2. GET /settings returns all current settings; POST /settings/\* updates subtitle and TTS configuration
3. POST /subtitle/show displays text on screen; POST /subtitle/hide dismisses it
4. Settings persist to disk and survive binary restart
5. All endpoints respond in under 200ms
   **Plans**: 2 plans

Plans:

- [x] 08-01-PLAN.md -- FlyingFox dependency + SettingsStore persistence + HTTPControlServer endpoints
- [ ] 08-02-PLAN.md -- Wire HTTP server into main.swift + build verification

### Phase 9: SwiftBar Integration

**Goal**: Menu bar plugin provides unified control surface for all subsystems via HTTP API
**Depends on**: Phase 8
**Requirements**: BAR-01, BAR-02, BAR-03, BAR-04, BAR-05, EXT-03
**Success Criteria** (what must be TRUE):

1. claude-hq v3.0.0 plugin monitors single unified service (com.terryli.claude-tts-companion)
2. SwiftBar menu shows subtitle controls (font S/M/L, position, karaoke toggle) and TTS controls (enable/disable, test)
3. Menu actions call HTTP API endpoints with response under 200ms
4. SwiftBar shows per-subsystem health status from /health endpoint
5. User can switch subtitle display to external monitor via SwiftBar menu
   **Plans**: 2 plans

Plans:

- [ ] 21-01-PLAN.md -- TTSPipelineCoordinator: exclusive pipeline access, rapid-fire subtitle-only fallback, concurrent TTS test race elimination
- [ ] 21-02-PLAN.md -- Audio route change recovery (AVAudioEngine config change) + memory pressure subtitle-only degradation
      **UI hint**: yes

### Phase 10: Deployment & Extras

**Goal**: Binary runs as a managed launchd service with rollback capability and polish features
**Depends on**: Phase 9
**Requirements**: DEP-01, DEP-02, DEP-03, DEP-04, EXT-01, EXT-02, EXT-04
**Success Criteria** (what must be TRUE):

1. Single launchd plist (com.terryli.claude-tts-companion) manages the binary with auto-restart
2. Existing services (telegram-bot, kokoro-tts-server) are stopped but plists preserved on disk
3. Rollback script re-enables old services and stops unified binary in under 30 seconds
4. User can scroll through caption history and copy subtitle text to clipboard
5. Thinking watcher summarizes Claude's extended thinking via MiniMax
   **Plans**: 2 plans

Plans:

- [x] 10-01-PLAN.md -- Launchd plist + rollback script + service cutover
- [x] 10-02-PLAN.md -- Caption history + clipboard copy + thinking watcher

</details>

<details>
<summary>v4.6.0 Legacy Pipeline Feature Parity Phase Details (Phases 11-17)</summary>

### Phase 11: Notification Formatting

**Goal**: Session notifications arrive in Telegram with rich HTML formatting identical to the legacy TypeScript pipeline
**Depends on**: Phase 10 (existing bot infrastructure)
**Requirements**: FMT-01, FMT-02, FMT-03, FMT-04, FMT-05, FMT-06
**Success Criteria** (what must be TRUE):

1. Session notification header displays project name, session ID (8-char), git branch, duration, and turn count in structured HTML
2. Arc Summary message shows the last prompt (condensed if >800 chars) followed by AI narrative with transition words
3. Tail Brief is sent as a separate silent Telegram message after Arc Summary
4. Markdown bold, italic, code, pre, and links convert correctly to Telegram HTML entities
5. Messages exceeding 4096 chars split at fence-aware boundaries with fence close/reopen across chunks, and file references (.md, .py, .go, .sh) are wrapped to prevent Telegram auto-linking
   **Plans**: 2 plans

Plans:

- [x] 11-01-PLAN.md -- TelegramFormatter upgrade: renderSessionNotification, meta-tag stripping, file ref wrapping, fence close/reopen chunking
- [x] 11-02-PLAN.md -- Wire formatting into TelegramBot + main.swift: rich header, separate silent Tail Brief, metadata extraction

### Phase 12: AI Summary Prompts

**Goal**: MiniMax summarization uses the exact legacy prompts with correct transcript budgeting and noise filtering
**Depends on**: Phase 11 (formatting pipeline delivers summaries)
**Requirements**: PROMPT-01, PROMPT-02, PROMPT-03, PROMPT-04, PROMPT-05
**Success Criteria** (what must be TRUE):

1. Arc Summary prompt matches legacy verbatim, with turn-by-turn transcript respecting 2000/4000/1500 char budgets per section
2. Tail Brief prompt matches legacy verbatim, with 20% context / 80% final turn weighting applied to transcript input
3. Single-exchange summarizer produces "you prompted me X ago to..." output with ||| delimiter parsing for multi-segment responses
4. Prompts exceeding 800 chars are condensed to under 150 words via MiniMax before display
5. System-injected noise patterns (tool results, environment blocks) are stripped from transcripts before summarization
   **Plans**: 2 plans

Plans:

- [x] 12-01-PLAN.md -- Noise filtering and improved turn extraction in TranscriptParser
- [x] 12-02-PLAN.md -- Exact legacy prompt templates and prompt condensing in SummaryEngine

### Phase 13: Auto-Continue Evaluation

**Goal**: Stop hook evaluates session completion with full legacy logic including state tracking, rich notifications, and sweep fallback
**Depends on**: Phase 12 (summary prompts feed evaluation context)
**Requirements**: EVAL-01, EVAL-02, EVAL-03, EVAL-04, EVAL-05, EVAL-06
**Success Criteria** (what must be TRUE):

1. MiniMax evaluation returns CONTINUE/SWEEP/REDIRECT/DONE using the exact legacy system prompt with plan context
2. Plan files are discovered from both the transcript and sibling JSONL files in the session directory
3. Per-session state tracks iteration count, sweep status, and manual intervention detection across multiple stop-hook invocations
4. Decision notification sent to Telegram includes icon, reason, progress bar, tool breakdown, and timing
5. When plan checkboxes are all checked but no review section exists, evaluation deterministically returns SWEEP without calling MiniMax
   **Plans**: 2 plans

Plans:

- [x] 13-01-PLAN.md -- Full legacy evaluation logic with state tracking, exact prompts, sibling plan discovery
- [x] 13-02-PLAN.md -- Rich decision notifications and main.swift wiring

### Phase 14: TTS Dispatch & Feature Gates

**Goal**: Tail Brief text is automatically spoken via Kokoro TTS with language-aware voice selection and per-outlet toggles
**Depends on**: Phase 12 (Tail Brief generation), Phase 3 (TTS engine)
**Requirements**: TTS-10, TTS-11, TTS-12, TTS-13
**Success Criteria** (what must be TRUE):

1. After Tail Brief generation, text is dispatched to Kokoro TTS and played with karaoke subtitle overlay
2. TTS greeting prepends "Hi Terry, you were working in {project}:" before the Tail Brief text
3. Text with >20% CJK characters switches voice from af_heart to zf_xiaobei
4. Each notification outlet (Telegram summary, TTS brief, auto-continue) can be independently enabled/disabled via feature gates
   **Plans**: 2 plans

Plans:

- [x] 14-01-PLAN.md -- LanguageDetector + FeatureGates + Config constants
- [x] 14-02-PLAN.md -- Wire feature gates and language detection into TelegramBot

### Phase 15: Telegram Inline Buttons

**Goal**: Notification messages include interactive inline buttons for quick actions
**Depends on**: Phase 11 (notification messages to attach buttons to)
**Requirements**: BTN-01, BTN-02, BTN-03
**Success Criteria** (what must be TRUE):

1. Arc Summary notification includes Focus Tab, Follow Up, and Transcript inline buttons below the message
2. Pressing Focus Tab switches to the iTerm tab where the session ran
3. When a new notification arrives for the same iTerm tab, buttons are removed from the older message (deduplication)
   **Plans**: 2 plans
   **UI hint**: yes

Plans:

- [x] 15-01-PLAN.md -- InlineButtonManager + callback handlers + keyboard attachment
- [x] 15-02-PLAN.md -- Wire itermSessionId into notification flow + build verification + visual checkpoint

### Phase 16: Integration & Reliability

**Goal**: The notification pipeline handles edge cases, deduplicates, rate-limits, and fails gracefully matching legacy reliability
**Depends on**: Phase 13 (auto-continue), Phase 14 (TTS dispatch), Phase 15 (buttons)
**Requirements**: REL-01, REL-02, REL-03, REL-04, REL-05
**Success Criteria** (what must be TRUE):

1. Duplicate notifications are skipped when the transcript file has not grown since the last notification for that session
2. Notification processing is rate-limited to at most one every 5 seconds
3. Circuit breaker trips after 3 consecutive MiniMax failures, enters 5-minute cooldown, and uses fallback narrative during cooldown
4. Stop hook writes notification JSON to the correct directory with all required fields (project, session ID, branch, transcript path, duration, turns)
5. Tool breakdown computes top 6 tools by count, excluding subagent orchestration tools (Task, Bash spawning agents)
   **Plans**: 1 plan

Plans:

- [x] 16-01-PLAN.md -- NotificationProcessor with dedup + rate limiting + main.swift wiring + build verification

### Phase 17: TTS Streaming & Subtitle Chunking

**Goal**: TTS audio starts playing within 5 seconds of session end; subtitles display one sentence at a time with karaoke word highlighting
**Depends on**: Phase 14
**Requirements**: STREAM-01, STREAM-02, STREAM-03
**Success Criteria** (what must be TRUE):

1. First audio starts playing within 5 seconds of TTS dispatch (paragraph-level synthesis)
2. Subtitle panel shows one sentence at a time, advancing as each sentence completes
3. Karaoke gold word highlighting advances within each displayed sentence
   **Plans**: 2 plans
   **UI hint**: yes

Plans:

- [x] 17-01-PLAN.md -- SubtitleChunker + SubtitlePanel paged karaoke refactor
- [x] 17-02-PLAN.md -- Wire chunker into TelegramBot.dispatchTTS() + visual verification

</details>

<details>
<summary>v4.7.0 Architecture Hardening + Feature Expansion Phase Details (Phases 18-24)</summary>

### Phase 18: CompanionCore Library & Test Infrastructure

**Goal**: All business logic is testable via `swift test` through a library target extraction
**Depends on**: Phase 17 (existing codebase from v4.6.0)
**Requirements**: ARCH-01, TEST-01
**Success Criteria** (what must be TRUE):

1. `swift test` runs and passes with at least one unit test for a pure type (e.g., SubtitleChunker or LanguageDetector)
2. `main.swift` is the only file in the executable target -- all business logic lives in CompanionCore library
3. `@testable import CompanionCore` works in the test target without build errors
   **Plans**: 2 plans

Plans:

- [x] 18-01-PLAN.md -- CompanionCore library extraction + CompanionApp coordinator + thin main.swift
- [x] 18-02-PLAN.md -- Unit tests for LanguageDetector, SubtitleChunker, TelegramFormatter, TranscriptParser, CircuitBreaker

### Phase 19: TTSEngine Decomposition & Actor Migration

**Goal**: TTSEngine is a thin stateless facade delegating to actor-isolated components with compile-time concurrency safety
**Depends on**: Phase 18
**Requirements**: ARCH-02, ARCH-03, ARCH-04, ARCH-05, ARCH-06, CONC-01, CONC-02, CONC-03, CONC-04
**Success Criteria** (what must be TRUE):

1. PlaybackManager owns AVAudioPlayer lifecycle and pre-buffering as a @MainActor-isolated class
2. WordTimingAligner and PronunciationProcessor are pure structs with no mutable state
3. TTSEngine delegates all work to extracted components -- it holds no mutable state and no NSLock
4. All callers (TelegramBot, HTTPControlServer, SubtitleSyncDriver) compile and work against the decomposed API without behavior changes
5. `swift build` produces zero `@unchecked Sendable` warnings for any TTSEngine-related type
   **Plans**: 2 plans

Plans:

- [x] 19-01-PLAN.md -- Extract pure structs (WordTimingAligner, PronunciationProcessor, SentenceSplitter) + PlaybackDelegate + TTSError
- [x] 19-02-PLAN.md -- PlaybackManager @MainActor extraction + TTSEngine actor migration + caller updates

### Phase 20: Unit & Integration Tests

**Goal**: Decomposed components have test coverage that catches regressions before they reach production
**Depends on**: Phase 19
**Requirements**: TEST-02, TEST-03, TEST-04, TEST-05
**Success Criteria** (what must be TRUE):

1. SubtitleChunker tests verify page splitting, line breaks, and font size variants produce correct output
2. WordTimingAligner tests verify MToken-to-word alignment, onset resolution, and hyphenated word handling
3. PronunciationProcessor tests verify override dictionary matching and regex boundary behavior
4. Integration test verifies a mock synthesis produces correctly sequenced chunks through the streaming pipeline
   **Plans**: 2 plans

Plans:

- [x] 20-01-PLAN.md -- Unit tests for WordTimingAligner, PronunciationProcessor, SentenceSplitter
- [x] 20-02-PLAN.md -- Expanded SubtitleChunker tests + streaming pipeline integration test

### Phase 20.1: MLX Metal Memory Lifecycle

**Goal**: MLX Metal GPU memory is bounded and reclaimed between TTS sessions, preventing IOAccelerator leak from exhausting system RAM
**Depends on**: Phase 18 (CompanionCore for testability)
**Requirements**: LEAK-01, LEAK-02, LEAK-03
**Success Criteria** (what must be TRUE):

1. kokoro-ios fork sets `Memory.cacheLimit` to <=20MB and calls `Memory.clearCache()` after each `generateAudio()` call
2. Service exits cleanly after N synthesis sessions; launchd auto-restarts within 2 seconds
3. IOAccelerator (graphics) memory stays under 4GB across 10 consecutive TTS sessions without manual restart
4. No regression in audio quality -- batch-then-play pattern preserved, gapless playback confirmed
   **Plans**: 1 plan

Plans:

- [x] 20.1-01-PLAN.md -- kokoro-ios cache reduction + synthesis counter + graceful restart + launchd tuning

**Context**: MLX-Swift creates ~1.7-6GB of unreclaimable IOAccelerator (Metal driver) allocations per synthesis call. Confirmed intentional by design (ml-explore/mlx issue #1086). The static MetalAllocator pools buffers and only frees on process exit. `Memory.clearCache()` manages MLX internal buffer pool but not Metal driver allocations. Process restart is the only 100% reclamation mechanism.

### Phase 21: Pipeline Hardening

**Goal**: The streaming pipeline handles edge cases gracefully without crashes, queue corruption, or resource exhaustion
**Depends on**: Phase 20
**Requirements**: HARD-01, HARD-02, HARD-03, HARD-04
**Success Criteria** (what must be TRUE):

1. Five notifications arriving within 10 seconds are processed without crash or audio queue corruption
2. Disconnecting Bluetooth headphones mid-playback recovers gracefully (audio resumes on default output or subtitle-only fallback)
3. Under simulated memory pressure during synthesis, the binary degrades to subtitle-only mode rather than crashing
4. A TTS test request arriving simultaneously with a real notification does not produce interleaved or corrupted audio
   **Plans**: 2 plans

Plans:

- [x] 21-01-PLAN.md -- TTSPipelineCoordinator: exclusive pipeline access, rapid-fire subtitle-only fallback, concurrent TTS test race elimination
- [x] 21-02-PLAN.md -- Audio route change recovery (AVAudioEngine config change) + memory pressure subtitle-only degradation

### Phase 22: Bionic Reading Mode

**Goal**: Users can toggle a bold-prefix reading mode that makes subtitle text easier to scan at a glance
**Depends on**: Phase 18
**Requirements**: BION-01, BION-02, BION-03, BION-04
**Success Criteria** (what must be TRUE):

1. User can toggle bionic reading on/off from the SwiftBar settings menu
2. User can toggle bionic reading on/off via HTTP API endpoint
3. When enabled, each word in the subtitle renders with bold first ~40% of characters and regular-weight remainder
4. Bionic rendering and karaoke highlighting are mutually exclusive -- enabling one disables the other
   **Plans**: 2 plans

Plans:

- [x] 22-01-PLAN.md -- DisplayMode enum + BionicRenderer + SettingsStore + HTTP API + SubtitlePanel integration + tests
- [x] 22-02-PLAN.md -- SwiftBar Bionic Reading toggle + visual verification checkpoint
      **UI hint**: yes

### Phase 23: Caption History Panel

**Goal**: Users can review and copy past subtitle captions from a scrollable panel
**Depends on**: Phase 18
**Requirements**: CAPT-01, CAPT-02, CAPT-03, CAPT-04
**Success Criteria** (what must be TRUE):

1. User can open a scrollable panel showing past captions with HH:MM timestamps
2. Panel auto-scrolls to the latest caption, but manual scrolling up pauses auto-scroll until user returns to bottom
3. User can click a caption to copy its text to the clipboard as plain text
4. Panel is accessible via both a SwiftBar menu button and an HTTP API endpoint
   **Plans**: 2 plans

Plans:

- [x] 23-01-PLAN.md -- CaptionHistoryPanel NSPanel + HTTP API endpoints + CompanionApp wiring
- [x] 23-02-PLAN.md -- SwiftBar Caption History button + visual verification checkpoint
      **UI hint**: yes

### Phase 24: Chinese TTS Fallback

**Goal**: CJK text is automatically spoken via sherpa-onnx Chinese voice while English continues through the default engine
**Depends on**: Phase 19
**Requirements**: CJK-01, CJK-02, CJK-03, CJK-04
**Success Criteria** (what must be TRUE):

1. Text with >20% CJK characters is synthesized using the sherpa-onnx multilingual engine instead of kokoro-ios MLX
2. English text continues to use the kokoro-ios MLX engine with no behavior change
3. The sherpa-onnx Chinese model loads on first CJK request (not at startup) to avoid RSS bloat
4. If the sherpa-onnx model file is missing or synthesis fails, the system logs a warning and falls back to subtitle-only display
   **Plans**: 2 plans

Plans:

- [x] 24-01-PLAN.md -- CSherpaOnnx C module + SherpaOnnxEngine with on-demand model loading
- [x] 24-02-PLAN.md -- Wire CJK routing into TTSEngine + TelegramBot dispatch + build verification

</details>

### v4.8.0 Python MLX TTS Consolidation Phase Details

### Phase 25: Python TTS Server Timestamp Endpoint

**Goal**: Python MLX server exposes a word-level timestamp API so Swift can receive native per-word onset/duration data over HTTP instead of computing character-weighted fallbacks

**Why Python MLX**: mlx-swift IOAccelerator leak is by design (+2.3GB/call, ml-explore/mlx #1086). Python MLX leaks only +4MB/call. sherpa-onnx Kokoro `durations` field is NULL (no word timestamps without C++ patching). FluidAudio CoreML has no word-level timestamp API (opaque compiled graphs). No Rust/candle Kokoro implementation exists. Evidence: `benchmark-python-mlx-baseline.md`, `benchmark-sherpa-onnx.md`, `benchmark-fluidaudio.md`, `tts-runtime-alternatives-research.md`.

**Why word timestamps are non-negotiable**: Karaoke subtitle highlighting requires per-word onset/duration data. Character-weighted fallback produces visible drift on multi-syllable words. Native duration model output (MToken.start_ts/end_ts) gives zero-drift timing.

**Depends on**: Phase 24 (existing codebase from v4.7.0)
**Requirements**: PTS-01, PTS-02, PTS-03
**Success Criteria** (what must be TRUE):

1. `curl localhost:PORT/v1/audio/speech-with-timestamps -d '{"input":"Hello world"}'` returns JSON containing base64 WAV bytes and per-word onset/duration arrays
2. Word timestamps come from mlx-audio MToken.start_ts/end_ts (duration model native output), not character-weighted approximation
3. Python server runs as a launchd service that starts automatically before claude-tts-companion via service dependency ordering
   **Plans**: 1 plan

Plans:

- [x] 25-01-PLAN.md — synthesize_with_timestamps + /v1/audio/speech-with-timestamps endpoint + launchd verification

### Phase 26: Swift TTSEngine Python Integration

**Goal**: TTSEngine delegates all English TTS to the Python server and feeds native word onsets into SubtitleSyncDriver, eliminating character-weighted fallback timing

**Depends on**: Phase 25 (Python server must be running and returning timestamps)
**Requirements**: SWI-01, SWI-02, SWI-03
**Success Criteria** (what must be TRUE):

1. TTSEngine sends text to Python server via HTTP, parses the JSON response, and passes native word onsets to SubtitleSyncDriver
2. Karaoke subtitle gold highlighting advances using Python-derived word onsets with zero accumulated drift across a 60-second passage
3. `tts_kokoro.sh` CLI script synthesizes and plays audio end-to-end via the Swift companion -> Python server chain
   **Plans**: 1 plan
   **UI hint**: yes

Plans:

- [x] 26-01-PLAN.md -- Switch TTSEngine to /v1/audio/speech-with-timestamps + native word onset passthrough

### Phase 27: MLX Dependency Removal

**Goal**: kokoro-ios, mlx-swift, and MLXUtilsLibrary are completely removed from Package.swift, producing a smaller binary with no MLX-related symbols

**Depends on**: Phase 26 (Swift no longer imports MLX for English TTS)
**Requirements**: DEP-01, DEP-02, DEP-03, DEP-04, DEP-05
**Success Criteria** (what must be TRUE):

1. Package.swift has zero references to kokoro-ios, mlx-swift, or MLXUtilsLibrary
2. `grep -r 'import MLX\|import KokoroSwift\|import MLXUtilsLibrary' Sources/` returns zero matches
3. `swift build -c release` succeeds with zero errors and no MLX-related symbols in the binary
4. Stripped release binary is under 20 MB (down from ~25+ MB with MLX dependencies)
   **Plans**: 1 plan

Plans:

- [x] 27-01-PLAN.md — Remove MLX packages from Package.swift, strip dead MToken code, update tests, verify binary size

### Phase 28: Memory Lifecycle Cleanup

**Goal**: All IOAccelerator leak mitigation code is removed because there is no MLX running in the Swift process -- the companion stays under 100 MB RSS indefinitely

**Depends on**: Phase 27 (MLX dependencies must be gone first)
**Requirements**: MEM-01, MEM-02, MEM-03
**Success Criteria** (what must be TRUE):

1. Synthesis-count restart logic is removed from TTSEngine (no `exit(42)`, no counter, no `checkMemoryLifecycleRestart`)
2. MemoryLifecycle.swift is either deleted or reduced to a no-op stub (no IOAccelerator mitigation code remains)
3. Swift companion RSS stays under 100 MB across 50+ consecutive TTS calls (all synthesis happens in Python process, not Swift)
   **Plans**: 1 plan

Plans:

- [x] 28-01-PLAN.md — Delete MemoryLifecycle.swift, strip restart logic from TTSEngine/CompanionApp/TelegramBot/HTTPControlServer

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> ... -> 10 -> 11 -> 12 -> 13 -> 14 -> 15 -> 16 -> 17 -> 18 -> 19 -> 20 -> 20.1 -> 21 -> 22 -> 23 -> 24 -> 25 -> 26 -> 27 -> 28

| Phase                                           | Plans Complete | Status      | Completed  |
| ----------------------------------------------- | -------------- | ----------- | ---------- |
| 1. Foundation & Build System                    | 2/2            | Complete    | -          |
| 2. Subtitle Overlay                             | 2/2            | Complete    | -          |
| 3. TTS Engine                                   | 1/2            | In progress | -          |
| 4. AI Summaries                                 | 0/0            | Not started | -          |
| 5. Telegram Bot Core                            | 0/0            | Not started | -          |
| 6. Telegram Bot Commands                        | 2/2            | Complete    | 2026-03-26 |
| 7. File Watching & Auto-Continue                | 2/2            | Complete    | 2026-03-26 |
| 8. HTTP Control API                             | 1/2            | In progress | -          |
| 9. SwiftBar Integration                         | 0/0            | Not started | -          |
| 10. Deployment & Extras                         | 2/2            | Complete    | 2026-03-26 |
| 11. Notification Formatting                     | 2/2            | Complete    | 2026-03-27 |
| 12. AI Summary Prompts                          | 2/2            | Complete    | 2026-03-27 |
| 13. Auto-Continue Evaluation                    | 2/2            | Complete    | 2026-03-27 |
| 14. TTS Dispatch & Feature Gates                | 2/2            | Complete    | 2026-03-27 |
| 15. Telegram Inline Buttons                     | 2/2            | Complete    | 2026-03-27 |
| 16. Integration & Reliability                   | 1/1            | Complete    | 2026-03-27 |
| 17. TTS Streaming & Subtitle Chunking           | 2/2            | Complete    | 2026-03-27 |
| 18. CompanionCore Library & Test Infrastructure | 2/2            | Complete    | 2026-03-28 |
| 19. TTSEngine Decomposition & Actor Migration   | 2/2            | Complete    | 2026-03-28 |
| 20. Unit & Integration Tests                    | 2/2            | Complete    | 2026-03-28 |
| 20.1. MLX Metal Memory Lifecycle                | 1/1            | Complete    | 2026-03-28 |
| 21. Pipeline Hardening                          | 2/2            | Complete    | 2026-03-28 |
| 22. Pipeline Hardening                          | 2/2            | Complete    | 2026-03-28 |
| 22. Bionic Reading Mode                         | 2/2            | Complete    | 2026-03-28 |
| 23. Caption History Panel                       | 2/2            | Complete    | 2026-03-28 |
| 24. Chinese TTS Fallback                        | 2/2            | Complete    | 2026-03-28 |
| 25. Python TTS Server Timestamp Endpoint        | 1/1            | Complete    | 2026-03-28 |
| 26. Swift TTSEngine Python Integration          | 1/1            | Complete    | 2026-03-28 |
| 27. MLX Dependency Removal                      | 1/1 | Complete    | 2026-03-28 |
| 28. Memory Lifecycle Cleanup                    | 1/1 | Complete    | 2026-03-28 |
