# Phase 11: Notification Formatting — Context

**Gathered:** 2026-03-26
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure porting phase — discuss skipped)

<domain>
## Phase Boundary

Port the legacy Telegram notification formatting from TypeScript to Swift. Rich HTML session notifications with metadata header, markdown-to-HTML conversion, fence-aware chunking at 4096 chars, and file reference wrapping.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — infrastructure porting phase.

**Source files to port from:**

- `~/.claude/automation/claude-telegram-sync/src/claude-sync/formatter.ts` — renderMessage(), metadata extraction
- `~/.claude/automation/claude-telegram-sync/src/claude-sync/format.ts` — markdownToTelegramHtml(), chunkTelegramHtml()
- `~/.claude/automation/claude-telegram-sync/src/claude-sync/fences.ts` — parseFenceSpans(), isSafeFenceBreak()

**Key porting requirements:**

- Session metadata header: project name, path (~/ substituted), session ID (8-char), git branch, duration, turn count
- Markdown → Telegram HTML: **bold**, _italic_, `code`, `pre`, [links]
- File reference wrapping: .md, .py, .go, .sh etc. wrapped in `<code>` to prevent Telegram auto-linking
- Fence-aware chunking: split at 4096 chars, close/reopen fences across chunks
- Arc Summary shows last prompt (condensed if >800 chars) + AI narrative
- Tail Brief sent as separate silent message

**Integration points:**

- TelegramBot.swift — sendSessionNotification() needs to use the new formatting
- TelegramFormatter.swift (Phase 5) — already exists but needs to be replaced/upgraded with legacy-parity formatting
- TranscriptParser.swift (Phase 6) — provides parsed transcript data

</decisions>

<code_context>

## Existing Code Insights

### Reusable Assets

- TelegramFormatter.swift (Phase 5) — has basic HTML escaping + chunking, needs upgrade
- TranscriptParser.swift (Phase 6) — JSONL parsing
- TelegramBot.swift (Phase 5) — sendNotification(), sendSessionNotification()
- Config.swift — Telegram constants

### Files to Modify

- TelegramFormatter.swift — major rewrite to match legacy formatting
- TelegramBot.swift — update sendSessionNotification() to use new formatting

</code_context>

<specifics>
## Specific Ideas

Port directly from TypeScript source — don't reinvent.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
