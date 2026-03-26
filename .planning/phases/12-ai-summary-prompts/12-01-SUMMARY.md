---
phase: 12-ai-summary-prompts
plan: 01
subsystem: ai
tags: [swift, noise-filtering, transcript-parsing, turn-extraction]

requires:
  - phase: 06-telegram-bot
    provides: TranscriptParser base with JSONL parsing and entry types
provides:
  - Noise filtering (isSystemNoise, isRealPrompt) matching legacy TypeScript
  - Improved entriesToTurns with longest-response selection and tool count aggregation
  - stripSkillExpansion for transcript-level prompt cleaning
  - getLastUserPrompt for extracting meaningful prompts from arrays
affects: [12-02-ai-summary-prompts, SummaryEngine]

tech-stack:
  added: []
  patterns:
    [noise-pattern-matching, longest-response-selection, tool-count-aggregation]

key-files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/TranscriptParser.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift

key-decisions:
  - "TranscriptParser gets its own stripSkillExpansion (matching legacy TS architecture where transcript-parser.ts had its own copy separate from display formatting)"
  - "noisePatterns as static let on enum (value-type, no instances needed)"

patterns-established:
  - "Noise filtering before summarization: always filter via isSystemNoise before passing turns to MiniMax"
  - "Longest response selection: scan all responses per turn, keep longest (not first)"

requirements-completed: [PROMPT-05]

duration: 3min
completed: 2026-03-26
---

# Phase 12 Plan 01: Noise Filtering & Turn Extraction Summary

**Ported 18 legacy noise patterns + regex filters into TranscriptParser with longest-response turn extraction and tool count aggregation**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-26T23:54:07Z
- **Completed:** 2026-03-26T23:57:00Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- Added 18 string-match noise patterns + 2 regex patterns matching legacy TypeScript verbatim
- Implemented isSystemNoise, isRealPrompt, stripSkillExpansion, getLastUserPrompt static methods
- Replaced naive entriesToTurns (first-response, no filtering) with improved version that filters noise, finds longest response, and aggregates tool counts as "Edit x3, Bash x2" format
- Removed local entriesToTurns from main.swift, centralized in TranscriptParser

## Task Commits

Each task was committed atomically:

1. **Task 1: Add noise filtering and improved turn extraction to TranscriptParser** - `971e0aa1` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/TranscriptParser.swift` - Added noise filtering (noisePatterns, noiseRegexPatterns, isSystemNoise, isRealPrompt, stripSkillExpansion, getLastUserPrompt) and improved entriesToTurns static method
- `plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift` - Removed local entriesToTurns function, updated call site to TranscriptParser.entriesToTurns

## Decisions Made

- TranscriptParser gets its own stripSkillExpansion separate from TelegramFormatter's copy, matching the legacy TypeScript architecture where transcript-parser.ts had its own copy distinct from display formatting
- Used static let on enum for noise patterns (no instances needed, value-type semantics)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Clean noise-filtered turns now available for SummaryEngine consumption
- Plan 12-02 can build on these turns for improved MiniMax prompt construction

---

_Phase: 12-ai-summary-prompts_
_Completed: 2026-03-26_
