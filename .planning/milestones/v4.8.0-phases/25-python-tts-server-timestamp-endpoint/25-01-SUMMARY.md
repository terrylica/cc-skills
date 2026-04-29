---
phase: 25-python-tts-server-timestamp-endpoint
plan: 01
subsystem: tts
tags: [python, mlx, kokoro, tts, timestamps, http-api, karaoke]

# Dependency graph
requires: []
provides:
  - "POST /v1/audio/speech-with-timestamps endpoint returning JSON with base64 WAV + per-word timing"
  - "synthesize_with_timestamps() in kokoro_common.py using MToken.start_ts/end_ts"
affects: [26-swift-tts-native-word-onset]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pipeline-direct access pattern: bypass Kokoro.generate() to get MToken timestamps from KokoroPipeline.Result"
    - "Multi-chunk offset accumulation for word timing across sentence boundaries"

key-files:
  created: []
  modified:
    - "~/.local/share/kokoro/kokoro_common.py"
    - "~/.local/share/kokoro/tts_server.py"

key-decisions:
  - "Access KokoroPipeline directly instead of model.generate() because Kokoro.generate() wraps results into GenerationResult which discards MToken timestamp data"
  - "Squeeze audio array from (1,N) to (N,) to match existing synthesize() output shape -- pipeline returns 2D, Kokoro.generate() does audio[0] internally"

patterns-established:
  - "Pipeline-direct pattern: model._get_pipeline(lang) + pipeline.voices = {} to get KokoroPipeline.Result with .tokens"
  - "Punctuation filtering: re.match(r'^[^\\w]+$', t.text) to exclude punctuation-only tokens from word timing"

requirements-completed: [PTS-01, PTS-02, PTS-03]

# Metrics
duration: 5min
completed: 2026-03-28
---

# Phase 25 Plan 01: Python TTS Server Timestamp Endpoint Summary

**Added /v1/audio/speech-with-timestamps endpoint to Python MLX Kokoro TTS server, returning base64 WAV + per-word onset/duration from native MToken timestamps for karaoke subtitle highlighting**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-28T07:27:03Z
- **Completed:** 2026-03-28T07:31:51Z
- **Tasks:** 2
- **Files modified:** 2 (outside repo at ~/.local/share/kokoro/)

## Accomplishments

- `synthesize_with_timestamps()` function in kokoro_common.py extracts per-word onset/duration from mlx-audio MToken.start_ts/end_ts with multi-chunk offset accumulation
- `/v1/audio/speech-with-timestamps` HTTP endpoint returns JSON with audio_b64, words array, audio_duration, and sample_rate
- Punctuation-only tokens filtered from word timing output
- Existing `/v1/audio/speech` and `/v1/audio/speak` endpoints unaffected (verified)
- Launchd plist already has KeepAlive:true and RunAtLoad:true (PTS-03 satisfied)

## Task Commits

Files modified are outside the cc-skills git repo (at `~/.local/share/kokoro/`), so no per-task git commits are possible. Changes are to:

1. **Task 1: Add synthesize_with_timestamps to kokoro_common.py** - Modified `~/.local/share/kokoro/kokoro_common.py`
2. **Task 2: Add /v1/audio/speech-with-timestamps endpoint** - Modified `~/.local/share/kokoro/tts_server.py`

## Files Created/Modified

- `~/.local/share/kokoro/kokoro_common.py` - Added `synthesize_with_timestamps()` function using pipeline-direct access for MToken timestamps
- `~/.local/share/kokoro/tts_server.py` - Added `/v1/audio/speech-with-timestamps` route, `_handle_speech_with_timestamps()` handler, `synthesize_with_timestamps_locked()` wrapper, `import base64`

## Decisions Made

- **Pipeline-direct access instead of model.generate()**: Kokoro.generate() wraps pipeline results into GenerationResult, which discards the MToken.start_ts/end_ts data. Calling model.\_get_pipeline(lang) directly preserves the full KokoroPipeline.Result with .tokens containing word timestamps.
- **Audio array squeeze(0)**: Pipeline result.audio is shape (1, N) but existing to_wav_bytes() expects 1D. Kokoro.generate() does audio[0] internally; synthesize_with_timestamps() uses squeeze(0) to match.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed 2D audio array shape mismatch**

- **Found during:** Task 2 (endpoint testing)
- **Issue:** KokoroPipeline.Result.audio returns mx.array with shape (1, N), but to_wav_bytes() via soundfile expects 1D array. Kokoro.generate() handles this with audio[0] before yielding GenerationResult, but our pipeline-direct path skipped that.
- **Fix:** Added `.squeeze(0)` in synthesize_with_timestamps() when converting mx.array to numpy
- **Files modified:** ~/.local/share/kokoro/kokoro_common.py
- **Verification:** Endpoint returns valid WAV audio, soundfile.write succeeds

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Essential fix for audio serialization. No scope creep.

## Issues Encountered

None beyond the audio shape fix documented above.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all data paths are fully wired.

## Next Phase Readiness

- Endpoint is live and verified at <http://127.0.0.1:8779/v1/audio/speech-with-timestamps>
- Word timing data confirmed: non-uniform onset spacing from native MToken timestamps (not character-weighted)
- Ready for Phase 26: Swift TTSEngine native word onset integration

---

_Phase: 25-python-tts-server-timestamp-endpoint_
_Completed: 2026-03-28_

## Self-Check: PASSED
