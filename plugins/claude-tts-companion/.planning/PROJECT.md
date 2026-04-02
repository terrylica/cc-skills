# claude-tts-companion — Notification Intelligence Milestone

## What This Is

A unified macOS accessory app that monitors Claude Code sessions and delivers real-time summaries via Telegram, TTS audio, and karaoke subtitles. Replaces three separate processes (Swift runner + Bun/TypeScript bot + Python TTS server) with a single ~18MB binary running under launchd. The companion watches session transcript files, summarizes them via MiniMax, and delivers through multiple "Outlets" (Telegram, TTS, subtitles).

## Core Value

**Every session end produces an accurate, self-explanatory notification** — the user should understand what happened without opening Claude Code. Summaries must reflect the _actual last work done_, not stale intermediate state.

## Requirements

### Validated

- ✓ Session-end Telegram notifications with Arc Summary + Tail Brief — existing
- ✓ TTS audio synthesis via Kokoro (Python server delegation on port 8779) — existing
- ✓ Karaoke subtitle overlay with word-level highlighting — existing
- ✓ Telegram inline buttons (Focus Tab, Ask About This, Transcript) — existing
- ✓ Auto-continue hook for session resumption decisions — existing
- ✓ Circuit breaker on MiniMax API calls — existing
- ✓ Session dedup with transcript-size-growth detection — existing
- ✓ SwiftBar control center (claude-hq.10s.sh) — existing
- ✓ HTTP control API (FlyingFox on port 8780) — existing
- ✓ Thinking block monitor with real-time JSONL tailing — existing

### Active

- [ ] Transcript staleness fix: parse-then-edit (3s re-check) + JSONL tail watcher (catches full 79s gap)
- [ ] MiniMax Q&A refinements: chained follow-ups in companion, better error messages, transcript context caching
- [ ] SwiftBar UX polish: SSH tunnel health, remove legacy references, service section cleanup
- [ ] Notification dedup: consolidate to companion-only consumer (remove Bun bot notification watcher)
- [ ] Self-explanatory messages: all notifications must be verbose and evidential (no vague fallbacks)

### Out of Scope

- Bun bot as notification consumer — consolidating to companion-only (Bun bot retains /prompt, /sessions commands)
- Multi-user monitoring — this is Terry's personal infrastructure, not a SaaS
- iOS/mobile companion — macOS only
- Real-time streaming summaries — batch on session-end only

## Context

**Brownfield project**: ~7,500 lines of Swift across 20+ source files, production since March 2026. Running under launchd with `KeepAlive`. Uses swift-telegram-sdk for bot, FlyingFox for HTTP API, sherpa-onnx for CJK TTS, Python Kokoro server for English TTS.

**Dual notification consumers (legacy)**: Stop hook writes to `~/.claude/notifications/` (companion picks up) AND the Bun bot watches `state/notifications/`. This causes architectural confusion — the companion is the production consumer, the Bun bot only gets synthetic tests. Consolidating to companion-only in this milestone.

**Transcript staleness**: Stop hook fires ~79 seconds before Claude Code finishes writing the JSONL. The companion reads immediately and misses the tail. Root cause spiked and confirmed 2026-04-02.

**28 vague messages fixed**: Auto-continue ("No reason provided") and summarizer ("Session completed.") fallbacks replaced with context-rich messages across both TS and Swift codebases (2026-04-02).

**NASIM bot learnings**: Ported MiniMax Q&A (Ask About This), lastSessionBox pattern, callback cooldown middleware, and notification metadata override from <private-repo> (2026-04-02).

## Constraints

- **Platform**: macOS Apple Silicon only (sherpa-onnx requires ARM64)
- **macOS version**: 14+ (swift-telegram-sdk requirement)
- **Build**: `swift build` via SwiftPM, NOT Xcode
- **Binary**: Single binary at `~/.local/bin/claude-tts-companion`
- **Deploy**: `make` handles build + deploy + restart
- **Python dependency**: Kokoro TTS server on port 8779 must remain (companion delegates English TTS)
- **No breaking changes**: Telegram message format must stay compatible (users have muscle memory for buttons)

## Key Decisions

| Decision                                     | Rationale                                                                      | Outcome   |
| -------------------------------------------- | ------------------------------------------------------------------------------ | --------- |
| Consolidate to companion-only notifications  | Bun bot's notification watcher was a parallel consumer causing confusion       | — Pending |
| Parse-then-edit + tail watcher for staleness | User chose most accurate approach: fast initial delivery with self-correction  | — Pending |
| Port NASIM's MiniMax Q&A to companion        | Read-only Q&A about sessions is more useful than session resume for monitoring | ✓ Good    |
| Replace "Follow Up" with "Ask About This"    | Clearer intent — the button queries MiniMax, not Claude Code                   | ✓ Good    |
| 28 vague messages → context-rich messages    | User policy: every message must be self-explanatory and self-evidential        | ✓ Good    |

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

_Last updated: 2026-04-02 after initialization_
