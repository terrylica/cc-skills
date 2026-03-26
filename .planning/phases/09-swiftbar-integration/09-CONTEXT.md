# Phase 09: SwiftBar Integration — Context

**Gathered:** 2026-03-26
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Updated SwiftBar plugin (claude-hq v3.0.0) monitors the unified service via HTTP API. Menu shows subtitle controls (font S/M/L, position, karaoke toggle), TTS controls, and per-subsystem health status. External monitor switching via SwiftBar.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — infrastructure phase.

Requirements:
- BAR-01: claude-hq v3.0.0 monitors single unified service
- BAR-02: SwiftBar menu shows subtitle controls
- BAR-03: SwiftBar menu shows TTS controls
- BAR-04: Actions call HTTP API endpoints (response under 200ms)
- BAR-05: Shows per-subsystem health status from /health
- EXT-03: Switch subtitle display to external monitor

Key: The SwiftBar plugin is Python (244 lines, not being rewritten in Swift per project constraints). It calls HTTP endpoints at localhost:8780.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Existing SwiftBar plugin at ~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.py (v2.0.0)
- HTTP API from Phase 8 at localhost:8780
- All endpoints defined in HTTPControlServer.swift

### Integration Points
- SwiftBar calls GET/POST to localhost:8780/*
- Plugin outputs SwiftBar menu format (pipe-delimited)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>
