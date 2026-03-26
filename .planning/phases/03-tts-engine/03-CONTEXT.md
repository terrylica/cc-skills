# Phase 03: TTS Engine — Context

**Gathered:** 2026-03-26
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

The binary synthesizes speech from text with word-level timestamps that drive the subtitle overlay. Uses sherpa-onnx C API with Kokoro int8 model for synthesis, afplay subprocess for playback, and duration tensor extraction for zero-drift word timestamps.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — pure infrastructure phase. Use ROADMAP phase goal, success criteria, and spike findings to guide decisions.

Key spike references:

- Spike 03/09: sherpa-onnx TTS synthesis, int8 model (561MB peak RSS)
- Spike 13b: Timestamped model — bit-identical audio, zero-drift word timestamps
- Spike 16: ONNX timestamps from Swift — ~50 lines C++ patch for duration tensor
- Spike 10: E2E flow — subtitle + TTS + afplay, zero deadlocks

Key technical decisions (from PROJECT.md):

- sherpa-onnx static libs with C API via CSherpaOnnx module (Phase 1 established)
- Dedicated serial DispatchQueue for synthesis (TTS-02)
- Lazy model loading on first synthesis request (TTS-03)
- 24kHz mono 16-bit WAV output via afplay subprocess (TTS-08)
- Duration tensor extracted from patched sherpa-onnx for word timestamps (TTS-06)
- Word timestamps with zero accumulated drift (TTS-07)

</decisions>

<code_context>

## Existing Code Insights

### Reusable Assets

- CSherpaOnnx C module target (Phase 1) — `import CSherpaOnnx` works
- Config.swift — `Config.sherpaOnnxPath` and `Config.kokoroModelPath` already defined
- SubtitlePanel.swift (Phase 2) — `showUtterance(_:wordTimings:)` accepts text + timing array
- sherpa-onnx static libraries at build path with linker flags in Package.swift

### Established Patterns

- @MainActor for UI operations (Phase 2)
- DispatchQueue for background work
- Logging via swift-log Logger

### Integration Points

- TTS engine produces word timings → feeds SubtitlePanel.showUtterance()
- afplay subprocess plays WAV file → runs concurrently with subtitle display
- Model path from Config.kokoroModelPath

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. Refer to ROADMAP phase description and success criteria.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>
