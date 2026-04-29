---
phase: 12-ai-summary-prompts
plan: 02
subsystem: ai
tags: [swift, minimax, prompt-engineering, tts, telegram]

requires:
  - phase: 12-ai-summary-prompts
    provides: Noise filtering and turn extraction from Plan 01
  - phase: 07-auto-continue
    provides: Shared MiniMaxClient with circuit breaker
provides:
  - Exact legacy prompt templates in SummaryEngine (arcSummary, tailBrief, singleTurnSummary)
  - summarizePromptForDisplay method for Telegram prompt condensing
affects: [telegram-notifications, tts-dispatch]

tech-stack:
  added: []
  patterns:
    [
      unicode-em-dash-prompts,
      right-arrow-prior-context,
      prompt-condensing-fallback,
    ]

key-files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/SummaryEngine.swift

key-decisions:
  - "Use Swift \\u{2014} unicode escapes for em dashes rather than literal characters (explicit intent, grep-friendly)"
  - "summarizePromptForDisplay uses circuit breaker check before API call with truncation fallback"

patterns-established:
  - "Prompt text verbatim from legacy TS: any prompt changes require side-by-side comparison with summarizer.ts"
  - "Unicode escapes for special characters in prompt templates: \\u{2014} for em dash, \\u{2192} for right arrow"

requirements-completed: [PROMPT-01, PROMPT-02, PROMPT-03, PROMPT-04]

duration: 3min
completed: 2026-03-26
---

# Phase 12 Plan 02: Legacy Prompt Templates & Prompt Condensing Summary

**Ported exact legacy TypeScript prompt text into SummaryEngine with em dashes, right arrows, correct char budgets, and new summarizePromptForDisplay method**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-26T23:57:07Z
- **Completed:** 2026-03-27T00:00:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Replaced all double-hyphen `--` with Unicode em dash `\u{2014}` in singleTurnSummary (6 occurrences), arcSummary (5 occurrences), and tailBrief (2 occurrences + system prompt)
- Replaced `->` with Unicode right arrow `\u{2192}` in tailBrief prior context line format
- Added missing "Summarize based on what is shown" clause to arcSummary truncation rule
- Added new summarizePromptForDisplay method with 800 char threshold, 150 word MiniMax condensing, circuit breaker check, and truncation fallback

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite SummaryEngine with exact legacy prompts and add prompt condensing** - `7445d647` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/SummaryEngine.swift` - Replaced all prompt template text with exact legacy TypeScript wording (em dashes, right arrows, char budgets), added summarizePromptForDisplay method

## Decisions Made

- Used Swift `\u{2014}` unicode escapes for em dashes rather than inserting literal Unicode characters (explicit intent, grep-friendly for verification)
- summarizePromptForDisplay checks circuit breaker before attempting API call, falls back to simple truncation on failure

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All four prompt templates now match legacy TypeScript verbatim
- SummaryEngine ready for integration with session notification pipeline
- Phase 12 (ai-summary-prompts) complete -- both plans finished

---

_Phase: 12-ai-summary-prompts_
_Completed: 2026-03-26_
