---
phase: 03-tts-engine
plan: 01
subsystem: tts
tags: [sherpa-onnx, kokoro, tts, c-api, swift, onnx, duration-tensor]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: SwiftPM build system, CSherpaOnnx module target, Config.swift
provides:
  - Patched sherpa-onnx static libs with duration tensor support
  - Vendored c-api.h with durations/num_durations fields
  - Timestamped Kokoro model with ONNX metadata
  - TTSEngine.swift wrapping full synthesis pipeline
affects: [03-tts-engine plan 02, 04-telegram-bot, 06-http-api]

# Tech tracking
tech-stack:
  added: [sherpa-onnx duration tensor patch, timestamped Kokoro model]
  patterns:
    [
      lazy model loading,
      serial DispatchQueue for TTS,
      strdup pattern for C string lifetime,
      afplay subprocess playback,
    ]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift
  modified:
    - plugins/claude-tts-companion/Sources/CSherpaOnnx/include/sherpa-onnx/c-api/c-api.h
    - plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift

key-decisions:
  - "strdup/free pattern for C string lifetime in SherpaOnnxOfflineTtsConfig (safer than nested withCString)"
  - "NSLock for lazy model init protection (serial queue handles synthesis serialization)"
  - "@unchecked Sendable on TTSEngine (all mutable state accessed from serial queue)"

patterns-established:
  - "Lazy loading: expensive resources (ML models) init on first use, not at app startup"
  - "Serial queue isolation: com.terryli.tts-engine queue serializes all TTS operations"
  - "C API wrapper: strdup for string lifetime, guard-let for nil checks, defer for cleanup"

requirements-completed: [TTS-01, TTS-02, TTS-03, TTS-04, TTS-05, TTS-08]

# Metrics
duration: 5min
completed: 2026-03-26
---

# Phase 03 Plan 01: TTS Engine Core Summary

**Patched sherpa-onnx C++ for duration tensors, rebuilt static libs, and created TTSEngine.swift with lazy-loaded Kokoro synthesis, serial queue execution, WAV output, and afplay playback**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-26T08:33:00Z
- **Completed:** 2026-03-26T08:38:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Patched 5 sherpa-onnx C++ source files (~50 lines) to expose duration tensor from Kokoro model
- Prepared timestamped Kokoro model with ONNX metadata copied from standard int8 model
- Created TTSEngine.swift with full synthesis pipeline: lazy model loading, serial queue, WAV output, afplay playback
- All code compiles with zero errors under Swift 6 strict concurrency

## Task Commits

Each task was committed atomically:

1. **Task 1: Patch sherpa-onnx + rebuild static libs** - `ab057a2c` (feat)
2. **Task 2: Create TTSEngine.swift** - `c0ddd5b6` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift` - TTS engine wrapping sherpa-onnx C API with lazy loading, serial queue, WAV output, afplay playback
- `plugins/claude-tts-companion/Sources/CSherpaOnnx/include/sherpa-onnx/c-api/c-api.h` - Updated vendored header with durations/num_durations fields in SherpaOnnxGeneratedAudio
- `plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift` - Added kokoroModelFile constant for timestamped model

## Decisions Made

- Used strdup/free pattern instead of nested withCString for C string lifetime management -- cleaner code, explicit lifecycle
- NSLock for lazy model init protection rather than relying solely on serial queue (init could theoretically be called from multiple queues)
- @unchecked Sendable annotation on TTSEngine since all mutable state is protected by serial queue and NSLock
- SynthesisResult as a simple struct (not class) -- value semantics appropriate for immutable result data

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all functionality is fully wired. TTSEngine provides complete synthesis and playback pipeline.

## Next Phase Readiness

- TTSEngine.swift ready for Plan 02 (word-level timestamp conversion from raw duration tensor)
- Duration tensor exposure enables karaoke timing calculation
- Serial queue pattern established for TTS operations

---

_Phase: 03-tts-engine_
_Completed: 2026-03-26_
