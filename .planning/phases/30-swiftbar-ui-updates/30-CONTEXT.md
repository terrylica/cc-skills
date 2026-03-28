<!-- # SSoT-OK -->

# Phase 30: SwiftBar UI Updates - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

Update SwiftBar plugin to show Python TTS server health, proper bot status, and settings propagation to Python server.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

- Add Python TTS server health check (curl <http://127.0.0.1:8779/health>) to Service section
- Show green/red dot + PID + RSS for Python server alongside Swift companion
- Bot status: parse "bot" field from /health — show "connected" (green), "watching" (green), "disabled" (grey)
- Voice/Speed: verify SwiftBar POST /settings/tts propagates to Python server via Swift companion

</decisions>

<canonical_refs>

## Canonical References

- `~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.sh` — Main SwiftBar plugin
- `~/Library/Application Support/SwiftBar/Plugins/nc-action.sh` — Action handler
- `.planning/REQUIREMENTS.md` — BAR-10, BAR-11, BAR-12

</canonical_refs>

<code_context>

## Existing Code Insights

- claude-hq.10s.sh already queries <http://localhost:8780/health> for Swift companion status
- Python server at <http://127.0.0.1:8779/health> returns JSON with status, model, device fields
- nc-action.sh handles SwiftBar menu actions via curl to HTTP API

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond ROADMAP success criteria.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

_Phase: 30-swiftbar-ui-updates_
_Context gathered: 2026-03-28 via auto mode_
