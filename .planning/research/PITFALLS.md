# Domain Pitfalls <!-- # SSoT-OK -->

**Domain:** Architecture hardening + feature expansion for existing Swift macOS daemon (claude-tts-companion)
**Researched:** 2026-03-27
**Focus:** Pitfalls when adding actor concurrency, XCTest, dual TTS engines, bionic reading, caption history, and Focus/DND to an existing @unchecked Sendable + NSLock codebase

## Critical Pitfalls

Mistakes that cause rewrites, deadlocks, or extended debugging sessions.

### Pitfall 1: Actor Reentrancy Silently Breaks State Invariants During Migration

**What goes wrong:** After migrating TTSEngine from `@unchecked Sendable` + NSLock to an actor, synthesis calls that were previously serialized by the serial DispatchQueue now interleave at every `await` point. A method that reads state, awaits an async operation, then writes state based on what it read finds the state has changed underneath it. Example: `ensureModelLoaded()` checks `ttsInstance == nil`, awaits model loading, then assigns `ttsInstance` -- but a second caller already loaded the model during the await, causing double initialization or wasted memory.

**Why it happens:** Actors are reentrant by design. Unlike NSLock (which blocks the thread) or a serial DispatchQueue (which queues work), actors suspend at await points and allow other messages to execute. This is the correct design for preventing deadlocks, but it means every `await` is a potential state mutation point. The existing codebase has 15 files using `@unchecked Sendable` -- each one has implicit assumptions about serial execution that actors will violate.

**Consequences:** Double model loading (561MB wasted), corrupted playback state (two AVAudioPlayers competing for audio output), synthesis results delivered to wrong callers, or subtle data races that only manifest under load.

**Prevention:**

- **Audit every method for "read-await-write" patterns** before converting to an actor. Every method that reads state, awaits, then writes based on the read is a reentrancy bug. List them explicitly.
- **Perform all state mutations in synchronous (non-async) methods.** Synchronous actor methods cannot be reentrantly interleaved. Use the "check-then-act" pattern:

```swift
// GOOD: Atomic check-then-act in sync method
private func tryDequeue() -> AudioSegment? {
    guard !queue.isEmpty else { return nil }
    return queue.removeFirst()  // read + mutate in one sync block
}

// BAD: Split across await
func playNext() async {
    let segment = queue.first!  // read
    await prepare(segment)      // INTERLEAVING HAPPENS HERE
    queue.removeFirst()         // mutate (may remove wrong item!)
}
```

- **Guard with state flags for lazy init.** Replace the NSLock-guarded lazy init with an actor-internal enum: `.unloaded`, `.loading(Task<KokoroTTS, Error>)`, `.loaded(KokoroTTS)`. Second callers await the existing loading Task rather than starting a new one.
- **Do NOT mix NSLock inside actors.** An NSLock inside an actor blocks the cooperative thread pool thread, defeating the actor's purpose and risking thread starvation.
- **Migrate one class at a time, not all 15.** Convert TTSEngine first (highest complexity), validate, then proceed.

**Detection:** Double model load shows as RSS jumping to ~1,100MB instead of 561MB. Two AVAudioPlayers active simultaneously causes audio glitching. Swift 6 strict concurrency catches data races across isolation boundaries but does NOT catch reentrancy logic errors within the same actor -- code review and testing are the only defense.

**Phase:** Actor migration phase. TTSEngine first, then PlaybackManager, then others.

**Confidence:** HIGH -- actor reentrancy is well-documented ([Hacking with Swift](https://www.hackingwithswift.com/quick-start/concurrency/what-is-actor-reentrancy-and-how-can-it-cause-problems), [Swift Forums](https://forums.swift.org/t/actor-reentrancy/59484), [SE-0306](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md)).

---

### Pitfall 2: MainActor Isolation Deadlock with Actor-Isolated TTS Calls from AppKit

**What goes wrong:** SubtitlePanel (AppKit, must be @MainActor) calls into TTSEngine (now an actor). The call is `await ttsActor.synthesize(text)`. If this is called from a synchronous AppKit context (e.g., an NSButton action or notification handler), the compiler forces you to wrap it in a Task. But if the TTS actor's method then calls back to update the subtitle panel via `await MainActor.run { ... }`, you get a classic ping-pong pattern that, while not technically deadlocking (actors are reentrant), introduces unbounded latency and confusing execution ordering.

**Why it happens:** AppKit callbacks are synchronous and MainActor-isolated. Actors communicate asynchronously. The mismatch creates a "bridge tax" at every AppKit-to-actor boundary. The existing codebase uses `DispatchQueue.main.async { }` for UI updates from background queues -- this pattern changes fundamentally with actors.

**Consequences:** Subtitle updates lag behind audio by hundreds of milliseconds. Word highlighting appears to "jump" because multiple queued MainActor updates execute in a burst. In worst case, the cooperative thread pool saturates with MainActor hops and the entire UI freezes.

**Prevention:**

- **Establish a one-way data flow.** TTSEngine actor produces results. SubtitlePanel (MainActor) consumes them. Never have TTSEngine call back into SubtitlePanel directly. Use `AsyncStream<TTSResult>` as the communication channel.
- **Use `@MainActor` on SubtitlePanel explicitly.** Don't rely on implicit inference. Mark the class, not individual methods.
- **For AppKit callbacks that need actor calls**, use `Task { @MainActor in ... }` to bridge, but keep the Task body minimal -- just the `await` call and a UI update.
- **Never call `MainActor.assumeIsolated` from actor methods.** This crashes if the assumption is wrong, and during migration it will be wrong. Always use `await MainActor.run { }` or `@MainActor` closures.
- **Benchmark MainActor hop latency.** If round-trip actor-to-MainActor exceeds 5ms, batch updates or use a timer-driven refresh pattern (poll actor state every 16ms from MainActor).

**Detection:** Instrument with `os_signpost` around MainActor hops. If hop count exceeds 60/second (one per frame), the design is too chatty.

**Phase:** Actor migration phase -- must be designed before TTSEngine conversion, not after.

**Confidence:** HIGH -- documented in [Swift Forums](https://forums.swift.org/t/mainactor-assumeisolated-crashes-on-main-thread/80624), [avanderlee](https://www.avanderlee.com/swift/mainactor-dispatch-main-thread/).

---

### Pitfall 3: XCTest Cannot @testable import Executable Targets in SwiftPM

**What goes wrong:** You add a test target to Package.swift with `@testable import claude_tts_companion` and get a linker error: "undefined symbol `_main`" or "no such module." The test binary cannot link against the executable target because SwiftPM compiles executable targets differently (with a `main` entry point) than library targets.

**Why it happens:** SwiftPM passes `-parse-as-library` for library targets but not for executable targets. The `main.swift` file creates a `_main` symbol that conflicts with XCTest's own entry point. This is a fundamental SwiftPM architectural limitation, not a bug -- [GitHub issue #7596](https://github.com/swiftlang/swift-package-manager/issues/7596) has been open since 2023 with no resolution.

**Consequences:** Without the library extraction pattern, you cannot write any unit tests for the existing 15+ source files. The entire XCTest infrastructure goal is blocked.

**Prevention:**

- **Extract a library target immediately.** Restructure Package.swift:

  ```swift
  .target(
      name: "CompanionCore",
      dependencies: [/* all deps */],
      path: "Sources/CompanionCore"
  ),
  .executableTarget(
      name: "claude-tts-companion",
      dependencies: ["CompanionCore"],
      path: "Sources/claude-tts-companion"  // only main.swift
  ),
  .testTarget(
      name: "CompanionCoreTests",
      dependencies: ["CompanionCore"],
      path: "Tests/CompanionCoreTests"
  )
  ```

- **Move ALL source files except main.swift into CompanionCore.** The executable target becomes a thin shell: just `main.swift` that calls into the library.
- **Do this BEFORE any actor migration.** Changing the target structure and concurrency model simultaneously creates merge conflicts and makes debugging impossible.
- **Verify with `swift test` immediately.** Don't wait until you have real tests -- create a trivial `XCTAssertTrue(true)` test to confirm the infrastructure works.

**Detection:** `swift test` fails with linker errors mentioning `_main` or "no such module."

**Phase:** Must be the FIRST task in the milestone, before actor migration or any feature work. Everything else depends on testability.

**Confidence:** HIGH -- well-documented SwiftPM limitation ([Swift Forums](https://forums.swift.org/t/command-line-tool-target-cannot-have-a-unit-testing-bundle/45596), [GitHub #7596](https://github.com/swiftlang/swift-package-manager/issues/7596)).

---

### Pitfall 4: Cooperative Thread Pool Starvation When Actor Wraps Blocking TTS Call

**What goes wrong:** You migrate TTSEngine to an actor and the `synthesize()` method becomes `func synthesize(_ text: String) async -> TTSResult`. But the underlying kokoro-ios `KokoroTTS.synthesize()` is synchronous and blocks for 3-7 seconds. This blocks one of Swift's cooperative thread pool threads. With 8 cores, you have ~8 cooperative threads. Block one for 7 seconds and you've reduced throughput by 12.5%. Block two (overlapping requests) and the impact doubles. Block all 8 and the entire app deadlocks.

**Why it happens:** Actors run on the cooperative thread pool by default. A synchronous blocking call inside an actor method holds the thread for the entire duration. Unlike the previous serial DispatchQueue approach (which used a dedicated thread), the actor approach borrows from the shared pool.

**Consequences:** Bot stops responding to Telegram messages during synthesis. HTTP control API times out. File watchers miss events. The entire app appears frozen.

**Prevention:**

- **Do NOT put blocking synthesis calls directly in an actor.** Keep the dedicated `DispatchQueue(label: "tts", qos: .userInitiated)` and bridge to async:

  ```swift
  actor TTSEngine {
      private let synthesisQueue = DispatchQueue(label: "tts", qos: .userInitiated)

      func synthesize(_ text: String) async throws -> TTSResult {
          try await withCheckedThrowingContinuation { continuation in
              synthesisQueue.async {
                  // blocking synthesis runs on dedicated thread, not cooperative pool
                  let result = self.performSynthesis(text)
                  continuation.resume(returning: result)
              }
          }
      }
  }
  ```

- **This is the SAME pattern as the current codebase** (serial DispatchQueue for blocking work), just wrapped in actor syntax for the non-blocking parts (state management, queue depth tracking).
- **Never use `Task { }` for blocking work.** Tasks run on the cooperative pool. `Task.detached` also runs on the cooperative pool -- it only detaches from the parent task's priority and cancellation, NOT from the thread pool.
- **Apply the same pattern to sherpa-onnx CJK synthesis** if added.

**Detection:** `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` environment variable causes a runtime trap if a cooperative thread blocks. Use during development. If `swift test` hangs or UI becomes unresponsive during synthesis, C FFI is blocking the pool.

**Phase:** Actor migration phase. This is the most important architectural decision in the migration.

**Confidence:** HIGH -- documented in [Problematic Swift Concurrency Patterns](https://www.massicotte.org/problematic-patterns/) and the existing codebase's Phase 3 design rationale.

---

### Pitfall 5: Dual TTS Engine Memory Pressure -- Two Models Cannot Coexist at 1.1GB RSS

**What goes wrong:** Loading both kokoro-ios MLX (primary, ~561MB RSS) and sherpa-onnx (CJK fallback, ~310MB) simultaneously pushes peak RSS above 800MB. On a 16GB MacBook running Xcode + Chrome + Claude Code, this triggers macOS memory pressure warnings and potential jetsam kills.

**Why it happens:** Each TTS engine loads its own model into memory independently. kokoro-ios uses MLX Metal GPU buffers. sherpa-onnx uses ONNX Runtime CPU buffers. These are separate memory pools that cannot be shared. The existing architecture assumes a single TTS engine with 561MB peak -- adding a second was never in the original memory budget.

**Consequences:** Process killed by jetsam during CJK synthesis. Or: system-wide slowdown as macOS compresses memory.

**Prevention:**

- **Never load both models simultaneously.** Use a "load-on-demand, unload-on-idle" strategy:
  1. kokoro-ios is the default, loaded lazily on first English TTS request.
  2. When CJK text is detected, unload kokoro-ios MLX arrays (`voice = nil; ttsInstance = nil`) and wait for ARC to reclaim memory.
  3. Load sherpa-onnx CJK model.
  4. After CJK synthesis completes and 30 seconds pass with no CJK requests, unload sherpa-onnx and reload kokoro-ios on next English request.
- **Model load time is the tax.** kokoro-ios loads in ~0.56s (Spike 03). This is acceptable as a one-time cost per language switch. Do not try to avoid it by keeping both loaded.
- **Add RSS monitoring.** After each model load/unload, log `task_info()` RSS. If RSS after unload is not within 50MB of baseline, there's a memory leak in the unload path.
- **Gate behind feature flag.** CJK fallback should be disabled by default in the first release. Enable only after memory behavior is validated in production.

**Detection:** RSS exceeds 800MB during language transitions. `task_info()` shows RSS not dropping after model unload (leak). System `memory_pressure` notifications fire.

**Phase:** Dual TTS engine phase. Design the load/unload lifecycle before writing any CJK code.

**Confidence:** HIGH -- RSS figures from Spikes 03/09 (561MB for single model), extrapolated for dual loading. ONNX Runtime memory behavior confirmed in [GitHub issue #3802](https://github.com/microsoft/onnxruntime/issues/3802).

---

### Pitfall 6: Focus/DND Detection Has No Public macOS API

**What goes wrong:** You build a Focus mode integration that reads `~/Library/DoNotDisturb/DB/Assertions.json` to detect DND state. It works in testing. Then a macOS update changes the JSON schema, moves the file, or removes it entirely. The feature silently breaks with no compiler warning and no runtime error.

**Why it happens:** Apple has explicitly refused to provide a public API for reading Focus/DND state on macOS. A Feedback Assistant request was closed as "not to be fixed" due to privacy implications. The `Assertions.json` / `ModeConfigurations.json` files in `~/Library/DoNotDisturb/DB/` are private implementation details. The only public API is `AppIntents.Focus`, which lets you configure Focus filters but NOT query the current Focus state from a background daemon.

**Consequences:** Feature works on your machine today, breaks on next macOS update. If the feature is load-bearing (suppressing audio during Focus), the break means audio plays when the user expects silence -- embarrassing during meetings.

**Prevention:**

- **Accept the limitation.** There is no reliable, future-proof way to detect Focus mode from a background daemon on macOS.
- **Use DistributedNotificationCenter as a heuristic.** Some developers have found that `com.apple.donotdisturb.state.changed` notifications fire on DND toggle. This is undocumented but more stable than file parsing.
- **Alternative: Manual toggle.** Add a "Suppress Audio" button to the SwiftBar menu and Telegram inline buttons. Let the user control audio suppression explicitly rather than trying to detect system state. This is the most robust approach.
- **Wrap in a `FocusDetecting` protocol.** The file-based implementation handles missing files gracefully (returns "Focus not active"). Log a warning when the file is missing so you notice after a macOS upgrade.
- **If using the JSON file approach**, check file existence, validate JSON schema, and fall back to "Focus unknown" (don't suppress audio) if anything is unexpected.

**Detection:** Focus detection returns stale state after macOS update. Audio plays during meetings despite Focus mode being active.

**Phase:** Focus/DND phase. Should be the LAST feature implemented because it has the weakest API foundation.

**Confidence:** HIGH -- Apple's refusal to provide a public API is documented in [Apple Developer Forums](https://developer.apple.com/forums/thread/100511) and [Hacking with Swift Forums](https://www.hackingwithswift.com/forums/swiftui/api-to-detect-focus-mode-personal-work-sleep-etc/25818). The JSON file approach is from [community scripts](https://gist.github.com/drewkerr/0f2b61ce34e2b9e3ce0ec6a92ab05c18) with no stability guarantee.

---

## Moderate Pitfalls

### Pitfall 7: @unchecked Sendable Removal Triggers Cascade of Swift 6 Errors

**What goes wrong:** You remove `@unchecked Sendable` from TTSEngine and convert it to an actor. Immediately, every call site that passes TTSEngine across concurrency domains produces Swift 6 strict concurrency errors. The cascade spreads to TelegramBot, NotificationProcessor, HTTPControlServer, and every other class that holds a reference to TTSEngine. What should be a single-class migration becomes a 15-file change.

**Why it happens:** `@unchecked Sendable` was a lie to the compiler -- it said "trust me, this is thread-safe" for all 15 classes. Removing it for even one class exposes every boundary crossing.

**Prevention:**

- **Do NOT remove @unchecked Sendable from all classes at once.** Migrate one class at a time.
- **Convert to actor but keep the actor conforming to Sendable** (actors are implicitly Sendable). Callers that previously passed the `@unchecked Sendable` class can pass the actor -- Sendable conformance is preserved.
- **The real issue is the callers.** When TTSEngine becomes an actor, callers must `await` its methods. Change callers one at a time, starting with the most isolated.
- **Keep a working build at every step.** If converting TTSEngine to an actor breaks the build, the migration step was too large. Split it: first make all TTSEngine methods async (keep as class), then convert to actor.

**Detection:** `swift build` produces 50+ concurrency errors after a single class change. This means the migration step was too large.

**Phase:** Actor migration phase. Design the migration order (dependency graph) before starting.

**Confidence:** HIGH -- documented migration challenge ([Jared Sinclair](https://jaredsinclair.com/2024/11/12/beware-unchecked.html), [Fat Bob Man](https://fatbobman.com/en/posts/sendable-sending-nonsending/)).

---

### Pitfall 8: NSScrollView Bottom-Pinning Flickers on Rapid Content Append

**What goes wrong:** The caption history NSScrollView auto-scrolls to bottom when new captions arrive (during TTS playback, captions arrive every ~200ms). Each append triggers a layout pass + scroll animation. On rapid-fire appends, the scroll position oscillates, creating visible jitter. The user also cannot scroll up to read history because the auto-scroll keeps yanking them back down.

**Why it happens:** NSScrollView's coordinate system in AppKit has the origin at bottom-left unless `isFlipped` returns `true`. If the documentView height changes between the scroll animation start and end, the target position is stale.

**Consequences:** Caption history panel is unusable during active playback -- too jittery to read, impossible to scroll up.

**Prevention:**

- **Only auto-scroll if the user is already at the bottom.** Before appending, check: `isAtBottom = (scrollView.contentView.bounds.maxY >= scrollView.documentView!.frame.maxY - 20)`. If the user has scrolled up, do NOT auto-scroll.
- **Batch appends.** Buffer captions for 500ms and append in a batch. One layout pass per batch, not per caption.
- **Make the documentView return `isFlipped = true`** (override in your NSView subclass). This makes the coordinate system top-down.
- **Set `textView.textContainer?.heightTracksTextView = false`** and `textView.isVerticallyResizable = true`. Without these, the text view expands to match the scroll view height, eliminating scrolling.
- **Disable scroll animation during rapid updates.** Use `NSAnimationContext.beginGrouping(); NSAnimationContext.current.duration = 0; ...; NSAnimationContext.endGrouping()`.

**Detection:** Visual jitter during playback. User reports being unable to scroll up in caption history.

**Phase:** Caption history phase. Prototype the scroll behavior before building the full panel.

**Confidence:** MEDIUM -- based on [NSScrollView documentation](https://developer.apple.com/documentation/appkit/nsscrollview) and common AppKit patterns.

---

### Pitfall 9: Bionic Reading + Karaoke Highlighting Conflict on Same NSAttributedString

**What goes wrong:** Both bionic reading (bold/regular font weights) and karaoke (gold color highlighting) modify the same NSAttributedString. Applying both simultaneously creates visual chaos -- bold ranges from bionic reading interfere with the highlight ranges from karaoke, producing inconsistent styling that flickers on every word transition.

**Why it happens:** NSAttributedString attributes are applied by range. Bionic reading sets `.font` attributes (bold for prefix, regular for suffix). Karaoke sets `.foregroundColor` attributes (gold for spoken, white for unspoken). When both operate on the same string, the karaoke update may inadvertently reset the font attributes if using `setAttributes` instead of `addAttributes`.

**Consequences:** Visual chaos during playback. Bold formatting disappears when karaoke highlight advances, or karaoke colors disappear when bionic formatting is applied.

**Prevention:**

- **Make them mutually exclusive display modes.** Use a single enum (`DisplayMode.karaoke`, `.bionicReading`, `.plain`), not two independent booleans.
- **If both are desired simultaneously**, use `addAttributes` (not `setAttributes`) for karaoke highlighting to preserve existing font attributes. But this adds complexity -- recommend against it for v1.
- **NSRange off-by-one with multi-byte characters:** Always work in NSString coordinates. Convert to NSString once, calculate all ranges using `NSString.length`. Never mix Swift String indices with NSRange. Test with emoji-heavy text, accented characters, and CJK.

**Detection:** Bold formatting visually wrong on accented text. Crash with NSRange out-of-bounds exceptions on multi-byte characters.

**Phase:** Bionic reading phase. Write a comprehensive test suite for range calculations before integrating with SubtitlePanel.

**Confidence:** MEDIUM -- NSString/String range mismatch is a well-known Swift pitfall.

---

### Pitfall 10: sherpa-onnx CJK Model Has Different API Surface Than kokoro-ios

**What goes wrong:** You build the dual TTS engine assuming both engines have the same interface: `synthesize(text) -> (wavPath, wordTimings)`. But sherpa-onnx (C API) returns a flat audio buffer with no word-level timestamps for CJK text. kokoro-ios (Swift, MLX) returns `MToken` objects with `start_ts`/`end_ts`. The abstraction layer that works for English karaoke subtitles produces no timing data for CJK.

**Why it happens:** Word-level timestamps come from the Kokoro duration model. CJK text uses a different phonemization pipeline. The timestamp extraction may not apply or may produce meaningless results.

**Consequences:** CJK subtitles display with no karaoke highlighting -- all text appears at once.

**Prevention:**

- **Define the TTS protocol explicitly** with optional word timings:

  ```swift
  protocol TTSProvider {
      func synthesize(_ text: String) async throws -> TTSResult
  }
  ```

  Where `TTSResult.wordTimings` is optional (nil for CJK if timestamps unavailable).

- **SubtitlePanel must handle the "no timestamps" case gracefully.** Fall back to character-proportional timing for CJK.
- **Test CJK synthesis end-to-end before committing to the dual engine architecture.** If quality is poor, the feature may not be worth shipping.

**Detection:** CJK subtitles show all text highlighted simultaneously (no progressive karaoke).

**Phase:** Dual TTS engine phase. Spike the CJK integration first to validate feasibility.

**Confidence:** MEDIUM -- the English pipeline is proven (Spikes 03/09/16/19) but CJK is untested.

---

### Pitfall 11: Swift Testing Parallel Execution with Shared State

**What goes wrong:** Swift Testing (`@Test`) runs tests in parallel by default. Tests that share global state (e.g., a singleton TTS engine, a shared NSPanel) interfere with each other, producing flaky test results.

**Prevention:**

- Use `@Test(.serialized)` trait for tests that require exclusive access to shared resources.
- Better yet, design tests with injected dependencies (mock synthesizer, mock panel) so they don't share state at all.
- For integration tests needing AppKit, call `NSApplication.shared` in `setUp()` to initialize the application object. Add `.linkedFramework("AppKit")` to the test target's linker settings.

**Phase:** XCTest infrastructure phase.

**Confidence:** MEDIUM -- standard testing best practice.

---

## Minor Pitfalls

### Pitfall 12: Caption History Memory Growth in Long-Running Daemon

**What goes wrong:** The caption history stores every caption since process launch. After days of running, thousands of NSAttributedString entries accumulate with no bound.

**Prevention:**

- Cap history at 500-1000 entries. Drop oldest when cap is reached.
- Store plain text in history, render NSAttributedString only for visible entries.
- Add a "Clear History" button in the panel and SwiftBar menu.

**Phase:** Caption history phase.

**Confidence:** HIGH -- standard long-running daemon memory management.

---

### Pitfall 13: Model Unload/Reload Latency Creates Audible Gap During Language Switch

**What goes wrong:** Mixed English/CJK sessions trigger frequent model swaps. Each language switch introduces ~800ms of silence (unload + reload). Repeated switching creates a stuttering experience.

**Prevention:**

- Buffer language-consecutive text. Don't switch engines on every sentence.
- Add a cooldown timer (30 seconds) to keep the current engine loaded after a switch.
- Accept the gap for v1. Document the latency, ship it, optimize later.

**Phase:** Dual TTS engine phase.

**Confidence:** MEDIUM -- load times from spikes, language switching pattern is untested.

---

### Pitfall 14: NSTextView Copy Includes Invisible Formatting

**What goes wrong:** Users copy text from caption history and paste it elsewhere with unexpected bold/font formatting from bionic reading mode.

**Prevention:** Override `copy:` to strip formatting and copy plain text, or provide a "Copy as Plain Text" menu item.

**Phase:** Caption history phase.

**Confidence:** LOW -- minor UX concern.

---

### Pitfall 15: Actor Initialization Race at App Startup

**What goes wrong:** Actors are initialized, but their async `setup()` methods haven't completed when other components start sending messages to them. The Telegram bot starts polling before TTSEngine has loaded its model, causing the first synthesis request to fail or queue indefinitely.

**Prevention:** Use structured concurrency (`TaskGroup` or `async let`) in the app coordinator to ensure all actors are initialized and setup-complete before starting the Telegram bot polling loop.

**Phase:** Actor migration phase.

**Confidence:** MEDIUM -- depends on app startup sequence design.

---

## Phase-Specific Warnings

| Phase Topic           | Likely Pitfall                                 | Mitigation                                                        |
| --------------------- | ---------------------------------------------- | ----------------------------------------------------------------- |
| XCTest Infrastructure | Cannot import executable target (#3)           | Extract library target FIRST, before any other work               |
| Actor Migration       | Reentrancy breaks lazy init (#1)               | State machine enum for loading states, sync mutations             |
| Actor Migration       | MainActor deadlock with AppKit (#2)            | One-way data flow via AsyncStream                                 |
| Actor Migration       | Sendable cascade from removing @unchecked (#7) | Migrate one class at a time, keep build green                     |
| Actor Migration       | Thread pool starvation (#4)                    | Keep DispatchQueue for blocking work, actor for state only        |
| Actor Migration       | Init race at startup (#15)                     | TaskGroup to sequence actor setup                                 |
| Dual TTS Engine       | Two models at 1.1GB RSS (#5)                   | Load-on-demand, unload-on-idle, never both loaded                 |
| Dual TTS Engine       | CJK has no word timestamps (#10)               | TTSProvider protocol with optional timings, proportional fallback |
| Dual TTS Engine       | Language switch latency (#13)                  | Buffer consecutive language, cooldown timer                       |
| Bionic Reading        | Conflicts with karaoke highlighting (#9)       | Mutually exclusive display modes via enum                         |
| Caption History       | NSScrollView bottom-pin jitter (#8)            | isAtBottom check, batch appends, disable animation                |
| Caption History       | Memory growth in long-running daemon (#12)     | Cap entries, store plain text, render on demand                   |
| Caption History       | Copy includes formatting (#14)                 | Override copy: to strip attributes                                |
| Focus/DND             | No public API exists (#6)                      | Manual toggle preferred, JSON file as unreliable heuristic        |
| Testing               | Parallel test interference (#11)               | @Test(.serialized) or injected mocks                              |

## Sources

- [Hacking with Swift: Actor Reentrancy](https://www.hackingwithswift.com/quick-start/concurrency/what-is-actor-reentrancy-and-how-can-it-cause-problems) -- actor reentrancy explanation (HIGH confidence)
- [SE-0306: Actors](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md) -- official actor proposal with reentrancy design rationale (HIGH confidence)
- [Swift Forums: Actor Reentrancy](https://forums.swift.org/t/actor-reentrancy/59484) -- community discussion of reentrancy pitfalls (HIGH confidence)
- [Swift Forums: MainActor.assumeIsolated Crashes](https://forums.swift.org/t/mainactor-assumeisolated-crashes-on-main-thread/80624) -- MainActor isolation edge cases (HIGH confidence)
- [avanderlee: MainActor](https://www.avanderlee.com/swift/mainactor-dispatch-main-thread/) -- MainActor dispatch patterns (HIGH confidence)
- [GitHub SwiftPM #7596: Cannot @testable import executable](https://github.com/swiftlang/swift-package-manager/issues/7596) -- library extraction workaround (HIGH confidence)
- [Swift Forums: Executable Target Testability](https://forums.swift.org/t/executable-target-testability/52351) -- Package.swift restructuring pattern (HIGH confidence)
- [Swift Forums: CLI Target Testing](https://forums.swift.org/t/command-line-tool-target-cannot-have-a-unit-testing-bundle/45596) -- confirms limitation (HIGH confidence)
- [ONNX Runtime #3802: Model Load Memory](https://github.com/microsoft/onnxruntime/issues/3802) -- ONNX model memory consumption (MEDIUM confidence)
- [Apple Developer Forums: DND Detection](https://developer.apple.com/forums/thread/100511) -- Apple refusing public DND API (HIGH confidence)
- [Hacking with Swift Forums: Focus Mode API](https://www.hackingwithswift.com/forums/swiftui/api-to-detect-focus-mode-personal-work-sleep-etc/25818) -- no public Focus query API (HIGH confidence)
- [drewkerr: macOS Focus Mode JXA Script](https://gist.github.com/drewkerr/0f2b61ce34e2b9e3ce0ec6a92ab05c18) -- JSON file approach for Focus detection (LOW confidence, private API)
- [Automators Talk: Focus Mode via Script](https://talk.automators.fm/t/get-current-focus-mode-via-script/12423) -- community workarounds (LOW confidence)
- [Jared Sinclair: Beware @unchecked Sendable](https://jaredsinclair.com/2024/11/12/beware-unchecked.html) -- migration pitfalls (HIGH confidence)
- [Fat Bob Man: Sendable in Swift 6](https://fatbobman.com/en/posts/sendable-sending-nonsending/) -- comprehensive Sendable guide (HIGH confidence)
- [Massicotte: Problematic Swift Concurrency Patterns](https://www.massicotte.org/problematic-patterns/) -- thread pool exhaustion (HIGH confidence)
- [Bionic Reading NSAttributedString Extension](https://developer.bionic-reading.com/framework/Extensions/NSAttributedString.html) -- official SDK reference (MEDIUM confidence)
- [NSScrollView Programmatic Setup](https://dev.to/onmyway133/how-to-make-scrollable-nstextview-in-appkit-986) -- AppKit scroll configuration (MEDIUM confidence)
- Spikes 03, 09, 10, 16, 19 -- validated RSS, model load times, word timing accuracy (HIGH confidence, local)
