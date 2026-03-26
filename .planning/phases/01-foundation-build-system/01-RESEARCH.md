# Phase 1: Foundation & Build System - Research

**Researched:** 2026-03-25
**Domain:** SwiftPM build system, sherpa-onnx C interop, macOS accessory app lifecycle
**Confidence:** HIGH

## Summary

Phase 1 establishes the build system for a unified Swift macOS accessory app that links sherpa-onnx static libraries alongside swift-telegram-sdk via SwiftPM. The core challenge is getting the C/C++ static library linking, bridging header, and SwiftPM module map working together so that `swift build -c release` produces a single binary under 30MB.

All critical unknowns have been resolved by spike work. Spike 08 designed the Package.swift structure with linker flags. Spike 10 proved the E2E compilation with a bridging header importing sherpa-onnx C API. The sherpa-onnx static libraries exist pre-built at `~/fork-tools/sherpa-onnx/build-swift-macos/install/` with 15 `.a` files totaling the combined archive. Swift 6.2.4 is installed (compatible with swift-tools-version 6.0).

**Primary recommendation:** Use the CSherpaOnnx system library target approach (module.modulemap + shim.h) rather than `-import-objc-header` unsafeFlags. This is cleaner and recommended by Spike 08 as the preferred option. Vendor the C API headers into the project to avoid path fragility.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

None -- all implementation choices are at Claude's discretion for this infrastructure phase.

### Claude's Discretion

All implementation choices are at Claude's discretion -- pure infrastructure phase. Use ROADMAP phase goal, success criteria, and spike findings to guide decisions.

Key spike references:

- Spike 08: Package.swift design with sherpa-onnx linker flags
- Spike 10: Bridging header (`bridge.h`) for sherpa-onnx C API
- Spike 04: swift-telegram-sdk dependency setup
- Stack research: swift-telegram-sdk v4.5.0 (not v3.x from spikes)

### Deferred Ideas (OUT OF SCOPE)

None -- infrastructure phase.
</user_constraints>

<phase_requirements>

## Phase Requirements

| ID       | Description                                                                                 | Research Support                                                                                                                               |
| -------- | ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| BUILD-01 | `swift build -c release` succeeds with zero errors, single binary under 30MB                | Package.swift design from Spike 08; CSherpaOnnx module map approach; linker flags for 15 static libs; swift-telegram-sdk v4.5.0 SPM dependency |
| BUILD-02 | Package.swift includes swift-telegram-sdk v4.5.0 and sherpa-onnx static lib linker settings | STACK.md Package.swift template; Spike 08 Section 3 draft; verified lib paths at `~/fork-tools/sherpa-onnx/build-swift-macos/install/`         |
| BUILD-03 | Bridging header correctly imports sherpa-onnx C API and ONNX Runtime C API                  | Spike 10 bridge.h pattern; c-api.h at install/include/sherpa-onnx/c-api/; CSherpaOnnx module.modulemap alternative to bridging header          |
| BUILD-04 | Release binary is a single file under 30MB (excluding model files)                          | Spike 03: 19MB for TTS alone; Spike 04: 4.5MB for bot; combined target 19-25MB per STACK.md                                                    |

</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Bun-First Policy**: JavaScript global packages via `bun add -g` (not relevant to Swift build but relevant to validation scripts)
- **Plugin validation**: `bun scripts/validate-plugins.mjs` must pass after adding the new plugin
- **Plugin registry SSoT**: `.claude-plugin/marketplace.json` must include the new plugin entry
- **Plugin structure**: Each plugin needs its own `CLAUDE.md`
- **No Xcode**: SwiftPM only (`swift build`), explicitly listed in Out of Scope

## Standard Stack

### Core (Phase 1 only)

| Library            | Version                  | Purpose            | Why Standard                                                               |
| ------------------ | ------------------------ | ------------------ | -------------------------------------------------------------------------- |
| Swift              | 6.2.4 (installed)        | Primary language   | `swift --version` confirms arm64-apple-macosx15.0                          |
| SwiftPM            | swift-tools-version: 6.0 | Build system       | Spike 08 validated; compatible with Swift 6.2.4                            |
| macOS 14+          | `.macOS(.v14)`           | Deployment target  | Required by swift-telegram-sdk v4 Swift 6 concurrency                      |
| swift-telegram-sdk | 4.5.0 (from: "4.5.0")    | Telegram Bot API   | Stack research confirmed v4.5.0; Swift 6 strict concurrency support        |
| swift-log          | 1.10.1 (from: "1.6.0")   | Structured logging | Transitive dependency of swift-telegram-sdk; use directly                  |
| sherpa-onnx        | Static libs (pre-built)  | TTS engine C API   | 15 `.a` files at `~/fork-tools/sherpa-onnx/build-swift-macos/install/lib/` |

### Not Added in Phase 1

| Library               | Why Deferred                                                 |
| --------------------- | ------------------------------------------------------------ |
| FlyingFox             | HTTP server not needed until Phase 8; start with BSD sockets |
| swift-argument-parser | CLI flags not needed for initial build validation            |

## Architecture Patterns

### Recommended Project Structure

```
plugins/claude-tts-companion/
├── Package.swift                     <- SwiftPM manifest
├── Sources/
│   └── claude-tts-companion/
│       ├── main.swift                <- Entry point (NSApp accessory + SIGTERM)
│       ├── Config.swift              <- Paths, ports, token loading (enum, immutable)
│       └── Bridging/
│           └── CSherpaOnnx/
│               ├── module.modulemap  <- C module map for sherpa-onnx headers
│               └── shim.h            <- Umbrella header (#include c-api.h)
├── Sources/
│   └── CSherpaOnnx/
│       ├── include/
│       │   ├── module.modulemap
│       │   ├── shim.h
│       │   └── sherpa-onnx/
│       │       └── c-api/
│       │           └── c-api.h       <- Vendored from sherpa-onnx install
│       └── empty.c                   <- Required for SwiftPM to recognize C target
└── CLAUDE.md                         <- Plugin documentation
```

**Correction on structure:** The CSherpaOnnx target must be a separate target in Package.swift, not nested inside the executable target's Sources. SwiftPM requires each target to have its own directory.

### Final Structure

```
plugins/claude-tts-companion/
├── Package.swift
├── CLAUDE.md
├── Sources/
│   └── claude-tts-companion/
│       ├── main.swift
│       └── Config.swift
└── Sources/
    └── CSherpaOnnx/
        ├── include/
        │   ├── module.modulemap
        │   ├── shim.h
        │   └── sherpa-onnx/
        │       └── c-api/
        │           └── c-api.h       <- Vendored (1990 lines)
        └── empty.c
```

### Pattern 1: CSherpaOnnx Module Map (C Interop)

**What:** Create a SwiftPM C target that wraps sherpa-onnx headers with a module.modulemap, allowing `import CSherpaOnnx` from Swift code.

**When:** Always -- this is the standard SwiftPM approach for C library interop.

**Why:** Avoids the `-import-objc-header` unsafeFlags hack. Module maps are the SwiftPM-native way to import C headers. Spike 08 recommends this as the "cleaner" option.

```
// Sources/CSherpaOnnx/include/module.modulemap
module CSherpaOnnx {
    header "shim.h"
    link "sherpa-onnx"
    link "onnxruntime"
    export *
}
```

```c
// Sources/CSherpaOnnx/include/shim.h
#ifndef CSHERPAONNX_SHIM_H
#define CSHERPAONNX_SHIM_H
#include "sherpa-onnx/c-api/c-api.h"
#endif
```

### Pattern 2: NSApplication Accessory App Entry Point

**What:** Manual NSApplication setup as an accessory app (no dock icon, no app switcher).

**When:** Phase 1 establishes this pattern; all future phases build on it.

```swift
// main.swift
import AppKit
import Foundation
import Logging

// Unbuffer stdout/stderr for launchd
setbuf(stdout, nil)
setbuf(stderr, nil)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Set up SIGTERM handler
let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)  // Let DispatchSource handle it
sigSource.setEventHandler {
    LoggingSystem.bootstrap(StreamLogHandler.standardError)
    let logger = Logger(label: "claude-tts-companion")
    logger.info("SIGTERM received, shutting down")
    // Post dummy event to unblock RunLoop (Pitfall 10)
    let event = NSEvent.otherEvent(
        with: .applicationDefined, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, subtype: 0, data1: 0, data2: 0
    )!
    app.postEvent(event, atStart: true)
    app.stop(nil)
}
sigSource.resume()

// Store sigSource globally to prevent ARC deallocation (Pitfall 1)
// This is a module-level variable
nonisolated(unsafe) var keepAlive: (any DispatchSourceSignal)? = sigSource

// Verify C interop works
import CSherpaOnnx
let version = String(cString: SherpaOnnxGetVersion())
print("sherpa-onnx version: \(version)")

// Configure logging
LoggingSystem.bootstrap(StreamLogHandler.standardError)
let logger = Logger(label: "claude-tts-companion")
logger.info("Starting claude-tts-companion")

// Enter run loop (blocks forever)
app.run()
```

### Anti-Patterns to Avoid

- **`@main` attribute:** Conflicts with custom `main.swift` entry point. Do not use SwiftUI App protocol.
- **Bridging header via unsafeFlags:** Use CSherpaOnnx module map target instead.
- **Hardcoded absolute paths in Package.swift:** Use environment variable expansion or relative paths for sherpa-onnx lib directory.

## Don't Hand-Roll

| Problem          | Don't Build                       | Use Instead                                | Why                                                            |
| ---------------- | --------------------------------- | ------------------------------------------ | -------------------------------------------------------------- |
| C header import  | `-import-objc-header` unsafeFlags | CSherpaOnnx module.modulemap target        | SwiftPM-native, no unsafeFlags for headers                     |
| Logging          | `print()` statements              | swift-log `StreamLogHandler.standardError` | Already a transitive dependency; unbuffered stderr for launchd |
| SIGTERM handling | `signal(SIGTERM, handler)`        | `DispatchSource.makeSignalSource`          | Integrates with RunLoop; proven in Spike 10                    |

## Common Pitfalls

### Pitfall 1: sherpa-onnx Library Path Fragility

**What goes wrong:** Package.swift references `~/fork-tools/sherpa-onnx/build-swift-macos/install/lib` with a hardcoded path. The build breaks if the directory moves or the home directory differs.

**Why it happens:** SwiftPM `unsafeFlags` for `-L` linker paths don't support `~` expansion natively. `ProcessInfo.processInfo.environment["HOME"]` works but is fragile.

**How to avoid:** Use `ProcessInfo.processInfo.environment["HOME"]` in Package.swift (as Spike 08 does) or set `SHERPA_ONNX_PATH` environment variable with a fallback default. Document the expected path.

**Warning signs:** `swift build` fails with `ld: library not found for -lsherpa-onnx`.

### Pitfall 2: Missing Linker Libraries

**What goes wrong:** Linking with just `-lsherpa-onnx -lonnxruntime` is insufficient. The combined `libsherpa-onnx.a` archive may not pull all transitive dependencies automatically depending on the linker.

**Why it happens:** The 15 individual `.a` files have interdependencies. The combined archive (`libsherpa-onnx.a`) should contain them all, but if it doesn't, individual libs must be listed.

**How to avoid:** Start with `-lsherpa-onnx -lonnxruntime -lc++`. If undefined symbol errors appear, add individual libraries: `-lsherpa-onnx-c-api`, `-lsherpa-onnx-core`, `-lkaldi-native-fbank-core`, `-lkissfft-float`, `-lpiper_phonemize`, `-lespeak-ng`, `-lssentencepiece_core`, `-lucd`.

**Warning signs:** Linker errors with undefined symbols like `_SherpaOnnxCreateOfflineTts` or `_OrtGetApiBase`.

### Pitfall 3: DispatchSource ARC Deallocation

**What goes wrong:** SIGTERM handler stops working silently because `DispatchSource` is deallocated by ARC.

**How to avoid:** Store all DispatchSource instances as `nonisolated(unsafe) var` at module scope. Never as function-local variables.

**Warning signs:** SIGTERM kills process immediately instead of running cleanup handler.

### Pitfall 4: NSApplication.stop() Requires Dummy Event

**What goes wrong:** `app.stop(nil)` does not return from `app.run()` until another event is processed.

**How to avoid:** Always post a dummy `NSEvent.otherEvent` immediately after calling `app.stop(nil)`. See Pattern 2 code example.

### Pitfall 5: stdout Buffering in Daemon Context

**What goes wrong:** `print()` output never appears in logs when running under launchd.

**How to avoid:** Call `setbuf(stdout, nil)` and `setbuf(stderr, nil)` at process startup. Use swift-log's `StreamLogHandler.standardError` for all production logging.

### Pitfall 6: Swift 6 Strict Concurrency Warnings

**What goes wrong:** swift-telegram-sdk types (e.g., `TGBot`) are not marked `Sendable`. Swift 6 strict mode produces errors when passing them across concurrency boundaries.

**How to avoid:** Use `@preconcurrency import SwiftTelegramSdk`. Not needed in Phase 1 (no bot code yet), but establish the import pattern in main.swift.

## Code Examples

### Package.swift (Phase 1 Minimal)

```swift
// swift-tools-version: 6.0
import PackageDescription

let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
let sherpaOnnxPath = "\(home)/fork-tools/sherpa-onnx/build-swift-macos/install"

let package = Package(
    name: "claude-tts-companion",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/nerzh/swift-telegram-sdk", from: "4.5.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "CSherpaOnnx",
            path: "Sources/CSherpaOnnx",
            cSettings: [
                .headerSearchPath("include"),
            ]
        ),
        .executableTarget(
            name: "claude-tts-companion",
            dependencies: [
                "CSherpaOnnx",
                .product(name: "SwiftTelegramSdk", package: "swift-telegram-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(sherpaOnnxPath)/lib",
                ]),
                .linkedLibrary("sherpa-onnx"),
                .linkedLibrary("onnxruntime"),
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)
```

**Key decisions in this Package.swift:**

1. `CSherpaOnnx` is a separate `.target` (not `.systemLibrary`) so vendored headers work without pkg-config.
2. `linkerSettings` uses the combined `libsherpa-onnx.a` archive first. If linking fails, switch to individual libraries.
3. `swift-telegram-sdk` is included now to validate dependency resolution even though bot code comes in Phase 5.
4. `Accelerate` framework is NOT linked -- sherpa-onnx static build does not reference Accelerate symbols (verified via `nm`).

### module.modulemap

```
module CSherpaOnnx {
    header "shim.h"
    link "sherpa-onnx"
    link "onnxruntime"
    export *
}
```

### shim.h

```c
#ifndef CSHERPAONNX_SHIM_H
#define CSHERPAONNX_SHIM_H

// sherpa-onnx C API
#include "sherpa-onnx/c-api/c-api.h"

#endif /* CSHERPAONNX_SHIM_H */
```

### Trivial C Function Call Verification (main.swift)

```swift
import CSherpaOnnx

// Verify C interop by calling a simple sherpa-onnx function
let version = String(cString: SherpaOnnxGetVersion())
print("sherpa-onnx C API version: \(version)")
// Expected output: something like "1.12.33"
```

## Environment Availability

| Dependency               | Required By        | Available                | Version                                                                               | Fallback |
| ------------------------ | ------------------ | ------------------------ | ------------------------------------------------------------------------------------- | -------- |
| Swift compiler           | BUILD-01           | Yes                      | 6.2.4 (arm64-apple-macosx15.0)                                                        | --       |
| SwiftPM                  | BUILD-01           | Yes                      | Bundled with Swift 6.2.4                                                              | --       |
| sherpa-onnx static libs  | BUILD-02, BUILD-03 | Yes                      | Pre-built at `~/fork-tools/sherpa-onnx/build-swift-macos/install/lib/` (15 .a files)  | --       |
| sherpa-onnx C API header | BUILD-03           | Yes                      | `c-api.h` (1990 lines) at install/include/sherpa-onnx/c-api/                          | --       |
| Kokoro int8 model        | Verify path        | Yes (different location) | At `~/tmp/subtitle-spikes-7aqa/03-textream/models-int8/kokoro-int8-en-v0_19/` (152MB) | --       |
| macOS SDK (AppKit)       | BUILD-01           | Yes                      | macOS 15.0 (Xcode CLT)                                                                | --       |

**Missing dependencies with no fallback:** None.

**Important path discrepancy:** The Kokoro int8 model is at `~/tmp/subtitle-spikes-7aqa/03-textream/models-int8/kokoro-int8-en-v0_19/`, NOT at the path stated in DEP-04 (`~/.local/share/kokoro/models/kokoro-int8-en-v0_19/`). Phase 1 Config.swift should use the actual path as default but allow override via environment variable. The model copy to the canonical path is a Phase 10 (Deployment) concern.

## Validation Architecture

### Test Framework

| Property           | Value                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------ | --- | ----- |
| Framework          | Swift built-in assertions + shell verification                                                                           |
| Config file        | None -- Phase 1 uses build success as primary validation                                                                 |
| Quick run command  | `swift build -c release 2>&1`                                                                                            |
| Full suite command | `swift build -c release && ls -la .build/release/claude-tts-companion && .build/release/claude-tts-companion --help 2>&1 |     | true` |

### Phase Requirements to Test Map

| Req ID   | Behavior                                                                         | Test Type | Automated Command                                                                                                                | File Exists?        |
| -------- | -------------------------------------------------------------------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------- |
| BUILD-01 | `swift build -c release` succeeds                                                | build     | `cd plugins/claude-tts-companion && swift build -c release 2>&1; echo "EXIT: $?"`                                                | N/A (build system)  |
| BUILD-02 | Package.swift resolves swift-telegram-sdk v4.5.0 and sherpa-onnx linker settings | build     | `cd plugins/claude-tts-companion && swift package resolve 2>&1`                                                                  | N/A (Package.swift) |
| BUILD-03 | Bridging header imports C API; trivial C function call succeeds                  | smoke     | `cd plugins/claude-tts-companion && swift build -c release && .build/release/claude-tts-companion 2>&1 \| grep -q "sherpa-onnx"` | N/A (main.swift)    |
| BUILD-04 | Release binary is single file under 30MB                                         | smoke     | `cd plugins/claude-tts-companion && swift build -c release && stat -f%z .build/release/claude-tts-companion`                     | N/A (build output)  |

### Sampling Rate

- **Per task commit:** `swift build -c release` in the plugin directory
- **Per wave merge:** Full build + binary size check + trivial run
- **Phase gate:** All 4 BUILD requirements verified before `/gsd:verify-work`

### Wave 0 Gaps

None -- Phase 1 validation is build-system-level (compile success, binary size, trivial run). No test framework setup needed. Unit tests will be introduced in later phases when there is testable logic.

## State of the Art

| Old Approach                        | Current Approach                        | When Changed                        | Impact                              |
| ----------------------------------- | --------------------------------------- | ----------------------------------- | ----------------------------------- |
| `-import-objc-header` for C interop | CSherpaOnnx module.modulemap target     | SwiftPM convention since Swift 5.4+ | Avoids unsafeFlags; cleaner imports |
| swift-telegram-sdk v3.x             | v4.5.0 with Swift 6 concurrency         | March 2026                          | Strict Sendable conformance support |
| Spike 08 used `Task { }` for bot    | Architecture recommends `Task.detached` | Spike 10 finding                    | Prevents main actor inheritance     |

## Open Questions

1. **Combined vs individual static libraries**
   - What we know: `libsherpa-onnx.a` is a combined archive; 14 individual `.a` files also exist
   - What's unclear: Whether `-lsherpa-onnx` alone pulls all symbols, or individual libs must be listed
   - Recommendation: Try combined first (`-lsherpa-onnx -lonnxruntime -lc++`). If undefined symbols appear, add individual libraries one by one. This will be resolved during implementation.

2. **Binary size with swift-telegram-sdk v4.5.0**
   - What we know: Spike 04 measured 4.5MB with v3.x; Spike 03 measured 19MB for TTS alone
   - What's unclear: Whether v4.5.0 adds significant binary size
   - Recommendation: Build and measure. Target is under 30MB. Spike data suggests ~23MB combined which is well within budget.

3. **CSherpaOnnx as .target vs .systemLibrary**
   - What we know: `.systemLibrary` requires pkg-config or manual provider setup; `.target` with vendored headers is simpler
   - Recommendation: Use `.target` with vendored c-api.h header. The sherpa-onnx.pc file exists but `.target` is more portable.

## Sources

### Primary (HIGH confidence)

- Spike 08: Integration Architecture -- Package.swift design, linker flags, concurrency model
- Spike 10: E2E Flow -- bridge.h pattern, NSApp.run() + background coexistence, SIGTERM handling
- STACK.md -- Verified stack decisions, dependency tree, Package.swift template
- ARCHITECTURE.md -- Component boundaries, thread model, build order
- PITFALLS.md -- 17 catalogued pitfalls with prevention strategies
- Local filesystem verification: `~/fork-tools/sherpa-onnx/build-swift-macos/install/` (15 .a files, c-api.h confirmed)
- `swift --version` output: Swift 6.2.4, arm64-apple-macosx15.0

### Secondary (MEDIUM confidence)

- Spike 04: swift-telegram-sdk v3.x validation (v4.5.0 is newer but API pattern is same)
- sherpa-onnx SherpaOnnx.swift wrapper at `~/fork-tools/sherpa-onnx/swift-api-examples/SherpaOnnx.swift` (1909 lines)

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH -- all libraries and paths verified on local machine
- Architecture: HIGH -- spike 08/10 validated the exact build approach
- Pitfalls: HIGH -- comprehensive pitfall catalog from spike work and PITFALLS.md

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable domain, static library approach is well-established)
