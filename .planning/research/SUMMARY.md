# Project Research Summary

**Project:** claude-tts-companion
**Domain:** macOS native background service — unified Swift TTS/subtitle/Telegram bot companion
**Researched:** 2026-03-25
**Confidence:** HIGH

## Executive Summary

This project replaces three separate runtime processes (TypeScript Telegram bot, Python TTS pipeline, Swift subtitle overlay prototype) with a single Swift 6 binary running as a macOS LaunchAgent. The approach is well-validated: 23 spikes have proven every critical subsystem independently — sherpa-onnx Kokoro TTS at 561MB peak RSS, NSPanel karaoke overlay at 6us/word, swift-telegram-sdk long polling without Vapor, and the hub-and-spoke concurrency model with zero deadlocks. The stack has only 3 SwiftPM dependencies plus system frameworks and pre-built static libraries. This is not a speculative project; it is an integration and hardening effort.

The recommended approach is a phased build following the proven architecture from Spikes 08 and 10: an event-driven coordinator where a `@MainActor` AppState hub serializes all shared state, background subsystems (bot, TTS, HTTP, file watcher) run on dedicated queues, and the main thread is reserved exclusively for AppKit UI. The build order is dictated by dependencies: foundation/build system first, then subtitle overlay (validates NSApplication coexistence), then TTS engine, then Telegram bot, then full integration with HTTP API and file watchers, then deployment with atomic cutover.

The primary risks are (1) the all-or-nothing rollout — one subsystem crash takes down all three services, mitigated by per-subsystem feature flags and fast rollback scripts; (2) the Telegram bot token conflict during cutover — only one consumer can long-poll a token, requiring atomic switchover; and (3) feature parity drift when porting 4,500 lines of battle-tested TypeScript bot logic, mitigated by golden test fixtures captured from production. All six critical pitfalls have been observed in spikes and have proven solutions.

## Key Findings

### Recommended Stack

The stack is Swift 6 on macOS 14+, built with SwiftPM (no Xcode project). The entire dependency tree is remarkably small: swift-telegram-sdk for the bot, swift-log for logging (already a transitive dep), and sherpa-onnx as pre-built static libraries. Everything else — AppKit, AVFoundation, URLSession, DispatchSource — is system frameworks. See [STACK.md](./STACK.md) for full details.

**Core technologies:**

- **Swift 6 / SwiftPM**: Unifies three runtimes into one binary; strict concurrency checking prevents data races across the multi-threaded architecture
- **sherpa-onnx 1.12.33 (static)**: Kokoro int8 TTS — 129MB model, 561MB peak RSS, word-level timestamps via ~50-line C++ patch
- **swift-telegram-sdk 4.5.0**: Long polling without Vapor/SwiftNIO; 4.5MB binary contribution, 8.6MB RSS
- **AppKit NSPanel**: 88KB, 19MB RSS subtitle overlay; `sharingType = .none` for screen sharing privacy
- **BSD sockets (raw)**: HTTP control API for SwiftBar integration; upgrade to FlyingFox only if endpoints exceed 4-5
- **DispatchSource + FSEvents**: File watching and SIGTERM handling; zero dependencies

**Binary targets:** ~19-25MB stripped, 27MB idle RSS, 561MB peak during synthesis.

### Expected Features

See [FEATURES.md](./FEATURES.md) for the complete feature landscape with dependency graph.

**Must have (table stakes):**

- TTS playback via sherpa-onnx Kokoro — core audio value prop
- Subtitle overlay with word-level karaoke highlighting — core visual value prop
- Telegram bot with session notifications — replaces existing service
- AI session summaries via MiniMax — replaces existing pipeline
- JSONL transcript parsing — foundation for all content flow
- Screen sharing privacy (auto-hide) — one line, prevents critical failure
- Font/position/background presets — baseline UX expectations
- Single launchd service — the architectural goal

**Should have (differentiators):**

- HTTP control API — enables SwiftBar and automation ecosystem
- SwiftBar integration (claude-hq v3.0.0) — unified menu bar control surface
- Scrollable caption history and copy-to-clipboard
- Multi-monitor display selection
- Auto-continue hook with MiniMax evaluation

**Defer (out of scope):**

- CoreML/FluidAudio (3.9GB models), multi-language TTS, bionic reading, Sidecar iPad, GUI preferences, STT, WebSocket sync

### Architecture Approach

Single-binary accessory app using `NSApplication.setActivationPolicy(.accessory)` with an event-driven hub-and-spoke concurrency model. The `@MainActor` AppState coordinator owns all shared mutable state. Background subsystems (TelegramBot, TTSEngine, HTTPServer, FileWatcher) each run on dedicated threads/queues and dispatch state updates to main. This eliminates data races without locks. See [ARCHITECTURE.md](./ARCHITECTURE.md) for full component boundaries and data flow diagrams.

**Major components:**

1. **AppState** (`@MainActor`) — central state coordinator for all subsystem status
2. **SubtitlePanel** (`@MainActor`) — NSPanel overlay with NSAttributedString karaoke rendering
3. **TTSEngine** (`@unchecked Sendable` + serial DispatchQueue) — sherpa-onnx wrapper with lazy loading
4. **TelegramBot** (`Task.detached`) — long-polling bot with command dispatch
5. **HTTPServer** (DispatchQueue.global) — BSD socket API for external control
6. **FileWatcher** (DispatchSource) — monitors notification files and JSONL transcripts
7. **Config** (immutable value type) — paths, ports, tokens loaded at startup

### Critical Pitfalls

See [PITFALLS.md](./PITFALLS.md) for all 17 pitfalls with detailed prevention strategies.

1. **DispatchSource silent deallocation** — ARC kills file watchers stored as local variables with zero errors. Store all sources as long-lived properties. Add heartbeat assertions.
2. **NSApplication.run() must own main thread** — any blocking call on main freezes the subtitle overlay. Iron rule: main thread = UI only. All subsystems get their own queues.
3. **Bot token long-polling conflict** — two consumers on one token causes HTTP 409 and SIGKILL. Use a test token during development; atomic cutover script for rollout.
4. **561MB peak RSS during synthesis** — serialize all synthesis on a single queue; cap queue depth at 3-5; lazy model loading.
5. **All-or-nothing rollout** — one subsystem crash kills all three services. Per-subsystem feature flags (`--no-tts`, `--no-bot`), crash isolation with do/catch, fast rollback script.
6. **sherpa-onnx bridging header fragility** — vendor headers into the project, pin to exact commit hash.

## Implications for Roadmap

### Phase 1: Foundation and Build System

**Rationale:** Everything depends on Package.swift resolving with sherpa-onnx static libs + swift-telegram-sdk coexisting. Concurrency patterns must be established first and never violated. This phase has no user-visible output but prevents every critical pitfall.
**Delivers:** Compiling Package.swift, vendored sherpa-onnx headers, Config module, logging infrastructure (`setbuf` + swift-log), signal handling with dummy event pattern, DispatchSource lifecycle pattern.
**Addresses:** JSONL transcript parsing foundation, single launchd service skeleton.
**Avoids:** Pitfalls #1 (DispatchSource dealloc), #2 (main thread ownership), #6 (bridging header), #12 (stdout buffering), #14 (Agent vs Daemon).

### Phase 2: Subtitle Overlay

**Rationale:** The subtitle overlay is the novel feature and the reason the binary needs NSApplication at all. Building it second validates that background work coexists with the AppKit RunLoop in the real codebase.
**Delivers:** NSPanel with karaoke highlighting, font/position/background presets, word-wrap, screen sharing privacy, HTTP `/subtitle` endpoint for testing.
**Addresses:** Table stakes: subtitle overlay, word-level karaoke, font presets, position control, dark background, word-wrap, screen sharing privacy.
**Avoids:** Pitfall #2 (main thread starvation), #10 (NSApp.stop hang).

### Phase 3: TTS Engine

**Rationale:** TTS depends on the foundation layer (sherpa-onnx libs) and feeds timestamps to the subtitle overlay (Phase 2). Must be built before the bot (Phase 4) because `/tts` commands depend on it.
**Delivers:** TTSEngine with lazy model loading, serial synthesis queue, word timestamp extraction, audio playback via AVAudioPlayer/afplay, queue depth monitoring.
**Addresses:** Table stakes: TTS playback. Differentiator: pipelined synthesis.
**Avoids:** Pitfall #4 (561MB RSS), #9 (phonemization gap), #13 (thread pool exhaustion), #15 (afplay zombies).

### Phase 4: Telegram Bot

**Rationale:** The bot is the most complex port (4,500 lines of production-hardened TypeScript). It requires TTSEngine and SubtitlePanel to be functional for testing commands. Must use a separate test token during development.
**Delivers:** Long-polling bot, command handlers (/tts, /subtitle, /session, /ping), noise-filter patterns, fence-aware HTML chunking, safe message editing with fallback.
**Addresses:** Table stakes: Telegram bot integration, AI session summaries.
**Avoids:** Pitfall #3 (token conflict), #8 (TGBot Sendable), #11 (feature parity drift), #17 (HTML parse errors).

### Phase 5: Integration and HTTP API

**Rationale:** All subsystems must work independently before wiring through AppState. This phase replicates Spike 10's proven concurrency model at full scale.
**Delivers:** Full AppState coordinator, HTTP control API (health, settings, subtitle, TTS endpoints), file watcher for notifications, JSONL tailing for thinking watcher, end-to-end data flow.
**Addresses:** Differentiators: HTTP control API, JSONL thinking watcher, file-based notifications.
**Avoids:** Pitfall #5 (all-or-nothing) via feature flags and crash isolation.

### Phase 6: Deployment and SwiftBar

**Rationale:** Deployment is last because it requires all subsystems working. The rollout is inherently risky (token conflict, all-or-nothing) and needs the rollback infrastructure.
**Delivers:** launchd plist, atomic cutover script, rollback script, SwiftBar claude-hq v3.0.0 update, smoke test on launch, multi-monitor display selection.
**Addresses:** Differentiators: SwiftBar integration, multi-monitor selection. Table stakes: single launchd service.
**Avoids:** Pitfall #3 (token conflict during cutover), #5 (all-or-nothing rollout).

### Phase Ordering Rationale

- **Foundation first** because every other phase depends on the build system and concurrency patterns being correct. A wrong concurrency decision in Phase 1 causes rewrites in every subsequent phase.
- **Subtitle before TTS** because the overlay validates NSApplication.run() coexistence — the hardest architectural question. TTS is "just" a C library wrapper by comparison.
- **TTS before Bot** because the bot's `/tts` command is the primary integration point. You cannot test bot commands without a working TTS engine.
- **Bot before Integration** because the bot is the riskiest port (4,500 lines, 17 noise filters, fence-aware chunking). It needs focused attention, not integration distractions.
- **Integration before Deployment** because wiring subsystems through AppState will surface concurrency bugs that must be fixed before going live.

### Research Flags

Phases likely needing deeper research during planning:

- **Phase 3 (TTS Engine):** Word-level timestamp extraction via the C++ patch is validated in spike 16, but word-to-phoneme alignment across diverse text is untested. May need `/gsd:research-phase` for the phonemization mapping.
- **Phase 4 (Telegram Bot):** Feature parity audit of 4,500 lines of TypeScript. The 17 noise-filter patterns and fence-aware chunking need line-by-line porting analysis. Likely needs `/gsd:research-phase` to catalog every behavior.

Phases with standard patterns (skip research):

- **Phase 1 (Foundation):** Well-documented SwiftPM + C interop patterns. Spikes 08/10 provide exact code.
- **Phase 2 (Subtitle Overlay):** NSPanel pattern is validated in Spike 02. Karaoke rendering validated in Spike 19. No unknowns.
- **Phase 5 (Integration):** Spike 10 E2E flow is the exact blueprint. Replication, not invention.
- **Phase 6 (Deployment):** Standard launchd + SwiftBar patterns. Rollout script is straightforward.

## Confidence Assessment

| Area         | Confidence | Notes                                                                                                                                                        |
| ------------ | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Stack        | HIGH       | Every technology validated in at least one spike. Version numbers verified against current releases. Only 3 SwiftPM dependencies.                            |
| Features     | HIGH       | Feature landscape derived from 23 spikes + reference products (Apple Live Captions, Textream, GhostLayer). Clear MVP/differentiator/anti-feature separation. |
| Architecture | HIGH       | Hub-and-spoke concurrency model proven in Spike 10 with measured timings (82ms time-to-first-subtitle, zero deadlocks). Component boundaries well-defined.   |
| Pitfalls     | HIGH       | 6 critical pitfalls all observed in spikes with proven fixes. Phase-specific warnings mapped. Only gap: phonemization alignment (MEDIUM).                    |

**Overall confidence:** HIGH — This is one of the most thoroughly spiked projects possible. 23 spikes covering every subsystem, with measured performance numbers and proven concurrency patterns. The research is based on first-party spike data, not third-party blog posts.

### Gaps to Address

- **Phonemization word alignment:** Spike 16 proved duration tensor extraction but word-to-phoneme mapping across diverse text (punctuation, numbers, contractions) is untested. Fallback: proportional timing (divide duration by word count). Address during Phase 3 planning.
- **swift-telegram-sdk v4.5.0 migration:** Spikes used v3.x/4.x; the latest v4.5.0 API surface needs verification. The core `TGClientPrtcl` approach is stable, but method signatures may have changed. Address at Phase 4 start.
- **FlyingFox vs raw BSD sockets decision:** Start with raw sockets; evaluate FlyingFox if HTTP API grows beyond 5 endpoints. Not a gap — a deferred decision.
- **Feature parity completeness:** The TypeScript bot has 4,500 lines of edge-case handling. Some behaviors may not be cataloged in the spike reports. Capture golden test fixtures from production before starting Phase 4.

## Sources

### Primary (HIGH confidence)

- Spike 08: Integration Architecture — Package.swift, concurrency model, dependency analysis
- Spike 10: E2E Flow Report — zero-deadlock concurrency proof, 82ms TTFS
- Spike 02: Swift Subtitle Overlay — NSPanel, 88KB/19MB RSS
- Spike 04: Swift Telegram Bot — long polling, DispatchSource dealloc, token conflict
- Spike 03/09: sherpa-onnx TTS — synthesis validation, int8 quantization (561MB peak)
- Spike 16: ONNX Timestamps — duration tensor extraction, C++ patch
- Spike 19: Karaoke Highlighting — 6us/word, NSAttributedString
- Spike 21: Screen Sharing Privacy — `sharingType = .none`
- Spike 06: Feature Parity Audit — 4,500 lines TypeScript catalog

### Secondary (MEDIUM confidence)

- [swift-telegram-sdk v4.5.0](https://github.com/nerzh/swift-telegram-sdk) — single maintainer risk noted
- [FlyingFox v0.26.2](https://github.com/swhitty/FlyingFox) — deferred decision, not yet validated in spikes
- [Problematic Swift Concurrency Patterns](https://www.massicotte.org/problematic-patterns/) — thread pool exhaustion patterns

### Tertiary (LOW confidence)

- [sherpa-onnx memory leak issue #974](https://github.com/k2-fsa/sherpa-onnx/issues/974) — single issue report about memory growth in long-running processes; monitor RSS in production

---

_Research completed: 2026-03-25_
_Ready for roadmap: yes_
