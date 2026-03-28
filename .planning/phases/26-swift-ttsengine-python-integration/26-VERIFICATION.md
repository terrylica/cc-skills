---
phase: 26-swift-ttsengine-python-integration
verified: 2026-03-28T08:10:00Z
status: human_needed
score: 4/5 must-haves verified
re_verification: null
gaps: []
human_verification:
  - test: "Observe karaoke subtitle highlighting in live TTS playback"
    expected: "Gold word-level highlighting advances word-by-word in precise sync with audio, no visible accumulated drift across a 3+ sentence passage"
    why_human: "Zero-drift behavior requires audio playback through the full Swift companion -> Python server chain with visual subtitle overlay running -- cannot verify programmatically without running both services"
---

# Phase 26: Swift TTSEngine Python Integration Verification Report

**Phase Goal:** TTSEngine delegates all English TTS to the Python server and feeds native word onsets into SubtitleSyncDriver, eliminating character-weighted fallback timing
**Verified:** 2026-03-28T08:10:00Z
**Status:** human_needed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                                                         | Status    | Evidence                                                                                                                                                                                                                                                                                                                                                                 |
| --- | ----------------------------------------------------------------------------------------------------------------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | TTSEngine calls /v1/audio/speech-with-timestamps instead of /v1/audio/speech for English synthesis                            | VERIFIED  | `callPythonServerWithTimestamps()` builds URL `Config.pythonTTSServerURL + "/v1/audio/speech-with-timestamps"` (line 408); `grep -c` returns 5 occurrences. All three English paths (`synthesize`, `synthesizeWithTimestamps`, `synthesizeStreaming`) call this method exclusively.                                                                                      |
| 2   | ChunkResult.wordOnsets is populated with native onset times from Python server JSON response                                  | VERIFIED  | `TimestampResult.wordOnsets` is mapped from `tsResponse.words.map { TimeInterval($0.onset) }` (line 450); `ChunkResult(wordOnsets: tsResult.wordOnsets)` at line 291. Only the CJK path passes `wordOnsets: nil` (line 354) -- intentional per spec.                                                                                                                     |
| 3   | TTSResult.wordOnsets is populated with native onset times from Python server JSON response                                    | VERIFIED  | `synthesizeWithTimestamps()` returns `TTSResult(wordOnsets: tsResult.wordOnsets)` at line 208. `tsResult.wordOnsets` comes from the `callPythonServerWithTimestamps` JSON parse.                                                                                                                                                                                         |
| 4   | SubtitleSyncDriver receives native onsets and uses them for karaoke highlighting (no character-weighted fallback for English) | VERIFIED  | `TTSPipelineCoordinator.startBatchPipeline()` calls `driver.addChunk(nativeOnsets: chunk.wordOnsets)` at line 179. `SubtitleSyncDriver.resolveOnsets()` uses native onsets directly when count matches word count; falls back to duration-derived only on mismatch (correct behavior). `WordTimingAligner.extractWordTimings()` has zero occurrences in TTSEngine.swift. |
| 5   | tts_kokoro.sh works end-to-end via Swift companion -> Python server chain                                                     | UNCERTAIN | The shell script at `~/.local/bin/tts_kokoro.sh` calls the Swift companion's HTTP endpoint. The pipeline code path exists and compiles, but live E2E verification requires both services running with audio output. Routes to human verification.                                                                                                                        |

**Score:** 4/5 automated truths verified (5th is human-only)

### Required Artifacts

| Artifact                                                             | Expected                                              | Status   | Details                                                                                                                                                                                                                                                         |
| -------------------------------------------------------------------- | ----------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift` | Python server JSON parsing with word onset extraction | VERIFIED | File exists, 601 lines. Contains `PythonTimestampWord`, `PythonTimestampResponse`, `TimestampResult` Codable/value types. `callPythonServerWithTimestamps()` fully implemented with URLSession POST, JSON decode, base64 WAV decode, onset/duration extraction. |

### Key Link Verification

| From                                          | To                                                      | Via                            | Status | Details                                                                                                                                                                                                                                                                                                  |
| --------------------------------------------- | ------------------------------------------------------- | ------------------------------ | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TTSEngine.callPythonServerWithTimestamps()`  | `http://127.0.0.1:8779/v1/audio/speech-with-timestamps` | URLSession POST with JSON body | WIRED  | URL constructed at line 408 from `Config.pythonTTSServerURL`. POST with `Content-Type: application/json` body at lines 411-420. Response decoded via `JSONDecoder().decode(PythonTimestampResponse.self, ...)` at line 444.                                                                              |
| `TTSEngine.synthesizeStreaming()`             | `ChunkResult.wordOnsets`                                | JSON parsing of words array    | WIRED  | `tsResult.wordOnsets` from `tsResponse.words.map { TimeInterval($0.onset) }`. Passed as `wordOnsets: tsResult.wordOnsets` in ChunkResult constructor at line 291. `grep -c "wordOnsets.*onset"` style: `wordOnsets: [TimeInterval]?` struct field present, populated non-nil for all English chunks.     |
| `TTSPipelineCoordinator.startBatchPipeline()` | `SubtitleSyncDriver.addChunk(nativeOnsets:)`            | chunk.wordOnsets passthrough   | WIRED  | TTSPipelineCoordinator line 179: `nativeOnsets: chunk.wordOnsets` -- exact passthrough. SubtitleSyncDriver.addChunk signature confirmed at line 222: `func addChunk(wavPath: String, samples: [Float]? = nil, pages: [SubtitlePage], wordTimings: [TimeInterval], nativeOnsets: [TimeInterval]? = nil)`. |

### Data-Flow Trace (Level 4)

| Artifact                 | Data Variable         | Source                                                                               | Produces Real Data                                                                         | Status  |
| ------------------------ | --------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ | ------- |
| TTSEngine.swift          | `tsResult.wordOnsets` | `callPythonServerWithTimestamps()` -> JSON decode of `words[].onset`                 | Yes -- live HTTP call to Python server, decoded from `PythonTimestampResponse.words` array | FLOWING |
| SubtitleSyncDriver.swift | `wordOnsets` property | `resolveOnsets(nativeOnsets:...)` -- uses nativeOnsets when count matches totalWords | Yes -- non-nil nativeOnsets from TTSEngine pass through unchanged                          | FLOWING |

### Behavioral Spot-Checks

| Behavior                                                       | Command                                             | Result                                                              | Status        |
| -------------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------- | ------------- |
| swift build succeeds                                           | `swift build` in plugins/claude-tts-companion       | `Build complete! (1.42s)`                                           | PASS          |
| speech-with-timestamps endpoint URL present (>= 2 occurrences) | `grep -c "speech-with-timestamps" TTSEngine.swift`  | 5                                                                   | PASS          |
| PythonTimestampResponse struct present (>= 2 occurrences)      | `grep -c "PythonTimestampResponse" TTSEngine.swift` | 2                                                                   | PASS          |
| audio_b64 field parsed (>= 1 occurrence)                       | `grep -c "audio_b64" TTSEngine.swift`               | 2                                                                   | PASS          |
| wordOnsets: nil only on CJK path (1 occurrence)                | `grep -c "wordOnsets: nil" TTSEngine.swift`         | 1                                                                   | PASS          |
| No WordTimingAligner.extractWordTimings in English paths       | `grep "extractWordTimings" TTSEngine.swift`         | 0 matches                                                           | PASS          |
| Commit 8b6a7b7b exists                                         | `git show 8b6a7b7b --stat`                          | `feat(26-01): switch TTSEngine to /v1/audio/speech-with-timestamps` | PASS          |
| tts_kokoro.sh E2E live playback                                | Requires services running + audio                   | Not runnable in CI                                                  | SKIP -> human |

### Requirements Coverage

| Requirement | Source Plan   | Description                                                                                                      | Status      | Evidence                                                                                                                                                                                                   |
| ----------- | ------------- | ---------------------------------------------------------------------------------------------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SWI-01      | 26-01-PLAN.md | TTSEngine parses word timestamps from Python server JSON response and passes native onsets to SubtitleSyncDriver | SATISFIED   | `PythonTimestampResponse` Codable struct decodes `words[].onset`; `TimestampResult.wordOnsets` flows to ChunkResult/TTSResult; `driver.addChunk(nativeOnsets: chunk.wordOnsets)` in TTSPipelineCoordinator |
| SWI-02      | 26-01-PLAN.md | Karaoke subtitle highlighting uses Python-derived word onsets with zero accumulated drift                        | NEEDS HUMAN | Code path is wired end-to-end. Zero-drift behavior requires live playback observation to confirm absence of visual timing drift                                                                            |
| SWI-03      | 26-01-PLAN.md | `tts_kokoro.sh` CLI script works end-to-end via Swift companion -> Python server chain                           | NEEDS HUMAN | Shell script calls Swift companion HTTP endpoint; chain exists in code; requires both services live to verify                                                                                              |

No orphaned requirements: REQUIREMENTS.md shows SWI-01/02/03 all mapped to Phase 26, all claimed by 26-01-PLAN.md.

### Anti-Patterns Found

| File | Line | Pattern                                                                                         | Severity | Impact |
| ---- | ---- | ----------------------------------------------------------------------------------------------- | -------- | ------ |
| None | --   | No TODOs, FIXMEs, placeholders, empty returns, or hardcoded empty data found in TTSEngine.swift | --       | --     |

### Human Verification Required

#### 1. Karaoke Zero-Drift Highlighting (SWI-02 + SWI-03)

**Test:** With both services running (`curl http://127.0.0.1:8779/health` and `curl http://127.0.0.1:8780/health` both return 200), run:

```bash
~/.local/bin/tts_kokoro.sh "Claude is an AI assistant made by Anthropic. It helps people with coding, writing, analysis, and many other tasks. The karaoke subtitles should highlight each word precisely as it is spoken, with no accumulated timing drift even across multiple sentences."
```

**Expected:** Gold word-level highlighting advances word-by-word in precise sync with audio playback. No word highlighted too early or too late. No visible accumulated drift across sentence boundaries.
**Why human:** Visual/perceptual timing quality cannot be verified without running both services with audio output and observing the subtitle overlay.

### Gaps Summary

No gaps. All automated verification points pass. The single outstanding item (SWI-02/SWI-03 live E2E behavior) is a human verification checkpoint, not a code defect. The implementation is complete:

- `callPythonServerWithTimestamps()` calls the correct endpoint and parses the JSON response
- All three English synthesis paths (`synthesize`, `synthesizeWithTimestamps`, `synthesizeStreaming`) are wired to the timestamp endpoint
- `WordTimingAligner.extractWordTimings()` is not called anywhere in TTSEngine.swift
- `ChunkResult.wordOnsets` and `TTSResult.wordOnsets` are populated for English; nil only for the CJK sherpa-onnx path (intentional)
- `SubtitleSyncDriver.addChunk(nativeOnsets: chunk.wordOnsets)` passthrough is present in TTSPipelineCoordinator
- `swift build` succeeds with zero errors in 1.42s

---

_Verified: 2026-03-28T08:10:00Z_
_Verifier: Claude (gsd-verifier)_
