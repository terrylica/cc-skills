# Phase 07: File Watching & Auto-Continue — Context

**Gathered:** 2026-03-26
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Event-driven file monitoring for notification files and JSONL transcript tailing. Auto-continue hook evaluates session completion via MiniMax (CONTINUE/SWEEP/REDIRECT/DONE). Plan file discovery from transcript.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — pure infrastructure phase.

Key references:
- Spike 15: Offset-based JSONL tailing at 0.34ms P95
- DispatchSource.makeFileSystemObjectSource(.write) for file watching
- DispatchSource watchers stored as strong references (no ARC deallocation)

Requirements:
- WATCH-01: Notification file watcher for .json files in notification directory
- WATCH-02: JSONL file tailer with offset tracking
- WATCH-03: DispatchSource watchers as strong references
- WATCH-04: File watcher latency under 100ms
- AUTO-01: Stop hook evaluates via MiniMax (CONTINUE/SWEEP/REDIRECT/DONE)
- AUTO-02: Plan file discovery scans transcript for .claude/plans/*.md
- AUTO-03: SWEEP mode injects 5-step review pipeline

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- SummaryEngine.swift (Phase 4) — MiniMax API calls for evaluation
- TranscriptParser.swift (Phase 6) — JSONL parsing
- TelegramBot.swift (Phase 5) — notification delivery
- TTSEngine.swift (Phase 3) — TTS dispatch
- Config.swift — add notification directory path

### Integration Points
- File watcher detects notification → calls SummaryEngine → sends via TelegramBot
- JSONL tailer feeds TranscriptParser
- Auto-continue evaluates session → decides CONTINUE/SWEEP/REDIRECT/DONE

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>
