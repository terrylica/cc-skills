---
phase: 04-ai-summaries
plan: 01
subsystem: api
tags: [minimax, circuit-breaker, urlsession, anthropic-api]

requires:
  - phase: 01-foundation
    provides: Config.swift pattern, swift-log Logger pattern
provides:
  - MiniMaxClient for Anthropic-compatible API calls via URLSession
  - CircuitBreaker with consecutive failure tracking and timed cooldown
  - SummaryError enum covering all API failure modes
  - Config.swift MiniMax constants (API key, base URL, model, max tokens)
affects:
  [
    04-ai-summaries plan 02 (prompt templates),
    05-telegram-bot (summary command),
  ]

tech-stack:
  added: []
  patterns:
    [
      circuit-breaker-nslock,
      anthropic-compatible-api,
      env-var-config-with-defaults,
    ]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/CircuitBreaker.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/MiniMaxClient.swift
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift

key-decisions:
  - "NSLock + @unchecked Sendable for CircuitBreaker thread safety (matching TTSEngine pattern)"
  - "JSONSerialization over Codable for MiniMax response parsing (response shape varies with thinking blocks)"

patterns-established:
  - "Circuit breaker pattern: NSLock-based, configurable maxFailures/cooldownSeconds, auto-reset on cooldown expiry"
  - "API client pattern: circuit breaker check -> API key check -> request -> status check -> parse -> record success/failure"

requirements-completed: [SUM-04]

duration: 4min
completed: 2026-03-26
---

# Phase 04 Plan 01: MiniMax API Client & Circuit Breaker Summary

**URLSession-based MiniMax API client with Anthropic-compatible headers and circuit breaker (3 failures / 5-min cooldown)**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-26T16:28:40Z
- **Completed:** 2026-03-26T16:32:46Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- MiniMax API client with Anthropic-compatible endpoint (x-api-key, anthropic-version headers)
- Circuit breaker opens after 3 consecutive failures, auto-resets after 5-minute cooldown
- SummaryError enum with 5 cases covering all failure modes
- Config.swift extended with 4 MiniMax constants (all env-var-overridable)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add MiniMax config constants and create CircuitBreaker** - `ee1ce773` (feat)
2. **Task 2: Create MiniMaxClient with URLSession API calls** - `58d71d0d` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift` - Added miniMaxAPIKey, miniMaxBaseURL, miniMaxModel, summaryMaxTokens
- `plugins/claude-tts-companion/Sources/claude-tts-companion/CircuitBreaker.swift` - Thread-safe circuit breaker with NSLock and SummaryError enum
- `plugins/claude-tts-companion/Sources/claude-tts-companion/MiniMaxClient.swift` - URLSession API client with circuit breaker integration

## Decisions Made

- NSLock + @unchecked Sendable for CircuitBreaker (matches established TTSEngine pattern)
- JSONSerialization over Codable for response parsing (MiniMax responses include thinking blocks that need filtering)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed swift-log string concatenation in CircuitBreaker**

- **Found during:** Task 1 (CircuitBreaker creation)
- **Issue:** Logger.Message does not accept concatenated strings (`"a" + "b"`), requires string interpolation
- **Fix:** Combined concatenated warning message into single string interpolation
- **Files modified:** CircuitBreaker.swift
- **Verification:** swift build succeeds
- **Committed in:** ee1ce773 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor syntax fix for swift-log compatibility. No scope creep.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required. MINIMAX_API_KEY will be needed at runtime but is handled by the existing launchd plist environment.

## Next Phase Readiness

- MiniMaxClient and CircuitBreaker ready for prompt template integration (Plan 02)
- All types exported: MiniMaxClient, MiniMaxResult, CircuitBreaker, SummaryError

---

_Phase: 04-ai-summaries_
_Completed: 2026-03-26_
