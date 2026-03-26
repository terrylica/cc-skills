# claude-tts-companion

## What This Is

A single Swift binary that consolidates the Telegram session bot, Kokoro TTS engine, and a new subtitle overlay into one macOS launchd service. Replaces three separate processes (Swift runner + Bun/TypeScript bot + Python TTS server) with a unified ~27MB idle / 561MB peak binary. Includes word-level karaoke subtitles synced with TTS playback for silent-mode session consumption.

## Core Value

**See what Claude says, anywhere** — real-time karaoke subtitles overlaid on your macOS screen, synced with TTS playback or displayed standalone when audio is off. One binary, one service, one control surface.

## Current Milestone: v4.6.0 Legacy Pipeline Feature Parity

**Goal:** Port the working Telegram + TTS notification pipeline from the legacy TypeScript system to claude-tts-companion with full feature parity.

**Target features:**

- Session-end notification with rich HTML formatting (repo, commit, branch, duration, turns, tool breakdown)
- Arc Summary + Tail Brief generation via MiniMax with exact legacy prompts
- Auto-continue evaluation (CONTINUE/SWEEP/REDIRECT/DONE) with Telegram delivery
- TTS dispatch of Tail Brief via Kokoro af_heart with karaoke subtitles
- Stop hook integration and inline Telegram buttons
- Circuit breaker + error handling matching legacy reliability

**Source:** `~/.claude/automation/claude-telegram-sync/` (port directly, don't reinvent)

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Unified Swift binary replacing telegram-bot-runner + bun bot + python TTS server
- [ ] Word-level karaoke subtitle overlay with gold highlighting (NSPanel, NSAttributedString)
- [ ] Kokoro TTS synthesis via sherpa-onnx (int8 quantized, 561MB peak RSS)
- [ ] Subtitle timing from duration model timestamps (zero-drift, zero-cost)
- [ ] Telegram bot via swift-telegram-sdk (long polling, no Vapor)
- [ ] AI session summaries via MiniMax API (URLSession)
- [ ] JSONL transcript parsing (Foundation, line-by-line streaming at 67 MB/s)
- [ ] Claude CLI subprocess integration (Process + Pipe, streaming NDJSON)
- [ ] File watcher for notification files (DispatchSource + FSEvents)
- [ ] JSONL file tailing for thinking watcher (offset-based, 0.34ms P95)
- [ ] Auto-continue hook with MiniMax evaluation
- [ ] HTTP control API (settings, health, subtitle, TTS endpoints)
- [ ] SwiftBar integration (font size S/M/L, position top/center/bottom, screen selection)
- [ ] Screen sharing auto-hide (NSWindow.sharingType = .none)
- [ ] MacBook built-in display default, configurable to external
- [ ] Scrollable caption history
- [ ] Copy-to-clipboard for subtitle text
- [ ] Single launchd service (com.example.claude-tts-companion)
- [ ] Updated SwiftBar plugin (claude-hq v3.0.0) monitoring unified service

### Out of Scope

- CoreML/FluidAudio path — evaluated in Spike 05, sherpa-onnx wins for this use case
- Bionic reading mode — interesting but deferred (Spike 17 research)
- Focus mode / DND integration — no public macOS API (Spike 21)
- Rewriting SwiftBar plugin in Swift — 244 lines of Python, not worth porting (Spike 06)

## Context

**23 spikes completed** with 6,500+ lines of reports at `~/tmp/subtitle-spikes-7aqa/`:

| Spike | Key Finding                                                               |
| ----- | ------------------------------------------------------------------------- |
| 02    | Swift subtitle overlay: 88KB binary, 19MB RSS                             |
| 03/09 | sherpa-onnx TTS: 19MB binary, int8 model cuts RSS 49% to 561MB            |
| 04    | Swift Telegram bot: 4.5MB binary, 8.6MB RSS (6.7x lighter than Bun)       |
| 08    | Integration architecture: no dependency conflicts, Package.swift designed |
| 10    | E2E flow: subtitle + TTS + afplay, zero deadlocks                         |
| 13b   | Timestamped model: bit-identical audio, zero-drift word timestamps        |
| 16    | ONNX timestamps from Swift: patch sherpa-onnx ~50 lines C++               |
| 19    | Word karaoke: 6us per update, 37x headroom                                |
| 21    | Privacy: `sharingType = .none`, multi-monitor works                       |
| 22-23 | Visual tuning: dark 30% opacity bg, word-wrap (no shrink), S/M/L presets  |

**Existing system being replaced:**

- `~/.claude/automation/claude-telegram-sync/` — TypeScript bot (keep for reference)
- `~/.local/share/kokoro/tts_server.py` — Python TTS server (keep for reference)
- `~/Library/LaunchAgents/com.example.telegram-bot.plist` — stop, don't delete
- `~/Library/LaunchAgents/com.example.kokoro-tts-server.plist` — stop, don't delete

**Rollout strategy:** All or nothing. Stop existing services, start unified binary. Old code preserved for reference.

## Constraints

- **Platform**: macOS Apple Silicon only (Apple Silicon required for sherpa-onnx/MLX)
- **macOS version**: macOS 14+ (for swift-telegram-sdk, sherpa-onnx)
- **Python**: Not used — pure Swift + C (sherpa-onnx static libs)
- **Build**: `swift build` via SwiftPM (not Xcode) for the main binary; sherpa-onnx C++ libs pre-built
- **Model**: Kokoro int8 English at `~/.local/share/kokoro/models/kokoro-int8-en-v0_19/` (129MB on disk)
- **Display**: Default to MacBook built-in (2056x1329), configurable to external via SwiftBar

## Key Decisions

| Decision                           | Rationale                                                           | Outcome   |
| ---------------------------------- | ------------------------------------------------------------------- | --------- |
| sherpa-onnx over CoreML/FluidAudio | 3.9GB CoreML models overkill; sherpa-onnx proven in 5 spikes        | — Pending |
| swift-telegram-sdk over raw API    | 266 stars but only viable modern Swift library                      | — Pending |
| Patch sherpa-onnx for timestamps   | ~50 lines C++ vs reimplementing phonemization in Swift (300+ lines) | — Pending |
| Word-wrap over auto-shrink         | User preference: font size differences must be visible              | — Pending |
| Dark 30% opacity background        | User-approved in Spike 22 visual tuning session                     | — Pending |
| All-or-nothing rollout             | User preference: stop old services, don't delete code               | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):

1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):

1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---

_Last updated: 2026-03-25 after initialization_
