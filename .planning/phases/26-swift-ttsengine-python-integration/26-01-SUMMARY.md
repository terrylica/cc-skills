---
phase: 26-swift-ttsengine-python-integration
plan: 01
subsystem: tts
tags: [swift, kokoro, python-mlx, karaoke, word-timestamps, urlsession]

# Dependency graph
requires:
  - phase: 25-python-tts-server-timestamp-endpoint
    provides: "/v1/audio/speech-with-timestamps endpoint returning JSON with base64 WAV + per-word onset/duration"
provides:
  - "TTSEngine calls Python server timestamp endpoint for all English synthesis"
  - "ChunkResult.wordOnsets and TTSResult.wordOnsets populated with native Kokoro duration model timing"
  - "SubtitleSyncDriver receives native onsets for zero-drift karaoke highlighting"
affects: [27-remove-mlx-swift-dependencies, 28-remove-synthesis-restart]

# Tech tracking
tech-stack:
  added: []
  patterns:
    [
      "JSON timestamp response parsing with Codable structs",
      "TimestampResult value type for internal pipeline data",
    ]

key-files:
  created: []
  modified:
    - "plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift"

key-decisions:
  - "Keep callPythonServer() as fallback -- CJK path and potential emergency fallback still need raw WAV endpoint"
  - "Use Codable structs (PythonTimestampResponse) for JSON parsing -- type-safe, no manual JSONSerialization"
  - "Pass native wordDurations as wordTimings fallback -- SubtitleSyncDriver uses them if onset count mismatches"

patterns-established:
  - "Python server JSON response pattern: Codable struct -> TimestampResult value type -> pipeline passthrough"

requirements-completed: [SWI-01, SWI-02, SWI-03]

# Metrics
duration: 2min
completed: 2026-03-28
---

# Phase 26 Plan 01: Swift TTSEngine Python Integration Summary

**TTSEngine now calls /v1/audio/speech-with-timestamps for native Kokoro word onsets, replacing character-weighted fallback that caused visible karaoke drift on multi-syllable words**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-28T07:43:51Z
- **Completed:** 2026-03-28T07:46:13Z
- **Tasks:** 2 (1 auto + 1 checkpoint auto-approved)
- **Files modified:** 1

## Accomplishments

- All three English synthesis paths (synthesize, synthesizeWithTimestamps, synthesizeStreaming) now use /v1/audio/speech-with-timestamps
- ChunkResult.wordOnsets and TTSResult.wordOnsets populated with native onset times from Kokoro duration model
- Character-weighted WordTimingAligner.extractWordTimings() removed from English synthesis paths
- CJK path unchanged (sherpa-onnx, wordOnsets: nil as expected)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add callPythonServerWithTimestamps and wire all synthesis paths** - `8b6a7b7b` (feat)
2. **Task 2: Verify karaoke highlighting uses native word onsets end-to-end** - auto-approved checkpoint

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift` - Added PythonTimestampResponse Codable structs, callPythonServerWithTimestamps() method, wired all English synthesis paths to use native word onsets

## Decisions Made

- **Keep callPythonServer() as fallback:** CJK path still uses raw WAV endpoint, and having a fallback for emergency scenarios costs nothing.
- **Codable structs for JSON parsing:** PythonTimestampResponse/PythonTimestampWord provide type-safe decoding vs manual JSONSerialization. Standard Swift pattern.
- **Native wordDurations as wordTimings:** SubtitleSyncDriver can fall back to duration-based timing if onset count mismatches word count, so we pass the native durations in wordTimings too.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all data paths are wired end-to-end. wordOnsets populated from Python server response for English; nil for CJK (intentional, CJK karaoke timing is out of scope per PROJECT.md).

## Next Phase Readiness

- Phase 27 (remove kokoro-ios, mlx-swift, MLXUtilsLibrary) can proceed -- TTSEngine no longer uses MToken types for English paths
- WordTimingAligner.swift still imports MLXUtilsLibrary for MToken types -- cleanup target for Phase 27
- Phase 28 (remove synthesis-count restart) can proceed -- Python server manages its own memory lifecycle

---

_Phase: 26-swift-ttsengine-python-integration_
_Completed: 2026-03-28_
