---
phase: 32-audio-device-resilience
plan: 01
subsystem: audio
tags:
  [
    coreaudio,
    hal-listener,
    avfoundation,
    avaudioengine,
    debounce,
    device-resilience,
  ]

# Dependency graph
requires: []
provides:
  - CoreAudio HAL listener for default output device changes
  - Full AVAudioEngine teardown/rebuild recovery path
  - Debounce (200ms) + cooldown (5s) for rebuild triggers
  - Audio resilience constants in Config.swift
affects: [32-02, audio-health-check, playback-manager]

# Tech tracking
tech-stack:
  added: [CoreAudio HAL API]
  patterns:
    [
      C function pointer HAL listener,
      debounced rebuild via DispatchWorkItem,
      full engine detach/reset/re-attach cycle,
    ]

key-files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/Config.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/AudioStreamPlayer.swift

key-decisions:
  - "C function pointer HAL listener over block variant (Apple removal bug)"
  - "Cached device ID approach over AudioUnit query (simpler, avoids API complexity)"
  - "kAudioObjectPropertyElementMain over deprecated kAudioObjectPropertyElementMaster"

patterns-established:
  - "Three-layer device detection: HAL listener + AVAudioEngineConfigurationChange + health check feed into single debounced rebuild"
  - "Full engine teardown: stop -> detach -> reset -> attach -> connect -> prepare -> start"

requirements-completed: [AUDIO-01, AUDIO-02, AUDIO-03, AUDIO-04]

# Metrics
duration: 2min
completed: 2026-03-29
---

# Phase 32 Plan 01: Audio Device Resilience Summary

**CoreAudio HAL listener + full AVAudioEngine teardown/rebuild with 200ms debounce and 5s cooldown for audio device change recovery**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-29T07:26:06Z
- **Completed:** 2026-03-29T07:28:35Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added three audio resilience constants to Config.swift (health check interval, debounce, cooldown)
- Replaced lightweight handleConfigurationChange (just engine.start()) with full three-step recovery: stop -> detach/reset -> re-attach/connect/start
- Added CoreAudio HAL property listener for default output device changes with C function pointer API
- Implemented 200ms debounce + 5s cooldown to collapse Bluetooth reconnect flapping into single rebuild
- Device ID + name telemetry on every engine start and rebuild

## Task Commits

Each task was committed atomically:

1. **Task 1: Add audio resilience constants to Config.swift** - `af9c0e75` (feat)
2. **Task 2: Replace handleConfigurationChange with full HAL listener + engine rebuild + debounce** - `4becbd35` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/CompanionCore/Config.swift` - Added audioHealthCheckInterval (30s), audioRebuildDebounceMs (200ms), audioRebuildCooldownSeconds (5s)
- `plugins/claude-tts-companion/Sources/CompanionCore/AudioStreamPlayer.swift` - Added CoreAudio HAL listener, RebuildSource enum, setupHALListener/removeHALListener, getSystemDefaultOutputDeviceID, getDeviceName, triggerRebuild (debounce), rebuildEngine (full teardown/rebuild)

## Decisions Made

- Used C function pointer variant of AudioObjectAddPropertyListener (block variant has known Apple removal bug)
- Cached device ID on engine start/rebuild for health check comparison (simpler than querying AudioUnit on engine.outputNode)
- Used kAudioObjectPropertyElementMain (not deprecated kAudioObjectPropertyElementMaster)
- All rebuild paths (HAL, config notification, future health check) converge to single triggerRebuild entry point

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- HAL listener and rebuild infrastructure ready for Plan 02 (periodic health check timer)
- onRouteChange callback fires after rebuild completes, maintaining coordinator integration
- All three Config constants available for health check timer in Plan 02

---

_Phase: 32-audio-device-resilience_
_Completed: 2026-03-29_
