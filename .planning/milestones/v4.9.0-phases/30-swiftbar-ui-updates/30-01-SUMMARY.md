---
phase: 30-swiftbar-ui-updates
plan: 01
subsystem: ui
tags: [swiftbar, bash, tts-health, bot-status, macos-menubar]

requires:
  - phase: 28-memory-lifecycle-cleanup
    provides: Python TTS delegation architecture (Swift companion -> Python server chain)
provides:
  - Python TTS server health display in SwiftBar Service section
  - Bot status mapping (unknown -> disabled) for accurate subsystem display
  - Verified voice/speed propagation through Swift -> Python chain
affects: [31-e2e-integration-verification]

tech-stack:
  added: []
  patterns: [dual-health-check (Swift 8780 + Python 8779), bot-status-mapping]

key-files:
  created: []
  modified:
    - ~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.sh

key-decisions:
  - "Python TTS PID/RSS fetched via pgrep + ps rather than /health endpoint because Python server health response does not include process metrics"
  - "Bot 'unknown' status mapped to 'disabled' with white dot (not yellow) because unknown means no token configured, which is a deliberate choice not an error"
  - "BAR-11 verified as already working -- voice/speed params pass through callPythonServerWithTimestamps() HTTP body to Python server"

patterns-established:
  - "Dual health check: SwiftBar queries both Swift companion (8780) and Python TTS server (8779) independently"

requirements-completed: [BAR-10, BAR-11, BAR-12]

duration: 2min
completed: 2026-03-28
---

# Phase 30: SwiftBar UI Updates Summary

**SwiftBar v5.0.0 with Python TTS server health (green/red + PID + RSS) and bot status mapping (watching/connected=green, disabled=grey)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-28T19:06:25Z
- **Completed:** 2026-03-28T19:08:33Z
- **Tasks:** 3 (BAR-10, BAR-11, BAR-12)
- **Files modified:** 1

## Accomplishments

- SwiftBar Service section now shows Python TTS server health with green/red dot, PID, and RSS alongside Swift companion
- Bot subsystem status maps "unknown" to "disabled" (white dot) and adds "connected" to green dot list -- never shows raw "unknown"
- Confirmed voice/speed settings propagate end-to-end: SwiftBar -> POST /settings/tts -> SettingsStore -> callPythonServerWithTimestamps(voice, speed) -> Python server

## Task Commits

Plugin file lives outside the git repo (~/Library/Application Support/SwiftBar/Plugins/), so changes are deployed directly without git commits. Swift build verified passing.

## Files Created/Modified

- `~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.sh` - v5.0.0: Python TTS health check, bot status mapping, dual-server health display

## Decisions Made

1. **Python TTS PID/RSS via pgrep+ps**: The Python /health endpoint returns model/status but not process metrics. Used `pgrep -f 'kokoro.tts_server'` for PID and `ps -o rss=` for RSS, matching the pattern used for the Swift companion PID fallback.

2. **Bot "unknown" -> "disabled" mapping**: The Swift /health endpoint returns "unknown" when TELEGRAM_BOT_TOKEN is not set. Displaying "unknown" is confusing -- "disabled" accurately communicates the intentional state. White dot (not yellow) because this is not a warning condition.

3. **BAR-11 no changes needed**: Voice and speed parameters are already passed in the HTTP POST body to the Python server via `callPythonServerWithTimestamps(text:voice:speed:)`. The SwiftBar -> Swift companion -> Python server chain works end-to-end without modification.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All SwiftBar UI requirements complete (BAR-10, BAR-11, BAR-12)
- Ready for Phase 31: E2E Integration Verification
- Bot credentials (BOT-10 from Phase 29) must be active for E2E testing

---

_Phase: 30-swiftbar-ui-updates_
_Completed: 2026-03-28_
