---
gsd_state_version: 1.0
milestone: v4.8.0
milestone_name: Python MLX TTS Consolidation
status: roadmapped
stopped_at: Roadmap created for Phases 25-28
last_updated: "2026-03-28T06:00:00.000Z"
last_activity: 2026-03-28
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

<!-- # SSoT-OK -->

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-28)

**Core value:** See what Claude says, anywhere -- real-time karaoke subtitles synced with TTS playback
**Current focus:** v4.8.0 -- Python MLX TTS Consolidation (roadmapped, ready to plan Phase 25)

## Current Position

Phase: 25 of 28 (Python TTS Server Timestamp Endpoint)
Plan: Not yet planned
Status: Ready to plan
Last activity: 2026-03-28 -- Roadmap created for v4.8.0 (Phases 25-28)

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 32
- Average duration: ~3 min
- Total execution time: ~1.5 hours

**By Phase (v4.7.0):**

| Phase                           | Plans | Total | Avg/Plan |
| ------------------------------- | ----- | ----- | -------- |
| 18 CompanionCore Library        | 2     | 14min | 7min     |
| 19 TTSEngine Decomposition      | 2     | 21min | 10.5min  |
| 20 Unit & Integration Tests     | 2     | 6min  | 3min     |
| 20.1 MLX Metal Memory Lifecycle | 1     | 6min  | 6min     |
| 21 Pipeline Hardening           | 2     | 7min  | 3.5min   |
| 22 Bionic Reading Mode          | 2     | 6min  | 3min     |
| 23 Caption History Panel        | 2     | 4min  | 2min     |
| 24 Chinese TTS Fallback         | 2     | 8min  | 4min     |

**Recent Trend:**

- Last 5 plans: 3min, 1min, 3min, 3min, 5min
- Trend: Stable (~3min average)

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v4.8.0]: Python MLX over Swift MLX -- IOAccelerator leak +2.3GB/call by design (ml-explore/mlx #1086)
- [v4.8.0]: Python MLX over sherpa-onnx -- Kokoro durations field is NULL, no word timestamps
- [v4.8.0]: Python MLX over FluidAudio -- no word-level timestamp API, opaque CoreML graphs
- [v4.8.0]: Python MLX over Rust/candle -- no Kokoro implementation exists
- [v4.8.0]: Word timing non-negotiable -- karaoke highlighting requires per-word onset/duration
- [Phase 20.1]: exit(42) as restart signal for IOAccelerator memory reclaim via launchd KeepAlive (to be removed in Phase 28)

### Pending Todos

None yet.

### Blockers/Concerns

- Python MLX server must use `uv` for all Python tooling (user policy)
- Python 3.13 ONLY -- never use 3.14 or any other version (user policy)
- mlx-audio MToken.start_ts/end_ts API must be verified against current mlx-audio version

## Session Continuity

Last session: 2026-03-28T06:00:00.000Z
Stopped at: Roadmap created for v4.8.0 Phases 25-28
Resume file: None
