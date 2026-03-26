# Phase 05: Telegram Bot Core — Context

**Gathered:** 2026-03-26
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Bot connects to Telegram via long polling using swift-telegram-sdk, handles basic commands (/start, /stop, /status, /health, /sessions, /done, /commands), sends session notifications with Arc Summary + Tail Brief, dispatches TTS for Tail Brief text with synchronized karaoke subtitles, and sends messages with HTML formatting and fence-aware chunking (4096 char limit).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — pure infrastructure phase.

Key references:

- Spike 04: Swift Telegram bot validated — 4.5MB binary, 8.6MB RSS, long polling without Vapor
- swift-telegram-sdk v4.5.0 already in Package.swift dependencies
- Existing TypeScript bot at ~/.claude/automation/claude-telegram-sync/ (reference for commands and message formatting)
- Bot token from environment variable (TELEGRAM_BOT_TOKEN)
- Must use test bot token during dev to avoid long-polling conflict with production bot (STATE.md blocker)

Requirements:

- BOT-01: Long polling connection via swift-telegram-sdk
- BOT-02: Command handlers for /start, /stop, /status, /health, /sessions, /done, /commands
- BOT-03: Session-end notifications with Arc Summary + Tail Brief
- BOT-04: TTS dispatch for Tail Brief with subtitle overlay
- BOT-08: HTML formatting, fence-aware chunking (4096 char limit)

</decisions>

<code_context>

## Existing Code Insights

### Reusable Assets

- swift-telegram-sdk already linked (Phase 1)
- TTSEngine.swift (Phase 3) — synthesizeWithTimestamps() for TTS dispatch
- SummaryEngine.swift (Phase 4) — arcSummary(), tailBrief() for notifications
- SubtitlePanel.swift (Phase 2) — showUtterance() for karaoke display
- Config.swift — add bot token constant

### Established Patterns

- Dedicated DispatchQueue for background work
- swift-log Logger
- @MainActor for UI operations
- async/await (from MiniMaxClient)

### Integration Points

- Bot receives session-end events → calls SummaryEngine → sends notification
- Bot dispatches TTS for Tail Brief → TTSEngine → SubtitlePanel
- Bot token from Config or environment

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>
