# Phase 10: Deployment & Extras — Context

**Gathered:** 2026-03-26
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Binary runs as a managed launchd service with rollback capability. Extras: scrollable caption history, clipboard copy, external monitor switching, thinking watcher.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — infrastructure phase.

Requirements:
- DEP-01: Single launchd plist (com.example.claude-tts-companion)
- DEP-02: Existing services stopped but plists preserved
- DEP-03: Rollback script to re-enable old services
- DEP-04: Kokoro model at canonical path
- EXT-01: Scrollable caption history (last N subtitles)
- EXT-02: Copy subtitle text to clipboard
- EXT-04: Thinking watcher summarizes Claude's thinking via MiniMax

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Config.swift — serviceLabel already defined
- HTTPControlServer (Phase 8) — could add history/clipboard endpoints
- SubtitlePanel (Phase 2) — track history
- SummaryEngine (Phase 4) — MiniMax for thinking summarization
- Existing launchd plists at ~/Library/LaunchAgents/

### Integration Points
- launchd plist references release binary path
- Rollback script toggles between old and new services
- Model path in Config.swift → canonical ~/.local/share/kokoro/

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>
