---
phase: 08-http-control-api
plan: 01
subsystem: api
tags: [flyingfox, http, rest, settings, json-persistence, nslcok]

requires:
  - phase: 02-subtitle-overlay
    provides: SubtitlePanel with show/hide/karaoke API
  - phase: 03-tts-engine
    provides: TTSEngine with synthesize/play/stop API
provides:
  - HTTPControlServer with 6 REST endpoints on localhost:8780
  - SettingsStore with thread-safe JSON disk persistence
  - SubtitleSettings and TTSSettings Codable structs
affects: [09-swiftbar-integration, 10-launchd-service]

tech-stack:
  added: [FlyingFox 0.26.2]
  patterns:
    [partial-update-structs for PATCH semantics, loopback-only HTTP binding]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/SettingsStore.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/HTTPControlServer.swift
  modified:
    - plugins/claude-tts-companion/Package.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift

key-decisions:
  - "FlyingFox 0.26.2 for HTTP server (pure BSD sockets, zero SwiftNIO dependency)"
  - "NSLock for SettingsStore thread safety (consistent with TTSEngine, CircuitBreaker patterns)"
  - "Partial update structs with optional fields for PATCH-style POST endpoints"
  - "mach_task_basic_info for RSS monitoring in health endpoint"

patterns-established:
  - "Partial update pattern: *Update struct with all-optional fields merged into stored settings"
  - "Loopback-only binding: HTTPServer(address: .loopback(port:)) for local-only access"

requirements-completed: [API-01, API-02, API-03, API-04, API-05, API-06, API-07]

duration: 2min
completed: 2026-03-26
---

# Phase 08 Plan 01: HTTP Control API Summary

**FlyingFox HTTP server with 6 REST endpoints (health, settings CRUD, subtitle control) plus SettingsStore with JSON disk persistence at ~/.config/claude-tts-companion/settings.json**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-26T17:43:38Z
- **Completed:** 2026-03-26T17:45:31Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- FlyingFox v0.26.2 integrated as HTTP server dependency (zero SwiftNIO overhead)
- SettingsStore with SubtitleSettings/TTSSettings structs, NSLock thread safety, atomic JSON persistence
- HTTPControlServer with all 6 API endpoints: health, settings read/write, subtitle show/hide
- Health endpoint reports uptime_seconds, rss_mb via mach_task_basic_info, subsystem status
- Partial update pattern with optional-field structs for POST /settings/\* endpoints

## Task Commits

Each task was committed atomically:

1. **Task 1: Add FlyingFox dependency and create SettingsStore** - `3eb18c9a` (feat)
2. **Task 2: Create HTTPControlServer with all API endpoints** - `f5958678` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/SettingsStore.swift` - Thread-safe settings manager with SubtitleSettings, TTSSettings, AppSettings structs and JSON disk persistence
- `plugins/claude-tts-companion/Sources/claude-tts-companion/HTTPControlServer.swift` - FlyingFox HTTP server with 6 route handlers for health, settings, and subtitle control
- `plugins/claude-tts-companion/Package.swift` - Added FlyingFox v0.26.0+ dependency
- `plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift` - Added httpPort = 8780 constant

## Decisions Made

- Used FlyingFox 0.26.2 (pure BSD sockets + Swift Concurrency, zero framework overhead)
- NSLock for SettingsStore thread safety, consistent with TTSEngine and CircuitBreaker patterns in codebase
- Partial update structs (SubtitleSettingsUpdate, TTSSettingsUpdate) with all-optional fields for PATCH semantics
- mach_task_basic_info for RSS measurement in health endpoint (no external dependency)
- Bot subsystem status hardcoded to "unknown" (will be wired in Phase 9)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- HTTP control API ready for SwiftBar integration (Phase 9)
- SettingsStore and HTTPControlServer need to be wired into main.swift (Phase 8 Plan 2)
- Bot status can be upgraded from "unknown" once TelegramBot reference is passed to HTTPControlServer

## Self-Check: PASSED

- All 3 files found on disk
- Both commit hashes verified in git log

---

_Phase: 08-http-control-api_
_Completed: 2026-03-26_
