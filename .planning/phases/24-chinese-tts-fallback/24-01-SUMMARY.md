---
phase: 24-chinese-tts-fallback
plan: 01
subsystem: tts
tags: [sherpa-onnx, c-interop, cjk, chinese-tts, swiftpm]

requires:
  - phase: 18-companioncore-extraction
    provides: CompanionCore library target and Config.swift pattern
provides:
  - CSherpaOnnx C module target with vendored sherpa-onnx header
  - SherpaOnnxEngine class for on-demand CJK TTS synthesis
  - Config constants for sherpa-onnx model path, idle timeout, thread count
affects: [24-02, chinese-tts-router, cjk-synthesis]

tech-stack:
  added: [sherpa-onnx static libs (14 libraries), CSherpaOnnx C module]
  patterns:
    [
      on-demand model loading with idle unload timer,
      NSLock for C library thread safety,
      withCString chains for C interop,
    ]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/CSherpaOnnx/include/module.modulemap
    - plugins/claude-tts-companion/Sources/CSherpaOnnx/include/c-api.h
    - plugins/claude-tts-companion/Sources/CSherpaOnnx/shim.c
    - plugins/claude-tts-companion/Sources/CompanionCore/SherpaOnnxEngine.swift
  modified:
    - plugins/claude-tts-companion/Package.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/Config.swift

key-decisions:
  - "NSLock + @unchecked Sendable for SherpaOnnxEngine (C library wrapper, not async-compatible)"
  - "Vendored c-api.h avoids system-level pkg-config dependency"
  - "14 static libraries linked via unsafeFlags -L path"

patterns-established:
  - "C module interop: modulemap + vendored header + shim.c for SwiftPM C targets"
  - "On-demand model lifecycle: load on first call, unload after idle timeout via DispatchWorkItem"

requirements-completed: [CJK-01, CJK-03, CJK-04]

duration: 3min
completed: 2026-03-28
---

# Phase 24 Plan 01: CSherpaOnnx Module + SherpaOnnxEngine Summary

**CSherpaOnnx C module with vendored header and SherpaOnnxEngine for on-demand CJK TTS via sherpa-onnx kokoro-int8-multi-lang model**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-28T03:38:41Z
- **Completed:** 2026-03-28T03:41:12Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- CSherpaOnnx C module target compiles with vendored c-api.h header and module.modulemap
- Package.swift links 14 sherpa-onnx static libraries plus libc++ via unsafeFlags
- SherpaOnnxEngine provides lazy model loading with 30-second idle unload timer
- Graceful nil return when model files are missing (no crash on absent model)

## Task Commits

Each task was committed atomically:

1. **Task 1: CSherpaOnnx C module + Package.swift linker settings** - `3503580d` (feat)
2. **Task 2: SherpaOnnxEngine + Config constants for CJK TTS** - `f1c9d089` (feat)

## Files Created/Modified

- `Sources/CSherpaOnnx/include/module.modulemap` - C module declaration for sherpa-onnx header
- `Sources/CSherpaOnnx/include/c-api.h` - Vendored sherpa-onnx C API header (1992 lines)
- `Sources/CSherpaOnnx/shim.c` - Empty shim required by SwiftPM for C targets
- `Sources/CompanionCore/SherpaOnnxEngine.swift` - On-demand CJK TTS engine with idle unload
- `Package.swift` - Added CSherpaOnnx target, CompanionCore dependency, 14+ linker settings
- `Sources/CompanionCore/Config.swift` - Added sherpaOnnxModelDir, idle timeout, thread count

## Decisions Made

- NSLock + @unchecked Sendable for SherpaOnnxEngine (C library wrapper is blocking synchronous code, not async-compatible -- matches pre-Phase-19 pattern appropriate for C wrappers)
- Vendored c-api.h header instead of system pkg-config to avoid build environment dependency
- Nested withCString chains keep all C strings alive during SherpaOnnxCreateOfflineTts call
- memset zero-initializes C config struct to avoid garbage in unused fields (vits, matcha, etc.)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required. Model files already present at ~/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0/.

## Known Stubs

None - SherpaOnnxEngine is fully wired to CSherpaOnnx C API. Integration with the routing layer is in Plan 02.

## Next Phase Readiness

- CSherpaOnnx module importable from CompanionCore
- SherpaOnnxEngine ready for integration with CJK routing in Plan 02
- Config constants ready for use by the CJK detection and routing layer

## Self-Check: PASSED

All files exist on disk. All commit hashes found in git log.

---

_Phase: 24-chinese-tts-fallback_
_Completed: 2026-03-28_
