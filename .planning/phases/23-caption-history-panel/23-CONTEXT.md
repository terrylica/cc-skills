<!-- # SSoT-OK -->

# Phase 23: Caption History Panel - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (--auto flag)

<domain>
## Phase Boundary

Users can review and copy past subtitle captions from a scrollable panel. Panel shows past captions with HH:MM timestamps, auto-scrolls to latest, supports manual scroll override, and copy-to-clipboard on click. Accessible via SwiftBar menu button and HTTP API.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion. Use ROADMAP success criteria (CAPT-01 through CAPT-04) and existing patterns (SubtitlePanel NSPanel, SettingsStore, HTTPControlServer, SwiftBar) to guide decisions.

Key constraints from prior phases:

- CaptionHistory ring buffer already exists (Phase 10) — stores past captions
- SubtitlePanel uses NSPanel with AppKit — same pattern for history panel
- HTTP API pattern established for all control surfaces
- SwiftBar plugin pattern established for menu items

</decisions>

<canonical_refs>

## Canonical References

### Source Code

- `plugins/claude-tts-companion/Sources/CompanionCore/CaptionHistory.swift` — Existing ring buffer
- `plugins/claude-tts-companion/Sources/CompanionCore/SubtitlePanel.swift` — NSPanel pattern reference
- `plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift` — API endpoints
- `plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift` — Wiring coordinator
- `.planning/ROADMAP.md` — Phase 23 success criteria (CAPT-01 through CAPT-04)
- `.planning/REQUIREMENTS.md` — Caption History requirement definitions

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- CaptionHistory.swift already has record() and entries access
- NSPanel pattern from SubtitlePanel (floating, click-through options)
- HTTPControlServer endpoint pattern
- SwiftBar menu item pattern from Phase 22

### Integration Points

- CompanionApp creates CaptionHistory and passes to subsystems
- HTTPControlServer needs /captions endpoint
- SwiftBar needs "Caption History" menu button

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

_Phase: 23-caption-history-panel_
_Context gathered: 2026-03-28 via --auto mode_
