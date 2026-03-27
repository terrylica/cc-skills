---
phase: 15-telegram-inline-buttons
plan: 01
subsystem: telegram
tags:
  [swift, telegram-bot, inline-keyboard, callback-query, applescript, iterm2]

requires:
  - phase: 11-telegram-formatter
    provides: TelegramFormatter HTML rendering and chunking
  - phase: 12-transcript-parser
    provides: TranscriptParser JSONL parsing

provides:
  - InlineButtonManager with notification lookup, Focus Tab dedup, keyboard construction
  - Callback query handlers for Focus Tab, Follow Up, Transcript, Transcript pagination
  - Inline keyboard attachment on Arc Summary messages
  - Focus Tab dedup via editMessageReplyMarkup

affects: [15-02, telegram-bot, notification-watcher]

tech-stack:
  added:
    [
      TGCallbackQueryHandler,
      TGInlineKeyboardMarkup,
      TGEditMessageReplyMarkupParams,
    ]
  patterns:
    [callback-query-dispatch, FIFO-bounded-maps, applescript-via-process]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/InlineButtonManager.swift
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift

key-decisions:
  - "Inline counts computed inline rather than adding summarize() to TranscriptParser"
  - "Logger changed from private to fileprivate for BotDispatcher access to callback error logging"
  - "BotDispatcher callback handlers use non-optional self.bot (TGDefaultDispatcher superclass provides it)"

patterns-established:
  - "FIFO bounded map: insertion-order array + dictionary, evict oldest when over limit"
  - "Callback query pattern: TGCallbackQueryHandler with regex, answerCallbackQuery for ack"

requirements-completed: [BTN-01, BTN-02, BTN-03]

duration: 5min
completed: 2026-03-27
---

# Phase 15 Plan 01: Inline Button Infrastructure Summary

**Inline keyboard with Focus Tab/Follow Up/Transcript buttons on Arc Summary, callback handlers with AppleScript iTerm2 switching and FIFO-bounded state maps**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-27T00:36:31Z
- **Completed:** 2026-03-27T00:41:53Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- InlineButtonManager tracks notifications (200 FIFO) and Focus Tab dedup (100 FIFO) with keyboard construction
- Four callback query handlers registered: iterm: (AppleScript), fu: (workspace info), tx: (transcript view), txp: (pagination)
- Arc Summary messages now include inline keyboard when transcriptPath is available
- Focus Tab dedup removes old message keyboards via editMessageReplyMarkup before tracking new one

## Task Commits

Each task was committed atomically:

1. **Task 1: Create InlineButtonManager** - `cc858ef9` (feat)
2. **Task 2: Add callback handlers and inline keyboard to TelegramBot** - `64de0e40` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/InlineButtonManager.swift` - Button state manager with FIFO maps, keyboard builder, transcript page store
- `plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift` - Callback query handlers, sendMessageWithKeyboard, removeInlineKeyboard, formatTranscriptView
- `plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift` - Passes itermSessionId and transcriptPath to sendSessionNotification

## Decisions Made

- Computed transcript prompt/tool counts inline in formatTranscriptView rather than adding a summarize() method to TranscriptParser (avoids modifying Phase 12 artifacts)
- Changed logger from private to fileprivate so BotDispatcher callback handlers can log errors
- BotDispatcher callback handlers use `self.bot` directly (non-optional TGBot from TGDefaultDispatcher superclass)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed optional binding on non-optional TGBot**

- **Found during:** Task 2 (callback handler registration)
- **Issue:** BotDispatcher's `self.bot` is inherited from TGDefaultDispatcher and is non-optional TGBot, but code used `if let bot = self.bot` which fails Swift compilation
- **Fix:** Changed to `let bot = self.bot` (direct assignment, no optional binding)
- **Files modified:** TelegramBot.swift
- **Verification:** swift build succeeds
- **Committed in:** 64de0e40

**2. [Rule 3 - Blocking] Fixed private logger access from BotDispatcher**

- **Found during:** Task 2 (callback handler registration)
- **Issue:** logger was private to TelegramBot, but BotDispatcher (separate class in same file) needs to log callback errors
- **Fix:** Changed `private let logger` to `fileprivate let logger`
- **Files modified:** TelegramBot.swift
- **Verification:** swift build succeeds
- **Committed in:** 64de0e40

**3. [Rule 3 - Blocking] Removed call to nonexistent TranscriptParser.summarize()**

- **Found during:** Task 2 (formatTranscriptView implementation)
- **Issue:** Plan referenced TranscriptParser.summarize() which doesn't exist
- **Fix:** Computed promptCount and toolUseCount inline by iterating entries
- **Files modified:** TelegramBot.swift
- **Verification:** swift build succeeds
- **Committed in:** 64de0e40

---

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking)
**Impact on plan:** All auto-fixes necessary for compilation. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all button handlers are fully wired.

## Next Phase Readiness

- Inline button infrastructure complete, ready for Phase 15-02 (if applicable)
- Follow Up handler shows informational message; full session resume wiring depends on session lister (not yet ported)

---

_Phase: 15-telegram-inline-buttons_
_Completed: 2026-03-27_
