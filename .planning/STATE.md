---
gsd_state_version: 1.0
milestone: v4.8.0
milestone_name: Python MLX TTS Consolidation
status: verifying
stopped_at: Completed 26-01-PLAN.md
last_updated: "2026-03-28T07:54:30.534Z"
last_activity: 2026-03-28
progress:
  total_phases: 25
  completed_phases: 24
  total_plans: 48
  completed_plans: 47
  percent: 0
---

<!-- # SSoT-OK -->

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-28)

**Core value:** See what Claude says, anywhere -- real-time karaoke subtitles synced with TTS playback
**Current focus:** Phase 26 — swift-ttsengine-python-integration

## Current Position

Phase: 26
Plan: Not started
Status: Phase complete — ready for verification
Last activity: 2026-03-28

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

| Phase 25 P01 | 5min | 2 tasks | 2 files |
| Phase 26 P01 | 2min | 2 tasks | 1 files |

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
- [Phase 25]: Access KokoroPipeline directly instead of model.generate() because GenerationResult discards MToken timestamp data
- [Phase 25]: Audio array squeeze(0) needed because pipeline returns (1,N) shape vs generate() which does audio[0] internally
- [Phase 26]: Keep callPythonServer() as fallback for CJK path and emergency scenarios
- [Phase 26]: Use Codable structs for Python timestamp JSON parsing (type-safe vs manual JSONSerialization)
- [Phase 26]: Pass native wordDurations as wordTimings fallback for SubtitleSyncDriver onset count mismatches

### Pending Todos

None yet.

### Blockers/Concerns

- Python MLX server must use `uv` for all Python tooling (user policy)
- Python 3.13 ONLY -- never use 3.14 or any other version (user policy)
- mlx-audio MToken.start_ts/end_ts API must be verified against current mlx-audio version

## Session Continuity

Last session: 2026-03-28T07:47:06.435Z
Stopped at: Completed 26-01-PLAN.md
Resume file: None
