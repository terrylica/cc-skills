# Project Research Summary <!-- # SSoT-OK -->

**Project:** claude-tts-companion v4.7.0
**Domain:** macOS TTS/subtitle companion daemon — architecture hardening + feature expansion
**Researched:** 2026-03-27
**Confidence:** HIGH

## Executive Summary

The v4.7.0 milestone is an architecture hardening milestone wrapped around feature delivery. The existing codebase is a working but structurally fragile Swift 6 daemon: a 1058-line TTSEngine god object, 15 files using `@unchecked Sendable` to silence Swift 6 concurrency checks, and an executable-only Package.swift that prevents any unit testing. The research confirms that the migration path is well-understood — extract a `CompanionCore` library target, decompose TTSEngine into actor-isolated components, and add Swift Testing — but sequence matters critically. Every new feature depends on the decomposition being done first; attempting features before the architecture is settled will force rewrites.

The recommended approach follows a dependency-first build order: Package.swift restructure and test infrastructure first (unblocks everything), TTSEngine decomposition with actor migration second (defines the component boundaries that new features plug into), then four new features in priority order: bionic reading (lowest risk, independent), caption history panel (medium risk, `CaptionHistory` ring buffer already exists), Chinese TTS fallback (medium risk, model integration via existing sherpa-onnx linkage), and Focus/DND awareness last (highest risk, relies on undocumented private macOS file). All new features require zero new SPM dependencies — every capability is achievable with built-in Swift/macOS frameworks or data files for the already-linked sherpa-onnx library.

The two most critical risks to manage are actor reentrancy (state invariant violations when `@unchecked Sendable` classes become proper actors) and cooperative thread pool starvation (blocking TTS synthesis calls must stay on a dedicated DispatchQueue, not the actor's cooperative thread). A third structural risk — the SwiftPM executable-target testability limitation — is a known hard blocker that must be resolved as the very first task before any other work begins. The research is HIGH confidence across all areas because it is grounded in multiple validated spikes, official Swift Evolution proposals, and first-party Apple documentation.

## Key Findings

### Recommended Stack

See [STACK.md](./STACK.md) for full details. The v4.7.0 stack introduces zero new SPM dependencies. All additions use built-in Swift 6 language features (actors, Swift Testing, `@MainActor`), built-in macOS frameworks (`NSScrollView`, `NSTextView`, `NSFont`, `NSAttributedString`), and data files for the already-linked sherpa-onnx library (Chinese TTS kokoro-multi-lang-v1_0 model, ~310MB download).

**Core technologies:**

- Swift Actors (built-in, Swift 6.0+): Replace `@unchecked Sendable + NSLock` — actors give compile-time data race safety and suspend (not block) cooperative threads
- `@MainActor` (built-in): Enforce UI-thread isolation for `SubtitlePanel`, `PlaybackManager`, `CaptionHistoryPanel` at compile time rather than via manual `DispatchQueue.main.async`
- Swift Testing (built-in, Swift 6.0+): Macro-based (`@Test`, `#expect`), parallel by default, native async/await; no SPM dependency needed — ships with the toolchain
- `NSScrollView + NSTextView` (AppKit): Native scrollable caption history panel; zero SwiftUI bridging required
- `NSAttributedString + NSFont` (AppKit): Bionic reading bold-prefix rendering via the same infrastructure as existing karaoke highlighting (spike 19: 6us per word update)
- kokoro-multi-lang-v1_0 (sherpa-onnx data file): Chinese TTS via 8 Chinese voices (4F/4M), same 24kHz audio pipeline, same C API surface already in the binary
- `DispatchSource` file monitoring of `~/Library/DoNotDisturb/DB/Assertions.json` (private/undocumented): Focus/DND detection; wrap in `FocusDetecting` protocol for future API swap

**Critical version note:** Swift 6.2's `defaultIsolation: MainActor` would simplify the codebase but is not required. Swift 6.0 strict mode provides full data race safety for this milestone.

### Expected Features

See [FEATURES.md](./FEATURES.md) for complexity ratings, dependencies, and implementation notes on each feature.

**Must have (table stakes — milestone incomplete without these):**

- Actor-based concurrency migration — replaces `@unchecked Sendable + NSLock` across all 15 components; data race safety must be compiler-verified
- TTSEngine decomposition into `SynthesisEngine` (actor), `PlaybackManager` (@MainActor), `WordTimingAligner` (pure struct), `PronunciationProcessor` (pure struct), `TTSCircuitBreaker` (actor) — prerequisite for all other work
- Swift Testing infrastructure via `CompanionCore` library target extraction — enables `@testable import` and unit tests for all business logic

**Should have (differentiators):**

- Bionic reading mode — bold first N chars per word via `NSAttributedString`; HTTP API + Telegram toggle; light/medium/heavy intensity presets; mutually exclusive with karaoke mode
- Scrollable caption history panel — auto-scroll-to-bottom Google Meet pattern; timestamps; copy-to-clipboard; non-activating NSPanel; `CaptionHistory` ring buffer already exists
- Chinese TTS fallback — routes CJK text to sherpa-onnx kokoro-multi-lang-v1_0; `LanguageDetector` already flags CJK at 20% threshold; same audio pipeline; no karaoke (CJK word boundaries require tokenizer)
- Focus/DND awareness — suppresses audio when Focus active; subtitles continue; `focusMode` field in HTTP `/status`; graceful fail-open when file parse fails

**Defer to v4.8.0+:**

- Chinese karaoke word timing (CJK word boundaries require tokenization)
- Mixed CJK/English per-sentence routing (sentence splitting + engine routing + audio concatenation)
- Multi-language TTS beyond Chinese
- Caption search/filtering (NSTextView cmd+F natively; sufficient)
- Animated bionic text transitions (spike 17: animations fatigue users in long-form content)
- Caption history disk persistence (privacy concerns; ring buffer sufficient)
- SwiftUI migration (NSHostingView bridging overhead for zero UI benefit)

**Research caveat on bionic reading:** 2025 peer-reviewed eye-tracking studies (PMC, SAGE) found bionic reading does NOT significantly improve reading speed for general users. ADHD-specific 27% improvement is reported (Myndset Therapeutics). Position as an optional preference, not a scientifically proven speed enhancement.

### Architecture Approach

See [ARCHITECTURE.md](./ARCHITECTURE.md) for full component diagrams, actor migration steps with before/after code, data flow sequences, and anti-patterns with explanations.

The migration follows the "Extract-and-Delegate" pattern: the existing `TTSEngine` becomes a thin facade that delegates to new actor-isolated components. All current call sites continue calling the same `TTSEngine` API — zero caller changes required during decomposition. The streaming pipeline converts from callback pairs (`onChunkReady + onAllComplete`) to `AsyncStream<ChunkResult>`, which eliminates the `NSLock`-protected `firstChunkDispatched` flag in `TelegramBot`. Chinese TTS integration uses a `Synthesizer` protocol so `LanguageDetector` can route to `KokoroMLXSynthesizer` (English) or `SherpaOnnxSynthesizer` (Chinese) without modifying the existing synthesis path.

**Major components:**

1. `CompanionCore` (library target, testable) — all business logic: `WordTimingAligner`, `PronunciationProcessor`, `SynthesisEngine`, `TTSCircuitBreaker`, `BionicRenderer`, `CaptionHistory`, `LanguageDetector`, `Config`, `NotificationProcessor`
2. `SynthesisEngine` (actor) — model loading, audio generation, streaming pipeline; wraps blocking C FFI via dedicated `DispatchQueue` bridged to async via `withCheckedThrowingContinuation` — never blocks cooperative thread pool
3. `PlaybackManager` (@MainActor) — AVAudioPlayer lifecycle, hardware warm-up, pre-buffering; owned by the executable target, not the library
4. `TTSEngine` (facade class) — preserves existing public API while delegating to decomposed actors; becomes stateless after migration
5. `CaptionHistoryPanel` (@MainActor, new) — NSScrollView + NSTextView; auto-scroll with Google Meet "Jump to bottom" pattern; non-activating
6. `FocusMonitor` (new) — reads `Assertions.json` via `DispatchSource`; `FocusDetecting` protocol allows future public API swap
7. `BionicRenderer` (pure struct, new) — bold first `ceil(len * ratio)` chars per word; composes with `SubtitleStyle`; fully testable

**Key architectural decisions:**

- `CompanionCore` library extraction is the mandatory first step — blocks all testing without it
- Blocking TTS synthesis stays on `DispatchQueue(label: "tts")` bridged via `withCheckedThrowingContinuation` — never in the cooperative thread pool
- Bionic and karaoke are mutually exclusive display modes (single `DisplayMode` enum) — not composable booleans, to avoid Pitfall 9
- Chinese model uses load-on-demand, unload-on-idle strategy (30-second cooldown) — both models must never be loaded simultaneously

### Critical Pitfalls

See [PITFALLS.md](./PITFALLS.md) for all 15 pitfalls with detection signals, code samples, and phase warnings.

1. **SwiftPM cannot `@testable import` executable targets (Pitfall 3)** — this is a hard blocker that must be resolved first. Extract `CompanionCore` library, verify `swift test` runs with a trivial test, then proceed. Nothing else can be tested without this.
2. **Actor reentrancy silently breaks state invariants (Pitfall 1)** — every "read-await-write" pattern across an `await` is a potential bug after actor migration. Use synchronous state mutations, state machine enums for lazy init (`.unloaded`, `.loading(Task)`, `.loaded`), and never mix `NSLock` inside actors. The Swift 6 compiler does NOT catch reentrancy logic errors — only code review and testing do.
3. **Cooperative thread pool starvation (Pitfall 4)** — kokoro-ios and sherpa-onnx synthesis block for 3-7 seconds. An actor method calling blocking C FFI directly will starve the cooperative thread pool and freeze the entire app. Keep the dedicated `DispatchQueue` bridged to async via continuation.
4. **Dual TTS engine memory pressure (Pitfall 5)** — kokoro-ios (~561MB) + sherpa-onnx (~310MB) together push RSS above 800MB. Use load-on-demand with 30-second idle cooldown. Gate Chinese TTS behind a feature flag for initial release. Never load both models simultaneously.
5. **Focus/DND has no public macOS API (Pitfall 6)** — `Assertions.json` is private and may break on any macOS update. Wrap in `FocusDetecting` protocol. Consider manual SwiftBar toggle as primary UX, with file-based detection as best-effort automation. Build this feature last.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: CompanionCore Library + Test Infrastructure

**Rationale:** The SwiftPM executable-target testability limitation (Pitfall 3) is a hard blocker. Every subsequent phase requires `@testable import CompanionCore`. This is a one-time structural change that takes one session and unblocks all future work. Must be done before touching any logic.
**Delivers:** `CompanionCore` library target with all existing source files except `main.swift`; thin executable target with only boot wiring; `CompanionCoreTests` test target; `swift test` passing with unit tests for pure types (`WordTimingAligner`, `PronunciationProcessor`, `SubtitleChunker`, `LanguageDetector`).
**Addresses:** XCTest/Swift Testing infrastructure (table stakes feature)
**Avoids:** Pitfall 3 (cannot import executable), Pitfall 11 (parallel test interference — design for dependency injection from day one)
**Research flag:** Standard pattern — skip `/gsd:research-phase`. The exact Package.swift structure is documented in STACK.md and ARCHITECTURE.md.

### Phase 2: TTSEngine Decomposition + Actor Migration

**Rationale:** TTSEngine is a god object that owns all mutable state. Every new feature (Chinese TTS, Focus/DND audio suppression, streaming improvements) requires either modifying TTSEngine directly or depending on its decomposed sub-components. Decomposition must precede feature delivery. The 7-step migration sequence in ARCHITECTURE.md (pure types first, then actors, then facade, then AsyncStream) provides the safe incremental path.
**Delivers:** `WordTimingAligner`, `PronunciationProcessor` as pure structs; `TTSCircuitBreaker`, `SynthesisEngine` as actors; `PlaybackManager` as @MainActor class; `TTSEngine` as stateless facade; `AsyncStream`-based streaming pipeline replacing callback pairs; unit tests for all extracted components; `@unchecked Sendable` removed from TTSEngine.
**Addresses:** Actor-based concurrency (table stakes), TTSEngine decomposition (table stakes), streaming pipeline hardening
**Avoids:** Pitfall 1 (reentrancy), Pitfall 2 (MainActor deadlock), Pitfall 4 (thread pool starvation), Pitfall 7 (Sendable cascade — migrate one class at a time), Pitfall 15 (init race — TaskGroup to sequence actor setup)
**Research flag:** Recommend a pre-migration audit session to enumerate every "read-await-write" pattern in TTSEngine before writing code. Actor reentrancy bugs are not caught by Swift 6 — only code review and tests catch them.

### Phase 3: Bionic Reading Mode

**Rationale:** Lowest complexity of the four new features. Fully independent of Chinese TTS and Focus/DND. Requires only `CompanionCore` to exist (Phase 1 complete). Ships fast, delivers user-facing value, and validates the `NSAttributedString` composition approach before caption history (Phase 4) reuses the same technique.
**Delivers:** `BionicRenderer` pure struct in `CompanionCore`; HTTP API toggle (`POST /subtitle/bionic`); Telegram bot toggle; light/medium/heavy intensity presets; `SubtitlePanel` integration with `DisplayMode` enum enforcing karaoke mutual exclusion; unit tests for all range calculations.
**Addresses:** Bionic reading mode (differentiator feature)
**Avoids:** Pitfall 9 (bionic + karaoke conflict — single `DisplayMode` enum enforces mutual exclusion); NSRange off-by-one on multi-byte characters (test with emoji and CJK from the start)
**Research flag:** Standard pattern — skip research. Algorithm is ~15 lines, fully documented with code in STACK.md and FEATURES.md.

### Phase 4: Caption History Panel

**Rationale:** `CaptionHistory` ring buffer already exists. The new work is the `NSScrollView + NSTextView` panel and the Google Meet auto-scroll UX pattern. Medium complexity, independent of Chinese TTS. Building after bionic reading (Phase 3) lets the team warm up on AppKit attributed string work before the more complex scroll UX.
**Delivers:** `CaptionHistoryPanel` @MainActor NSPanel with auto-scroll and "Jump to bottom" button; HH:MM timestamps on entries; click-to-copy per line and "Copy All"; `POST /captions/panel/toggle` HTTP endpoint; non-activating, floating panel positioned right of screen; `copy:` override to strip NSAttributedString formatting.
**Addresses:** Scrollable caption history panel (differentiator feature)
**Avoids:** Pitfall 8 (NSScrollView bottom-pin jitter — `isAtBottom` check before auto-scroll, batch appends every 500ms, disable animation during rapid updates); Pitfall 12 (memory growth — cap at 500 entries, store plain text, render `NSAttributedString` only for visible entries); Pitfall 14 (copy includes formatting — override `copy:` to write plain text to `NSPasteboard`)
**Research flag:** Prototype the scroll behavior before building the full panel. NSScrollView bottom-pinning with rapid appends (one per ~200ms during playback) is a known AppKit pain point. Validate the `isAtBottom` check + batch append pattern works in isolation.

### Phase 5: Chinese TTS Fallback

**Rationale:** Requires TTSEngine decomposition (Phase 2) to have defined the `Synthesizer` protocol that `SherpaOnnxSynthesizer` conforms to. Depends on `SynthesisEngine` actor routing through `LanguageDetector`. Medium complexity but the highest memory risk of the four features. The load-on-demand strategy needs explicit design before any code is written.
**Delivers:** `SherpaOnnxSynthesizer` implementing `Synthesizer` protocol; `SynthesisEngine` routing based on `LanguageDetector` CJK threshold; default Chinese voice (zf_xiaobei, sid=45); load-on-demand model lifecycle with 30-second idle cooldown; feature flag (`Settings.chineseTTSEnabled`) for safe rollout; plain-text Chinese subtitles (no karaoke — `wordTimings` is optional nil for CJK).
**Addresses:** Chinese TTS fallback (differentiator feature)
**Avoids:** Pitfall 5 (dual model memory — never load both; unload before loading the other); Pitfall 10 (CJK no word timestamps — `TTSResult.wordTimings` is optional, proportional character timing as fallback); Pitfall 13 (language switch latency — buffer consecutive-language text, 30-second cooldown keeps current model loaded)
**Research flag:** Spike CJK synthesis quality before committing. Validate that sherpa-onnx kokoro-multi-lang-v1_0 produces intelligible Chinese output on this Apple Silicon hardware before building the routing infrastructure. The English pipeline is proven by spikes; CJK is untested.

### Phase 6: Focus/DND Awareness

**Rationale:** Highest implementation risk (undocumented private macOS file API breakable by any OS update) and lowest urgency (users can manually pause via SwiftBar). Build last after all other features are shipped and stable. The `FocusDetecting` protocol wrapping enables a clean swap to a future public Apple API.
**Delivers:** `FocusMonitor` wrapping `DispatchSource` file watching of `~/Library/DoNotDisturb/DB/Assertions.json`; audio suppression via `PlaybackManager.suppressAudio()`; subtitle-only fallback (SubtitleSyncDriver already supports this mode); `focusMode: String?` field added to HTTP `/status` response; graceful fail-open on file parse failure (log warning, assume Focus inactive, never crash).
**Addresses:** Focus/DND awareness (differentiator feature)
**Avoids:** Pitfall 6 (no public API — wrap in `FocusDetecting` protocol, fail-open for audio, validate JSON schema on each read, log warning on missing file)
**Research flag:** Consider offering the SwiftBar manual toggle as v1 and promoting automatic detection to v4.8.0 if the file-based approach proves unreliable. Apple has explicitly closed the public API request as "won't fix."

### Phase Ordering Rationale

- Phase 1 is a hard prerequisite for every other phase — without `CompanionCore`, nothing can be tested
- Phase 2 is a hard prerequisite for Phase 5 (Chinese TTS needs the `Synthesizer` protocol from `SynthesisEngine`) and Phase 6 (Focus/DND audio suppression needs isolated `PlaybackManager`)
- Phases 3 and 4 are independent of each other and of Phases 5 and 6 — they can be worked in parallel with Phase 2 if bandwidth allows, provided `CompanionCore` exists
- Phase 6 is deliberately last because it has the weakest API foundation and lowest urgency for user value

### Research Flags

Phases likely needing `/gsd:research-phase` during planning:

- **Phase 2 (Actor Migration):** Pre-migration audit of every "read-await-write" pattern in TTSEngine is necessary before any code is written. The 7-step migration sequence in ARCHITECTURE.md is the starting point, but actor reentrancy bugs are not caught by the Swift 6 compiler — only code review and tests catch them.
- **Phase 5 (Chinese TTS):** CJK synthesis quality via sherpa-onnx kokoro-multi-lang-v1_0 is untested on this hardware. Run a local listening test before building the routing infrastructure to validate voice quality and confirm the 24kHz audio pipeline requires no changes.

Phases with standard patterns (skip research-phase):

- **Phase 1 (Library extraction):** Exact Package.swift structure is documented in STACK.md and ARCHITECTURE.md. Mechanical change with one success criterion: `swift test` passes.
- **Phase 3 (Bionic reading):** Algorithm is ~15 lines, fully documented with code samples. No research needed.
- **Phase 4 (Caption history):** NSScrollView + NSTextView pattern documented with specific AppKit configuration flags in STACK.md. Prototype scroll behavior before full build.
- **Phase 6 (Focus/DND):** Research has already identified the only viable approach and its limitations. The decision between automatic detection and manual toggle does not require additional research.

## Confidence Assessment

| Area         | Confidence | Notes                                                                                                                                                                                  |
| ------------ | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Stack        | HIGH       | Zero new SPM dependencies. All additions are built-in Swift/macOS or existing sherpa-onnx data files. Validated by multiple spikes.                                                    |
| Features     | HIGH       | Table stakes features are unambiguous. Differentiator features are well-scoped with clear complexity and dependency mapping. Bionic reading research caveats are documented honestly.  |
| Architecture | HIGH       | Grounded in official Swift Evolution proposals (SE-0306, SE-0337), SwiftPM GitHub issues (#7596), and the existing codebase's validated patterns from spikes 03/09/16/19.              |
| Pitfalls     | HIGH       | Actor reentrancy, thread pool starvation, SwiftPM testability limits all sourced from authoritative documents. Focus/DND limitation confirmed by Apple (Feedback closed as won't fix). |

**Overall confidence:** HIGH

### Gaps to Address

- **CJK synthesis quality (MEDIUM confidence):** No spike has validated sherpa-onnx kokoro-multi-lang-v1_0 Chinese voice output on this Apple Silicon hardware. Run a quick local test before Phase 5 planning begins. If quality is poor, the feature may not be worth shipping.
- **Memory unload behavior after nil-assignment:** The load-on-demand strategy assumes ARC promptly reclaims kokoro-ios MLX GPU buffers after `ttsInstance = nil`. Validate with `task_info()` RSS logging before relying on this in production. A memory leak in the unload path would make dual-language sessions unusable.
- **Focus/DND JSON schema stability:** `Assertions.json` schema is undocumented. A macOS update could silently change the format. Validate JSON schema on every read; log a warning (not crash) on unexpected structure; fail-open for audio.
- **Swift 6.2 adoption timing:** ARCHITECTURE.md notes that `defaultIsolation: MainActor` in Swift 6.2 would simplify the codebase. Current milestone targets Swift 6.0 strict mode. If toolchain upgrades during development, evaluate whether 6.2 adoption is worth the mid-milestone disruption.

## Sources

### Primary (HIGH confidence)

- SE-0306: Actors — canonical actor semantics, reentrancy design rationale
- SE-0337: Incremental Migration to Concurrency Checking — migration strategy for @unchecked Sendable codebases
- SwiftPM GitHub #7596 — executable target testability limitation (open since 2023, no planned fix)
- sherpa-onnx Kokoro multilingual models documentation — Chinese voice IDs, model configuration, C API compatibility
- Apple Developer Forums thread 100511 — Apple confirms no public DND/Focus API, closed as won't fix
- Spikes 02, 03, 04, 09, 10, 15, 16, 17, 19, 21 — local validated performance and design data (RSS figures, model load times, word timing accuracy, panel behavior)

### Secondary (MEDIUM confidence)

- Jared Sinclair: Beware @unchecked Sendable — migration cascade pitfall patterns
- Massicotte: Problematic Swift Concurrency Patterns — thread pool starvation from blocking C FFI
- avanderlee: MainActor dispatch patterns — MainActor isolation and cross-actor communication
- text-vide (OSS) — confirms bionic reading algorithm is "bold first half of word"
- Google Workspace blog: Scrollable Live Captions in Meet (Feb 2025) — Google Meet auto-scroll UX pattern that set the industry standard
- PMC / SAGE 2025 bionic reading eye-tracking studies — mixed results for general users; ADHD benefits reported
- ONNX Runtime #3802 — ONNX model memory consumption, extrapolated for dual-load scenario

### Tertiary (LOW confidence)

- drewkerr JXA gist — `Assertions.json` + `ModeConfigurations.json` file paths for Focus detection (undocumented, no stability guarantee)
- Community Focus/DND workarounds — confirms file path approach, multiple independent reporters

---

_Research completed: 2026-03-27_
_Ready for roadmap: yes_
