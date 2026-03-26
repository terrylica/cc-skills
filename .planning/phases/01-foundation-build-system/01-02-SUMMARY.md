---
phase: 01-foundation-build-system
plan: 02
subsystem: infra
tags: [swift, nsapplication, sigterm, c-interop, sherpa-onnx, swiftpm]

# Dependency graph
requires:
  - phase: 01-foundation-build-system/01
    provides: "SwiftPM scaffold, CSherpaOnnx module, Config.swift, Package.swift"
provides:
  - main.swift entry point with NSApp accessory + SIGTERM + C interop verification
  - Working release binary (18.3MB stripped)
  - Updated plugin CLAUDE.md with architecture documentation
affects: [03-tts-engine, 04-telegram-bot, 05-bot-core]

# Tech tracking
tech-stack:
  added: []
  patterns:
    [nsapp-accessory-daemon, dispatch-source-sigterm, setbuf-unbuffered-launchd]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift
  modified:
    - plugins/claude-tts-companion/Package.swift
    - plugins/claude-tts-companion/CLAUDE.md
    - .claude-plugin/marketplace.json

key-decisions:
  - "SherpaOnnxGetVersionStr (not SherpaOnnxGetVersion) is the actual C API function name"
  - "SwiftTelegramBot (not SwiftTelegramSdk) is the correct SPM product name"
  - "strip binary for release: 32MB -> 18MB"

patterns-established:
  - "NSApp accessory pattern: setActivationPolicy(.accessory) for background launchd service"
  - "DispatchSource SIGTERM: makeSignalSource + SIG_IGN + dummy NSEvent for clean shutdown"
  - "nonisolated(unsafe) var keepAlive for preventing ARC deallocation of DispatchSource"
  - "setbuf(stdout/stderr, nil) for unbuffered output in launchd context"

requirements-completed: [BUILD-01, BUILD-04]

# Metrics
duration: 3min
completed: 2026-03-26
---

# Phase 01 Plan 02: Entry Point & Build Verification Summary

**NSApp accessory entry point with SIGTERM handling, sherpa-onnx C interop verification, and 18.3MB stripped release binary**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-26T01:52:00Z
- **Completed:** 2026-03-26T01:55:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- main.swift with NSApplication accessory app (no dock icon), DispatchSource SIGTERM handler, and SherpaOnnxGetVersionStr() C interop call
- Release binary builds, runs, prints sherpa-onnx version (1.12.28), starts cleanly, handles SIGTERM shutdown
- Binary size 18.3MB stripped (well under 30MB target)
- Plugin CLAUDE.md expanded with architecture documentation

## Task Commits

Each task was committed atomically:

1. **Task 1: Create main.swift entry point with NSApp accessory + SIGTERM + C interop** - `5bc1bd4a` (feat)
2. **Task 2: Update plugin CLAUDE.md and marketplace.json** - `d7fc1368` (docs)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift` - NSApplication accessory entry point with SIGTERM handling and C interop verification
- `plugins/claude-tts-companion/Package.swift` - Fixed SwiftTelegramBot product name
- `plugins/claude-tts-companion/CLAUDE.md` - Expanded with architecture details
- `.claude-plugin/marketplace.json` - Updated description and keywords

## Decisions Made

- **SherpaOnnxGetVersionStr:** Plan referenced `SherpaOnnxGetVersion` but the actual vendored c-api.h declares `SherpaOnnxGetVersionStr` -- used correct name
- **SwiftTelegramBot product name:** Plan 01-01 used `SwiftTelegramSdk` but the actual SPM product is `SwiftTelegramBot` -- fixed in Package.swift
- **strip for size target:** Unstripped binary is 32MB (over 30MB limit); stripped is 18.3MB -- standard practice for release builds

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Wrong C API function name**

- **Found during:** Task 1 (build)
- **Issue:** Plan specified `SherpaOnnxGetVersion()` but vendored c-api.h declares `SherpaOnnxGetVersionStr()`
- **Fix:** Changed to `SherpaOnnxGetVersionStr()` in main.swift
- **Files modified:** plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift
- **Verification:** `swift build -c release` succeeds
- **Committed in:** 5bc1bd4a (Task 1 commit)

**2. [Rule 1 - Bug] Wrong SPM product name for swift-telegram-sdk**

- **Found during:** Task 1 (build)
- **Issue:** Package.swift referenced product `SwiftTelegramSdk` but actual product is `SwiftTelegramBot`
- **Fix:** Changed product name in Package.swift dependencies
- **Files modified:** plugins/claude-tts-companion/Package.swift
- **Verification:** `swift build -c release` succeeds
- **Committed in:** 5bc1bd4a (Task 1 commit)

**3. [Rule 1 - Bug] marketplace.json schema validation**

- **Found during:** Task 2 (validation)
- **Issue:** Plan specified `"category": "application"` and `"skills": []` but schema doesn't allow those
- **Fix:** Used `"category": "productivity"` and `"strict": false` (matching other plugins)
- **Files modified:** .claude-plugin/marketplace.json
- **Verification:** `bun scripts/validate-plugins.mjs` passes (29/29)
- **Committed in:** d7fc1368 (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (3 bugs)
**Impact on plan:** All fixes necessary for correctness. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all files contain complete implementations for their intended purpose.

## Next Phase Readiness

- Build system fully proven: `swift build -c release` produces working binary
- CSherpaOnnx C interop verified end-to-end via SherpaOnnxGetVersionStr()
- SIGTERM clean shutdown pattern established for launchd service
- Ready for Phase 2 (subtitle overlay) and Phase 3 (TTS engine)

## Self-Check: PASSED

All 5 key files verified present. All 2 commit hashes verified in git log.

---

_Phase: 01-foundation-build-system_
_Completed: 2026-03-26_
