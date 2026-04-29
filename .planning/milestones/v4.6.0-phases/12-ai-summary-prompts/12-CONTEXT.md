# Phase 12: AI Summary Prompts — Context

**Gathered:** 2026-03-26
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure porting phase — discuss skipped)

<domain>
## Phase Boundary

Port the exact MiniMax prompt templates from legacy TypeScript to Swift. Arc Summary (multi-turn), Tail Brief (end-weighted), Single-exchange, prompt condensing, and noise pattern filtering.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — infrastructure porting phase.

**Source files to port from:**

- `~/.claude/automation/claude-telegram-sync/src/claude-sync/summarizer.ts` — summarizeSessionArc(), summarizeTailBrief(), summarizeSession()
- `~/.claude/automation/claude-telegram-sync/src/claude-sync/summary-model.ts` — querySummaryModel(), circuit breaker
- `~/.claude/automation/claude-telegram-sync/src/claude-sync/transcript-parser.ts` — noise patterns, content extraction

**Key porting requirements:**

- Arc Summary: exact legacy prompt with turn-by-turn transcript, 2000/4000/1500 char budgets, 102400 total
- Tail Brief: exact legacy prompt with 20% context / 80% final turn, 3000/8000 char budgets
- Single-exchange: ||| delimiter parsing, "you prompted me X ago to..." format
- Prompt condensing: >800 chars → MiniMax condensed to <150 words
- Noise pattern filtering: all legacy patterns (system-reminder, command-name, etc.)

</decisions>

<code_context>

## Existing Code Insights

### Files to Modify

- SummaryEngine.swift (Phase 4) — needs major rewrite with exact legacy prompts
- MiniMaxClient.swift (Phase 4) — may need response parsing fixes
- TranscriptParser.swift (Phase 6) — add noise pattern filtering

</code_context>

<specifics>
Port directly from TypeScript source — don't reinvent. Use the exact prompt templates.
</specifics>

<deferred>
None.
</deferred>
