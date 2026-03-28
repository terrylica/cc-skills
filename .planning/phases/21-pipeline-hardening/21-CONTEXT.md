# Phase 21: Pipeline Hardening - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

The streaming pipeline handles edge cases gracefully without crashes, queue corruption, or resource exhaustion. Covers: rapid-fire notifications, Bluetooth hardware disconnect, memory pressure degradation, and concurrent TTS test + real notification race conditions.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — infrastructure hardening phase. Use ROADMAP success criteria (HARD-01 through HARD-04) and the decomposed actor architecture from Phase 19 to guide decisions.

Key constraints from prior phases:

- TTSEngine is now a Swift actor (Phase 19) — concurrent access is serialized by the actor
- PlaybackManager is @MainActor (Phase 19) — AVAudioPlayer lifecycle is main-thread-safe
- AudioStreamPlayer uses AVAudioEngine for streaming playback
- Batch-then-play pattern must be preserved (synthesize all chunks, then play — zero GPU during playback)
- NotificationProcessor already has dedup + rate limiting (Phase 16)

</decisions>

<canonical_refs>

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Source Code

- `plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift` — Actor-based TTS facade
- `plugins/claude-tts-companion/Sources/CompanionCore/PlaybackManager.swift` — @MainActor playback
- `plugins/claude-tts-companion/Sources/CompanionCore/AudioStreamPlayer.swift` — AVAudioEngine wrapper
- `plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift` — Streaming subtitle sync
- `plugins/claude-tts-companion/Sources/CompanionCore/NotificationProcessor.swift` — Dedup + rate limiting
- `plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift` — Orchestration coordinator

### Project Context

- `.planning/ROADMAP.md` — Phase 21 success criteria (HARD-01 through HARD-04)
- `.planning/REQUIREMENTS.md` — Hardening requirement definitions

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- NotificationProcessor already handles dedup and 5s rate limiting
- CircuitBreaker exists for MiniMax API failure resilience
- TTSEngine actor serializes concurrent synthesis requests naturally
- 59 tests from Phase 20 provide regression safety net

### Integration Points

- CompanionApp.handleNotification() is the entry point for notification processing
- SubtitleSyncDriver manages the streaming playback pipeline
- PlaybackManager.warmUpAudioHardware() handles CoreAudio re-init after idle

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. Follow ROADMAP success criteria exactly.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>

---

_Phase: 21-pipeline-hardening_
_Context gathered: 2026-03-28 via auto mode (infrastructure phase)_
