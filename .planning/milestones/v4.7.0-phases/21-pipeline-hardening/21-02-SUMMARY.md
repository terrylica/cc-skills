---
phase: 21-pipeline-hardening
plan: 02
subsystem: audio
tags:
  [
    avfoundation,
    avaudioengine,
    memory-pressure,
    bluetooth,
    graceful-degradation,
  ]

requires:
  - phase: 21-pipeline-hardening-01
    provides: TTSPipelineCoordinator, AudioStreamPlayer with gapless streaming
provides:
  - AVAudioEngine configuration change recovery for Bluetooth disconnect
  - Memory pressure monitoring with subtitle-only degradation
  - Audio route change callback wiring through coordinator
affects: [tts-pipeline, telegram-bot, http-api]

tech-stack:
  added: []
  patterns:
    [
      DispatchSource memory pressure monitoring,
      AVAudioEngine configurationChangeNotification observer,
      60s auto-recovery for memory pressure,
    ]

key-files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/AudioStreamPlayer.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSPipelineCoordinator.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/TelegramBot.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift

key-decisions:
  - "60-second auto-recovery timer for memory pressure (cancels on each new event, clears flag if no new pressure within 60s)"
  - "AudioStreamPlayer restarts engine in-place on route change; coordinator cancels pipeline but next request auto-works on new device"

patterns-established:
  - "DispatchSource.makeMemoryPressureSource for system memory monitoring with auto-recovery"
  - "AVAudioEngineConfigurationChange notification observer pattern for hardware route changes"

requirements-completed: [HARD-02, HARD-03]

duration: 3min
completed: 2026-03-28
---

<!-- # SSoT-OK -->

# Phase 21 Plan 02: Hardware Event Hardening Summary

**AVAudioEngine route change recovery for Bluetooth disconnect + DispatchSource memory pressure monitoring with subtitle-only degradation**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-28T02:45:32Z
- **Completed:** 2026-03-28T02:48:41Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- AudioStreamPlayer observes AVAudioEngine configuration changes, auto-restarts engine on new audio device (Bluetooth disconnect recovery)
- TTSPipelineCoordinator monitors memory pressure via DispatchSource, degrades to subtitle-only under .warning, cancels active pipeline under .critical
- Both TelegramBot and HTTPControlServer check shouldUseSubtitleOnly before synthesis
- Audio route change callback wired through coordinator to cancel in-progress pipelines

## Task Commits

Each task was committed atomically:

1. **Task 1: Audio route change recovery in AudioStreamPlayer** - `ac47c354` (feat)
2. **Task 2: Memory pressure monitoring and subtitle-only degradation** - `920abab8` (feat)

## Files Created/Modified

- `AudioStreamPlayer.swift` - Added configChangeObserver, onRouteChange callback, handleConfigurationChange() method
- `TTSPipelineCoordinator.swift` - Added memoryPressureSource, isMemoryConstrained, shouldUseSubtitleOnly, startMonitoring()/stopMonitoring(), handleAudioRouteChange()
- `CompanionApp.swift` - Calls startMonitoring() in start(), stopMonitoring() in shutdown()
- `TelegramBot.swift` - Memory pressure check before isStreamingInProgress guard in dispatchTTS()
- `HTTPControlServer.swift` - Memory pressure check in POST /tts/test returning subtitle_only JSON response

## Decisions Made

- 60-second auto-recovery timer for memory pressure flag (DispatchWorkItem cancelled on each new event, clears isMemoryConstrained if no new pressure within 60s)
- AudioStreamPlayer handles engine restart internally; coordinator only cancels the pipeline (separation of concerns)
- Used .AVAudioEngineConfigurationChange (actual Swift API name) rather than the deprecated configurationChangeNotification pattern

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 21 pipeline hardening complete (both plans executed)
- Ready for next phase in the current milestone

---

_Phase: 21-pipeline-hardening_
_Completed: 2026-03-28_
