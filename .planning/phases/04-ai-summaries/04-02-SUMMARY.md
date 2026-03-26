---
phase: 04-ai-summaries
plan: 02
subsystem: summary-engine
tags: [minimax, prompt-templates, tts-narrative, session-summary]

requires:
  - phase: 04-ai-summaries
    provides: MiniMaxClient, CircuitBreaker, SummaryError, Config MiniMax constants
provides:
  - SummaryEngine with three summary methods (arcSummary, tailBrief, singleTurnSummary)
  - ConversationTurn and SummaryResult data types
  - Prompt templates ported from TypeScript summarizer.ts
affects: [05-telegram-bot (summary command invokes SummaryEngine)]

tech-stack:
  added: []
  patterns:
    [
      three-tier-summary-prompts,
      delimiter-based-response-parsing,
      safe-fallback-on-error,
    ]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/SummaryEngine.swift
  modified: []

key-decisions:
  - "Removed unused projectName in tailBrief to eliminate compiler warning (TS original also has no greeting for TBR)"
  - "Used Swift multiline string literals for prompt templates (preserves readability of long prompts)"

patterns-established:
  - "Summary fallback pattern: empty/short input returns safe string without API call"
  - "Prompt template port: TS triple-quote delimiters -> Swift escaped triple-quotes in multiline strings"

requirements-completed: [SUM-01, SUM-02, SUM-03]

duration: 3min
completed: 2026-03-26
---

# Phase 04 Plan 02: Summary Prompt Templates Summary

**Three MiniMax prompt templates (arc, tail-brief, single-turn) ported from TypeScript with ||| delimiter parsing and safe fallbacks**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-26T16:35:55Z
- **Completed:** 2026-03-26T16:38:49Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- SummaryEngine class with three distinct prompt templates matching TypeScript originals
- arcSummary: chronological full-session narrative with transition words, per-turn truncation, 102400 char transcript cap
- tailBrief: end-weighted narrative with compressed prior context (~20%) and expanded final turn (~80%)
- singleTurnSummary: "you prompted me X ago to..." with ||| delimiter parsing for two-part response
- ConversationTurn and SummaryResult shared data types
- Safe fallbacks on all error paths (empty input, circuit breaker, API errors)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create SummaryEngine with data types and single-turn summary** - `51c01185` (feat)
2. **Task 2: Add Arc Summary and Tail Brief methods to SummaryEngine** - `c47a25ab` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/SummaryEngine.swift` - 447 lines: ConversationTurn, SummaryResult, SummaryEngine with 3 summary methods

## Decisions Made

- Removed unused `projectName` variable in tailBrief (TS original also has no greeting for TBR mode)
- Used Swift multiline string literals for prompt templates to preserve readability

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unused variable warning in tailBrief**

- **Found during:** Task 2
- **Issue:** `projectName` was computed but never used in tailBrief, causing a compiler warning
- **Fix:** Removed the unused variable (tailBrief has no ttsGreeting, matching the TS original)
- **Files modified:** SummaryEngine.swift
- **Verification:** swift build succeeds with zero warnings
- **Committed in:** c47a25ab (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 warning removal)
**Impact on plan:** Trivial cleanup. No scope creep.

## Issues Encountered

None

## User Setup Required

None - SummaryEngine uses MiniMaxClient which reads MINIMAX_API_KEY from environment at runtime.

## Next Phase Readiness

- All three summary types ready for Telegram bot integration (Phase 5)
- SummaryEngine, ConversationTurn, SummaryResult exported for use by bot command handlers

---

_Phase: 04-ai-summaries_
_Completed: 2026-03-26_
