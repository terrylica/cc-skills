---
phase: "06"
plan: "02"
subsystem: telegram-bot-commands
tags:
  [prompt-executor, edit-in-place, model-selection, circuit-breaker, streaming]
dependency_graph:
  requires:
    - phase: 06-01
      provides: ClaudeProcess subprocess + TranscriptParser + model selection
  provides:
    - PromptExecutor with flag parsing, streaming edit-in-place, circuit breaker
    - /prompt command handler in TelegramBot
    - editMessage and sendMessageReturningId methods
  affects: [telegram-bot, session-management, http-api]
tech_stack:
  added: []
  patterns:
    [
      PromptStreamState-class-for-sendable-callbacks,
      DispatchQueue-sync-for-async-safe-locking,
      closure-injection-for-decoupling,
    ]
key_files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/PromptExecutor.swift
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift
key-decisions:
  - "PromptStreamState class with NSLock for @Sendable callback state (avoids Swift 6 captured-var errors)"
  - "DispatchQueue.sync for executor pre-flight checks (NSLock forbidden in async contexts in Swift 6)"
  - "Closure injection for sendMessage/editMessage to decouple PromptExecutor from TelegramBot"
patterns-established:
  - "PromptStreamState: thread-safe shared state class for bridging callback-based APIs to Swift concurrency"
  - "Pre-flight enum pattern: synchronous guard checks before async work via DispatchQueue.sync"
requirements-completed: [BOT-05, BOT-06]
duration: 6min
completed: 2026-03-26
---

# Phase 6 Plan 2: Prompt Executor + /prompt Command Wiring Summary

**/prompt command with --haiku/--sonnet/--opus model flags, streaming edit-in-place to Telegram, circuit breaker + mutex safety**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-26T17:16:27Z
- **Completed:** 2026-03-26T17:22:27Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- PromptExecutor orchestrates full /prompt lifecycle: flag parsing, subprocess spawn, throttled streaming edits, final formatted response
- Edit-in-place pattern with 1.5s throttle, 200-char minimum, and regressive suppression for Telegram rate limits
- Mutex + rate limiting + circuit breaker (3 failures = 10min cooldown) prevent process storms
- /prompt registered in bot dispatcher, command menu, and /commands list

## Task Commits

Each task was committed atomically:

1. **Task 1: PromptExecutor with model flags, streaming, circuit breaker** - `1b74b2ef` (feat)
2. **Task 2: Wire /prompt into TelegramBot + update /done** - `d8ced0e2` (feat)

## Files Created/Modified

- `PromptExecutor.swift` - parsePromptFlags, modelLabel, PromptStreamState, PromptExecutor class
- `TelegramBot.swift` - handlePrompt, sendMessageReturningId, editMessage, /prompt dispatcher + menu
- `Config.swift` - haikuModel, sonnetModel, opusModel, promptDefaultCwd, promptTimeoutSeconds

## Decisions Made

- **PromptStreamState class**: Mutable streaming state wrapped in a Sendable class with NSLock to satisfy Swift 6 strict concurrency in @Sendable callbacks. Avoids the "reference to captured var in concurrently-executing code" error.
- **DispatchQueue.sync for pre-flight**: NSLock.lock() is unavailable from async contexts in Swift 6. Used serial DispatchQueue.sync for the mutex/rate-limit/circuit-breaker checks instead.
- **Closure injection**: sendMessage/editMessage passed as closures to PromptExecutor rather than importing TelegramBot, keeping the executor testable and decoupled.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Swift 6 Sendable violations in callback captures**

- **Found during:** Task 1
- **Issue:** Local `var` captures in `@Sendable` onChunk/onComplete callbacks violate Swift 6 strict concurrency
- **Fix:** Created PromptStreamState class wrapping all mutable state with NSLock, replacing local vars
- **Files modified:** PromptExecutor.swift
- **Committed in:** 1b74b2ef

**2. [Rule 3 - Blocking] NSLock unavailable from async contexts**

- **Found during:** Task 1
- **Issue:** `lock.lock()` inside `async func execute()` produces "unavailable from asynchronous contexts" errors
- **Fix:** Replaced NSLock with serial DispatchQueue.sync for executor-level state, used PreflightResult enum pattern
- **Files modified:** PromptExecutor.swift
- **Committed in:** 1b74b2ef

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes required for Swift 6 compilation. No scope creep -- same functionality, different concurrency primitives.

## Issues Encountered

None beyond the deviations above.

## Known Stubs

None. All components are fully implemented with no placeholder data or TODO markers.

## Next Phase Readiness

- /prompt command functional with model selection and streaming
- Session resume (BOT-06) plumbed through but resumeSessionId always nil until Phase 7 wires session tracking
- /done cancels running prompts but has no session state to detach from yet

---

_Phase: 06-telegram-bot-commands_
_Completed: 2026-03-26_
