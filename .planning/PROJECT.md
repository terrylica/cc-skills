# claude-tts-companion

## What This Is

A single Swift binary that consolidates the Telegram session bot, Kokoro TTS engine, and a new subtitle overlay into one macOS launchd service. Replaces three separate processes (Swift runner + Bun/TypeScript bot + Python TTS server) with a unified ~27MB idle / 561MB peak binary. Includes word-level karaoke subtitles synced with TTS playback for silent-mode session consumption.

## Core Value

**See what Claude says, anywhere** — real-time karaoke subtitles overlaid on your macOS screen, synced with TTS playback or displayed standalone when audio is off. One binary, one service, one control surface.

<!-- SSoT-OK: planning document, not a package version --> <!-- # SSoT-OK -->

## Current State

**Latest milestone:** v4.7.0 Architecture Hardening + Feature Expansion (shipped 2026-03-28)
**Codebase:** 38 Swift source files (10,618 LOC) + 10 test files (923 LOC) in CompanionCore library
**Tests:** 59+ Swift Testing unit/integration tests via `swift test`
**Architecture:** TTSEngine actor + PlaybackManager @MainActor + TTSPipelineCoordinator + 5 pure Sendable structs

## Requirements

### Validated

<!-- # SSoT-OK -->

- ✓ Unified Swift binary replacing telegram-bot-runner + bun bot + python TTS server — v4.5.0
- ✓ Word-level karaoke subtitle overlay with gold highlighting — v4.5.0
- ✓ Kokoro TTS synthesis (kokoro-ios MLX Metal GPU) — v4.5.0/v4.6.0
- ✓ Subtitle timing from duration model timestamps — v4.5.0
- ✓ Telegram bot via swift-telegram-sdk (long polling) — v4.5.0
- ✓ AI session summaries via MiniMax API — v4.5.0
- ✓ JSONL transcript parsing — v4.5.0
- ✓ File watcher for notification files — v4.5.0
- ✓ Auto-continue hook with MiniMax evaluation — v4.6.0
- ✓ HTTP control API — v4.5.0
- ✓ SwiftBar integration — v4.5.0
- ✓ Screen sharing auto-hide — v4.5.0
- ✓ Single launchd service — v4.5.0
- ✓ Rich HTML session notifications with legacy formatting parity — v4.6.0
- ✓ Inline Telegram buttons (Focus Tab/Follow Up/Transcript) — v4.6.0
- ✓ Feature-gated CJK language detection — v4.6.0
- ✓ Paged karaoke subtitles with pixel-width chunking — v4.6.0

- ✓ TTSEngine decomposition into PlaybackManager, WordTimingAligner, PronunciationProcessor — v4.7.0
- ✓ Actor-based concurrency replacing @unchecked Sendable + NSLock — v4.7.0
- ✓ Streaming pipeline edge-case hardening (rapid-fire, hardware disconnect, memory pressure) — v4.7.0
- ✓ Swift Testing infrastructure with 59+ unit + integration tests — v4.7.0
- ✓ Chinese TTS fallback via sherpa-onnx for CJK text — v4.7.0
- ✓ Bionic reading mode (bold/regular word splitting in subtitles) — v4.7.0
- ✓ Scrollable caption history panel with copy-to-clipboard — v4.7.0
- ✓ MLX Metal memory lifecycle with graceful restart — v4.7.0

### Active

(No active requirements — start next milestone with `/gsd:new-milestone`)

### Out of Scope

- CoreML/FluidAudio path — evaluated in Spike 05, sherpa-onnx wins for this use case
- Focus mode / DND integration — no public macOS API (Spike 21)
- Rewriting SwiftBar plugin in Swift — 244 lines of Python, not worth porting (Spike 06)
- CJK karaoke word timing — tokenization is a separate problem

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
- `~/Library/LaunchAgents/com.terryli.telegram-bot.plist` — stop, don't delete
- `~/Library/LaunchAgents/com.terryli.kokoro-tts-server.plist` — stop, don't delete

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

_Last updated: 2026-03-28 after v4.7.0 milestone completion_ <!-- # SSoT-OK -->
