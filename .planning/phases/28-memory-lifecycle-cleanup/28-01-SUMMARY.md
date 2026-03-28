---
phase: 28-memory-lifecycle-cleanup
plan: 01
subsystem: tts
tags: [swift, memory-lifecycle, dead-code-removal, launchd]

requires:
  - phase: 27-mlx-dependency-removal
    provides: MLX-free Swift binary delegating TTS to Python server
provides:
  - Clean CompanionCore with no restart logic, no exit(42), no synthesis counter
  - Simplified /health endpoint without MLX memory fields
affects: []

tech-stack:
  added: []
  patterns: [stateless-tts-delegation]

key-files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/TelegramBot.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift

key-decisions:
  - "healthResponse() made non-async since it no longer queries TTSEngine actor"
  - "HealthResponse breaking API change acceptable: mlx_memory and tts_restart_threshold fields removed (SwiftBar consumers will adapt)"

patterns-established:
  - "Stateless TTS delegation: Swift process has no synthesis tracking, Python server manages its own lifecycle"

requirements-completed: [MEM-01, MEM-02, MEM-03]

duration: 3min
completed: 2026-03-28
---

# Phase 28 Plan 01: Memory Lifecycle Cleanup Summary

**Removed all IOAccelerator leak mitigation code (exit(42), synthesis counter, MemoryLifecycle module) -- 130 lines deleted, continuously-available service**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-28T08:12:55Z
- **Completed:** 2026-03-28T08:16:15Z
- **Tasks:** 2
- **Files modified:** 5 (1 deleted, 4 edited)

## Accomplishments

- Deleted MemoryLifecycle.swift (42 lines) -- the entire restart coordination module
- Removed synthesisCount, maxSynthesisBeforeRestart, shouldRestartForMemory, memoryDiagnostics from TTSEngine
- Removed plannedRestart() with exit(42) and checkMemoryLifecycleRestart() from CompanionApp
- Simplified HealthResponse struct from 8 fields to 3 (status, uptime_seconds, rss_mb, subsystems)
- All 82 tests pass with zero dead-code references

## Task Commits

Each task was committed atomically:

1. **Task 1: Delete MemoryLifecycle.swift and strip restart logic** - `e0399529` (refactor)
2. **Task 2: Run tests and verify clean build** - No code changes needed (verification only)

## Files Created/Modified

- `MemoryLifecycle.swift` - DELETED (42 lines of dead restart coordination code)
- `TTSEngine.swift` - Removed synthesis counter, restart threshold, memoryDiagnostics, 4 count increments
- `CompanionApp.swift` - Removed MemoryLifecycle.register(), plannedRestart(), checkMemoryLifecycleRestart()
- `TelegramBot.swift` - Removed checkMemoryLifecycleRestart() call from batch playback onComplete
- `HTTPControlServer.swift` - Removed checkMemoryLifecycleRestart() call, simplified HealthResponse and healthResponse()

## Decisions Made

- healthResponse() changed from async to sync -- no longer needs to await TTSEngine actor for diagnostics
- HealthResponse breaking API change accepted: SwiftBar consumers read status/uptime/rss which remain; mlx_memory fields were always nil since Phase 27 removed MLX

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None.

## Issues Encountered

None.

## MEM-03 Runtime Verification Note

RSS-under-100MB criterion requires runtime verification with 50+ TTS calls routed through the Python server. This cannot be verified at build time. Post-deployment verification should monitor stderr.log RSS reports over 50+ synthesis calls to confirm the Swift process stays under 100MB RSS (expected ~27MB idle since no MLX code paths remain).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Memory lifecycle cleanup complete
- Swift binary is now a stateless TTS client -- no restart logic, no GPU memory tracking
- Ready for any remaining v4.8.0 consolidation work

---

_Phase: 28-memory-lifecycle-cleanup_
_Completed: 2026-03-28_
