---
gsd_state_version: 1.0
milestone: v4.9.0
milestone_name: SwiftBar UI & Telegram Bot Activation
status: executing
stopped_at: Completed 32-01-PLAN.md
last_updated: "2026-03-29T07:29:31.709Z"
last_activity: 2026-03-29
progress:
  total_phases: 29
  completed_phases: 28
  total_plans: 52
  completed_plans: 51
  percent: 0
---

<!-- # SSoT-OK -->

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-28)

**Core value:** See what Claude says, anywhere -- real-time karaoke subtitles synced with TTS playback
**Current focus:** Phase 32 — audio-device-resilience

## Current Position

Phase: 32 (audio-device-resilience) — EXECUTING
Plan: 2 of 2
Status: Ready to execute
Last activity: 2026-03-29

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 32
- Average duration: ~3 min
- Total execution time: ~1.5 hours

**By Phase (v4.8.0):**

| Phase                                 | Plans | Total | Avg/Plan |
| ------------------------------------- | ----- | ----- | -------- |
| 25 Python TTS Timestamp Endpoint      | 1     | 5min  | 5min     |
| 26 Swift TTSEngine Python Integration | 1     | 2min  | 2min     |
| 27 MLX Dependency Removal             | 1     | 4min  | 4min     |
| 28 Memory Lifecycle Cleanup           | 1     | 3min  | 3min     |

**Recent Trend:**

- Last 5 plans: 3min, 1min, 3min, 5min, 2min
- Trend: Stable (~3min average)

| Phase 30 P01 | 2min | 3 tasks | 1 files |
| Phase 32 P01 | 2min | 2 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v4.8.0]: Python MLX over Swift MLX -- IOAccelerator leak +2.3GB/call by design (ml-explore/mlx #1086)
- [v4.8.0]: Word timing non-negotiable -- karaoke highlighting requires per-word onset/duration
- [Phase 28]: healthResponse() made non-async -- no actor access needed after removing memoryDiagnostics
- [Phase 30]: Python TTS PID/RSS via pgrep+ps (server /health lacks process metrics)
- [Phase 30]: Bot 'unknown' mapped to 'disabled' (white dot) -- intentional config state, not error
- [Phase 32]: C function pointer HAL listener over block variant (Apple removal bug)
- [Phase 32]: Cached device ID approach over AudioUnit query for health check comparison

### Roadmap Evolution

- Phase 32 added: Audio Device Resilience — CoreAudio HAL listener + health check + engine rebuild for AVAudioEngine stale aggregate device (terrylica/cc-skills#73)

### Pending Todos

None yet.

### Blockers/Concerns

- Python MLX server must use `uv` for all Python tooling (user policy)
- Python 3.13 ONLY -- never use 3.14 or any other version (user policy)
- Bot credentials must exist at ~/.claude/.secrets/ccterrybot-telegram before Phase 29 execution

## Session Continuity

Last session: 2026-03-29T07:29:31.706Z
Stopped at: Completed 32-01-PLAN.md
Resume file: None
