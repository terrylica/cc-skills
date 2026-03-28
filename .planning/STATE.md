---
gsd_state_version: 1.0
milestone: v4.7.0
milestone_name: Architecture Hardening + Feature Expansion
status: verifying
stopped_at: Completed 20-01-PLAN.md
last_updated: "2026-03-28T02:31:16.950Z"
last_activity: 2026-03-28
progress:
  total_phases: 17
  completed_phases: 16
  total_plans: 33
  completed_plans: 32
  percent: 0
---

<!-- # SSoT-OK -->

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-27)

**Core value:** See what Claude says, anywhere -- real-time karaoke subtitles synced with TTS playback
**Current focus:** Phase 20 — unit-integration-tests

## Current Position

Phase: 20
Plan: Not started
Status: Phase complete — ready for verification
Last activity: 2026-03-28

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 32
- Average duration: ~3 min
- Total execution time: ~1.5 hours

**By Phase (v4.6.0):**

| Phase | Plans | Total | Avg/Plan |
| ----- | ----- | ----- | -------- |
| 11    | 2     | 5min  | 2.5min   |
| 12    | 2     | 6min  | 3min     |
| 13    | 2     | 6min  | 3min     |
| 14    | 2     | 3min  | 1.5min   |
| 15    | 2     | 6min  | 3min     |
| 16    | 1     | 2min  | 2min     |
| 17    | 2     | 3min  | 1.5min   |

**Recent Trend:**

- Last 5 plans: 2min, 5min, 1min, 2min, 1min
- Trend: Stable (~2.5min average)

| Phase 20.1 P01 | 6min | 2 tasks | 7 files |
| Phase 18 P01 | 8min | 2 tasks | 33 files |
| Phase 18 P02 | 6min | 2 tasks | 6 files |
| Phase 19 P01 | 10min | 2 tasks | 7 files |
| Phase 19 P02 | 11min | 2 tasks | 7 files |
| Phase 20-unit-integration-tests P02 | 3min | 2 tasks | 2 files |
| Phase 20 P01 | 3min | 2 tasks | 3 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Phase 17]: Generation counter pattern for interruption-safe work item scheduling in SubtitlePanel
- [Phase 16]: NSLock for thread safety (consistent with codebase -- to be replaced by actors in Phase 19)
- [v4.7.0]: CompanionCore library extraction must be first phase (SwiftPM cannot @testable import executable targets)
- [v4.7.0]: Blocking TTS synthesis stays on dedicated DispatchQueue bridged via withCheckedThrowingContinuation
- [v4.7.0]: Bionic and karaoke are mutually exclusive display modes (single DisplayMode enum)
- [v4.7.0]: Chinese model uses load-on-demand with 30-second idle cooldown
- [Phase 19]: PlaybackDelegate uses @MainActor with nonisolated(unsafe) let and nonisolated init for Swift 6 compatibility
- [Phase 19]: MToken type is in MLXUtilsLibrary (not KokoroSwift) -- extracted types import accordingly
- [Phase 20.1]: exit(42) as restart signal for IOAccelerator memory reclaim via launchd KeepAlive
- [Phase 20.1]: Max 10 synthesis calls before process restart (~17GB worst case fits 32GB RAM)
- [Phase 18]: CompanionApp @MainActor init/start/shutdown for SubtitlePanel compatibility
- [Phase 18]: MemoryLifecycle module-level callback registration pattern for cross-module restart
- [Phase 18]: swift-testing package dependency for test infrastructure (CommandLineTools lacks built-in Testing module)
- [Phase 19]: synthesizeStreaming changed from callback-based to return-based API for Swift 6 actor compatibility
- [Phase 19]: writeWav made static on TTSEngine actor for non-isolated DispatchQueue access
- [Phase 20-unit-integration-tests]: Closure syntax for whereSeparator in tests (Swift 6 key path type inference limitation)
- [Phase 20]: SentenceSplitter abbreviation detection only covers single-uppercase-letter patterns -- tests document actual behavior

### Pending Todos

None yet.

### Blockers/Concerns

- Actor reentrancy bugs are NOT caught by Swift 6 compiler -- only code review and tests catch them
- CJK synthesis quality via sherpa-onnx kokoro-multi-lang-v1_0 is untested on this hardware
- Focus/DND relies on undocumented macOS private file -- deferred to future milestone

### Quick Tasks Completed

| #          | Description                                                       | Date       | Commit   | Directory                                                                                                           |
| ---------- | ----------------------------------------------------------------- | ---------- | -------- | ------------------------------------------------------------------------------------------------------------------- |
| 260326-fvh | Deploy claude-tts-companion as unified launchd service            | 2026-03-26 | f8196055 | [260326-fvh-deploy-tts-companion](./quick/260326-fvh-deploy-tts-companion/)                                         |
| 260326-n1n | Upgrade ty hook: --python-version 3.13, concise output, Stop hook | 2026-03-26 | af5afb8d | [260326-n1n-upgrade-ty-hook-python-version-concise-o](./quick/260326-n1n-upgrade-ty-hook-python-version-concise-o/) |
| 260327-0rt | AVAudioPlayer + CADisplayLink subtitle sync (replace afplay)      | 2026-03-27 | 7ec4d6a0 | [260327-0rt-replace-afplay-with-avaudioplayer-plus-c](./quick/260327-0rt-replace-afplay-with-avaudioplayer-plus-c/) |
| 260327-c6s | Research: MLX Metal GPU for Kokoro TTS                            | 2026-03-27 | —        | [260327-c6s-replace-sherpa-onnx-with-mlx-metal-gpu-f](./quick/260327-c6s-replace-sherpa-onnx-with-mlx-metal-gpu-f/) |
| 260327-d2e | Replace sherpa-onnx with kokoro-ios MLX Metal TTS engine          | 2026-03-27 | f9a4475a | [260327-d2e-replace-sherpa-onnx-with-kokoro-ios-mlx-](./quick/260327-d2e-replace-sherpa-onnx-with-kokoro-ios-mlx-/) |
| 260327-d2e | Replace sherpa-onnx with kokoro-ios MLX Metal GPU TTS             | 2026-03-27 | cfa3d898 | [260327-d2e-replace-sherpa-onnx-with-kokoro-ios-mlx-](./quick/260327-d2e-replace-sherpa-onnx-with-kokoro-ios-mlx-/) |

### Roadmap Evolution

- Phase 20.1 inserted after Phase 20: MLX Metal Memory Lifecycle (URGENT) — MLX-Swift creates ~1.7-6GB unreclaimable IOAccelerator allocations per synthesis call; service disabled until fix is implemented

## Session Continuity

Last session: 2026-03-28T02:27:24.314Z
Stopped at: Completed 20-01-PLAN.md
Resume file: None
