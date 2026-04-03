# Phase 1: Single-Consumer Consolidation - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Companion owns the entire notification lifecycle with no competing consumers. Remove the Bun bot's notification watcher so the companion is the sole consumer of `~/.claude/notifications/` JSON files. The Bun bot retains /prompt and /sessions commands — only the notification watching code is removed.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — pure infrastructure phase. Key constraints:

- The Stop hook at `plugins/tts-tg-sync/hooks/telegram-notify-stop.ts` writes to `~/.claude/notifications/` — this path MUST NOT change
- The Bun bot's `/prompt` and `/sessions` commands at `~/.claude/automation/claude-telegram-sync/src/telegram/commands.ts` must continue working after the notification watcher is removed
- The Bun bot's `main.ts` imports and starts the notification watcher — this initialization must be removed or disabled without breaking other subsystems
- Check if removing the notification watcher from the Bun bot also removes the `lastSessionBox` and Q&A text handler we just added — if so, those need to stay

</decisions>

<code_context>

## Existing Code Insights

### Files to Modify

- `~/.claude/automation/claude-telegram-sync/src/main.ts` — remove watchNotifications() call
- `~/.claude/automation/claude-telegram-sync/src/claude-sync/notification-watcher.ts` — remove or disable entirely

### Files to Preserve

- `~/.claude/automation/claude-telegram-sync/src/telegram/commands.ts` — /prompt, /sessions, Q&A handler must stay
- `~/.claude/automation/claude-telegram-sync/src/telegram/bot.ts` — bot factory stays
- `~/.claude/automation/claude-telegram-sync/src/claude-sync/summarizer.ts` — still used by thinking watcher
- Companion's notification processing at `Sources/CompanionCore/CompanionApp.swift` — already the production consumer

### Risk Area

The Bun bot's `notification-watcher.ts` imports `registerNotificationButtons` and `lastSessionBox` from `commands.ts`. These exports are also used by the Q&A text handler. Removing the watcher must NOT remove these exports.

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. Refer to ROADMAP phase description and success criteria.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

_Phase: 01-single-consumer-consolidation_
_Context gathered: 2026-04-02 via autonomous mode (infrastructure skip)_
