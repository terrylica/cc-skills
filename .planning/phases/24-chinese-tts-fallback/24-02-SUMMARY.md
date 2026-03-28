---
phase: 24-chinese-tts-fallback
plan: 02
subsystem: tts
tags: [sherpa-onnx, cjk, chinese-tts, language-routing, kokoro-ios]

requires:
  - phase: 24-chinese-tts-fallback
    plan: 01
    provides: SherpaOnnxEngine class and CSherpaOnnx C module
provides:
  - CJK-to-sherpa-onnx routing in TTSEngine via synthesizeStreamingAutoRoute
  - English-to-kokoro-ios-MLX routing unchanged
  - Graceful subtitle-only fallback when CJK synthesis fails
affects: [tts-pipeline, subtitle-display, telegram-bot]

tech-stack:
  added: []
  patterns:
    [
      language-based TTS engine routing (CJK to sherpa-onnx,
      English to kokoro-ios MLX),
      uniform character-level timing for CJK subtitle display,
    ]

key-files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/TelegramBot.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/LanguageDetector.swift

key-decisions:
  - "CJK text sent as single chunk (no sentence splitting) -- sherpa-onnx handles segmentation internally"
  - "Uniform per-character timing for CJK karaoke (no word-level timestamps from sherpa-onnx)"
  - "synthesizeStreamingAutoRoute is the new primary entry point; synthesizeStreaming still available for direct English calls"

patterns-established:
  - "Language-based TTS routing: LanguageDetector.detect -> synthesizeStreamingAutoRoute -> CJK or English engine"
  - "CJK fallback chain: sherpa-onnx synthesis nil -> empty ChunkResult array -> subtitle-only display"

requirements-completed: [CJK-01, CJK-02, CJK-03, CJK-04]

duration: 5min
completed: 2026-03-28
---

# Phase 24 Plan 02: CJK TTS Routing Integration Summary

**CJK text auto-routes to sherpa-onnx engine while English stays on kokoro-ios MLX, with graceful subtitle-only fallback on failure**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-28T03:42:54Z
- **Completed:** 2026-03-28T03:47:38Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- TTSEngine.synthesizeStreamingAutoRoute routes CJK to sherpa-onnx and English to kokoro-ios MLX
- TelegramBot streaming dispatch uses auto-routing (no hardcoded voiceName)
- LanguageDetector returns chineseVoiceName for CJK text (was defaultVoiceName for graceful degradation)
- Both debug and release builds pass with zero linker errors

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire SherpaOnnxEngine into TTSEngine + CompanionApp** - `a8135295` (feat)
2. **Task 2: Update TelegramBot CJK dispatch + build verification** - `ba0a1b4c` (feat)

## Files Created/Modified

- `Sources/CompanionCore/TTSEngine.swift` - Added sherpaOnnxEngine property, synthesizeCJK(), synthesizeStreamingAutoRoute()
- `Sources/CompanionCore/CompanionApp.swift` - Creates SherpaOnnxEngine and passes to TTSEngine init
- `Sources/CompanionCore/LanguageDetector.swift` - Returns chineseVoiceName for CJK (routes to sherpa-onnx)
- `Sources/CompanionCore/TelegramBot.swift` - dispatchStreamingTTS uses auto-routing; dispatchFullTTS has CJK branch

## Decisions Made

- CJK text is sent as a single chunk to sherpa-onnx (no sentence splitting needed -- sherpa-onnx kokoro model handles Chinese segmentation internally)
- Uniform per-character timing for CJK subtitle karaoke (sherpa-onnx does not expose word-level timestamps like kokoro-ios MToken)
- synthesizeStreamingAutoRoute becomes the primary streaming entry point; existing synthesizeStreaming preserved for direct English-only callers

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - sherpa-onnx model files already present at ~/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0/ (validated in Plan 01).

## Known Stubs

None - CJK routing is fully wired from LanguageDetector through TTSEngine to SherpaOnnxEngine. Audio plays through the same AudioStreamPlayer pipeline as English.

## Next Phase Readiness

- Phase 24 complete: Chinese TTS fallback fully operational
- CJK text produces audio via sherpa-onnx with subtitle display
- English text continues through kokoro-ios MLX unchanged
- Missing model gracefully degrades to subtitle-only display

---

_Phase: 24-chinese-tts-fallback_
_Completed: 2026-03-28_
