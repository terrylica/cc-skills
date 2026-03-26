---
phase: 01-foundation-build-system
plan: 01
subsystem: infra
tags: [swiftpm, sherpa-onnx, c-interop, module-map, swift-telegram-sdk]

# Dependency graph
requires: []
provides:
  - SwiftPM project scaffold with Package.swift
  - CSherpaOnnx C module target for sherpa-onnx header interop
  - Config.swift centralized path constants with env var overrides
  - Plugin registration in marketplace.json
affects: [02-entry-point, 03-tts-engine, 04-telegram-bot, 05-bot-core]

# Tech tracking
tech-stack:
  added: [swift-telegram-sdk@4.5.0, swift-log@1.10.1, sherpa-onnx-static-libs]
  patterns: [csherpaonnx-module-map, env-var-path-override, vendored-c-headers]

key-files:
  created:
    - plugins/claude-tts-companion/Package.swift
    - plugins/claude-tts-companion/Sources/CSherpaOnnx/include/module.modulemap
    - plugins/claude-tts-companion/Sources/CSherpaOnnx/include/shim.h
    - plugins/claude-tts-companion/Sources/CSherpaOnnx/include/sherpa-onnx/c-api/c-api.h
    - plugins/claude-tts-companion/Sources/CSherpaOnnx/empty.c
    - plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift
    - plugins/claude-tts-companion/CLAUDE.md
    - plugins/claude-tts-companion/Package.resolved
  modified:
    - .claude-plugin/marketplace.json
    - .gitignore

key-decisions:
  - "CSherpaOnnx as .target (not .systemLibrary) with vendored headers for portability"
  - "SHERPA_ONNX_PATH env var override pattern for path flexibility"
  - "import Foundation required in Package.swift for ProcessInfo access"

patterns-established:
  - "C module map: module.modulemap + shim.h + vendored headers for C library interop"
  - "Env var override: SHERPA_ONNX_PATH / KOKORO_MODEL_PATH with hardcoded fallbacks"

requirements-completed: [BUILD-02, BUILD-03]

# Metrics
duration: 3min
completed: 2026-03-26
---

# Phase 01 Plan 01: Foundation Build System Summary

**SwiftPM project scaffold with CSherpaOnnx C module map, swift-telegram-sdk v4.5.0 dependency, and centralized Config.swift path constants**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-26T01:47:05Z
- **Completed:** 2026-03-26T01:50:06Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments

- CSherpaOnnx C module target with vendored 1990-line c-api.h header for `import CSherpaOnnx` from Swift
- Package.swift with swift-telegram-sdk v4.5.0, swift-log, and sherpa-onnx linker settings
- Config.swift centralizing sherpaOnnxPath, kokoroModelPath with SHERPA_ONNX_PATH/KOKORO_MODEL_PATH env var overrides
- `swift package resolve` succeeds -- all dependencies fetched and resolved

## Task Commits

Each task was committed atomically:

1. **Task 1: Create CSherpaOnnx C module target with vendored headers** - `292e1d2d` (feat)
2. **Task 2: Create Package.swift and Config.swift** - `de585611` (feat)
3. **Housekeeping: .gitignore + Package.resolved** - `55d878d4` (chore)

## Files Created/Modified

- `plugins/claude-tts-companion/Package.swift` - SwiftPM manifest with all dependencies and linker settings
- `plugins/claude-tts-companion/Sources/CSherpaOnnx/include/module.modulemap` - C module map for `import CSherpaOnnx`
- `plugins/claude-tts-companion/Sources/CSherpaOnnx/include/shim.h` - Umbrella header for sherpa-onnx C API
- `plugins/claude-tts-companion/Sources/CSherpaOnnx/include/sherpa-onnx/c-api/c-api.h` - Vendored C API header (1990 lines)
- `plugins/claude-tts-companion/Sources/CSherpaOnnx/empty.c` - Required for SwiftPM C target recognition
- `plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift` - Path constants with env var overrides
- `plugins/claude-tts-companion/CLAUDE.md` - Plugin documentation
- `plugins/claude-tts-companion/Package.resolved` - Locked dependency versions
- `.claude-plugin/marketplace.json` - Registered claude-tts-companion plugin
- `.gitignore` - Added .build/ directory

## Decisions Made

- **CSherpaOnnx as .target not .systemLibrary:** Vendored headers work without pkg-config, more portable
- **SHERPA_ONNX_PATH env var pattern:** Avoids hardcoded path fragility while keeping sensible defaults
- **import Foundation in Package.swift:** Required for ProcessInfo.processInfo.environment access (not auto-imported)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Plugin registration in marketplace.json**

- **Found during:** Task 1 (commit)
- **Issue:** Pre-commit hook rejected commit -- unregistered plugin directory
- **Fix:** Added claude-tts-companion entry to marketplace.json and created plugin CLAUDE.md
- **Files modified:** .claude-plugin/marketplace.json, plugins/claude-tts-companion/CLAUDE.md
- **Verification:** `bun scripts/validate-plugins.mjs` passes (29/29 plugins valid)
- **Committed in:** 292e1d2d (Task 1 commit)

**2. [Rule 1 - Bug] Missing Foundation import in Package.swift**

- **Found during:** Task 2 (`swift package resolve`)
- **Issue:** `ProcessInfo` not in scope -- Package.swift only imports PackageDescription by default
- **Fix:** Added `import Foundation` to Package.swift
- **Files modified:** plugins/claude-tts-companion/Package.swift
- **Verification:** `swift package resolve` succeeds after fix
- **Committed in:** de585611 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both fixes necessary for correctness. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all files contain complete implementations for their intended purpose.

## Next Phase Readiness

- Package.swift resolves all dependencies, ready for main.swift entry point (Plan 01-02)
- CSherpaOnnx module target ready for `import CSherpaOnnx` in Swift code
- Config.swift paths ready for TTS engine initialization in Phase 3

## Self-Check: PASSED

All 8 created files verified present. All 3 commit hashes verified in git log.

---

_Phase: 01-foundation-build-system_
_Completed: 2026-03-26_
