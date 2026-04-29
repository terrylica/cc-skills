---
phase: 14-tts-dispatch--feature-gates
plan: 01
subsystem: tts
tags: [swift, cjk, unicode, language-detection, feature-gates, env-vars]

requires:
  - phase: 01-project-bootstrap
    provides: Config.swift with defaultSpeakerId constant
provides:
  - LanguageDetector with CJK ratio detection and voice selection
  - FeatureGates with 5 env-var-based outlet toggles
  - Config.chineseSpeakerId and cjkDetectionThreshold constants
affects: [14-02-tts-dispatch-wiring]

tech-stack:
  added: []
  patterns:
    [
      enum-as-namespace for stateless utilities,
      unicode-scalar-iteration for code-point-level analysis,
    ]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/LanguageDetector.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/FeatureGates.swift
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift

key-decisions:
  - "Unicode scalars (not Character) for CJK detection -- correct abstraction for code point range checks"
  - "env() helper returns Optional<String> with != 'false' check -- matches legacy !== 'false' semantics exactly"

patterns-established:
  - "LanguageDetector pattern: enum with static detect() returning typed result struct"
  - "FeatureGates pattern: computed properties backed by ProcessInfo.processInfo.environment"

requirements-completed: [TTS-12, TTS-13]

duration: 1min
completed: 2026-03-27
---

# Phase 14 Plan 01: LanguageDetector + FeatureGates Summary

**CJK language detection across 3 Unicode ranges with per-outlet feature gates reading 5 legacy env vars**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-27T00:23:43Z
- **Completed:** 2026-03-27T00:24:45Z
- **Tasks:** 1
- **Files modified:** 3

## Accomplishments

- LanguageDetector detects CJK text via Unicode scalar ratio across U+4E00-9FFF, U+3400-4DBF, U+20000-2A6DF
- FeatureGates provides 5 computed properties matching legacy env var names exactly (SUMMARIZER_TG_ENABLED, TTS_ENABLED, SUMMARY_TTS_ENABLED, TBR_TG_ENABLED, TBR_TTS_ENABLED)
- Config extended with chineseSpeakerId=45 (zf_xiaobei) and cjkDetectionThreshold=20.0

## Task Commits

Each task was committed atomically:

1. **Task 1: LanguageDetector + FeatureGates + Config constants** - `622219ae` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/LanguageDetector.swift` - CJK ratio detection returning LanguageResult with lang and speakerId
- `plugins/claude-tts-companion/Sources/claude-tts-companion/FeatureGates.swift` - 5 per-outlet feature gates from env vars with default-enabled semantics
- `plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift` - Added chineseSpeakerId=45 and cjkDetectionThreshold=20.0

## Decisions Made

- Used `text.unicodeScalars` iteration (not `text.characters`) for correct code point range matching
- Private `env()` helper with Optional return and `!= "false"` check matches legacy `!== "false"` exactly

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- LanguageDetector and FeatureGates ready for Plan 02 to wire into notification pipeline
- Both types are consumed via static methods/properties, no initialization needed

---

_Phase: 14-tts-dispatch--feature-gates_
_Completed: 2026-03-27_
