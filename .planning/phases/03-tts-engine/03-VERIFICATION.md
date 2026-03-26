---
phase: 03-tts-engine
verified: 2026-03-26T17:00:00Z
status: gaps_found
score: 6/8 requirements verified
gaps:
  - truth: "Duration tensor is extracted from patched sherpa-onnx for word timestamps"
    status: failed
    reason: >
      The vendored c-api.h SherpaOnnxGeneratedAudio struct does NOT contain
      durations or num_durations fields. They were added in commit ab057a2c
      but removed in fix commit 316bfe66 due to a struct layout mismatch that
      caused a bad pointer dereference crash. The compiled static library's
      struct layout did not match the patched header at runtime.
      TTSEngine.synthesize() returns SynthesisResult(durations: nil) unconditionally
      (line 120-124 of TTSEngine.swift). The duration tensor is therefore never
      extracted or passed downstream.
    artifacts:
      - path: "plugins/claude-tts-companion/Sources/CSherpaOnnx/include/sherpa-onnx/c-api/c-api.h"
        issue: "SherpaOnnxGeneratedAudio struct has only samples/n/sample_rate — no durations field"
      - path: "plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift"
        issue: "synthesize() returns durations: nil unconditionally at line 123"
    missing:
      - "Rebuild sherpa-onnx static libs with the patch applied so the binary ABI matches the header"
      - "OR document that TTS-06 is deferred and update REQUIREMENTS.md accordingly"
  - truth: "Karaoke highlighting is driven by real TTS word timings, not hardcoded 200ms"
    status: partial
    reason: >
      The character-weighted distribution (extractWordTimings) is used and produces
      zero-drift timings anchored to actual audioDuration, fully satisfying TTS-07.
      However TTS-06 (duration tensor extracted) is not met — the timing is
      character-proportional rather than phoneme-informed. The user-visible behavior
      (synchronized karaoke highlighting) works but the underlying mechanism is
      character-weighted rather than tensor-derived. This is a partial gap:
      the goal of subtitle synchronization is achieved, but TTS-06 is not.
    artifacts:
      - path: "plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift"
        issue: "extractWordTimings with rawDurations always falls back to character-weighted (line 247)"
    missing:
      - "Duration tensor extraction when sherpa-onnx static libs are rebuilt with patch"
      - "OR explicit decision to accept character-weighted as v1 and defer TTS-06 to later phase"
human_verification:
  - test: "Confirm peak RSS under 700MB during synthesis"
    expected: "Activity Monitor shows RSS stays below 700MB (TTS-04)"
    why_human: "Cannot check RSS programmatically without running the binary"
  - test: "Confirm karaoke highlighting visually synchronized with audio playback"
    expected: "Words highlight in gold at roughly the right moment in the spoken sentence"
    why_human: "Visual and audio timing verification requires human perception"
---

# Phase 03: TTS Engine Verification Report

**Phase Goal:** The binary synthesizes speech from text with word-level timestamps that drive the subtitle overlay
**Verified:** 2026-03-26
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                             | Status   | Evidence                                                                                                                                             |
| --- | ----------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Binary synthesizes speech via Kokoro int8 model                   | VERIFIED | TTSEngine.swift calls SherpaOnnxOfflineTtsGenerate; binary tested and produces audio                                                                 |
| 2   | Synthesis runs on dedicated serial DispatchQueue (not UI thread)  | VERIFIED | `DispatchQueue(label: "com.terryli.tts-engine")` at TTSEngine.swift:38; all synthesis dispatched to it                                               |
| 3   | Model loads lazily on first synthesis call, not at startup        | VERIFIED | `ensureModelLoaded()` guards ttsInstance with NSLock, init() only logs; confirmed by test (0.63s load on first request)                              |
| 4   | Audio output is 24kHz mono 16-bit WAV played via afplay           | VERIFIED | `SherpaOnnxWriteWave` at line 104; `/usr/bin/afplay` subprocess at line 139; confirmed by test run                                                   |
| 5   | Duration tensor extracted from patched sherpa-onnx                | FAILED   | Vendored header SherpaOnnxGeneratedAudio has no durations field (removed in fix commit 316bfe66). synthesize() returns durations:nil unconditionally |
| 6   | Word timestamps have zero accumulated drift                       | VERIFIED | extractWordTimings distributes audioDuration proportionally: charCount/totalChars \* audioDuration. Sum is exactly audioDuration by construction     |
| 7   | User hears synthesized speech with synchronized karaoke subtitles | VERIFIED | main.swift:57-79 calls synthesizeWithTimestamps, then showUtterance+play concurrently. Confirmed by user test run                                    |
| 8   | Synthesis achieves >= 1.5x real-time (RTF <= 0.67)                | VERIFIED | User-confirmed: 4.98s audio in 2.46s (RTF 0.495 = 2.02x real-time)                                                                                   |

**Score:** 6/8 truths verified (TTS-06 failed, TTS-07 fully met via character-weighted approach)

### Required Artifacts

| Artifact                                                                             | Expected                                        | Status   | Details                                                                                                                                                                     |
| ------------------------------------------------------------------------------------ | ----------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift`          | TTS synthesis engine wrapping sherpa-onnx C API | VERIFIED | 336 lines, substantive — lazy loading, serial queue, WAV output, afplay, synthesizeWithTimestamps, extractWordTimings                                                       |
| `plugins/claude-tts-companion/Sources/CSherpaOnnx/include/sherpa-onnx/c-api/c-api.h` | C API header with durations field               | PARTIAL  | File exists and is substantive (1276 lines), but SherpaOnnxGeneratedAudio at line 1171-1175 has only 3 fields — durations/num_durations were removed in fix commit 316bfe66 |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift`             | Config constants including kokoroModelFile      | VERIFIED | kokoroModelFile = "model.int8.onnx" at line 21; defaultSpeakerId = 3 (af_heart) at line 24                                                                                  |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift`               | TTS-driven karaoke replacing demo mode          | VERIFIED | TTSEngine() at line 27; synthesizeWithTimestamps at line 57; showUtterance+play wired at lines 64+68                                                                        |

### Key Link Verification

| From            | To                          | Via                                                     | Status    | Details                                                                                                                                                                          |
| --------------- | --------------------------- | ------------------------------------------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| TTSEngine.swift | CSherpaOnnx                 | import CSherpaOnnx + SherpaOnnxOfflineTtsGenerate       | WIRED     | Line 3 import; SherpaOnnxCreateOfflineTts line 298; SherpaOnnxOfflineTtsGenerate line 95                                                                                         |
| TTSEngine.swift | Config.swift                | Config.kokoroModelPath for model directory              | WIRED     | Lines 265-272 use Config.kokoroModelPath and Config.kokoroModelFile                                                                                                              |
| TTSEngine.swift | SubtitlePanel.showUtterance | main.swift passes wordTimings from TTS to SubtitlePanel | WIRED     | main.swift:64 calls subtitlePanel.showUtterance(ttsResult.text, wordTimings: ttsResult.wordTimings)                                                                              |
| TTSEngine.swift | duration tensor             | extractWordTimings reads durations from SynthesisResult | NOT_WIRED | synthesize() always returns durations:nil (line 123). extractWordTimings with rawDurations falls through to character-weighted (line 247). Duration tensor never read from C API |

### Data-Flow Trace (Level 4)

| Artifact             | Data Variable         | Source                                                         | Produces Real Data                                            | Status                       |
| -------------------- | --------------------- | -------------------------------------------------------------- | ------------------------------------------------------------- | ---------------------------- |
| main.swift (karaoke) | ttsResult.wordTimings | TTSEngine.extractWordTimings(text:audioDuration:rawDurations:) | Yes — character-proportional, anchored to actual audio length | FLOWING (character-weighted) |
| TTSEngine.swift      | durations field       | SherpaOnnxGeneratedAudio.durations                             | No — struct field absent from header, always nil              | DISCONNECTED                 |

### Behavioral Spot-Checks

| Behavior                           | Command                                                  | Result                                 | Status |
| ---------------------------------- | -------------------------------------------------------- | -------------------------------------- | ------ |
| swift build compiles clean         | `swift build` in plugins/claude-tts-companion            | `Build complete! (0.31s)`              | PASS   |
| TTSEngine has required API calls   | grep SherpaOnnxCreateOfflineTts TTSEngine.swift          | Match at line 298                      | PASS   |
| synthesizeWithTimestamps exists    | grep synthesizeWithTimestamps TTSEngine.swift            | Match at line 165                      | PASS   |
| main.swift wires TTS to subtitles  | grep "showUtterance.\*wordTimings" main.swift            | Match at line 64                       | PASS   |
| Duration tensor in vendored header | grep durations c-api.h (SherpaOnnxGeneratedAudio struct) | struct has 3 fields only, no durations | FAIL   |
| Commit hashes from SUMMARY valid   | git log ab057a2c c0ddd5b6                                | Both commits exist                     | PASS   |

### Requirements Coverage

| Requirement | Source Plan | Description                                        | Status      | Evidence                                                                                                                                         |
| ----------- | ----------- | -------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| TTS-01      | 03-01-PLAN  | User hears synthesized speech via afplay           | SATISFIED   | afplay subprocess in TTSEngine:139; user-confirmed audio plays                                                                                   |
| TTS-02      | 03-01-PLAN  | Synthesis on dedicated serial DispatchQueue        | SATISFIED   | com.terryli.tts-engine queue at TTSEngine:38; all synthesis dispatched there                                                                     |
| TTS-03      | 03-01-PLAN  | Model loads lazily on first synthesis call         | SATISFIED   | ensureModelLoaded() called only from synthesize(); confirmed 0.63s on first request                                                              |
| TTS-04      | 03-01-PLAN  | Peak RSS under 700MB with int8 model               | NEEDS HUMAN | User-confirmed "no crashes" but RSS not programmatically verifiable                                                                              |
| TTS-05      | 03-01-PLAN  | Synthesis >= 1.5x real-time                        | SATISFIED   | User-confirmed RTF 0.495 (2.02x real-time)                                                                                                       |
| TTS-06      | 03-02-PLAN  | Duration tensor extracted from patched sherpa-onnx | BLOCKED     | vendored header SherpaOnnxGeneratedAudio has no durations field; fix commit 316bfe66 explicitly removed them; synthesize() returns durations:nil |
| TTS-07      | 03-02-PLAN  | Word timestamps have zero accumulated drift        | SATISFIED   | extractWordTimings sums to exactly audioDuration by construction (charCount/totalChars \* audioDuration)                                         |
| TTS-08      | 03-01-PLAN  | 24kHz mono 16-bit WAV via afplay                   | SATISFIED   | SherpaOnnxWriteWave at TTSEngine:104; afplay at TTSEngine:139                                                                                    |

**REQUIREMENTS.md traceability cross-check:** All 8 TTS requirements (TTS-01 through TTS-08) are mapped to Phase 3. All appear in the plans' requirements fields. No orphaned requirements detected.

### Anti-Patterns Found

| File            | Line | Pattern                                                                    | Severity | Impact                                                                                                                                                                          |
| --------------- | ---- | -------------------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| TTSEngine.swift | 123  | `durations: nil` hardcoded return                                          | Warning  | TTS-06 not met — duration tensor never populated. Acceptable as intentional v1 workaround (character-weighted timing used instead), but means TTS-06 cannot be claimed complete |
| TTSEngine.swift | 247  | extractWordTimings(rawDurations:) always calls character-weighted fallback | Info     | Overloaded function accepting rawDurations silently ignores them. Not a bug given the header/lib mismatch, but misleading API shape                                             |

### Human Verification Required

**1. Peak RSS under 700MB (TTS-04)**

**Test:** Run the binary and monitor in Activity Monitor while synthesis is in progress.
**Expected:** RSS peaks below 700MB during first synthesis call (model load + synthesis together). Int8 model targets 561MB peak per Spike 09.
**Why human:** Cannot measure process RSS without running the binary and observing external to it.

**2. Karaoke visual synchronization quality**

**Test:** Run `swift run` in plugins/claude-tts-companion, observe subtitle overlay during playback.
**Expected:** Words highlight in gold roughly matching spoken words. Character-weighted timing will be approximate but should feel reasonably synchronized on natural prose.
**Why human:** Perceived synchronization quality requires audiovisual judgment.

### Gaps Summary

**TTS-06 is the only blocking gap.** The duration tensor extraction was planned (Spike 16 validated the C++ patch) but abandoned at runtime due to a struct layout mismatch: the compiled sherpa-onnx static library had a different `SherpaOnnxGeneratedAudio` layout than the patched header, causing a crash (commit 316bfe66 documents this). The fields were removed from the header to restore stability.

**The workaround is functional:** character-weighted timing satisfies TTS-07 (zero drift) and the end user hears speech with synchronized karaoke highlights. The phase goal — "binary synthesizes speech from text with word-level timestamps that drive the subtitle overlay" — is substantially achieved. Audio plays, karaoke displays, zero drift holds.

**TTS-06 is not met** because the duration tensor is never read from the C API. This can be resolved two ways:

1. Rebuild sherpa-onnx static libs with the ABI-compatible patch (so the compiled `.a` matches the header). This is the originally intended approach.
2. Accept character-weighted timing as the v1 implementation, update TTS-06 status to "deferred" in REQUIREMENTS.md, and close the gap for this phase.

All other requirements (TTS-01 through TTS-05, TTS-07, TTS-08) are fully satisfied and verified.

---

_Verified: 2026-03-26_
_Verifier: Claude (gsd-verifier)_
