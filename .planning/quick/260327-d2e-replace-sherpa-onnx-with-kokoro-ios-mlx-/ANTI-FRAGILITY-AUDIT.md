# Anti-Fragility Audit: claude-tts-companion TTS Pipeline

**Date**: 2026-03-27
**Auditor**: Deep code review + web research
**Scope**: TTSEngine, SubtitleSyncDriver, TelegramBot, SubtitlePanel, HTTPControlServer, main.swift, all debug sessions

---

## Part 1: Audit of Recent Fixes

### 1.1 MLX Metal Resource Exhaustion (TTSEngine.swift)

**Fix**: `Memory.clearCache()` called at the top of `synthesizeStreaming()` (line 335).

**Verdict**: PARTIALLY CORRECT -- needs strengthening.

**Findings**:

- `Memory.clearCache()` releases cached Metal buffers from the MLX buffer pool. This is the right function to call between synthesis sessions. It frees buffers that MLX has retained in its internal cache for reuse but are no longer needed.

- **Gap 1: No `GPU.synchronize()` call.** `Memory.clearCache()` only releases _cached_ (idle) buffers. If there are in-flight Metal command buffers still executing from the previous session, their resources cannot be freed until they complete. A `GPU.synchronize()` call _before_ `clearCache()` would ensure all pending Metal commands finish, making their buffers eligible for cache release. Without it, back-to-back sessions with overlapping Metal work could still accumulate resources.

  ```swift
  // Recommended pattern:
  GPU.synchronize()      // Wait for in-flight Metal commands to complete
  Memory.clearCache()    // Release all cached Metal buffers
  ```

- **Gap 2: No `GPU.set(cacheLimit:)` or `GPU.set(memoryLimit:)`.** The MLX framework supports explicit memory limits via `GPU.set(memoryLimit:relaxed:)` and `GPU.set(cacheLimit:)`. Setting a cache limit (e.g., 512MB) would provide a hard cap that prevents unbounded cache growth even if `clearCache()` is called too late. This is a defense-in-depth measure.

- **Gap 3: No per-chunk cleanup.** `clearCache()` is called once at the top of `synthesizeStreaming()`, but a 15-chunk synthesis session accumulates Metal resources across all chunks. If each chunk's `generateAudio()` creates intermediate tensors that aren't freed, resources grow linearly. Calling `clearCache()` every N chunks (e.g., every 5) would bound peak usage.

- **Gap 4: Individual tensor disposal.** The `audio` and `tokenArray` arrays returned from `generateAudio()` are Swift arrays (`[Float]`, `[MToken]?`), not MLX tensors, so they are managed by ARC. However, intermediate MLXArray tensors created _inside_ kokoro-ios during generation may persist in the MLX evaluator graph. `eval()` forces evaluation, and subsequent `clearCache()` can then free the backing buffers. The current code does not explicitly `eval()` intermediate results.

- **Web research confirms**: The `[metal::malloc] Resource limit (499000) exceeded` error is a known issue across MLX projects (mlx-lm #831, lmstudio mlx-engine #264). The community-recommended fix is `mx.metal.clear_cache()` (Python) / `Memory.clearCache()` (Swift) between inference calls, plus reducing context length. Some users report that only a process restart fully clears the metal allocator state.

**Risk**: P0 -- process crash on sustained load (15+ chunks over multiple sessions).

### 1.2 SubtitleSyncDriver Lifecycle (SubtitleSyncDriver.swift)

**Fix**: `stop()` cancels timer, stops stream players, clears pre-buffered players, fires `onStreamingComplete` if not already finished.

**Verdict**: MOSTLY CORRECT -- minor issues remain.

**Findings**:

- **Timer invalidation is correct.** `timer?.cancel()` on a `DispatchSourceTimer` is the proper way to stop it. The `deinit` also calls `timer?.cancel()` as a safety net. Good.

- **Retain cycle analysis**: The timer's `setEventHandler` captures `[weak self]` (line 408). This is correct -- no retain cycle. The `onStreamingComplete` closure captures `[weak self]` in the TelegramBot (line 276). Also correct.

- **Gap 1: `stop()` during chunk transition is racy.** If `stop()` is called from the main thread while `tickStreaming()` is about to call `advanceToPrebuilt()`, the `tickStreaming()` method reads `streamPlayer`, `prebufferedChunkIndex`, and `nextStreamPlayer` -- all of which `stop()` mutates. Since both run on the main queue (timer dispatches to `.main`, and `stop()` is called from main), there is no actual data race -- GCD serializes them. However, `stop()` sets `streamPlayer` to stopped state but doesn't nil it. `tickStreaming()` checks `!currentPlayer.isPlaying` which would then be true (stopped), triggering `playStreamChunk(at: nextIndex)`. The `didFinish` guard at line 418 prevents this. **This is safe.**

- **Gap 2: Pre-buffered player cleanup.** `stop()` calls `nextStreamPlayer?.stop()` and nils it. But the _current_ `streamPlayer` is stopped but not nilled. After `stop()`, the driver's state has a stopped player reference. If any code path checked `streamPlayer != nil` as a "playing" indicator, it would be wrong. Currently `tickStreaming()` checks `isPlaying`, so this is safe, but fragile.

- **Gap 3: WAV file cleanup for pre-buffered players.** When `stop()` cancels a pre-buffered player via `nextStreamPlayer?.stop()`, the `PlaybackDelegate.audioPlayerDidFinishPlaying()` does NOT fire (Apple docs: `stop()` does not trigger delegate callbacks). This means the WAV file for the pre-buffered chunk is never cleaned up. Over time, orphaned WAV files accumulate in `/tmp/`.

  Similarly, when `stop()` stops `streamPlayer`, the delegate doesn't fire, leaving the current chunk's WAV orphaned too.

- **Gap 4: `onStreamingComplete` double-fire potential.** In `stop()` (line 251): if `!didFinish`, it fires `onStreamingComplete?()` and nils it. In `finishPlayback()` (line 532-539): it sets `didFinish = true`, calls `stop()`, then fires `onStreamingComplete?()`. Since `stop()` fires the callback when `!didFinish` and `finishPlayback()` sets `didFinish = true` BEFORE calling `stop()`, the guard in `stop()` correctly prevents double-fire. **This is safe.**

**Risk**: P2 -- WAV file leak in /tmp/ (cosmetic, cleaned on reboot).

### 1.3 Streaming Pipeline (TelegramBot.swift)

**Fix**: `isStreamingInProgress` flag guards against concurrent TTS dispatch; previous SyncDriver cancelled immediately in `dispatchStreamingTTS()`.

**Verdict**: CORRECT -- well-designed with proper edge case handling.

**Findings**:

- **Flag lifecycle is sound.** Set `true` at line 236 (start of `dispatchStreamingTTS`). Cleared via `onStreamingComplete` callback in SyncDriver (line 277). Zero-chunk fallback at line 310 also clears it. The `stop()` path in SyncDriver also fires the callback (line 251-254).

- **Mid-stream synthesis failure.** If `generateAudio()` throws for one chunk (line 356-360), the `continue` statement skips that chunk. Subsequent chunks still synthesize. `onAllComplete` still fires. The flag is cleared properly. **Correct.**

- **SIGTERM during streaming.** The SIGTERM handler in main.swift (line 211) calls `notificationWatcher.stop()` and `bot.stop()` but does NOT explicitly stop the TTS engine or SyncDriver. However, `app.stop(nil)` terminates the run loop, and process exit cleans up everything. The `isStreamingInProgress` flag becomes irrelevant after process exit. **Acceptable** -- no persistent state is corrupted.

- **Back-pressure (chunks faster than playback).** Chunks are synthesized on the serial TTS queue and delivered to the main queue via `DispatchQueue.main.async`. If synthesis is faster than playback (RTF < 1.0, which is unlikely for MLX on this hardware at RTF ~2.0), chunks queue up in `streamChunks` array. The SyncDriver plays them sequentially. No back-pressure mechanism exists, but memory usage is bounded by chunk count \* WAV size (~200KB per chunk). For a 15-chunk session, that's ~3MB. **Acceptable.**

- **Gap 1: Race between `isStreamingInProgress` check and set.** `dispatchTTS()` checks the flag (line 206) and `dispatchStreamingTTS()` sets it (line 236). Both run on the calling context (async from notification handler). If two notifications arrive nearly simultaneously, both could pass the guard before either sets the flag. The `NotificationProcessor` mutex (line 106) prevents this in practice -- only one notification processes at a time. **Safe due to external serialization, but the flag itself is not thread-safe** (it's accessed from both the main thread and notification handler thread without synchronization).

- **Gap 2: Old SyncDriver stop is async.** At lines 248-252, the old `syncDriver` is stopped via `DispatchQueue.main.async`. The synthesis queue starts concurrently. If the first chunk synthesizes extremely fast (unlikely), the `onChunkReady` callback could dispatch to main before the `driverToStop?.stop()` block executes. Since both are `DispatchQueue.main.async`, they execute in FIFO order, so `stop()` runs first. **Safe.**

**Risk**: P1 -- `isStreamingInProgress` is not formally thread-safe (relies on external serialization).

### 1.4 AVAudioPlayer Lifecycle (TTSEngine.swift)

**Fix**: `PlaybackDelegate` retained by `self.playbackDelegate` property; WAV cleanup in `audioPlayerDidFinishPlaying()`.

**Verdict**: CORRECT with known limitations.

**Findings**:

- **Delegate deallocation prevention.** `AVAudioPlayer.delegate` is a weak reference. The engine holds a strong reference via `self.playbackDelegate`. When `stopPlayback()` nils the delegate, the player's delegate becomes nil (weak ref zeroed). This is intentional -- after stop, no callbacks are needed. **Correct.**

- **WAV file cleanup timing.** The delegate deletes the WAV in `audioPlayerDidFinishPlaying()`. The WAV is read from disk by AVAudioPlayer at `prepareToPlay()` time (buffered into memory). Deleting the file after playback completes is safe -- the player has already read all data. **Correct.**

- **Gap 1: `prepareToPlay()` silent failure.** `player.prepareToPlay()` returns `Bool` but the code ignores the return value (line 214, 504). If it fails (e.g., corrupted WAV, insufficient memory), `play()` still proceeds. The documentation states that `play()` implicitly calls `prepareToPlay()` if not already called, but if `prepareToPlay()` explicitly failed, `play()` may also fail. The code doesn't check `player.play()` return value either (line 215). On failure, `play()` returns `false` silently.

- **Gap 2: Multiple simultaneous players.** `stopPlayback()` only stops `self.audioPlayer` (the single stored reference). In streaming mode, the SyncDriver manages its own `streamPlayer` and `nextStreamPlayer` independently. If `stopPlayback()` is called, it only stops the engine's `audioPlayer`, not the SyncDriver's players. However, `dispatchStreamingTTS()` calls both `ttsEngine.stopPlayback()` AND `driverToStop?.stop()`, covering both. **Safe in practice.**

- **Gap 3: Warm-up player is not retained.** In `warmUpAudioHardware()` (line 753), the silent `player` is a local variable. After the function returns, ARC may deallocate it before playback completes (it's a 0.1s silent buffer). The `DispatchQueue.global().asyncAfter(deadline: .now() + 0.5)` cleanup runs after 0.5s, but if the player is deallocated earlier, the WAV cleanup block would try to delete a file that might still exist. More critically, the warm-up player has no delegate and its `delegate` property is nil, so `audioPlayerDidFinishPlaying` never fires. The warm-up WAV file is cleaned up by the asyncAfter block, but if that block runs before the player finishes (player was deallocated early), the file may or may not exist. **Minor leak potential.**

**Risk**: P2 -- silent `prepareToPlay()` failure, warm-up player lifetime.

---

## Part 2: Edge Case Spike Test Designs

### 2.1 Rapid-Fire Notifications (5 within 10 seconds)

**Expected behavior**: NotificationProcessor mutex serializes processing; rate limiter enforces 5s minimum interval. First notification processes immediately, second queues, third through fifth are coalesced into `pendingFilePath` (only last survives).

**Fragility**: The `pendingFilePath` only stores ONE path. If 5 notifications arrive, notifications 2-4 are silently dropped (replaced by subsequent pending). Only #1 and #5 actually process. **Design decision, but users may miss intermediate sessions.**

**Test**: Rapidly create 5 `.json` files in notification dir with 1s intervals. Verify exactly 2 process (first + last).

### 2.2 Very Short Sentence ("Hi." -- 2 chars)

**Expected behavior**: `splitIntoSentences("Hi.")` returns `["Hi."]`. `generateAudio()` produces a very short WAV (~0.2s). SubtitleChunker creates 1 page with 1 word. SyncDriver plays for ~0.2s.

**Fragility**: The trailing silence padding (100ms) is nearly as long as the audio. `audioDuration` = 0.2s but WAV duration = 0.3s. Karaoke timing based on `audioDuration` finishes at 0.2s, but audio plays until 0.3s. The 100ms silence at the end is fine. The word onset computation with 1 word is trivial.

**Risk**: Low. Character-weighted timing for 1 word degenerates to `[audioDuration]`. Works correctly.

### 2.3 Very Long Text (10,000 chars)

**Expected behavior**: `splitIntoSentences()` produces ~50-80 sentences. Each synthesizes sequentially on the serial queue. Memory pressure: each chunk produces a WAV (~200KB). At peak, 80 WAVs \* 200KB = 16MB in temp files plus MLX model memory (~561MB peak).

**Fragility**:

- **Metal resource exhaustion.** `Memory.clearCache()` is called once at the start. By chunk 60+, accumulated Metal buffers could hit the 499000 limit again. **HIGH RISK.**
- **Temp file accumulation.** WAV files are cleaned up by PlaybackDelegate after each chunk finishes. Files for already-played chunks should be cleaned. Only pre-buffered (next) and currently playing chunks are live. **Likely safe.**
- **NSAttributedString allocation.** 60Hz timer creates new NSAttributedString every tick for highlight updates. For short-lived objects, ARC handles this. **Low risk.**

### 2.4 Empty Text (MiniMax returns empty summary)

**Expected behavior**: In `sendSessionNotification()`, the tail brief check is `!tail.narrative.isEmpty` (line 159). Empty narrative skips TTS dispatch entirely. For arc summary, `message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` triggers the fallback message. **Correct handling.**

**Fragility**: If MiniMax returns a whitespace-only string (e.g., "\n\n"), `isEmpty` is false but `trimmingCharacters` catches it for arc. For TTS, `"\n\n"` would pass the non-empty check and dispatch to TTS. `splitIntoSentences()` trims whitespace first, returning `[]`. `synthesizeStreaming()` with 0 sentences calls `onAllComplete()` immediately. The zero-chunk fallback in `onAllComplete` (line 308-311) clears `isStreamingInProgress`. **Safe.**

### 2.5 Unicode Edge Cases (CJK, Emoji, RTL)

**Fragility**:

- **CJK text**: `LanguageDetector.detect()` correctly identifies CJK but logs a warning that kokoro-ios is English-only. CJK phonemes will produce garbage audio. No crash, just bad output.
- **Emoji**: NLTokenizer may split or merge emoji. `extractTimingsFromTokens()` might produce different token counts. `alignOnsetsToWords()` handles count mismatches via character-offset tracking. `stripPunctuation()` uses `CharacterSet.punctuationCharacters.union(.symbols)` which includes emoji. Emoji words become empty after stripping, hitting the empty-word interpolation path. **Should work but timing may be off for emoji-heavy text.**
- **RTL**: NSAttributedString handles RTL via Unicode bidi algorithm. The subtitle panel uses `.center` alignment, so RTL text would render correctly. Word splitting by whitespace works for Arabic/Hebrew. **Likely correct.**

### 2.6 Network Failure During MiniMax Summary Generation

**Expected behavior**: `MiniMaxClient` has a `CircuitBreaker` (3 failures, 300s cooldown). URLSession timeout (default 60s) triggers a failure. After 3 failures, circuit opens and all summary calls return `SummaryError.circuitBreakerOpen`. `SummaryEngine` returns fallback text.

**Fragility**: The `async let` concurrent summary generation (line 75-76 in TelegramBot) means both arc and tail summaries run simultaneously. If MiniMax is down, both block for up to 60s each, but since they're concurrent, total wait is ~60s. After 3 notifications with MiniMax down, circuit breaker opens and subsequent calls fail-fast. **Correct.**

**Gap**: No explicit timeout on the MiniMax HTTP call (relies on URLSession default). A stuck TCP connection could block indefinitely. Adding an explicit `timeoutIntervalForRequest` would harden this.

### 2.7 Audio Hardware Disappears (Bluetooth Disconnect Mid-Playback)

**Expected behavior**: AVAudioPlayer continues playing to the now-disconnected output. macOS typically routes audio to the built-in speaker when Bluetooth disconnects. AVAudioPlayer may fire `audioPlayerDecodeErrorDidOccur()` or continue playing to the new default output.

**Fragility**:

- No `AVAudioSession.routeChangeNotification` observer (macOS uses `AudioObjectAddPropertyListener` for route changes, not the iOS AVAudioSession API). If the output device disappears entirely (USB audio interface unplugged), the player may error or silently produce no output.
- The `audioPlayerDecodeErrorDidOccur` handler (line 890) cleans up the WAV and fires completion, which is correct for error recovery.
- **No automatic retry or re-route detection.** The subtitle karaoke continues advancing based on the timer regardless of whether audio actually plays.

### 2.8 Process Memory Pressure (macOS Memory Warning During Synthesis)

**Expected behavior**: macOS sends `NSNotification.Name.NSApplicationDidReceiveMemoryWarning` -- but this is only for iOS-style memory warnings. On macOS, the system uses compressed memory and swap. No explicit jetsam for launchd daemons unless they exceed a configured memory limit in the plist.

**Fragility**: The `mach_task_basic_info.resident_size` is monitored by the health endpoint but no proactive action is taken on high RSS. During synthesis, peak RSS is ~561MB. If the system is under memory pressure, swap will handle it (at the cost of synthesis speed). No crash risk unless the machine has < 1GB free and swap is full. **Low risk on Apple Silicon with unified memory.**

### 2.9 Concurrent TTS Test + Real Notification

**Expected behavior**: HTTP `POST /tts/test` triggers `ttsEngine.synthesizeWithTimestamps()` on the TTS serial queue. A real notification triggers `ttsEngine.synthesizeStreaming()` also on the same serial queue. The serial queue ensures they don't overlap -- one waits for the other.

**Fragility**:

- The HTTP test path (line 186 in HTTPControlServer) creates its own `SubtitleSyncDriver` stored in `activeSyncDriver`. The real notification path creates a different driver stored in `telegramBot.syncDriver`. Both try to control the same `subtitlePanel`.
- If the test is running and a real notification arrives, `dispatchStreamingTTS()` calls `ttsEngine.stopPlayback()` which stops the engine's `audioPlayer` -- but the test's player may be different (stored in the sync driver).
- The `isStreamingInProgress` flag is on TelegramBot, not checked by the HTTP test path. **The test can interrupt streaming playback, and streaming can interrupt the test.**

**Risk**: P2 -- test vs. real notification collision. Unlikely in production but could confuse diagnostics.

### 2.10 Model File Missing/Corrupted

**Expected behavior**: `ensureModelLoaded()` (line 772) attempts to load the model. `KokoroTTS(modelPath:)` would throw or crash on a missing/corrupted file. `NpyzReader.read()` returns nil for missing voices, triggering `TTSError.modelLoadFailed`.

**Fragility**:

- `KokoroTTS(modelPath:)` is an external library call. If it crashes (segfault in C++ layer), the entire process dies. No graceful fallback.
- The model path is read from `Config.kokoroMLXModelPath` which checks environment variables. If the env var points to a nonexistent path, the error surfaces on first synthesis, not at startup. **Late failure.**
- No startup probe to validate model files exist before accepting notifications.

**Risk**: P1 -- unrecoverable crash on corrupted model, no startup validation.

---

## Part 3: SOTA Anti-Fragile Patterns (Web Research)

### 3.1 MLX Memory Management

- **WWDC 2025 MLX sessions** confirm that `Memory.clearCache()` + `GPU.set(memoryLimit:)` are the primary memory management tools.
- `GPU.synchronize()` ensures all in-flight Metal commands complete before cache clearing.
- `GPU.set(cacheLimit:)` provides a hard upper bound on buffer cache size.
- The 499000 resource limit is a Metal-level hard limit. Community workarounds include periodic `clearCache()` and process restarts for long-running services.
- **Recommendation**: Call `GPU.synchronize()` then `Memory.clearCache()` between sessions, and set `GPU.set(cacheLimit: 512 * 1024 * 1024)` at startup.

### 3.2 AVAudioPlayer Resilience

- Apple docs: `prepareToPlay()` returns Bool indicating success -- should be checked.
- `AVAudioPlayer` handles audio session reactivation automatically on iOS. On macOS, there is no `AVAudioSession` -- the system handles routing changes transparently.
- For macOS background services, `AudioObjectAddPropertyListener` on `kAudioHardwarePropertyDefaultOutputDevice` detects output route changes.
- **Recommendation**: Check `prepareToPlay()` and `play()` return values. Add output device change listener for logging/diagnostics.

### 3.3 Timer Reliability on macOS

- **App Nap can delay DispatchSourceTimer** when the app is not frontmost. Since this is an accessory app with no visible windows (NSPanel is floating), macOS may apply App Nap.
- `ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "TTS playback")` prevents App Nap during active playback.
- CADisplayLink is iOS-only; macOS uses CVDisplayLink for display-synced callbacks. For non-display work (audio sync), `DispatchSourceTimer` with `leeway: .milliseconds(2)` is appropriate.
- **Recommendation**: Wrap active TTS playback in a `ProcessInfo.beginActivity()` block to prevent App Nap from degrading timer accuracy.

### 3.4 Circuit Breaker for ML Inference

- The existing `CircuitBreaker` class covers MiniMax API calls. No circuit breaker exists for the TTS engine itself.
- If `generateAudio()` fails 3 times consecutively, the code just logs and continues to the next chunk. No circuit breaker prevents repeated expensive synthesis attempts on a clearly-broken model.
- **Recommendation**: Add a TTS circuit breaker: after 3 consecutive synthesis failures, disable TTS for 5 minutes and show subtitle-only text.

### 3.5 Graceful Degradation

- Current degradation path: MiniMax down -> fallback text -> TTS fails -> log error -> nothing shown.
- Missing: TTS fails -> show subtitle-only (no audio). The subtitle display is coupled to audio playback via SyncDriver.
- **Recommendation**: When synthesis fails, show the full text as a static subtitle for `lingerDuration` seconds, then hide. This ensures the user always sees the content even when TTS is broken.

---

## Part 4: Ranked Recommendations

| Priority | Issue                                                       | Risk                                                             | Fix                                                                                                                                                                    | Effort |
| -------- | ----------------------------------------------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| P0       | MLX Metal resource exhaustion on long sessions (>15 chunks) | Process crash                                                    | Add `GPU.synchronize()` before `Memory.clearCache()`, set `GPU.set(cacheLimit: 512MB)` at startup, call `clearCache()` every 5 chunks in the synthesis loop            | 1h     |
| P0       | No startup model validation                                 | Crash on first synthesis if model files missing                  | Add `FileManager.default.fileExists()` checks for `kokoroMLXModelPath` and `kokoroVoicesPath` at init time; log fatal and exit cleanly instead of crashing mid-service | 30m    |
| P1       | `isStreamingInProgress` not formally thread-safe            | Potential double-dispatch on near-simultaneous notifications     | Move flag to an `NSLock`-protected property or ensure it is only ever read/written from the main thread                                                                | 30m    |
| P1       | No TTS circuit breaker                                      | Repeated expensive synthesis attempts on broken model            | Add synthesis failure counter; after 3 consecutive failures, disable TTS for 5 minutes, show subtitle-only fallback                                                    | 1h     |
| P1       | No graceful degradation when TTS fails                      | User sees nothing when synthesis fails                           | On synthesis failure, dispatch subtitle-only display (show full text for `lingerDuration`, then hide)                                                                  | 1h     |
| P1       | App Nap may degrade 60Hz timer during playback              | Karaoke drift or stutter when app is backgrounded                | Wrap active playback in `ProcessInfo.beginActivity(options: .userInitiated)`                                                                                           | 30m    |
| P1       | No explicit URLSession timeout for MiniMax                  | Stuck TCP connection blocks notification processing indefinitely | Set `timeoutIntervalForRequest: 30` on URLSession configuration                                                                                                        | 15m    |
| P2       | WAV file leak on `stop()` cancellation                      | Orphaned temp files in /tmp/                                     | In `stop()`, manually delete WAV files for `streamPlayer` and `nextStreamPlayer` since `AVAudioPlayer.stop()` does not trigger delegate callbacks                      | 30m    |
| P2       | `prepareToPlay()` / `play()` return values ignored          | Silent playback failure with no diagnostics                      | Check return values and log warnings on failure                                                                                                                        | 15m    |
| P2       | Warm-up player not retained by instance property            | Potential early deallocation of warm-up player                   | Store warm-up player in an instance property until cleanup delay fires                                                                                                 | 15m    |
| P2       | NotificationProcessor drops intermediate notifications      | Only first + last notifications process during rapid-fire        | Document as intentional, or add a small queue (capacity 3) instead of single `pendingFilePath`                                                                         | 1h     |
| P2       | HTTP /tts/test can collide with real TTS dispatch           | Confusing behavior during diagnostics                            | Check `isStreamingInProgress` before running test, or skip test if streaming is active                                                                                 | 30m    |
| P3       | No output device change monitoring                          | Audio silently routes to wrong device with no log                | Add `AudioObjectAddPropertyListener` on default output device for logging                                                                                              | 1h     |
| P3       | Late model loading (first synthesis, not startup)           | First notification experiences 2-3s extra latency                | Add optional eager model load at startup behind a config flag                                                                                                          | 30m    |
| P3       | `processedSessions` dict grows unbounded between prunes     | Memory growth for very long uptimes                              | Cap at 100 entries with LRU eviction                                                                                                                                   | 30m    |

---

## Summary of Key Findings

### What is working well

1. **Streaming pipeline architecture** is sound -- serial TTS queue, main-thread UI updates, pre-buffered chunk transitions.
2. **SyncDriver lifecycle** has proper `[weak self]` capture, generation counters for stale work item invalidation, and `didFinish` guards against double-completion.
3. **PlaybackDelegate pattern** correctly handles the AVAudioPlayer weak delegate issue.
4. **CircuitBreaker for MiniMax** provides 3-strike protection with 5-minute cooldown.
5. **NotificationProcessor** mutex + rate limiter prevents concurrent processing and flood protection.
6. **Trailing silence padding** (100ms) is a good fix for sentence boundary choppiness.
7. **`alignOnsetsToWords()`** properly handles the MToken-vs-whitespace tokenization mismatch.

### What needs attention

1. **MLX Metal memory management is the #1 risk.** `clearCache()` alone is necessary but may not be sufficient for sustained load. Add `GPU.synchronize()` and per-session cache limiting.
2. **No TTS-level circuit breaker or graceful degradation.** If the Kokoro model is broken, the system repeatedly attempts expensive synthesis with no fallback.
3. **Thread safety of `isStreamingInProgress`** relies on external serialization that could be violated if the notification pipeline changes.
4. **App Nap** can silently degrade timer accuracy for the 60Hz karaoke poller.
5. **Startup validation** is absent -- a missing model file causes a crash on first notification rather than a clean error at boot.

### Debug session history shows the team has systematically addressed

- Early cutoff (streaming guard) -- FIXED
- Orphaned SyncDriver (immediate cancellation) -- FIXED
- Inter-chunk gaps (pre-buffering) -- FIXED
- MToken/subtitle word mismatch (alignment) -- FIXED
- CoreAudio cold start (warm-up) -- FIXED
- Sentence boundary choppiness (trailing silence) -- FIXED
- Font size mismatch in chunker (dynamic font) -- FIXED
- Transcript parser mismatches (type field) -- FIXED
- Metal resource exhaustion (clearCache) -- PARTIALLY FIXED

The pipeline has matured significantly through iterative debugging. The remaining P0/P1 items are hardening measures that prevent regressions under sustained load or degraded conditions.

---

## Sources

- [MLX Swift Memory.swift](https://github.com/ml-explore/mlx-swift/blob/main/Source/MLX/Memory.swift)
- [GPU Memory/Cache Limit Issue #66](https://github.com/ml-explore/mlx-swift-examples/issues/66)
- [Metal malloc Resource Limit 499000 - mlx-lm #831](https://github.com/ml-explore/mlx-lm/issues/831)
- [Metal malloc Resource Limit - lmstudio mlx-engine #264](https://github.com/lmstudio-ai/mlx-engine/issues/264)
- [MLX GPU set(memoryLimit:relaxed:) docs](<https://swiftpackageindex.com/ml-explore/mlx-swift/0.29.1/documentation/mlx/gpu/set(memorylimit:relaxed:)>)
- [Apple: Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)
- [DispatchSourceTimer reliability - Apple Forums](https://developer.apple.com/forums/thread/115114)
- [WWDC 2025: Explore LLM on Apple silicon with MLX](https://dev.to/arshtechpro/wwdc-2025-explore-llm-on-apple-silicon-with-mlx-1if7)
- [Implementing Circuit Breakers for LLM Services in Go](https://dasroot.net/posts/2026/02/implementing-circuit-breakers-for-llm-services-in-go/)
- [Apple: Addressing watchdog terminations](https://developer.apple.com/documentation/xcode/addressing-watchdog-terminations)
- [CosyVoice TTS Resource Limit Discussion](https://huggingface.co/mlx-community/Fun-CosyVoice3-0.5B-2512-fp16/discussions/1)
