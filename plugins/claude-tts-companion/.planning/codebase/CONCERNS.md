# Codebase Concerns

**Analysis Date:** 2026-04-02

## Tech Debt

**Hardcoded sherpa-onnx Library Path:**

- Issue: `Package.swift` contains absolute path `/Users/terryli/fork-tools/sherpa-onnx/build-swift-macos/install/lib` for linking sherpa-onnx static libraries. This breaks on other machines and prevents reproducible builds.
- Files: `Package.swift` (line 32)
- Impact: Prevents collaborative development and CI/CD integration. Requires each developer to rebuild sherpa-onnx at the exact same path or manually edit Package.swift.
- Fix approach: Extract the path to an environment variable (`SHERPA_ONNX_LIB_PATH`) or use a build settings file (`build-settings.swift`) that reads from a local config, allowing per-machine customization without code edits.

**AudioStreamPlayer Inert After afplay Migration:**

- Issue: `AudioStreamPlayer.swift` is initialized and partially maintained (has health check stubs, HAL listener code) but never used—afplay subprocess is the sole playback backend. The class is marked as "inert" but retains 180+ lines of unused code for engine start/stop, buffer scheduling, health checks, and audio device monitoring.
- Files: `AudioStreamPlayer.swift`, `PlaybackManager.swift` (lines 41, 55)
- Impact: Increases binary size, maintenance burden, and complexity. Dead code path creates confusion about what's actually driving playback. If someone tries to use AudioStreamPlayer in the future (thinking it's active), it won't work.
- Fix approach: Delete AudioStreamPlayer entirely or move to a separate feature-gated module. Keep only afplay-based playback in the production binary.

**Weak Self Capture in Closures Without Null Checks:**

- Issue: Multiple locations capture `[weak self]` in closures but fail to check `guard let self` before using, or use force-unwrap patterns. Patterns found in:
  - `TTSPipelineCoordinator.swift` (memory pressure handler, recovery work items)
  - `TTSQueue.swift` (playback continuation boxes, subtitle panel updates)
  - `SubtitleSyncDriver.swift` (timer callbacks, chunk completion handlers)
- Files: `TTSPipelineCoordinator.swift` (lines 65, 77), `TTSQueue.swift` (lines 404-406, 458-459), `SubtitleSyncDriver.swift` (multiple timer callbacks)
- Impact: Silent failures when callbacks fire after object deallocation. No error logs; playback may stall or subtitles may freeze mid-display.
- Fix approach: Establish a pattern: all weak captures must have explicit null checks. Add Xcode warning suppression comments only when intentional (e.g., "weak self allowed to become nil here"). Use SwiftLint to enforce via `weak_delegate` rule.

**Floating Point Arithmetic for Onset Padding:**

- Issue: `TTSPipelineCoordinator.swift` (lines 199-204, 358-363, 417-427) estimates missing word onsets using floating-point division and accumulation:

  ```swift
  let avgGap: TimeInterval = existingOnsets.count >= 2
      ? (existingOnsets.last! - existingOnsets.first!) / Double(existingOnsets.count - 1)
      : 0.4
  ```

  This approximation drifts visually on multi-second audio when Kokoro drops trailing word timings. Drift compounds across multiple chunk merges.

- Files: `TTSPipelineCoordinator.swift` (lines 194-207, 354-365, 415-428)
- Impact: Karaoke highlighting desynchronizes on longer utterances. Word advance timing creeps backward or forward as buffer length increases. Visible on 10+ word sentences.
- Fix approach: Instead of extrapolating, request Kokoro to always return a complete word timing array. If incomplete, treat as synthesis failure and retry rather than guessing onsets. Or use a stability anchor: pin the last known onset to the audio duration, then fill gaps backward.

**File Descriptor Leaks in JSONLTailer:**

- Issue: `JSONLTailer.swift` opens a file descriptor via `open(filePath, O_EVTONLY)` (line 42) and closes it only via the DispatchSource cancel handler. If the DispatchSource is never started (`resume()` not called), the file descriptor leaks. Similarly, if `stop()` is called after deallocation, `source?.cancel()` may not execute immediately.
- Files: `JSONLTailer.swift` (lines 42-67)
- Impact: Each notification file tailed without being started leaks a file descriptor. Over time, the process hits the per-process FD limit (4096 on macOS), causing cascade failures in subsequent file operations.
- Fix approach: Ensure `start()` is always called after `init()`. Add a guard in `readNewLines()` to fail fast if source is nil. Store the file descriptor separately and close it in a deinit if source was never started.

**Untested Error Paths in MiniMax Client:**

- Issue: `MiniMaxClient.swift` has multiple error branches (missing API key, circuit breaker open, network timeout, malformed JSON response) but none are covered by unit tests. Testing focuses on happy path only.
- Files: `MiniMaxClient.swift` (lines 51-157)
- Impact: Silent failures when API is unavailable. Circuit breaker state isn't validated. Timeout behavior under network contention is unknown.
- Fix approach: Add integration tests mocking URLSession with various failure scenarios (network error, 500 response, truncated JSON, empty content blocks). Verify circuit breaker opens after 3 consecutive failures.

## Known Bugs

**Memory Pressure Cooldown Not Reset on New Event:**

- Symptoms: If system memory pressure clears for 55 seconds, then re-triggers at second 56, the cooldown counter doesn't reset—flag stays active until second 120 (60s from the original event). Multiple pressure spikes in quick succession compound.
- Files: `TTSPipelineCoordinator.swift` (lines 76-82)
- Trigger: Sustained memory pressure with intermittent brief windows of normal memory, then pressure returns.
- Workaround: Manually restart the service to clear the flag.
- Fix approach: On new memory pressure event, cancel the pending recovery work item BEFORE scheduling a new one. Current code cancels it correctly, but the timestamp (`disabledUntil`) is set relative to `Date()` at the time of event, creating overlapping windows.

**Onset Count Mismatch Fallback Not Logged Clearly:**

- Symptoms: When Kokoro word onset count doesn't match word count, the code silently falls back to duration-derived onsets with a warning log. But the warning appears alongside normal synthesis logs, making it hard to correlate with visible karaoke desync.
- Files: `SubtitleSyncDriver.swift` (lines 128-132)
- Trigger: Kokoro omits the last word timing in the duration model output.
- Workaround: Grep logs for "falling back to duration-derived".
- Fix approach: Log both the word count and onset count clearly: `"Onset count (\(nativeOnsets.count)) != word count (\(totalWords)) -- falling back to duration-derived onsets"`. Add telemetry to track frequency of this fallback.

**Process Spawn Race in AfplayPlayer:**

- Symptoms: On rapid successive TTS requests, afplay processes spawned by `posix_spawn` may still be running when `stop()` is called. The `waitpid()` thread blocks indefinitely if the process was never spawned successfully (PID is 0), hanging the callback.
- Files: `AfplayPlayer.swift` (lines 145-172)
- Trigger: Call `play()` immediately after `stop()` before previous afplay finishes cleanup.
- Workaround: Sleep 0.5s between stop and play in caller.
- Fix approach: Check `afplayPID != 0` before entering waitpid. Use a timeout in the waitpid thread (e.g., via `select` or `dispatch_after` fallback) so the monitor thread doesn't block forever.

**Unrecoverable Telegram Bot Crashes Don't Auto-Restart:**

- Symptoms: If the Telegram bot task crashes (e.g., network error, JSON decode panic), the error is logged in `CompanionApp.start()` (line 134) and the bot remains disabled for the rest of the service lifetime.
- Files: `CompanionApp.swift` (lines 129-136), `TelegramBot.swift`
- Trigger: Network interruption or protocol change in Telegram Bot API.
- Workaround: Restart the service manually via `make restart`.
- Fix approach: Wrap bot start in a retry loop with exponential backoff. Or use a supervision actor pattern where the bot task is monitored and restarted on crash.

## Security Considerations

**API Keys Not Rotated Automatically:**

- Risk: MiniMax API key and Telegram bot token are stored in environment variables and read once at startup. No rotation mechanism exists. If a key is compromised, the only recovery is manual environment update + service restart.
- Files: `Config.swift` (reads from environment)
- Current mitigation: Keys are stored in launchd plist as environment variables, not in code or shell history.
- Recommendations:
  1. Support hot-reloading of API keys from a secure config file (e.g., 1Password, macOS Keychain) with periodic refresh.
  2. Log all MiniMax API calls with a hash of the key (not the key itself) for audit trails.
  3. Add circuit breaker-triggered alerts if MiniMax API key fails (401 Unauthorized likely indicates compromise).

**No Rate Limiting on HTTP Control API:**

- Risk: `/tts/speak` and `/tts/stop` endpoints accept unlimited concurrent requests. A local attacker could DoS the service by flooding requests.
- Files: `HTTPControlServer.swift`
- Current mitigation: Queue depth is limited to 3 automated requests; user-initiated requests preempt.
- Recommendations:
  1. Add per-IP rate limiting (token bucket, sliding window).
  2. Require authentication token for control endpoints (Telegram bot token or separate API key).
  3. Log all requests with timestamp and payload size for forensic review.

**Subprocess Argument Injection in afplay Spawn:**

- Risk: `AfplayPlayer.swift` passes WAV file paths directly to `posix_spawn` via argv. If a path contains spaces or special characters, the argument parsing could be exploited (though unlikely with UUID-based filenames).
- Files: `AfplayPlayer.swift` (lines 113-115)
- Current mitigation: Filenames are generated deterministically with UUID and sanitized label (only alphanumerics + underscore).
- Recommendations:
  1. Use quote escaping or array-based argument passing (already done correctly with argv array).
  2. Add assertions to validate WAV path doesn't contain shell metacharacters before spawning.

**No Input Validation on TTS Text:**

- Risk: Text passed to `TTSEngine.synthesizeStreamingAutoRoute()` is not validated for size, encoding, or content. A malicious request could send 1MB of text, causing Python server to consume excessive memory or time out.
- Files: `TTSEngine.swift`, `TTSQueue.swift`
- Current mitigation: Python server has its own request timeout (30s).
- Recommendations:
  1. Enforce maximum text length (e.g., 5000 chars) at the HTTP layer before queuing.
  2. Add length telemetry to identify if users are exploiting this.

## Performance Bottlenecks

**Memory Pressure Check Only Once Per Synthesis:**

- Problem: `TTSQueue.executeWorkItem()` (line 266) checks `shouldUseSubtitleOnly` once at the start of synthesis. If the system suddenly runs out of memory mid-synthesis, the synthesize call will continue and consume memory, only to be discarded when the pipeline can't allocate subtitle buffer space.
- Files: `TTSQueue.swift` (line 266), `TTSPipelineCoordinator.swift` (lines 47)
- Cause: Memory pressure is event-driven; checking once assumes stable conditions throughout synthesis.
- Improvement path: Poll memory pressure periodically during synthesis (every 5 sentences). If it rises to .critical, cancel synthesis immediately via the cancellation token.

**Karaoke Timer Polling at 60Hz Regardless of Audio Duration:**

- Problem: `SubtitleSyncDriver` runs a 60Hz DispatchSourceTimer for the entire playback duration, even for 1-second audio clips. This wastes CPU and thermal budget on short utterances.
- Files: `SubtitleSyncDriver.swift` (timer setup code)
- Cause: Fixed 60Hz interval chosen for fluidity; doesn't adapt to content length.
- Improvement path: Detect audio duration upfront. For clips < 2s, use 30Hz. For > 30s, consider adaptive polling (start at 60Hz, drop to 30Hz after first 10s if no rapid word transitions detected).

**No Batching of Onsets Calculation Across Chunks:**

- Problem: When merging multiple chunks in paragraph mode (`TTSPipelineCoordinator.startBatchPipeline()`, lines 223-269), each chunk recalculates onset padding separately. This is redundant—could accumulate onsets once.
- Files: `TTSPipelineCoordinator.swift` (lines 223-269)
- Cause: Each chunk added separately; onset padding happens at add time, not at finalize time.
- Improvement path: Defer onset padding until the batch is complete, then compute all onsets in one pass.

## Fragile Areas

**SubtitleSyncDriver Dual-Mode Complexity:**

- Files: `SubtitleSyncDriver.swift` (entire 600+ line file)
- Why fragile: Supports both single-shot (AVAudioPlayer) and streaming (AudioStreamPlayer/afplay) modes with overlapping state. ~30% of the code is legacy single-shot mode that's rarely used now. Streaming mode has 15+ private state variables tracking chunk indices, offsets, completion flags.
- Safe modification:
  1. Add explicit mode guards (`if !isStreamingMode { ... }`) at the start of every method that differs between modes.
  2. Write integration tests for both modes (currently only streaming tested).
  3. Consider extracting each mode into a separate class with a common protocol.
- Test coverage: `StreamingPipelineTests.swift` covers streaming; single-shot mode untested.

**TTSEngine Actor Isolation Boundary:**

- Files: `TTSEngine.swift` (entire actor)
- Why fragile: Actor-isolated synthesis methods are called from both TTSQueue (actor) and HTTP server (non-actor context). Wrong isolation context can cause data races or deadlocks.
- Safe modification:
  1. Always wrap calls to TTSEngine in `await` or `Task { await ... }`.
  2. Never call synchronous methods on TTSEngine (all should be `async`).
  3. Add assertions to catch isolation violations at development time.
- Test coverage: No explicit actor isolation tests.

**File Descriptor Management in JSONLTailer + NotificationWatcher:**

- Files: `JSONLTailer.swift`, `NotificationWatcher.swift`
- Why fragile: Both open file descriptors and rely on DispatchSource for lifecycle. If DispatchSource is garbage collected or never resumed, descriptors leak.
- Safe modification:
  1. Add explicit ownership documentation: "JSONLTailer owns the FD lifetime until stop() is called."
  2. Implement a deinit that warns if source != nil (source should be nil after stop).
  3. Add tests that verify FD count after start/stop cycles.
- Test coverage: No resource cleanup tests.

**Paragraph Budget Bisection Logic Untested:**

- Files: `PronunciationProcessor.swift` (`enforceParargraphBudget` method), `TTSQueue.swift` (line 304)
- Why fragile: Splits large paragraphs into smaller segments with "isContinuation" and "isUnfinished" flags to add visual zigzag borders. Logic has 3 code paths (no split, single split, recursive split) that aren't covered by tests.
- Safe modification:
  1. Add unit tests for each edge case: text under budget, text == budget, text > budget by 1 char, text >> budget (10x).
  2. Verify that re-joining segments reconstructs the original text exactly.
  3. Validate that continuation flags are set correctly at segment boundaries.
- Test coverage: No unit tests for bisection logic.

## Scaling Limits

**Queue Depth Fixed at 3:**

- Current capacity: `maxAutomatedQueueDepth = 3` (TTSQueue.swift, line 103)
- Limit: If more than 3 automated TTS requests arrive while user-initiated request is in progress, requests 4+ are silently dropped (not queued, not rejected with a 503).
- Scaling path:
  1. Make queue depth configurable via HTTP `PATCH /config` endpoint.
  2. Add metrics to track dropped request rate; alert if it exceeds 10% of incoming requests.
  3. Consider a priority queue instead of FIFO (e.g., prioritize shorter texts over longer ones).

**Model Load Time Adds Latency to First CJK Synthesis:**

- Current capacity: ~560ms model load time on first CJK request
- Limit: If CJK request arrives 30+ seconds after last CJK synthesis, model is unloaded. Next request blocks for 560ms before synthesis starts.
- Scaling path:
  1. Pre-warm the CJK model at service startup (measure model load time separately from synthesis latency).
  2. Increase idle unload threshold from 30s to 5 minutes (trade idle RSS for latency).
  3. Use a background keep-alive task if CJK requests are frequent.

**No Backpressure on Subtitle Buffer Growth:**

- Current capacity: Subtitle text accumulated in `SubtitleSyncDriver.pages` with no size limit
- Limit: A single synthesis with 1000+ words will allocate proportional memory for word onset timings and page structures. No aggregation or overflow handling.
- Scaling path:
  1. Enforce a max subtitle length (e.g., 2000 words) at HTTP layer.
  2. Add memory telemetry: log total bytes allocated for current subtitle on each finalize.
  3. Implement a ring buffer if subtitle history grows too large.

## Dependencies at Risk

**swift-telegram-sdk v4.5.0:**

- Risk: Last commit was ~2024. Library is actively used but relatively niche. If upstream abandons it, no direct Swift alternative exists for Telegram Bot API.
- Impact: If library has a critical bug or Telegram API changes, migration effort is 3-4 weeks (new library or custom HTTP client).
- Migration plan: Fallback is to implement a minimal Telegram polling client directly via URLSession (spike 04 showed this is ~200 LOC). Pre-spike the implementation now so it's ready if needed.

**sherpa-onnx v1.12.33 Static Build:**

- Risk: Requires custom C++ build at `/Users/terryli/fork-tools/sherpa-onnx/build-swift-macos/install/lib`. If this build breaks or is lost, no prebuilt arm64 static libs are available from upstream (they provide dylibs, not static libs).
- Impact: Rebuilding from source takes 20+ minutes and requires a fork to be maintained.
- Migration plan:
  1. Add a build script (`scripts/build-sherpa-onnx.sh`) that automates the fork checkout and static build.
  2. Cache the built libraries in a separate repo (e.g., `terrylica/sherpa-onnx-macos-builds`) for quick CI/CD access.
  3. Document the exact CMake flags needed to reproduce the build.

**FlyingFox v0.26.2:**

- Risk: Lightweight HTTP server library with <100 stars. If maintainer stops updates, bugs in async/await handling could block critical fixes.
- Impact: Migrating to a different HTTP server (Vapor, Hummingbird) would require rewriting all endpoints and request handling.
- Mitigation: FlyingFox code is minimal and audited. If it stops being maintained, the risk of a critical bug is low. Current HTTP API is simple (5 endpoints), so migration effort would be ~1 week if needed.

## Missing Critical Features

**No Persistent Queue Across Restarts:**

- Problem: If the service crashes or is restarted, all queued TTS requests are lost. Users don't know their request was dropped.
- Blocks: Reliable TTS delivery for long-running synthesis batches.
- Workaround: Callers must retry manually.
- Fix approach:
  1. Write queued requests to a persistent file (JSONL format, one request per line).
  2. On startup, replay the persistent queue.
  3. Remove entries from the file as synthesis completes.

**No Metrics or Observability Dashboard:**

- Problem: No way to see queue depth, latency, memory usage, or synthesis success rate over time. Debugging requires manual log grepping.
- Blocks: Production monitoring and performance tuning.
- Workaround: Parse stderr logs manually.
- Fix approach:
  1. Add a metrics exporter (Prometheus `/metrics` endpoint or CloudWatch integration).
  2. Track: queue depth, latency percentiles (p50, p95, p99), bytes synthesized, memory peaks, error counts by type.
  3. Build a Grafana dashboard from metrics.

**No Config Reload Without Restart:**

- Problem: Changing settings (subtitle position, font size, TTS speed, API keys) requires a service restart, which stops playback.
- Blocks: Zero-downtime configuration updates.
- Workaround: Manual restart via `make restart`.
- Fix approach:
  1. Add HTTP `PATCH /config` endpoint that validates and applies new settings.
  2. For critical settings (API keys), trigger graceful drain of queued requests before applying change.
  3. Log all config changes for audit purposes.

## Test Coverage Gaps

**No Integration Tests for TTS End-to-End:**

- What's not tested: Full synthesis flow from HTTP `/tts/speak` request through completion callback. Streaming multiline text. Word timing accuracy.
- Files: `TTSQueue.swift`, `TTSEngine.swift`, `SubtitleSyncDriver.swift`
- Risk: A subtle bug in audio buffering or callback ordering could go unnoticed in unit tests.
- Priority: HIGH — this is the core functionality.

**No Tests for Memory Pressure Handling:**

- What's not tested: Memory pressure event firing and recovery. Whether memory-constrained subtitle-only fallback activates correctly. Whether recovery cooldown resets properly.
- Files: `TTSPipelineCoordinator.swift` (lines 60-88)
- Risk: Behavior on memory-constrained systems is untested. May crash or hang under sustained memory pressure.
- Priority: MEDIUM — edge case, but critical for reliability on older Macs.

**No Tests for Audio Route Changes:**

- What's not tested: AVAudioEngine responding to default output device changes (e.g., headphones connected/disconnected). AudioStreamPlayer rebuild logic. Recovery callback firing.
- Files: `AudioStreamPlayer.swift` (audio route change handling)
- Risk: Playback may stall if user switches audio devices during synthesis.
- Priority: MEDIUM — common real-world scenario.

**No Crash Tests for subprocess Cleanup:**

- What's not tested: What happens if afplay process dies unexpectedly or is killed. Whether cleanup callbacks fire correctly. Whether the waitpid thread exits cleanly.
- Files: `AfplayPlayer.swift` (lines 150-172)
- Risk: Zombie processes or hung wait threads if afplay crashes.
- Priority: MEDIUM — robustness under failure.

**No Tests for Notification File Parsing:**

- What's not tested: JSONLTailer behavior with truncated JSONL, large files, rapid writes, or missing newlines at EOF.
- Files: `JSONLTailer.swift` (readNewLines logic)
- Risk: Notifications may be lost or duplicated if file parsing has edge case bugs.
- Priority: MEDIUM — data loss risk.

---

_Concerns audit: 2026-04-02_
