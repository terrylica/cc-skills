# Phase 08: HTTP Control API — Context

**Gathered:** 2026-03-26
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

HTTP server via FlyingFox providing health, settings, subtitle, and TTS control endpoints. External programs (SwiftBar) can query and control subsystems.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — pure infrastructure phase.

Key references:
- FlyingFox v0.26.2 already in Package.swift (lightweight HTTP, pure BSD sockets + Swift Concurrency)
- Spike 08: designed for raw BSD sockets; FlyingFox wraps them

Requirements:
- API-01: GET /health — subsystem status with RSS and uptime
- API-02: GET /settings — all current settings as JSON
- API-03: POST /settings/subtitle — fontSize, position, screen, opacity, karaoke toggle
- API-04: POST /settings/tts — enabled, voice, speed toggles
- API-05: POST /subtitle/show — display subtitle text with optional duration
- API-06: POST /subtitle/hide — dismiss current subtitle
- API-07: Settings persist to disk and survive binary restart

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- FlyingFox dependency in Package.swift
- SubtitlePanel.swift (Phase 2) — show/hide/updateAttributedText
- SubtitleStyle.swift (Phase 2) — fontSize presets
- TTSEngine.swift (Phase 3) — synthesis control
- Config.swift — add HTTP port constant

### Integration Points
- HTTP endpoints control SubtitlePanel, TTSEngine
- Settings persistence: JSON file at known path
- Health endpoint reports all subsystem states

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>
