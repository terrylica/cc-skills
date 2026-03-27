# Roadmap: claude-tts-companion

## Milestones

- 🚧 **v4.5.0 MVP** - Phases 1-10 (in progress)
- 📋 **v4.6.0 Legacy Pipeline Feature Parity** - Phases 11-16 (planned)

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

### v4.6.0 Legacy Pipeline Feature Parity (Phases 11-16)

- [ ] **Phase 11: Notification Formatting** - Rich HTML session notifications with fence-aware chunking and file reference wrapping
- [ ] **Phase 12: AI Summary Prompts** - Exact legacy prompts ported for Arc Summary, Tail Brief, and single-exchange summarizer
- [ ] **Phase 13: Auto-Continue Evaluation** - Full legacy evaluation logic with state tracking, rich notifications, and sweep fallback
- [ ] **Phase 14: TTS Dispatch & Feature Gates** - Wire TTS to Tail Brief output with language detection and per-outlet feature gates
- [ ] **Phase 15: Telegram Inline Buttons** - Interactive buttons on notifications for Focus Tab, Follow Up, and Transcript
- [ ] **Phase 16: Integration & Reliability** - Deduplication, rate limiting, circuit breaker, stop hook, and tool breakdown

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
   **Plans**: TBD

### Phase 5: Telegram Bot Core

**Goal**: Bot connects to Telegram, handles basic commands, and sends session notifications with TTS
**Depends on**: Phase 3, Phase 4
**Requirements**: BOT-01, BOT-02, BOT-03, BOT-04, BOT-08
**Success Criteria** (what must be TRUE):

1. Bot connects via long polling and responds to /start, /stop, /status, /health, /sessions, /done, /commands
2. Bot sends session-end notifications containing Arc Summary and Tail Brief
3. Bot dispatches TTS for Tail Brief text with karaoke subtitle overlay
4. Messages use HTML formatting with fence-aware chunking at 4096 char limit
   **Plans**: TBD

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
   **Plans**: TBD
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

### v4.6.0 Legacy Pipeline Feature Parity Phase Details

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

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> ... -> 10 -> 11 -> 12 -> 13 -> 14 -> 15 -> 16 -> 17

| Phase                                 | Plans Complete | Status      | Completed  |
| ------------------------------------- | -------------- | ----------- | ---------- |
| 1. Foundation & Build System          | 2/2            | Complete    | -          |
| 2. Subtitle Overlay                   | 2/2            | Complete    | -          |
| 3. TTS Engine                         | 1/2            | In progress | -          |
| 4. AI Summaries                       | 0/0            | Not started | -          |
| 5. Telegram Bot Core                  | 0/0            | Not started | -          |
| 6. Telegram Bot Commands              | 2/2            | Complete    | 2026-03-26 |
| 7. File Watching & Auto-Continue      | 2/2            | Complete    | 2026-03-26 |
| 8. HTTP Control API                   | 1/2            | In progress | -          |
| 9. SwiftBar Integration               | 0/0            | Not started | -          |
| 10. Deployment & Extras               | 2/2            | Complete    | 2026-03-26 |
| 11. Notification Formatting           | 2/2            | Complete    | 2026-03-27 |
| 12. AI Summary Prompts                | 2/2            | Complete    | 2026-03-27 |
| 13. Auto-Continue Evaluation          | 2/2            | Complete    | 2026-03-27 |
| 14. TTS Dispatch & Feature Gates      | 2/2            | Complete    | 2026-03-27 |
| 15. Telegram Inline Buttons           | 2/2            | Complete    | 2026-03-27 |
| 16. Integration & Reliability         | 1/1            | Complete    | 2026-03-27 |
| 17. TTS Streaming & Subtitle Chunking | 2/2 | Complete    | 2026-03-27 |

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
