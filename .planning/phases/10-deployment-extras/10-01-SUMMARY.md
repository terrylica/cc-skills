---
phase: 10-deployment-extras
plan: 01
subsystem: infra
tags: [launchd, deployment, macos, shell-scripts, plist]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: Package.swift and Config.swift configuration constants
provides:
  - launchd plist for com.terryli.claude-tts-companion service
  - install.sh build+deploy script with old service cutover
  - rollback.sh for reverting to telegram-bot + kokoro-tts-server
  - canonical kokoroModelPath in Config.swift
affects: [10-02]

# Tech tracking
tech-stack:
  added: []
  patterns: [launchd-plist-pattern, bootout-bootstrap-service-management]

key-files:
  created:
    - plugins/claude-tts-companion/launchd/com.terryli.claude-tts-companion.plist
    - plugins/claude-tts-companion/scripts/install.sh
    - plugins/claude-tts-companion/scripts/rollback.sh
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift

key-decisions:
  - "Nice -5 for moderate TTS priority (between 0 background and -10 aggressive)"
  - "1GB memory limit (peak 561MB + headroom) via SoftResourceLimits"
  - "bootout/bootstrap over legacy unload/load for modern launchctl"

patterns-established:
  - "launchd plist: KeepAlive with NetworkState + SuccessfulExit=false for crash-only restart"
  - "Service cutover: stop old services but preserve plist files on disk for rollback"

requirements-completed: [DEP-01, DEP-02, DEP-03, DEP-04]

# Metrics
duration: 2min
completed: 2026-03-26
---

# Phase 10 Plan 01: Deployment Scripts Summary

**Launchd plist with KeepAlive + env vars, install/rollback scripts using bootout/bootstrap, Config.swift canonical model path**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-26T18:11:18Z
- **Completed:** 2026-03-26T18:13:06Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Launchd plist with all required keys: KeepAlive (NetworkState + crash restart), RunAtLoad, env vars, 1GB memory limit, log paths
- install.sh: 66-line script for release build, strip, copy, old service cutover, health check
- rollback.sh: 39-line script for reverting to old services with elapsed time reporting
- Config.swift kokoroModelPath updated from dev spike path to canonical ~/.local/share/kokoro/models/

## Task Commits

Each task was committed atomically:

1. **Task 1: Launchd plist + Config.swift model path fix** - `cc713a5b` (feat)
2. **Task 2: Install and rollback scripts** - `04300860` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/launchd/com.terryli.claude-tts-companion.plist` - Launchd service definition with env vars, KeepAlive, log paths
- `plugins/claude-tts-companion/scripts/install.sh` - Build + strip + install + service cutover script
- `plugins/claude-tts-companion/scripts/rollback.sh` - Rollback to old telegram-bot + kokoro-tts-server services
- `plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift` - Canonical model path default

## Decisions Made

- Nice -5 chosen as moderate priority (TTS needs low latency but -10 was excessive per existing kokoro plist)
- 1GB SoftResourceLimit provides headroom over 561MB peak RSS
- Used modern `launchctl bootout/bootstrap` instead of legacy `unload/load`
- Old plist files preserved on disk during install for safe rollback

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - scripts are ready to use but not executed. User must fill in TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, and MINIMAX_API_KEY in the plist before running install.sh.

## Next Phase Readiness

- Deployment scripts ready for use
- Plan 10-02 (SwiftBar update) can proceed independently

---

_Phase: 10-deployment-extras_
_Completed: 2026-03-26_

## Self-Check: PASSED

- All 4 files exist on disk
- Both task commits verified (cc713a5b, 04300860)
