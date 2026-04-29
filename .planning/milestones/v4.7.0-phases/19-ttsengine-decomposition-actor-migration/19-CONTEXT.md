# Phase 19: TTSEngine Decomposition & Actor Migration - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (--auto flag)

<domain>
## Phase Boundary

Decompose TTSEngine (1139-line god object) into isolated components with compile-time concurrency safety. TTSEngine becomes a thin stateless facade delegating to actor-isolated and pure-struct components. All `@unchecked Sendable` and `NSLock` usage eliminated.

</domain>

<decisions>
## Implementation Decisions

### Decomposition Boundaries (ARCH-02/03/04/05)

- **D-01:** PlaybackManager (@MainActor class) — owns AVAudioPlayer lifecycle, pre-buffering, warm-up, AudioStreamPlayer. Must be @MainActor because AVAudioPlayer delegate requires main run loop.
- **D-02:** WordTimingAligner (pure struct) — extractTimingsFromTokens(), alignOnsetsToWords(), resolveWordTimings(), extractWordTimings(), stripPunctuation(). All static methods, no mutable state.
- **D-03:** PronunciationProcessor (pure struct) — pronunciationOverrides, compiledOverrides, preprocessText(). All static/pure, no mutable state.
- **D-04:** TTSEngine becomes thin facade — delegates synthesis to internal model, playback to PlaybackManager, timing to WordTimingAligner, preprocessing to PronunciationProcessor. Holds no mutable state except actor-isolated synthesis state.
- **D-05:** SentenceSplitter (pure struct or free function) — splitIntoSentences() extracted from TTSEngine. Currently static, stays pure.
- **D-06:** PlaybackDelegate stays as-is — simple NSObject delegate, already in its own concern area.

### Actor Concurrency Model (CONC-01/02/03/04)

- **D-07:** TTSEngine migrates from `@unchecked Sendable + NSLock` to Swift `actor`. All mutable state (ttsInstance, voicesDict, voice, synthesisCount, circuitBreaker state) becomes actor-isolated.
- **D-08:** Blocking TTS synthesis (`tts.generateAudio()`) stays on dedicated DispatchQueue, bridged to actor via `withCheckedThrowingContinuation`. Per v4.7.0 decision — cooperative thread pool cannot handle blocking Metal calls.
- **D-09:** PlaybackManager is `@MainActor` (not actor) because AVAudioPlayer requires main thread.
- **D-10:** WordTimingAligner, PronunciationProcessor, SentenceSplitter are `Sendable` structs — no actor needed, no mutable state.

### API Surface

- **D-11:** Migrate callback-based synthesis methods to async/await (`async throws -> TTSResult`). Callers already use `Task { await ... }` patterns.
- **D-12:** All callers (TelegramBot, HTTPControlServer, SubtitleSyncDriver, CompanionApp) updated to use decomposed API. No behavior changes — same observable output.

### Claude's Discretion

- Whether to keep circuitBreaker state inside TTSEngine actor or extract to a separate CircuitBreaker actor
- Exact file organization (one file per component or grouped)
- Whether writeWav() moves to a utility or stays in TTSEngine
- Whether ChunkResult stays as nested type or becomes top-level

</decisions>

<canonical_refs>

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Source Code (current state)

- `plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift` — 1139-line god object to decompose
- `plugins/claude-tts-companion/Sources/CompanionCore/AudioStreamPlayer.swift` — AVAudioEngine wrapper (moves under PlaybackManager's ownership)
- `plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift` — Primary caller of TTSEngine streaming API
- `plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift` — Wiring coordinator, instantiates TTSEngine
- `plugins/claude-tts-companion/Sources/CompanionCore/MemoryLifecycle.swift` — Cross-module restart (references TTSEngine)
- `plugins/claude-tts-companion/Package.swift` — SwiftPM manifest

### Project Context

- `.planning/ROADMAP.md` — Phase 19 success criteria (ARCH-02 through ARCH-06, CONC-01 through CONC-04)
- `.planning/REQUIREMENTS.md` — v4.7.0 Architecture and Concurrency requirement definitions

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- `CircuitBreaker.swift` already exists as separate type — TTSEngine has its own inline circuit breaker that should delegate to this
- `AudioStreamPlayer.swift` — AVAudioEngine wrapper, likely becomes property of PlaybackManager
- Phase 18 established CompanionCore library pattern with `@testable import`

### Established Patterns

- `@unchecked Sendable + NSLock` for thread safety (to be replaced by actors)
- Callback-based APIs (`completion: @escaping (Result<T, Error>) -> Void`)
- `DispatchQueue(label:)` for background work
- `nonisolated(unsafe)` for global state in main.swift

### Integration Points

- `TelegramBot.swift` calls `ttsEngine.synthesizeStreaming()` and `ttsEngine.play()`
- `HTTPControlServer.swift` calls `ttsEngine.synthesize()` for test TTS endpoint
- `SubtitleSyncDriver.swift` calls `ttsEngine.synthesizeStreaming()` and `ttsEngine.preparePlayer()`
- `CompanionApp.swift` creates `TTSEngine()` and calls `synthesizeWithTimestamps()` for demo mode

</code_context>

<specifics>
## Specific Ideas

### TTSEngine Current Structure (decomposition map)

| Lines    | Concern                                       | Target Component                                                   |
| -------- | --------------------------------------------- | ------------------------------------------------------------------ |
| 1-17     | SynthesisResult, TTSResult structs            | Stay in TTSEngine (public API types)                               |
| 36-43    | TTSEngine class + @unchecked Sendable         | → actor TTSEngine                                                  |
| 44-88    | Mutable state (model, player, locks)          | → actor-isolated properties                                        |
| 89-131   | Pronunciation overrides                       | → PronunciationProcessor struct                                    |
| 132-235  | Memory lifecycle + circuit breaker            | → actor-isolated + existing CircuitBreaker                         |
| 237-267  | init/deinit                                   | → actor init                                                       |
| 279-439  | synthesize/synthesizeWithTimestamps           | → async throws methods on actor                                    |
| 440-601  | synthesizeStreaming                           | → async method with AsyncStream                                    |
| 603-667  | splitIntoSentences                            | → SentenceSplitter struct                                          |
| 669-700  | play/preparePlayer/stopPlayback               | → PlaybackManager @MainActor                                       |
| 702-925  | Word timing extraction/alignment              | → WordTimingAligner struct                                         |
| 927-1092 | Private helpers (warmUp, modelLoad, wavWrite) | Split: warmUp/play → PlaybackManager, model → actor, wav → utility |

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

_Phase: 19-ttsengine-decomposition-actor-migration_
_Context gathered: 2026-03-28 via --auto mode_
