# Phase 04: AI Summaries — Context

**Gathered:** 2026-03-26
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

MiniMax API generates session narratives in three formats (Arc Summary, Tail Brief, Single-turn) with circuit breaker failure resilience. Uses URLSession for HTTPS calls with JSON encoding/decoding.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — pure infrastructure phase.

Key references:

- Spike 11: MiniMax integration from Swift via URLSession — validated
- Existing TypeScript implementation at ~/.claude/automation/claude-telegram-sync/src/summary/ (reference for prompts and format)
- MiniMax API endpoint and key from existing system's environment

Three summary formats:

1. **Arc Summary (SUM-01)**: Full-session narrative from JSONL transcript
2. **Tail Brief (SUM-02)**: End-weighted narrative (20% context, 80% final turn)
3. **Single-turn (SUM-03)**: "you prompted me X ago to..." narrative
4. **Circuit breaker (SUM-04)**: 3 consecutive failures → disable for 5 minutes

</decisions>

<code_context>

## Existing Code Insights

### Reusable Assets

- Config.swift — add MiniMax API key/endpoint constants
- Existing TypeScript summary system at ~/.claude/automation/claude-telegram-sync/src/summary/
- URLSession (system framework) — no additional dependencies needed

### Established Patterns

- Dedicated DispatchQueue for background work (from TTSEngine)
- swift-log Logger for structured logging
- Error types with descriptive cases (TTSError pattern)

### Integration Points

- Summary engine is called by Telegram bot (Phase 5) after session end
- JSONL transcript parsing needed (Phase 7 does file watching, but basic parsing needed here)
- MiniMax API key from environment variable or config

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>
