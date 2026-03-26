---
phase: 01-foundation-build-system
verified: 2026-03-25T18:30:00Z
status: human_needed
score: 7/8 must-haves verified
re_verification: false
human_verification:
  - test: "Verify binary exits cleanly on SIGTERM"
    expected: "Process logs 'SIGTERM received, shutting down' and exits with code 0"
    why_human: "Cannot send SIGTERM to background process in this verification context without starting the app"
  - test: "Confirm stripped binary is the intended release artifact"
    expected: "Build documentation or Makefile clarifies that `swift build -c release && strip` is the full release pipeline"
    why_human: "No strip step is scripted; unstripped binary (32.3MB) exceeds 30MB limit; stripped binary (18.3MB) passes — but strip is not automated"
---

# Phase 01: Foundation & Build System Verification Report

**Phase Goal:** The project compiles and runs as a macOS accessory app with all dependencies resolved
**Verified:** 2026-03-25T18:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| #   | Truth                                                                                                     | Status      | Evidence                                                                                                                                                                       |
| --- | --------------------------------------------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | `swift build -c release` succeeds with zero errors and produces a single binary under 30MB                | ⚠ PARTIAL   | Build succeeds (Build complete! 1.17s). Unstripped binary is 32.3MB (over limit). Stripped binary is 18.3MB (under limit). No automated strip step exists.                     |
| 2   | Package.swift resolves swift-telegram-sdk v4.5.0 and links sherpa-onnx static libraries without conflicts | ✓ VERIFIED  | Package.swift declares `from: "4.5.0"` for swift-telegram-sdk; linkerSettings include `-lsherpa-onnx`, `-lonnxruntime`, `-lc++`; `swift package resolve` succeeded per SUMMARY |
| 3   | Bridging header imports sherpa-onnx C API; a trivial C function call succeeds                             | ✓ VERIFIED  | `import CSherpaOnnx` present in main.swift; `SherpaOnnxGetVersionStr()` called and assigned to `version`; build succeeds confirming C interop works end-to-end                 |
| 4   | Binary launches as NSApplication accessory app, logs to stdout, and exits cleanly on SIGTERM              | ? UNCERTAIN | `setActivationPolicy(.accessory)` confirmed in main.swift; SIGTERM handler via `DispatchSource.makeSignalSource` confirmed; actual runtime behavior needs human verification   |

**Score:** 3/4 truths fully verified (Truth 1 partial due to strip gap; Truth 4 needs human)

### Required Artifacts

| Artifact                                                                             | Expected                                        | Status     | Details                                                                                                                                                                                                                                   |
| ------------------------------------------------------------------------------------ | ----------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `plugins/claude-tts-companion/Package.swift`                                         | SwiftPM manifest with all dependencies          | ✓ VERIFIED | 44 lines; contains swift-telegram-sdk, CSherpaOnnx, linkerSettings                                                                                                                                                                        |
| `plugins/claude-tts-companion/Sources/CSherpaOnnx/include/module.modulemap`          | C module map for sherpa-onnx headers            | ✓ VERIFIED | Contains `module CSherpaOnnx`, `header "shim.h"`, `link "sherpa-onnx"`, `link "onnxruntime"`, `export *`                                                                                                                                  |
| `plugins/claude-tts-companion/Sources/CSherpaOnnx/include/shim.h`                    | Umbrella header for sherpa-onnx C API           | ✓ VERIFIED | Contains `CSHERPAONNX_SHIM_H` guard; includes `sherpa-onnx/c-api/c-api.h`                                                                                                                                                                 |
| `plugins/claude-tts-companion/Sources/CSherpaOnnx/include/sherpa-onnx/c-api/c-api.h` | Vendored sherpa-onnx C API header               | ✓ VERIFIED | 1990 lines; contains `SherpaOnnxGetVersionStr` (note: plan said `SherpaOnnxGetVersion` but actual API is `SherpaOnnxGetVersionStr` — correctly fixed)                                                                                     |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift`             | Centralized path and configuration constants    | ✓ VERIFIED | 27 lines; contains `enum Config` with sherpaOnnxPath, kokoroModelPath, appName, serviceLabel                                                                                                                                              |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift`               | NSApplication accessory app entry point         | ✓ VERIFIED | 46 lines (plan required 30+); contains all required patterns: `import CSherpaOnnx`, `SherpaOnnxGetVersionStr`, `setActivationPolicy(.accessory)`, `makeSignalSource.*SIGTERM`, `nonisolated(unsafe) var keepAlive`, `setbuf` — no `@main` |
| `plugins/claude-tts-companion/CLAUDE.md`                                             | Plugin documentation                            | ✓ VERIFIED | Contains hub navigation link to `../../CLAUDE.md`; has architecture, build instructions, key files table                                                                                                                                  |
| `.claude-plugin/marketplace.json`                                                    | Plugin registry with claude-tts-companion entry | ✓ VERIFIED | Entry present with `source: "./plugins/claude-tts-companion"`, category: productivity, version 12.16.0; `bun scripts/validate-plugins.mjs` passes 29/29                                                                                   |

### Key Link Verification

| From          | To                      | Via                                                | Status  | Details                                                                      |
| ------------- | ----------------------- | -------------------------------------------------- | ------- | ---------------------------------------------------------------------------- |
| Package.swift | CSherpaOnnx target      | `.target(name: "CSherpaOnnx")`                     | ✓ WIRED | Found at line 17: `.target(name: "CSherpaOnnx", path: "Sources/CSherpaOnnx"` |
| Package.swift | sherpa-onnx static libs | linkerSettings unsafeFlags -L path                 | ✓ WIRED | Found: `-L\(sherpaOnnxPath)/lib` + `.linkedLibrary("sherpa-onnx")`           |
| main.swift    | CSherpaOnnx             | `import CSherpaOnnx` + `SherpaOnnxGetVersionStr()` | ✓ WIRED | Line 4: `import CSherpaOnnx`; line 15: `SherpaOnnxGetVersionStr()` called    |
| main.swift    | NSApplication           | `app.setActivationPolicy(.accessory)`              | ✓ WIRED | Line 20: `app.setActivationPolicy(.accessory)`                               |
| main.swift    | SIGTERM handler         | `DispatchSource.makeSignalSource`                  | ✓ WIRED | Line 23: `DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)`    |

All 5 key links verified present and correctly connected.

### Data-Flow Trace (Level 4)

Not applicable — this phase produces a binary entry point and build infrastructure, not components that render dynamic data from a data store.

### Behavioral Spot-Checks

| Behavior                          | Command                                                                     | Result                    | Status |
| --------------------------------- | --------------------------------------------------------------------------- | ------------------------- | ------ |
| `swift build -c release` succeeds | `cd plugins/claude-tts-companion && swift build -c release 2>&1 \| tail -5` | "Build complete! (1.17s)" | ✓ PASS |
| Binary exists after build         | `test -f .build/release/claude-tts-companion`                               | File present              | ✓ PASS |
| Stripped binary under 30MB        | `strip binary -o /tmp/stripped && stat -f%z /tmp/stripped`                  | 19,196,400 bytes (18.3MB) | ✓ PASS |
| Unstripped binary size            | `stat -f%z .build/release/claude-tts-companion`                             | 33,915,992 bytes (32.3MB) | ⚠ WARN |
| Plugin validation passes          | `bun scripts/validate-plugins.mjs`                                          | "29/29 plugins valid"     | ✓ PASS |
| All commit hashes exist in git    | `git log --oneline 292e1d2d de585611 55d878d4 5bc1bd4a d7fc1368`            | All 5 hashes found        | ✓ PASS |
| SIGTERM clean shutdown            | Requires launching binary and sending SIGTERM                               | — cannot test without run | ? SKIP |

### Requirements Coverage

| Requirement | Source Plan | Description                                                                      | Status      | Evidence                                                                                                                   |
| ----------- | ----------- | -------------------------------------------------------------------------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------- |
| BUILD-01    | 01-02       | User can compile with `swift build -c release` (no Xcode required)               | ✓ SATISFIED | Build succeeds in verification run: "Build complete! (1.17s)"                                                              |
| BUILD-02    | 01-01       | Package.swift includes swift-telegram-sdk v4.5.0 and sherpa-onnx linker settings | ✓ SATISFIED | Both present in Package.swift with correct versions and linker flags                                                       |
| BUILD-03    | 01-01       | Bridging header correctly imports sherpa-onnx C API and ONNX Runtime C API       | ✓ SATISFIED | CSherpaOnnx module target with vendored c-api.h; build success confirms import works                                       |
| BUILD-04    | 01-02       | Release binary is a single file under 30MB (excluding model files)               | ⚠ PARTIAL   | Unstripped: 32.3MB (over limit). Stripped: 18.3MB (under limit). Strip step not automated — SUMMARY notes this was manual. |

All 4 requirement IDs from PLAN frontmatter accounted for. No orphaned requirements found (REQUIREMENTS.md maps BUILD-01 through BUILD-04 to Phase 1 only).

### Anti-Patterns Found

| File                        | Line | Pattern                                                                       | Severity  | Impact                                                                                                      |
| --------------------------- | ---- | ----------------------------------------------------------------------------- | --------- | ----------------------------------------------------------------------------------------------------------- |
| `Package.swift` (PLAN spec) | —    | `SherpaOnnxGetVersion` in plan vs actual `SherpaOnnxGetVersionStr` in c-api.h | ℹ INFO    | Correctly fixed during execution; c-api.h declares `SherpaOnnxGetVersionStr`. Not an issue in current code. |
| No strip automation         | —    | `swift build -c release` alone produces 32.3MB binary                         | ⚠ WARNING | BUILD-04 requires under 30MB; only stripped binary meets this. No Makefile/script automates strip step.     |

No TODO/FIXME/placeholder comments found in phase files. No empty implementations. No hardcoded empty data that flows to rendering. No `@main` attribute.

### Human Verification Required

#### 1. SIGTERM Clean Shutdown

**Test:** Run the binary in a terminal: `cd plugins/claude-tts-companion && .build/release/claude-tts-companion`. Verify it starts (check stderr for "Starting claude-tts-companion" log). Then send SIGTERM: `kill -TERM <PID>`.
**Expected:** Process logs "SIGTERM received, shutting down" to stderr and exits with code 0 within 2 seconds.
**Why human:** Cannot start a foreground NSApplication process and send signals in this verification context.

#### 2. Strip Step Documentation or Automation

**Test:** Review whether the build process for release is documented to include `strip`, or whether a Makefile/task automates `swift build -c release && strip`.
**Expected:** Either (a) a script/task exists that automates the strip step so the 30MB requirement is reliably met, or (b) CLAUDE.md and the phase documentation clarify that "release binary" means stripped binary and the build command is `swift build -c release && strip .build/release/claude-tts-companion`.
**Why human:** The strip command was run manually by the executor during Plan 02. No automation exists. BUILD-04 is satisfied only after manual stripping — this should be formalized.

### Gaps Summary

No blocking gaps found. The build system is fully operational:

- All 8 artifacts exist and contain substantive, correct implementations
- All 5 key links are verified wired
- `swift build -c release` succeeds and produces a working binary
- All 4 requirements (BUILD-01 through BUILD-04) are at minimum partially satisfied
- Plugin passes marketplace validation (29/29)
- All 5 commit hashes from SUMMARY are verified in git history

The two items flagged for human verification are:

1. **SIGTERM runtime behavior** — code is correctly structured but runtime confirmation requires launching the binary
2. **Strip automation gap** — BUILD-04 (`<30MB`) is met only after manual `strip`; the step is not scripted. This is a process/documentation gap, not a correctness gap in the current code.

The phase goal ("The project compiles and runs as a macOS accessory app with all dependencies resolved") is substantively achieved. The binary compiles, the C interop is proven by successful build, the NSApp accessory pattern is correctly implemented, and the SIGTERM handler is structurally correct.

---

_Verified: 2026-03-25T18:30:00Z_
_Verifier: Claude (gsd-verifier)_
