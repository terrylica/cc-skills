<!-- # SSoT-OK -->

# Phase 26: Swift TTSEngine Python Integration - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

Update TTSEngine to call the Python server's `/v1/audio/speech-with-timestamps` endpoint (from Phase 25) instead of `/v1/audio/speech`. Parse the JSON response to extract native word onsets and pass them to SubtitleSyncDriver for zero-drift karaoke highlighting. Replace the character-weighted timing fallback with real MToken data.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion. Key constraints:

- TTSEngine already delegates to Python server (implemented in the interim fix earlier this session)
- Current code calls `/v1/audio/speech` (returns raw WAV bytes) — change to `/v1/audio/speech-with-timestamps` (returns JSON with WAV + word timing)
- Parse `words` array from JSON → create `[TimeInterval]` onset/duration arrays → pass to SubtitleSyncDriver
- The existing `WordTimingAligner.resolveWordTimings()` should be updated or bypassed — Python provides native timing, no alignment needed
- `tts_kokoro.sh` should continue to work (it calls `/tts/speak` on the Swift companion, not the Python server directly)

</decisions>

<canonical_refs>

## Canonical References

### Source Code

- `plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift` — Already delegates to Python server, needs JSON parsing update
- `plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift` — Consumes word onsets for karaoke
- `plugins/claude-tts-companion/Sources/CompanionCore/WordTimingAligner.swift` — May need updates or bypass
- `~/.local/share/kokoro/tts_server.py` — Python server with new `/v1/audio/speech-with-timestamps` endpoint
- `.planning/REQUIREMENTS.md` — SWI-01, SWI-02, SWI-03 requirement definitions

</canonical_refs>

<code_context>

## Existing Code Insights

### Current TTSEngine Python Delegation

TTSEngine currently calls `http://127.0.0.1:8779/v1/audio/speech` and receives raw WAV bytes.
Needs to switch to `http://127.0.0.1:8779/v1/audio/speech-with-timestamps` which returns:

```json
{
  "audio_b64": "<base64>",
  "words": [{ "text": "Hello", "onset": 0.0, "duration": 0.45 }],
  "audio_duration": 5.67,
  "sample_rate": 24000
}
```

### Integration Points

- TTSEngine.synthesize/synthesizeWithTimestamps/synthesizeStreaming all need JSON parsing
- ChunkResult needs wordOnsets populated from Python response
- SubtitleSyncDriver already accepts wordOnsets — just needs real data instead of null/fallback

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

_Phase: 26-swift-ttsengine-python-integration_
_Context gathered: 2026-03-28 via auto mode_
