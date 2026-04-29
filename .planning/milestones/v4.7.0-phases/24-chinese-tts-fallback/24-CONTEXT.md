<!-- # SSoT-OK -->

# Phase 24: Chinese TTS Fallback - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (--auto flag)

<domain>
## Phase Boundary

CJK text is automatically spoken via sherpa-onnx Chinese voice while English continues through the default kokoro-ios MLX engine. The sherpa-onnx Chinese model loads on first CJK request (not at startup) to avoid RSS bloat. Graceful fallback to subtitle-only if model is missing or synthesis fails.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion. Use ROADMAP success criteria (CJK-01 through CJK-04) and existing patterns (LanguageDetector, TTSEngine actor) to guide decisions.

Key constraints from prior phases:

- LanguageDetector already detects >20% CJK text (Phase 14, TTS-12)
- TTSEngine is now a Swift actor (Phase 19) — new synthesis path integrates within actor
- sherpa-onnx was the original TTS engine (replaced by kokoro-ios MLX in quick task) — C headers may still exist
- Chinese model uses load-on-demand with 30-second idle cooldown (milestone decision)
- Graceful fallback pattern: log warning + subtitle-only display (per CJK-04)

</decisions>

<canonical_refs>

## Canonical References

### Source Code

- `plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift` — Actor-based TTS (add CJK routing)
- `plugins/claude-tts-companion/Sources/CompanionCore/LanguageDetector.swift` — CJK detection (>20% threshold)
- `plugins/claude-tts-companion/Sources/CompanionCore/PlaybackManager.swift` — Audio playback
- `plugins/claude-tts-companion/Package.swift` — Dependencies (may need sherpa-onnx addition)
- `.planning/ROADMAP.md` — Phase 24 success criteria (CJK-01 through CJK-04)
- `.planning/REQUIREMENTS.md` — Chinese TTS requirement definitions

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- LanguageDetector.cjkPercentage() already computes CJK ratio
- TTSEngine actor pattern for synthesis dispatch
- CircuitBreaker for failure resilience
- Subtitle-only fallback pattern from Phase 21 (memory pressure)

### Integration Points

- TTSEngine.synthesize/synthesizeWithTimestamps/synthesizeStreaming need CJK routing
- LanguageDetector called before synthesis to determine engine
- New sherpa-onnx dependency in Package.swift (or use system-installed libs)

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond ROADMAP success criteria.

</specifics>

<deferred>
## Deferred Ideas

- CJK karaoke word timing (tokenization is a separate problem — out of scope per REQUIREMENTS.md)

</deferred>

---

_Phase: 24-chinese-tts-fallback_
_Context gathered: 2026-03-28 via --auto mode_
