---
phase: 260406-nts
plan: 01
subsystem: claude-tts-companion / TTSEngine
tags: [refactor, naming, codable, swift]
requires: []
provides:
  - "PythonTimestampResponse with camelCase Swift properties + CodingKeys"
affects:
  - plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift
tech_stack:
  added: []
  patterns:
    ["Explicit CodingKeys (Option A) for snake_case ↔ camelCase JSON mapping"]
key_files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift
decisions:
  - "Chose Option A (explicit CodingKeys) over .convertFromSnakeCase for self-documentation and per-struct scoping"
metrics:
  duration: ~3min
  completed: 2026-04-06
commits:
  - af9698be
---

# Quick Task 260406-nts: Fix PythonTimestampResponse snake_case Swift Property Names

## Objective

Eliminate the snake_case/camelCase duplicate-naming collision flagged by the telemetry similarity audit: `PythonTimestampResponse` in TTSEngine.swift used snake_case Swift properties (`audio_b64`, `audio_duration`, `sample_rate`) that were re-mapped to camelCase downstream, creating two names for the same concept.

## Properties Renamed (before → after)

| Before           | After           |
| ---------------- | --------------- |
| `audio_b64`      | `audioB64`      |
| `audio_duration` | `audioDuration` |
| `sample_rate`    | `sampleRate`    |

`PythonTimestampWord` required no changes (already camelCase: text/onset/duration).

## CodingKeys Added

```swift
enum CodingKeys: String, CodingKey {
    case audioB64 = "audio_b64"
    case words
    case audioDuration = "audio_duration"
    case sampleRate = "sample_rate"
}
```

Preserves the Python server's snake_case JSON wire contract with zero behavioral change.

## Call Sites Updated

| Line (post-edit) | Change                                                   |
| ---------------- | -------------------------------------------------------- |
| ~499             | `tsResponse.audio_b64` → `tsResponse.audioB64`           |
| ~512             | `tsResponse.audio_duration` → `tsResponse.audioDuration` |

`sample_rate`/`sampleRate` is declared but never read (kept for server contract parity).

## Build Verification

```
cd plugins/claude-tts-companion && swift build
Build complete! (5.16s)
```

Zero errors. Pre-existing warnings (unrelated `try?` unused result, `UnsafeMutableRawPointer` to CFString in CompanionApp.swift) untouched — out of scope.

## Verification Greps

- snake_case occurrences in TTSEngine.swift remaining:
  - Line 67: comment (`/// Exponential moving average of synthesis_time / audio_duration.`)
  - Lines 440, 442, 443: CodingKeys raw values
- No `let audio_b64 / let audio_duration / let sample_rate` declarations remain.
- No `tsResponse.audio_*` references remain.

## Deviations from Plan

None — plan executed exactly as written.

## Decisions Made

- **Option A (CodingKeys) over Option B (`.convertFromSnakeCase`):** Explicit, self-documenting, scoped to one struct, cannot accidentally affect other Codable types added later.

## Self-Check: PASSED

- Modified file exists: FOUND `plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift`
- Commit exists: FOUND `af9698be`
- Build exits 0 with no errors
