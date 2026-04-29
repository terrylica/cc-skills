---
phase: 24-chinese-tts-fallback
verified: 2026-03-27T00:00:00Z
status: passed
score: 4/4 must-haves verified
gaps: []
human_verification:
  - test: "Send a Chinese message via Telegram and confirm audio plays"
    expected: "Chinese text is synthesized and plays through the normal audio pipeline; subtitle shows with character-level karaoke"
    why_human: "Requires running launchd service, a real Telegram bot token, and a Mandarin text message"
  - test: "Remove or rename the sherpa-onnx model directory, restart service, send Chinese text"
    expected: "Service logs a warning and shows subtitle-only display without crashing"
    why_human: "Requires mutating filesystem state and observing live service behavior"
---

# Phase 24: Chinese TTS Fallback Verification Report

**Phase Goal:** CJK text is automatically spoken via sherpa-onnx Chinese voice while English continues through the default engine
**Verified:** 2026-03-27
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP Success Criteria)

| #   | Truth                                                                           | Status   | Evidence                                                                                                                                                                                                                                             |
| --- | ------------------------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Text with >20% CJK characters routes to sherpa-onnx, not kokoro-ios MLX         | VERIFIED | `LanguageDetector.detect` returns `lang="cmn"` when CJK ratio ≥ 20%; `TTSEngine.synthesizeStreamingAutoRoute` branches on `langResult.lang == "cmn"` to call `synthesizeCJK` (TTSEngine.swift:467-475)                                               |
| 2   | English text continues through kokoro-ios MLX with no behavior change           | VERIFIED | `synthesizeStreamingAutoRoute` falls through to `synthesizeStreaming(text:voiceName:speed:)` for non-CJK; `synthesizeStreaming` is unchanged (TTSEngine.swift:477-478)                                                                               |
| 3   | sherpa-onnx Chinese model loads on first CJK request, not at startup            | VERIFIED | `SherpaOnnxEngine.init()` only checks file existence; `loadModel()` is called inside `synthesize()` guarded by `ttsPtr == nil` (SherpaOnnxEngine.swift:67-68)                                                                                        |
| 4   | Missing model or synthesis failure falls back to subtitle-only with warning log | VERIFIED | `modelAvailable` check at top of `synthesize()` returns `nil` with warning log; `synthesizeStreamingAutoRoute` returns `[]` on `nil` chunk; `dispatchStreamingTTS` calls `showSubtitleOnlyFallback` when chunks is empty (TelegramBot.swift:298-303) |

**Score:** 4/4 truths verified

---

### Required Artifacts

| Artifact                                                                    | Status   | Details                                                                                                                                                  |
| --------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `plugins/claude-tts-companion/Sources/CSherpaOnnx/include/module.modulemap` | VERIFIED | Exists, declares `module CSherpaOnnx { header "c-api.h"; export * }`                                                                                     |
| `plugins/claude-tts-companion/Sources/CSherpaOnnx/include/c-api.h`          | VERIFIED | Exists, 1992 lines, vendored from sherpa-onnx source                                                                                                     |
| `plugins/claude-tts-companion/Sources/CSherpaOnnx/shim.c`                   | VERIFIED | Exists, contains `void _csherpaonnx_shim(void) {}` as required by SwiftPM                                                                                |
| `plugins/claude-tts-companion/Sources/CompanionCore/SherpaOnnxEngine.swift` | VERIFIED | 199 lines; exports `SherpaOnnxEngine`; imports `CSherpaOnnx`; implements lazy load + 30s idle unload + nil-return fallback                               |
| `plugins/claude-tts-companion/Sources/CompanionCore/Config.swift`           | VERIFIED | Contains `sherpaOnnxModelDir` (KOKORO_MODEL_PATH env var), `sherpaOnnxIdleTimeoutSeconds = 30`, `sherpaOnnxNumThreads = 2`                               |
| `plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift`        | VERIFIED | Contains `sherpaOnnxEngine` property, `synthesizeCJK()`, `synthesizeStreamingAutoRoute()`                                                                |
| `plugins/claude-tts-companion/Sources/CompanionCore/TelegramBot.swift`      | VERIFIED | `dispatchStreamingTTS` calls `synthesizeStreamingAutoRoute`; `dispatchFullTTS` has CJK branch calling `synthesizeCJK`; no "English-only" warning remains |
| `plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift`     | VERIFIED | Creates `SherpaOnnxEngine()` at line 38, passes to `TTSEngine(playbackManager:sherpaOnnxEngine:)` at line 39                                             |
| `plugins/claude-tts-companion/Sources/CompanionCore/LanguageDetector.swift` | VERIFIED | Returns `chineseVoiceName` for `cmn` (not `defaultVoiceName`); CJK ratio threshold reads from `Config.cjkDetectionThreshold` (20.0)                      |
| `plugins/claude-tts-companion/Package.swift`                                | VERIFIED | `CSherpaOnnx` target with `publicHeadersPath: "include"`; `CompanionCore` depends on `CSherpaOnnx`; 12+ sherpa-onnx static libs linked via `unsafeFlags` |

---

### Key Link Verification

| From                     | To                                       | Via                           | Status | Details                                                                                                                                                               |
| ------------------------ | ---------------------------------------- | ----------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SherpaOnnxEngine.swift` | `CSherpaOnnx`                            | `import CSherpaOnnx`          | WIRED  | Line 1 of SherpaOnnxEngine.swift; calls `SherpaOnnxOfflineTtsGenerate`, `SherpaOnnxCreateOfflineTts`, `SherpaOnnxDestroyOfflineTts`, `SherpaOnnxOfflineTtsSampleRate` |
| `Package.swift`          | sherpa-onnx static libs                  | `unsafeFlags`                 | WIRED  | `-L.../install/lib` with 12 `.linkedLibrary` entries including `sherpa-onnx-c-api`, `sherpa-onnx-core`, `sherpa-onnx`, `onnxruntime`, `espeak-ng`, plus `c++`         |
| `CompanionApp.swift`     | `SherpaOnnxEngine`                       | instantiation + injection     | WIRED  | `sherpaOnnxEngine = SherpaOnnxEngine()` (line 38); passed to `TTSEngine(playbackManager:sherpaOnnxEngine:)` (line 39)                                                 |
| `TTSEngine.swift`        | `SherpaOnnxEngine.swift`                 | `sherpaOnnxEngine.synthesize` | WIRED  | `synthesizeCJK` calls `sherpaOnnxEngine.synthesize(text:speed:)` (line 423); `synthesizeStreamingAutoRoute` calls `synthesizeCJK` (line 469)                          |
| `TelegramBot.swift`      | `TTSEngine.synthesizeStreamingAutoRoute` | `dispatchStreamingTTS`        | WIRED  | `dispatchStreamingTTS` calls `ttsEngine.synthesizeStreamingAutoRoute(text:)` (line 291-292)                                                                           |

---

### Data-Flow Trace (Level 4)

| Artifact                                 | Data Variable                                       | Source                                             | Produces Real Data                                        | Status  |
| ---------------------------------------- | --------------------------------------------------- | -------------------------------------------------- | --------------------------------------------------------- | ------- |
| `SherpaOnnxEngine.synthesize`            | `samples` from `SherpaOnnxOfflineTtsGenerate`       | sherpa-onnx C API with loaded `ttsPtr`             | Yes — C API call with opaque pointer to loaded ONNX model | FLOWING |
| `TTSEngine.synthesizeCJK`                | `result.samples` from `sherpaOnnxEngine.synthesize` | SherpaOnnxEngine (above)                           | Yes — copies from `UnsafeBufferPointer` returned by C API | FLOWING |
| `TTSEngine.synthesizeStreamingAutoRoute` | `[ChunkResult]`                                     | routes to `synthesizeCJK` or `synthesizeStreaming` | Yes — both paths produce real audio data                  | FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED (build verification requires swift build with sherpa-onnx static libs at hardcoded path; cannot run without full sherpa-onnx install at `/Users/terryli/fork-tools/sherpa-onnx/`).

Commit existence was verified: all 4 phase commits (`3503580d`, `f1c9d089`, `a8135295`, `ba0a1b4c`) exist in git history and are type `commit`.

---

### Requirements Coverage

| Requirement | Source Plan  | Description                                                         | Status    | Evidence                                                                                                                                                                              |
| ----------- | ------------ | ------------------------------------------------------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CJK-01      | 24-01, 24-02 | CJK text detected via LanguageDetector routes to sherpa-onnx engine | SATISFIED | `LanguageDetector.detect` returns `lang="cmn"`; `synthesizeStreamingAutoRoute` routes to `synthesizeCJK` on `cmn`                                                                     |
| CJK-02      | 24-02        | English text continues to use kokoro-ios MLX engine                 | SATISFIED | Non-CJK path in `synthesizeStreamingAutoRoute` calls unchanged `synthesizeStreaming` with `langResult.voiceName`                                                                      |
| CJK-03      | 24-01        | sherpa-onnx multilang model loads on-demand, not at startup         | SATISFIED | `SherpaOnnxEngine.init()` only checks file existence; `loadModel()` called inside `synthesize()` on first call when `ttsPtr == nil`                                                   |
| CJK-04      | 24-01, 24-02 | Graceful fallback if sherpa-onnx model missing or synthesis fails   | SATISFIED | `modelAvailable` false → `synthesize()` returns nil → `synthesizeCJK` returns nil → `synthesizeStreamingAutoRoute` returns `[]` → `dispatchStreamingTTS` shows subtitle-only fallback |

**Orphaned requirements check:** REQUIREMENTS.md maps CJK-01, CJK-02, CJK-03, CJK-04 to Phase 24. All four appear in plan frontmatter for 24-01 and/or 24-02. No orphaned requirements.

---

### Anti-Patterns Found

| File                       | Pattern                                                 | Severity | Assessment                                                                                                                                    |
| -------------------------- | ------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `SherpaOnnxEngine.swift`   | `private var ttsPtr: OpaquePointer?` initialized to nil | INFO     | Not a stub — this is intentional lazy load. `loadModel()` populates it on first `synthesize()` call.                                          |
| `TTSEngine.swift` line 473 | `return []` for CJK fallback                            | INFO     | Not a stub — this is the documented graceful fallback path (CJK-04). The empty array causes `showSubtitleOnlyFallback` to be called upstream. |

No blockers or warnings found. The `return nil` / `return []` patterns in the synthesis path are explicitly the CJK-04 graceful fallback design, not unimplemented placeholders. Each returns only after a failed real synthesis attempt or confirmed missing model.

---

### Human Verification Required

#### 1. End-to-end Chinese TTS Playback

**Test:** Send a Telegram message containing Chinese text (e.g., "你好，这是一段测试文字") to the running claude-tts-companion service.
**Expected:** Audio plays through the normal AudioStreamPlayer pipeline with character-level subtitle karaoke overlay. Log shows "CJK text detected -- will route to sherpa-onnx engine" and "sherpa-onnx synthesis: N samples at 24000Hz".
**Why human:** Requires the launchd service running with valid TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, and the kokoro-int8-multi-lang-v1_0 model present at the configured path.

#### 2. Graceful Fallback on Missing Model

**Test:** Rename `~/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0/model.int8.onnx` to `.bak`, restart the service, then send Chinese text.
**Expected:** Log shows "sherpa-onnx model not found at ... -- CJK TTS disabled" at startup. On message receipt, "CJK synthesis skipped -- model not available" is logged and subtitle-only display appears without crash.
**Why human:** Requires filesystem mutation and live service observation.

#### 3. 30-Second Idle Unload

**Test:** Send Chinese text (triggering model load), then wait 30 seconds without sending more, then check logs or RSS.
**Expected:** Log shows "sherpa-onnx model unloaded" approximately 30 seconds after the last CJK synthesis. RSS drops by ~500MB.
**Why human:** Requires timing observation over a 30-second window with live RSS monitoring.

---

### Gaps Summary

No gaps. All four ROADMAP success criteria are implemented with real code, properly wired end-to-end:

- CJK routing chain is complete: `LanguageDetector.detect` → `synthesizeStreamingAutoRoute` → `synthesizeCJK` → `SherpaOnnxEngine.synthesize` → sherpa-onnx C API
- English path is structurally preserved: non-CJK text falls through to unchanged `synthesizeStreaming`
- On-demand loading is correct: `ttsPtr == nil` check in `synthesize()` gates `loadModel()` call
- Graceful fallback is wired: nil from synthesis → empty chunks → `showSubtitleOnlyFallback`
- All commits exist in git history with consistent atomic structure (task-per-commit)

The only items requiring human verification are behavioral (live audio, timing, runtime model removal) — none are code correctness issues.

---

_Verified: 2026-03-27_
_Verifier: Claude (gsd-verifier)_
