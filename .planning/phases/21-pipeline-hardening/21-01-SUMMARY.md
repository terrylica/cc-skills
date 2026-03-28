---
phase: 21-pipeline-hardening
plan: 01
subsystem: tts
tags: [swift, concurrency, audio, pipeline, coordinator]

requires:
  - phase: 18-companion-core-extraction
    provides: CompanionCore library with PlaybackManager, SubtitleSyncDriver, AudioStreamPlayer
provides:
  - TTSPipelineCoordinator serializing all AudioStreamPlayer and SubtitleSyncDriver lifecycle
  - Subtitle-only fallback when TTS is busy (no silent drops)
affects: [21-02-edge-case-hardening]

tech-stack:
  added: []
  patterns: ["Coordinator pattern for shared mutable resource access"]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSPipelineCoordinator.swift
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/TelegramBot.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift

key-decisions:
  - "TTSPipelineCoordinator is @MainActor (matches SubtitleSyncDriver and PlaybackManager isolation)"
  - "Single-shot (dispatchFullTTS) uses coordinator.cancelCurrentPipeline but keeps AVAudioPlayer path (no AudioStreamPlayer conflict)"

patterns-established:
  - "Coordinator pattern: shared AudioStreamPlayer access goes through TTSPipelineCoordinator, never directly"

requirements-completed: [HARD-01, HARD-04]

duration: 4min
completed: 2026-03-28
---

# Phase 21 Plan 01: TTS Pipeline Coordinator Summary

**TTSPipelineCoordinator serializing AudioStreamPlayer access with subtitle-only fallback for busy-state notifications**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-28T02:38:51Z
- **Completed:** 2026-03-28T02:43:33Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Created TTSPipelineCoordinator as single owner of AudioStreamPlayer reset/schedule lifecycle and SubtitleSyncDriver creation
- Migrated both TelegramBot and HTTPControlServer to use coordinator -- eliminated all direct AudioStreamPlayer manipulation
- Rapid-fire notifications now show subtitle-only fallback instead of being silently dropped (HARD-04)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create TTSPipelineCoordinator with exclusive pipeline access** - `d457d1a0` (feat)
2. **Task 2: Migrate TelegramBot and HTTPControlServer to use TTSPipelineCoordinator** - `7267b8f8` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/CompanionCore/TTSPipelineCoordinator.swift` - New coordinator class serializing pipeline access
- `plugins/claude-tts-companion/Sources/CompanionCore/TelegramBot.swift` - Removed syncDriver, uses coordinator for streaming/full TTS
- `plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift` - Removed activeSyncDriver, uses coordinator for /tts/test
- `plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift` - Creates and injects coordinator to both consumers

## Decisions Made

- TTSPipelineCoordinator is @MainActor to match SubtitleSyncDriver and PlaybackManager isolation domains
- Single-shot TTS (dispatchFullTTS) only calls coordinator.cancelCurrentPipeline before AVAudioPlayer playback, since the race is specifically on AudioStreamPlayer not AVAudioPlayer

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Coordinator in place for edge-case hardening in plan 02
- All AudioStreamPlayer access serialized through single coordinator

## Self-Check: PASSED

- TTSPipelineCoordinator.swift: FOUND
- Commit d457d1a0: FOUND
- Commit 7267b8f8: FOUND
- SUMMARY.md: FOUND

---

_Phase: 21-pipeline-hardening_
_Completed: 2026-03-28_
