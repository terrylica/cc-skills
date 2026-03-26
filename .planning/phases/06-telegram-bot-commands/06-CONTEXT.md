# Phase 06: Telegram Bot Commands — Context

**Gathered:** 2026-03-26
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Advanced Telegram bot commands: /prompt with model selection (--haiku, --sonnet, --opus), Claude CLI subprocess integration (Process + Pipe, streaming NDJSON), session resume via Agent SDK, and JSONL transcript parsing for prompts/responses/tool counts.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — pure infrastructure phase.

Requirements:
- BOT-05: /prompt --haiku, --sonnet, --opus model selection
- BOT-06: Resume existing Claude Code sessions via Agent SDK subprocess
- BOT-07: JSONL transcript parsing (prompts, responses, tool counts)
- CLI-01: /prompt spawns claude CLI as subprocess via Process + Pipe
- CLI-02: Streaming NDJSON parsed and forwarded to Telegram as edit-in-place
- CLI-03: CLAUDECODE env var unset before spawning subprocess

Key references:
- Existing TypeScript bot at ~/.claude/automation/claude-telegram-sync/src/ (command patterns)
- Foundation Process + Pipe for subprocess management
- NDJSON streaming via pipe stdout reading

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- TelegramBot.swift (Phase 5) — command handler registration pattern
- TelegramFormatter.swift (Phase 5) — HTML formatting + chunking
- Config.swift — add claude CLI path constant

### Integration Points
- New commands register in TelegramBot's dispatcher
- Claude CLI subprocess output → Telegram edit-in-place updates
- JSONL parsing feeds transcript data for summaries

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>
