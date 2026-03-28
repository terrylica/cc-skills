# Phase 22: Bionic Reading Mode - Context

<!-- # SSoT-OK -->

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (--auto flag)

<domain>
## Phase Boundary

Users can toggle a bold-prefix reading mode that makes subtitle text easier to scan at a glance. When enabled, each word renders with bold first ~40% of characters and regular-weight remainder. Toggleable via SwiftBar settings menu and HTTP API. Bionic rendering and karaoke highlighting are mutually exclusive.

</domain>

<decisions>
## Implementation Decisions

### Display Mode

- **D-01:** Bionic and karaoke are mutually exclusive display modes (per milestone decision). Single DisplayMode enum: `.karaoke`, `.bionic`, `.plain`.
- **D-02:** Bold first ~40% of characters per word. Use `NSAttributedString` with `.bold` font trait for the prefix portion.
- **D-03:** Toggling bionic mode disables karaoke highlighting. Toggling karaoke disables bionic.

### Control Surface

- **D-04:** SwiftBar settings menu gets a "Bionic Reading" toggle item.
- **D-05:** HTTP API endpoint `POST /settings/subtitle` accepts `displayMode` parameter.
- **D-06:** SettingsStore persists the display mode to disk.

### Claude's Discretion

- Whether to compute 40% by character count or by Unicode scalar count
- NSFont weight for the bold prefix (system bold vs. semibold)
- How to handle single-character words (all bold? skip?)

</decisions>

<canonical_refs>

## Canonical References

### Source Code

- `plugins/claude-tts-companion/Sources/CompanionCore/SubtitlePanel.swift` — NSPanel with NSAttributedString rendering
- `plugins/claude-tts-companion/Sources/CompanionCore/SubtitleStyle.swift` — Font/color constants
- `plugins/claude-tts-companion/Sources/CompanionCore/SettingsStore.swift` — Persistent settings
- `plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift` — Settings endpoints
- `.planning/ROADMAP.md` — Phase 22 success criteria (BION-01 through BION-04)
- `.planning/REQUIREMENTS.md` — Bionic Reading requirement definitions

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- SubtitlePanel already uses NSAttributedString for karaoke highlighting
- SettingsStore has persistence pattern for all settings
- HTTPControlServer has `POST /settings/subtitle` endpoint

### Integration Points

- SubtitlePanel.show(text:) and SubtitlePanel.showUtterance() need display mode awareness
- SettingsStore needs displayMode property
- HTTPControlServer subtitle settings need displayMode parameter

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond ROADMAP success criteria.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

_Phase: 22-bionic-reading-mode_
_Context gathered: 2026-03-28 via --auto mode_
