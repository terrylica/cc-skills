# Domain Pitfalls

**Domain:** Unified Swift macOS service replacing multi-runtime TTS/bot/subtitle system
**Researched:** 2026-03-25

## Critical Pitfalls

Mistakes that cause rewrites, data loss, or extended downtime.

### Pitfall 1: DispatchSource Silent Deallocation (ARC Kills Your Watchers)

**What goes wrong:** DispatchSource file watchers stop receiving events with zero errors, zero warnings. The watcher simply goes silent. Production symptoms: notifications stop arriving, JSONL tailing stops, file watcher appears "stuck."

**Why it happens:** DispatchSource objects are reference-counted. If stored as a local variable in a function, ARC deallocates the source when the function scope exits. The kernel-side event registration is cleaned up, but no error is raised -- the source just vanishes.

**Consequences:** Silent feature failure. The bot stops detecting new sessions, thinking watcher stops detecting blocks, notification watcher stops processing. No crash, no log, just dead functionality that passes health checks.

**Prevention:**

- Store ALL DispatchSource instances as properties on a long-lived object (actor, class, or global). Never as function-local variables.
- Use `nonisolated(unsafe) var` at module scope if needed (proven pattern from Spike 04).
- Add heartbeat assertions: if a watched directory gets an fsync but the watcher callback does not fire within 5s, log a critical error.
- Integration test: create watcher, trigger event, assert callback fires. Run this in CI.

**Detection:** Monitoring gap -- if `lastNotificationProcessed` timestamp exceeds 30 minutes while sessions are active, the watcher is likely dead.

**Phase:** Phase 1 (Foundation). Establish the watcher lifecycle pattern in the first module. Every subsequent watcher follows it.

**Confidence:** HIGH -- proven in Spike 04, documented in spike report with exact fix.

---

### Pitfall 2: NSApplication.run() Must Own Main Thread -- Everything Else Must Yield

**What goes wrong:** Calling any blocking operation on the main thread after `NSApplication.run()` freezes the entire UI. Subtitles freeze, the overlay stops updating, AppKit event processing halts. Alternatively, failing to call `NSApplication.run()` at all means NSPanel never renders.

**Why it happens:** AppKit's RunLoop and NSApplication.run() are inseparable from the main thread on macOS. There is no alternative. `DispatchQueue.main.async` enqueues onto this RunLoop, so it only works if the RunLoop is actually running. If synthesis, network calls, or file I/O accidentally run on the main thread, the RunLoop starves.

**Consequences:** Subtitle overlay freezes or never appears. Since this is the project's headline feature (karaoke subtitles), a frozen overlay is a ship-blocking bug.

**Prevention:**

- Establish an iron rule: `main thread = UI only`. Every other subsystem gets its own DispatchQueue or Task.
- sherpa-onnx synthesis: dedicated `DispatchQueue(label: "tts", qos: .userInitiated)`.
- Telegram bot long-polling: `Task { }` (structured concurrency).
- HTTP server: `DispatchQueue.global(.utility)`.
- File watchers: `DispatchQueue(.utility)` per Spike 04/15.
- UI updates from background: `DispatchQueue.main.async { }` (not `.sync`!).
- Never use `DispatchQueue.main.sync` from a background thread when NSApplication.run() is active -- this can deadlock.

**Detection:** If `SubtitlePanel.update()` latency exceeds 16ms (one frame), something is blocking the main thread. Add a watchdog timer on main that logs if its callback is delayed by >100ms.

**Phase:** Phase 1 (Foundation). The concurrency architecture from Spike 08/10 must be the first thing built and never violated.

**Confidence:** HIGH -- proven sound in Spike 10 E2E flow, but any regression here is catastrophic.

---

### Pitfall 3: BOT_TOKEN Long-Polling Conflict (Two Consumers = 409 Crash)

**What goes wrong:** The new Swift bot and the old Bun/TypeScript bot both try to long-poll the same Telegram bot token. Telegram returns HTTP 409 Conflict. swift-telegram-sdk's error handling escalates this to a fatal crash (SIGKILL observed in Spike 04).

**Why it happens:** Telegram Bot API enforces single-consumer long-polling per token. This is server-side -- there is no client-side workaround. The all-or-nothing rollout means you must stop the old bot before starting the new one, but if anything goes wrong during cutover, you have zero bot functionality.

**Consequences:** During botched rollout: no Telegram bot at all. During development/testing: cannot test the Swift bot while the production Bun bot runs.

**Prevention:**

- **Development:** Use a separate test bot token for all Swift development and integration testing. Never test against the production token while the Bun bot runs.
- **Rollout script:** Atomic cutover: `launchctl unload old.plist && launchctl load new.plist` in a single script. Verify the new service is polling successfully before declaring success.
- **Rollback plan:** Keep the old plist intact (PROJECT.md says "stop, don't delete"). If the Swift binary crashes on first launch, re-enable the old bot within 30 seconds.
- **Health check:** After starting the Swift bot, verify `getMe()` succeeds and at least one `getUpdates` cycle completes before declaring rollout successful.

**Detection:** HTTP 409 in bot polling logs. Or: bot stops receiving messages entirely.

**Phase:** Phase 2 (Telegram Bot) for development token setup. Final phase (Integration/Rollout) for cutover script.

**Confidence:** HIGH -- directly observed in Spike 04.

---

### Pitfall 4: sherpa-onnx 561MB Peak RSS Starving Other Subsystems

**What goes wrong:** During TTS synthesis, the process RSS jumps from ~27MB to 561MB. If multiple synthesis requests queue up (e.g., thinking watcher fires rapidly, plus a session summary arrives), peak RSS can climb further. On a 16GB MacBook with heavy workloads (Xcode, Chrome, Claude Code), this causes memory pressure, swapping, and system-wide slowdown.

**Why it happens:** The ONNX Runtime loads the entire Kokoro int8 model into memory eagerly. The 561MB peak is the model weights + inference buffers + audio output. This is already 49% smaller than the fp32 model (1,237MB) but still significant.

**Consequences:** System becomes sluggish during synthesis. Worst case: macOS kills the process via jetsam (OOM killer) if memory pressure is extreme.

**Prevention:**

- **Serialize synthesis:** Never run two synthesis operations concurrently. Use a serial DispatchQueue for the TTS engine (Spike 08 design).
- **Queue depth limit:** Cap the TTS queue at 3-5 items. Drop older requests when the queue overflows (the user only cares about the most recent content).
- **Lazy model loading:** Don't load the sherpa-onnx model at startup. Load on first TTS request (~0.56s penalty). Consider unloading after 5 minutes of inactivity if RSS savings matter.
- **Monitor RSS:** Log RSS after each synthesis. If it trends upward across calls (leak), investigate immediately.
- **Pipelined synthesis:** Synthesize chunk N+1 while playing chunk N (existing Python pattern). This keeps a single model loaded, not multiple.

**Detection:** `task_info()` RSS monitoring. Alert if RSS exceeds 700MB or if RSS does not decrease after synthesis completes.

**Phase:** Phase 3 (TTS Engine). Build queue management and serialization from the start.

**Confidence:** HIGH -- measured in Spikes 03, 09, 10.

---

### Pitfall 5: All-or-Nothing Rollout With No Partial Fallback

**What goes wrong:** The unified binary must replace 3 services simultaneously. If any one subsystem fails (bot crashes, TTS produces silence, subtitles don't render), the entire system is down. There is no way to run "old bot + new TTS" or "new bot + old TTS."

**Why it happens:** By design -- the project consolidates 3 runtimes into 1 binary. This is the explicit goal and the source of all efficiency gains (88% idle RSS reduction, single process). But it means a bug in the subtitle overlay code can take down the Telegram bot.

**Consequences:** Total service outage. No Telegram notifications, no TTS, no subtitles. The old services still exist but are stopped.

**Prevention:**

- **Feature flags per subsystem:** The binary should have flags like `--no-tts`, `--no-subtitle`, `--no-bot` to disable individual subsystems. If TTS crashes, restart with `--no-tts` and fall back to macOS `say`.
- **Crash isolation:** Wrap each subsystem's initialization in do/catch. If sherpa-onnx model loading fails, log the error and continue with bot + subtitles. If swift-telegram-sdk fails, continue with TTS + subtitles.
- **Graceful degradation hierarchy:** Bot is most critical (notifications). TTS is second (audio). Subtitles are third (visual). If TTS fails, bot still sends text notifications. If subtitles fail, TTS still speaks.
- **Fast rollback:** Keep old plist files. `launchctl unload new && launchctl load old-bot && launchctl load old-tts` should be a one-liner script.
- **Smoke test on launch:** Before entering the main run loop, verify: (1) bot token is valid (`getMe()`), (2) sherpa-onnx model loads, (3) NSPanel can be created. Log results. If any critical check fails, exit with a descriptive error rather than running in a degraded state.

**Detection:** SwiftBar plugin (claude-hq v3.0.0) monitors the unified service PID. If PID disappears, SwiftBar shows red status immediately.

**Phase:** Every phase builds its subsystem with independent enable/disable. Final integration phase adds the smoke test and rollback script.

**Confidence:** HIGH -- this is an architectural decision, not a technical uncertainty.

---

### Pitfall 6: sherpa-onnx C Bridging Header Fragility

**What goes wrong:** The sherpa-onnx bridging header (`SherpaOnnx-Bridging-Header.h`) references headers at a hardcoded path (`~/fork-tools/sherpa-onnx/build-swift-macos/install/include`). If sherpa-onnx is rebuilt, updated, or the directory structure changes, the Swift project silently fails to find types, producing confusing compiler errors about unknown types.

**Why it happens:** SwiftPM's `-import-objc-header` is an `unsafeFlags` setting that bypasses the package manager's normal dependency resolution. The headers are not vendored into the Swift project -- they reference an external build tree.

**Consequences:** Build breaks after sherpa-onnx updates. Confusing error messages ("use of undeclared type 'OrtValue'") that don't point to the actual problem (wrong header path).

**Prevention:**

- **Vendor the headers:** Copy the required headers (`c-api.h`, `onnxruntime_c_api.h`) into the Swift project's `Sources/Bridging/` directory. Pin to the exact sherpa-onnx version.
- **Version pinning:** Document the exact sherpa-onnx commit hash in a `BUILD.md`. If the C API changes, the vendored headers must be updated explicitly.
- **Build verification:** The first CI step should be `swift build` with a clean SPM cache. If it fails, the bridging header is broken.
- **Static lib path:** Use a `Makefile` or `justfile` that resolves `SHERPA_ONNX_LIB` from a known location, not a hardcoded home directory path.

**Detection:** `swift build` fails with obscure type errors after any change to the sherpa-onnx installation.

**Phase:** Phase 1 (Foundation). Vendor headers and establish the build system before writing any feature code.

**Confidence:** HIGH -- bridging header fragility is a well-known Swift/C interop issue.

---

## Moderate Pitfalls

### Pitfall 7: swift-telegram-sdk Single Maintainer Risk

**What goes wrong:** The SDK (266 stars, maintained by `nerzh`) stops receiving updates. A Telegram Bot API change breaks compatibility. The SDK's Thread-based long polling has known issues (commented-out Task-based approach with "try fix longpolling freeze" comment).

**Prevention:**

- **Vendor the dependency.** Fork `nerzh/swift-telegram-sdk` to your GitHub. Pin to the fork in `Package.swift`. If upstream dies, you own the code.
- **Understand the escape hatch.** The SDK is essentially a type-safe wrapper over Telegram Bot API HTTP calls. The core is the `TGClientPrtcl` you already implement (88 lines URLSession). If the SDK breaks, replace it with direct `URLSession` calls to `https://api.telegram.org/bot{token}/{method}` -- roughly 500 lines of manual JSON encoding/decoding.
- **Monitor upstream.** If no commits for 6 months, evaluate whether to maintain the fork or switch to direct API calls.

**Phase:** Phase 2 (Telegram Bot). Fork the SDK before starting bot development.

**Confidence:** MEDIUM -- single maintainer is a risk factor, but the SDK has been maintained through Jan 2025 and the Telegram Bot API is stable.

---

### Pitfall 8: TGBot Not Sendable (Swift 6 Strict Concurrency)

**What goes wrong:** Swift 6 strict concurrency mode flags `TGBot` as non-Sendable. Passing it across actor/task boundaries produces compiler errors. The `@preconcurrency import` workaround suppresses warnings but does not make the type actually safe.

**Prevention:**

- Use `@preconcurrency import SwiftTelegramSdk` as proven in Spike 04.
- Confine all `TGBot` usage to a single actor or class. Never pass the bot instance across concurrency domains.
- Treat `TGBot` as a singleton owned by the bot subsystem. Other subsystems communicate via a message channel (AsyncStream), not by calling bot methods directly.

**Phase:** Phase 2 (Telegram Bot). Establish the bot actor boundary immediately.

**Confidence:** HIGH -- observed and resolved in Spike 04.

---

### Pitfall 9: Phonemization Gap in Timestamp Extraction

**What goes wrong:** The sherpa-onnx patch (~50 lines C++) exposes the duration tensor, but the mapping from duration indices back to words requires knowing which phoneme tokens correspond to which words. If the word-to-phoneme alignment is off, subtitle highlighting drifts from the actual audio.

**Why it happens:** espeak-ng phonemization can merge words, split words, or insert silence tokens in non-obvious ways. The Kokoro tokenizer adds padding tokens. The duration tensor has entries for every token including padding and silence, not just "word" tokens.

**Prevention:**

- Start with the Python reference implementation's alignment as ground truth. Port the exact same token-to-word mapping logic.
- Test with diverse text: short words ("I am"), long words ("unfortunately"), punctuation-heavy text ("Hello, world! How's it going?"), numbers ("42 users").
- Accept small drift (<50ms) as acceptable. Subtitle highlighting at word granularity is forgiving -- the human eye does not notice 50ms misalignment.
- If alignment is fundamentally broken, fall back to proportional timing (divide audio duration by word count). This is worse but still usable.

**Phase:** Phase 3 (TTS Engine) or Phase 4 (Subtitle/Karaoke). Depends on whether timestamps are part of TTS or subtitle responsibility.

**Confidence:** MEDIUM -- Spike 16 proved the duration tensor is extractable with 0.5% accounting error, but word-level alignment across diverse text is untested.

---

### Pitfall 10: NSApplication.stop() Requires Dummy Event to Unblock RunLoop

**What goes wrong:** Calling `NSApplication.shared.stop(nil)` does not immediately return from `NSApplication.run()`. The RunLoop continues blocking until it processes another event. If no event arrives, the process hangs on shutdown.

**Prevention:**

- After calling `app.stop(nil)`, always post a dummy event:

  ```swift
  let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
      modifierFlags: [], timestamp: 0, windowNumber: 0,
      context: nil, subtype: 0, data1: 0, data2: 0)
  app.postEvent(event!, atStart: true)
  ```

- Wrap this in a `func requestShutdown()` utility. Never call `app.stop()` directly.

**Phase:** Phase 1 (Foundation). Part of the app lifecycle boilerplate.

**Confidence:** HIGH -- proven in Spike 10.

---

### Pitfall 11: Feature Parity Drift During Rewrite

**What goes wrong:** The TypeScript bot has 4,500 lines of accumulated features (17 noise-filter patterns, 2 regexes, fence-aware HTML chunking, workspace path decoding with backtracking, etc.). During the Swift rewrite, subtle behaviors are lost: a regex pattern is forgotten, a noise filter is skipped, a edge case in transcript parsing is missed. The result "mostly works" but sends malformed Telegram messages for edge cases.

**Prevention:**

- **Port file by file, not feature by feature.** Each TypeScript module (e.g., `transcript-parser.ts`) becomes a corresponding Swift file. Compare line by line.
- **Capture test fixtures from production.** Run the existing TypeScript bot for a week, saving every JSONL transcript it processes and the Telegram messages it produces. Use these as golden test cases for the Swift port.
- **The 17 noise-filter patterns and 2 regexes must be ported verbatim.** These evolved from production bugs. Every one exists because a real session triggered a false positive.
- **Fence-aware chunking:** Port `parseFenceSpans()` and `chunkTelegramHtml()` with their exact splitting logic. Test with messages containing nested code blocks.

**Phase:** Phase 2 (Telegram Bot) and Phase 5 (Thinking Watcher). Establish golden test fixtures before starting each port.

**Confidence:** MEDIUM -- the risk is proportional to the number of edge cases in the TypeScript code, which is high (4,500 lines).

---

### Pitfall 12: stdout Buffering in Daemon Context

**What goes wrong:** `print()` statements from GCD queues and background threads buffer indefinitely in a launchd-managed process. Logs never appear in `Console.app` or `log stream`. Debugging production issues becomes impossible.

**Prevention:**

- Call `setbuf(stdout, nil)` and `setbuf(stderr, nil)` at process startup (proven in Spike 04).
- Use `os_log` / `Logger` (from `os` framework) instead of `print()` for all production logging. `os_log` is unbuffered and integrates with macOS unified logging.
- Reserve `print()` for development only.

**Phase:** Phase 1 (Foundation). Set up logging infrastructure first.

**Confidence:** HIGH -- standard macOS daemon behavior, noted in Spike 04.

---

### Pitfall 13: Mixing Swift Concurrency with GCD Causes Thread Pool Exhaustion

**What goes wrong:** Swift's cooperative thread pool has a limited number of threads (equal to CPU core count). If these threads block inside GCD dispatches, synchronous file I/O, or `withCheckedContinuation` wrappers around blocking calls, the entire concurrency system deadlocks.

**Prevention:**

- sherpa-onnx synthesis (7s blocking call) must NOT run on a Swift Concurrency Task. Use a dedicated `DispatchQueue` and bridge to async via `withCheckedContinuation` (Spike 08 design).
- HTTP server socket accept/read must NOT run on Swift Concurrency threads. Use `DispatchQueue.global(.utility)`.
- Only use `async/await` for truly non-blocking work: URLSession calls, timer-based scheduling, inter-actor messaging.
- Rule of thumb: if a call blocks for >10ms, it does not belong in a `Task { }`.

**Phase:** Phase 1 (Foundation). Document the concurrency policy. Enforce it in code review.

**Confidence:** HIGH -- well-documented Swift concurrency pitfall. See [Problematic Swift Concurrency Patterns](https://www.massicotte.org/problematic-patterns/) and [Swift Concurrency Challenges](https://twocentstudios.com/2025/08/12/3-swift-concurrency-challenges-from-the-last-2-weeks/).

---

## Minor Pitfalls

### Pitfall 14: launchd Agent vs. Daemon Confusion

**What goes wrong:** The unified binary needs AppKit (NSPanel for subtitles). Daemons (`/Library/LaunchDaemons/`) cannot access the window server. If the plist is installed as a daemon, subtitles will never appear.

**Prevention:** Always use LaunchAgent (`~/Library/LaunchAgents/`), never LaunchDaemon. The existing bot already uses LaunchAgents -- follow the same pattern.

**Phase:** Phase 1 (Foundation).

**Confidence:** HIGH -- Apple documentation is explicit about this.

---

### Pitfall 15: afplay Subprocess Zombie Accumulation

**What goes wrong:** Each TTS playback spawns an `afplay` subprocess. If the Process handle is not properly waited on (or terminated on cancellation), zombie processes accumulate. After hundreds of TTS utterances, the system hits process limits.

**Prevention:**

- Always call `process.waitUntilExit()` after launching afplay.
- On queue cancellation (`/v1/audio/stop` equivalent), call `process.terminate()` followed by `process.waitUntilExit()`.
- Consider AVAudioPlayer as an alternative to afplay subprocess for lower overhead. But afplay is proven and simpler for fire-and-forget.

**Phase:** Phase 3 (TTS Engine).

**Confidence:** MEDIUM -- standard Unix process management.

---

### Pitfall 16: Model File Path Hardcoding

**What goes wrong:** The Kokoro model path (`~/.local/share/kokoro/models/kokoro-int8-en-v0_19/`) is hardcoded. If the model is updated to a new version, or the user moves it, the binary fails at runtime with an opaque error from sherpa-onnx.

**Prevention:**

- Make model path configurable via environment variable (`KOKORO_MODEL_PATH`) with a sensible default.
- On startup, verify the model directory exists and contains expected files before attempting to load.
- Log the resolved model path at startup.

**Phase:** Phase 1 (Foundation) -- configuration system.

**Confidence:** HIGH -- simple but easy to forget.

---

### Pitfall 17: Telegram HTML Parse Errors on Malformed Markup

**What goes wrong:** Telegram's HTML parser is strict. Unclosed tags, nested `<b><i></b></i>`, or special characters in code blocks cause `400 Bad Request` with "can't parse entities." The TypeScript bot has extensive workarounds for this (safe edit, HTML-to-plaintext fallback, file reference de-linkification).

**Prevention:** Port the entire `format.ts` + `fences.ts` + `tg-send.ts` error handling chain. Specifically:

- `safeEditMessage` with HTML -> plaintext fallback.
- `wrapFileReferencesInHtml` to prevent `.md`, `.py`, `.ts` filenames from becoming clickable links.
- `chunkTelegramHtml` fence-aware splitting.
- Recursive error chain traversal for `isHtmlParseError` detection.

**Phase:** Phase 2 (Telegram Bot).

**Confidence:** HIGH -- this was hard-won in the TypeScript bot over months of production bugs.

---

## Phase-Specific Warnings

| Phase Topic               | Likely Pitfall                                                   | Mitigation                                                   |
| ------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------ |
| Foundation / Build System | Bridging header breaks on sherpa-onnx update (#6)                | Vendor headers, pin commit hash                              |
| Foundation / Lifecycle    | DispatchSource silent dealloc (#1), NSApp.run() main thread (#2) | Establish patterns in first PR, never deviate                |
| Foundation / Logging      | stdout buffering (#12)                                           | os_log from day 1                                            |
| Telegram Bot              | Token conflict (#3), SDK Sendable (#8), Feature drift (#11)      | Test token, @preconcurrency, golden fixtures                 |
| TTS Engine                | 561MB RSS (#4), Phonemization gap (#9), Thread pool (#13)        | Serial queue, proportional fallback, dedicated DispatchQueue |
| Subtitle / Karaoke        | Main thread starvation (#2), NSApp.stop() hang (#10)             | UI-only main thread, dummy event pattern                     |
| Rollout                   | All-or-nothing risk (#5), Token conflict (#3)                    | Feature flags, atomic cutover script, rollback plan          |

## Sources

- [Spike 04: Swift Telegram Bot Report](~/tmp/subtitle-spikes-7aqa/04-lyricfever/SPIKE-04-REPORT.md) -- TGBot Sendable, DispatchSource dealloc, token conflict (HIGH confidence)
- [Spike 08: Integration Architecture](~/tmp/subtitle-spikes-7aqa/SPIKE-08-INTEGRATION-ARCH.md) -- concurrency model, Package.swift design (HIGH confidence)
- [Spike 10: E2E Flow Report](~/tmp/subtitle-spikes-7aqa/10-e2e-flow/SPIKE-10-E2E-REPORT.md) -- main thread model, NSApp.stop() pattern (HIGH confidence)
- [Spike 15: JSONL Tailing Report](~/tmp/subtitle-spikes-7aqa/15-jsonl-tailing/SPIKE-15-JSONL-TAILING-REPORT.md) -- DispatchSource patterns (HIGH confidence)
- [Spike 16: ONNX Timestamps Report](~/tmp/subtitle-spikes-7aqa/16-onnx-timestamps-swift/SPIKE-16-ONNX-TIMESTAMPS-REPORT.md) -- phonemization gap, sherpa-onnx patch (HIGH confidence)
- [Spike 06: Feature Parity Audit](~/tmp/subtitle-spikes-7aqa/SPIKE-06-FEATURE-PARITY.md) -- 4,500 lines TS, feature catalog (HIGH confidence)
- [Problematic Swift Concurrency Patterns](https://www.massicotte.org/problematic-patterns/) -- thread pool exhaustion (MEDIUM confidence, WebSearch)
- [Swift Concurrency Challenges](https://twocentstudios.com/2025/08/12/3-swift-concurrency-challenges-from-the-last-2-weeks/) -- @MainActor misconceptions (MEDIUM confidence, WebSearch)
- [Apple: Designing Daemons and Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/DesigningDaemons.html) -- Agent vs Daemon (HIGH confidence, official)
- [sherpa-onnx memory leak issue #974](https://github.com/k2-fsa/sherpa-onnx/issues/974) -- memory growth in long-running processes (LOW confidence, single issue report)
