<!-- # SSoT-OK -->

# Phase 25: Python TTS Server Timestamp Endpoint - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

Add `/v1/audio/speech-with-timestamps` endpoint to the existing Python MLX Kokoro TTS server. Returns JSON with base64 WAV bytes and per-word onset/duration arrays from mlx-audio MToken.start_ts/end_ts. This is the foundation — Swift companion will consume this endpoint in Phase 26.

**Why this approach:** mlx-swift IOAccelerator leak is by design (+2.3GB/call, ml-explore/mlx #1086). Python MLX = +4MB/call with zero leak. Only Python MLX provides both stable memory AND word-level timestamps (MToken). sherpa-onnx durations field is NULL. FluidAudio CoreML has no timestamp API. No Rust/candle Kokoro implementation exists. Evidence: benchmark-\*.md files.

</domain>

<decisions>
## Implementation Decisions

### Endpoint Design

- **D-01:** New endpoint `/v1/audio/speech-with-timestamps` — separate from existing `/v1/audio/speech` (returns raw WAV bytes) and `/v1/audio/speak` (queues playback). New endpoint returns JSON only, no playback.
- **D-02:** Response JSON format: `{"audio_b64": "<base64 WAV>", "words": [{"text": "Hello", "onset": 0.0, "duration": 0.45}, ...], "audio_duration": 5.67, "sample_rate": 24000}`
- **D-03:** Word timestamps from mlx-audio `result.tokens` → MToken.start_ts/end_ts (native duration model output). Filter punctuation-only tokens.
- **D-04:** Use Python 3.13 ONLY (user policy). Use `uv` for all Python tooling (user policy).

### Service Dependency

- **D-05:** Python TTS server launchd plist should use KeepAlive to ensure it's running when Swift companion starts. No launchd dependency ordering needed — Swift companion already health-checks and retries.

### Claude's Discretion

- Whether to modify existing `tts_server.py` or create a separate handler
- JSON serialization library (stdlib json vs orjson which is already a dependency)
- Whether to include phoneme data in the response

</decisions>

<canonical_refs>

## Canonical References

### Source Code

- `~/.local/share/kokoro/tts_server.py` — Existing Python TTS server (add endpoint here)
- `~/.local/share/kokoro/kokoro_common.py` — Shared synthesis function with MToken access
- `~/Library/LaunchAgents/com.terryli.kokoro-tts-server.plist` — Launchd service config
- `.planning/REQUIREMENTS.md` — PTS-01, PTS-02, PTS-03 requirement definitions

### Benchmark Evidence

- `plugins/claude-tts-companion/.planning/debug/benchmark-python-mlx-baseline.md`
- `plugins/claude-tts-companion/.planning/debug/benchmark-sherpa-onnx.md`
- `plugins/claude-tts-companion/.planning/debug/benchmark-fluidaudio.md`
- `plugins/claude-tts-companion/.planning/debug/tts-runtime-alternatives-research.md`

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- `kokoro_common.py` already has `synthesize()` returning numpy audio + access to model.generate() tokens
- `tts_server.py` has `_handle_speech()` pattern for new endpoint
- orjson is already installed in the venv for fast JSON serialization

### Integration Points

- New endpoint follows existing pattern: parse JSON body → synthesize → return response
- MToken access: mlx-audio's `model.generate()` yields results with `.tokens` attribute
- Base64 encoding: stdlib `base64.b64encode()` for WAV bytes

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

_Phase: 25-python-tts-server-timestamp-endpoint_
_Context gathered: 2026-03-28 via auto mode (infrastructure phase)_
