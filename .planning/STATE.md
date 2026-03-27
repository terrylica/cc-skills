---
gsd_state_version: 1.0
milestone: v4.5.0
milestone_name: MVP
status: verifying
stopped_at: Completed 17-02-PLAN.md
last_updated: "2026-03-27T05:09:18.956Z"
last_activity: 2026-03-27
progress:
  total_phases: 7
  completed_phases: 7
  total_plans: 13
  completed_plans: 13
  percent: 59
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-26)

**Core value:** See what Claude says, anywhere -- real-time karaoke subtitles synced with TTS playback
**Current focus:** Phase 17 — tts-streaming-subtitle-chunking

## Current Position

Phase: 17
Plan: Not started
Status: Phase complete — ready for verification
Last activity: 2026-03-27

Progress: [██████░░░░] 59% (v4.5.0 phases largely complete, v4.6.0 starting)

## Performance Metrics

**Velocity:**

- Total plans completed: 19
- Average duration: ~3 min
- Total execution time: ~1 hour

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
| ----- | ----- | ----- | -------- |
| 01    | 2     | 6min  | 3min     |
| 02    | 2     | 5min  | 2.5min   |
| 03    | 1     | 6min  | 6min     |
| 06    | 2     | 10min | 5min     |
| 07    | 2     | 4min  | 2min     |
| 08    | 1     | 2min  | 2min     |
| 10    | 1     | 4min  | 4min     |

**Recent Trend:**

- Last 5 plans: 2min, 2min, 2min, 4min, 4min
- Trend: Stable (~3min average)

| Phase 11 P01 | 3min | 1 tasks | 1 files |
| Phase 11 P02 | 2min | 2 tasks | 2 files |
| Phase 12 P01 | 3min | 1 tasks | 2 files |
| Phase 12 P02 | 3min | 1 tasks | 1 files |
| Phase 13 P01 | 4min | 1 tasks | 2 files |
| Phase 13 P02 | 2min | 2 tasks | 2 files |
| Phase 14 P01 | 1min | 1 tasks | 3 files |
| Phase 14 P02 | 2min | 2 tasks | 1 files |
| Phase 15 P01 | 5min | 2 tasks | 3 files |
| Phase 15 P02 | 1min | 2 tasks | 0 files |
| Phase 16 P01 | 2min | 2 tasks | 3 files |
| Phase 17 P01 | 2min | 2 tasks | 3 files |
| Phase 17 P02 | 1min | 2 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Phase 10]: Ring buffer capacity 100 for caption history
- [Phase 08]: FlyingFox 0.26.2 for HTTP server (pure BSD sockets, zero SwiftNIO)
- [Phase 07]: Shared MiniMaxClient between SummaryEngine and AutoContinueEvaluator
- [Phase 07]: Default to DONE on evaluation error to prevent runaway auto-continue loops
- [v4.6.0]: Port directly from legacy TypeScript -- don't reinvent
- [Phase 11]: Used NSRegularExpression for HTML tag walker in wrapFileReferencesInHtml (Swift Regex requires macOS 13+)
- [Phase 11]: Tail Brief sent as separate silent Telegram message (disableNotification: true) matching legacy TS
- [Phase 12]: TranscriptParser owns its own stripSkillExpansion (matching legacy TS architecture)
- [Phase 12]: Use Swift unicode escapes for em dashes in prompt templates (explicit, grep-friendly)
- [Phase 13]: Snake-case CodingKeys on AutoContinueState for backward compat with legacy TS state files
- [Phase 13]: All auto-continue notifications sent as silent messages to avoid push spam
- [Phase 14]: Unicode scalars (not Character) for CJK detection -- correct abstraction for code point ranges
- [Phase 14]: TTS greeting computed inline using formatProjectName, not from SummaryEngine.ttsGreeting
- [Phase 15]: Inline counts computed inline rather than adding summarize() to TranscriptParser
- [Phase 15]: Logger changed from private to fileprivate for BotDispatcher callback handler access
- [Phase 15]: No new code changes needed for Plan 02 -- Plan 01 executor already wired main.swift itermSessionId + transcriptPath
- [Phase 16]: Ported dedup/rate-limit from legacy TS; used NSLock for thread safety (consistent with codebase)
- [Phase 17]: Bottom-heavy line preference: shorter first line via clause/phrase break backtracking
- [Phase 17]: Generation counter pattern for interruption-safe work item scheduling in SubtitlePanel
- [Phase 17]: 2-line replacement: showUtterance() replaced with chunkIntoPages() + showPages() in dispatchTTS()

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 3 (TTS): Word-to-phoneme alignment across diverse text is untested beyond Spike 16
- v4.6.0: Reference source is ~/.claude/automation/claude-telegram-sync/ -- must audit line-by-line for feature parity

### Quick Tasks Completed

| #          | Description                                                       | Date       | Commit   | Directory                                                                                                           |
| ---------- | ----------------------------------------------------------------- | ---------- | -------- | ------------------------------------------------------------------------------------------------------------------- |
| 260326-fvh | Deploy claude-tts-companion as unified launchd service            | 2026-03-26 | f8196055 | [260326-fvh-deploy-tts-companion](./quick/260326-fvh-deploy-tts-companion/)                                         |
| 260326-n1n | Upgrade ty hook: --python-version 3.13, concise output, Stop hook | 2026-03-26 | af5afb8d | [260326-n1n-upgrade-ty-hook-python-version-concise-o](./quick/260326-n1n-upgrade-ty-hook-python-version-concise-o/) |
| 260327-d2e | Replace sherpa-onnx with kokoro-ios MLX Metal GPU TTS             | 2026-03-27 | cfa3d898 | [260327-d2e-replace-sherpa-onnx-with-kokoro-ios-mlx-](./quick/260327-d2e-replace-sherpa-onnx-with-kokoro-ios-mlx-/) |

## Session Continuity

Last session: 2026-03-27T16:28:25Z
Stopped at: Completed 260327-d2e-PLAN.md
Resume file: None
