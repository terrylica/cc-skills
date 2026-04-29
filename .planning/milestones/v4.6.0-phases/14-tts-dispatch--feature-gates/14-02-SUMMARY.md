---
phase: 14-tts-dispatch--feature-gates
plan: 02
subsystem: tts
tags: [swift, feature-gates, language-detection, tts-dispatch, karaoke]

requires:
  - phase: 14-tts-dispatch--feature-gates
    provides: LanguageDetector and FeatureGates from Plan 01
provides:
  - Feature-gated TTS dispatch pipeline with language-aware voice selection
  - Per-outlet toggles for Arc Summary TG, Tail Brief TG, and TBR TTS
affects: []

tech-stack:
  added: []
  patterns:
    [
      feature-gate guard pattern at method top for early exit,
      language detection before TTS synthesis for voice routing,
    ]

key-files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift

key-decisions:
  - "TTS greeting computed inline in sendSessionNotification using formatProjectName -- not from SummaryEngine.ttsGreeting"
  - "Both tasks committed as single atomic change since they modify the same file and are tightly coupled"

patterns-established:
  - "Feature gate pattern: check FeatureGates.allOutletsDisabled first, then per-outlet gates wrapping each send/dispatch"

requirements-completed: [TTS-10, TTS-11]

duration: 2min
completed: 2026-03-27
---

# Phase 14 Plan 02: TTS Dispatch Wiring Summary

**Feature-gated notification pipeline with CJK language detection routing English to af_heart (3) and Chinese to zf_xiaobei (45)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-27T00:26:07Z
- **Completed:** 2026-03-27T00:28:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- All 5 feature gates wired into sendSessionNotification (allOutletsDisabled, summarizerTgEnabled, tbrTgEnabled, tbrTtsEnabled)
- LanguageDetector.detect wired into dispatchTTS, passing speakerId to synthesizeWithTimestamps
- TTS greeting changed from arc.ttsGreeting to computed "Hi Terry, you were working in {project}:" matching legacy pattern

## Task Commits

Each task was committed atomically:

1. **Tasks 1+2: Feature gates + language detection wiring** - `9012675b` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift` - Added FeatureGates checks around all 3 outlets, LanguageDetector.detect in dispatchTTS, computed TTS greeting

## Decisions Made

- Combined both tasks into single commit since they modify the same file and are logically coupled
- TTS greeting computed directly from `summaryEngine.formatProjectName(cwd)` rather than relying on `arc.ttsGreeting` which was nil for tail briefs

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 14 complete: LanguageDetector + FeatureGates created (Plan 01) and wired (Plan 02)
- All TTS dispatch requirements (TTS-10 through TTS-13) addressed
- Ready for next phase

---

_Phase: 14-tts-dispatch--feature-gates_
_Completed: 2026-03-27_
