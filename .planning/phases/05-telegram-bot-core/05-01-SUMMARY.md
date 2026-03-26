---
phase: 05-telegram-bot-core
plan: 01
subsystem: telegram
tags:
  [
    swift-telegram-sdk,
    long-polling,
    html-formatting,
    fence-aware-chunking,
    telegram-bot-api,
  ]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "Package.swift with swift-telegram-sdk dependency, Config.swift pattern"
provides:
  - "TelegramBot actor with long-polling connection and 7 command handlers"
  - "TelegramFormatter with HTML escaping, fence-aware chunking, markdown-to-HTML"
  - "Config.telegramBotToken and Config.telegramChatId env var lookups"
affects: [05-telegram-bot-core, 06-bot-commands, 07-file-watching]

# Tech tracking
tech-stack:
  added: [swift-telegram-sdk TGBot actor, TGCommandHandler, TGDefaultDispatcher]
  patterns:
    [
      BotDispatcher subclass pattern,
      fence-aware message chunking,
      plain-text fallback on send failure,
    ]

key-files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramFormatter.swift
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift

key-decisions:
  - "BotDispatcher subclass of TGDefaultDispatcher for handler registration"
  - "Graceful fallback: bot skips startup when TELEGRAM_BOT_TOKEN not set"
  - "Plain text retry on HTML send failure (matching TS safeEditMessage pattern)"

patterns-established:
  - "TGCommandHandler per command with [weak self] capture in closures"
  - "replyToChat helper for responding to the message sender"
  - "nonisolated(unsafe) var for main.swift global bot reference"

requirements-completed: [BOT-01, BOT-02, BOT-08]

# Metrics
duration: 3min
completed: 2026-03-26
---

# Phase 05 Plan 01: Telegram Bot Core Summary

**TelegramBot actor with swift-telegram-sdk long polling, 7 command handlers, and fence-aware HTML message chunking up to 4096 chars**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-26T16:50:18Z
- **Completed:** 2026-03-26T16:53:35Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- TelegramFormatter with escapeHtml, parseFenceSpans, chunkTelegramHtml, markdownToTelegramHtml, stripHtmlTags
- TelegramBot wrapping TGBot actor with long polling (limit=100, timeout=30)
- 7 command handlers: /start, /stop, /status, /health, /sessions, /done, /commands
- Graceful bot startup fallback when TELEGRAM_BOT_TOKEN not configured
- SIGTERM handler updated to stop bot cleanly

## Task Commits

Each task was committed atomically:

1. **Task 1: Config + TelegramFormatter** - `e413c6ad` (feat)
2. **Task 2: TelegramBot actor with long polling and 7 command handlers** - `533f8e49` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramFormatter.swift` - HTML escaping, fence-aware chunking, markdown-to-HTML conversion
- `plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift` - Bot actor with dispatcher, 7 commands, message sending
- `plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift` - Added telegramBotToken and telegramChatId
- `plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift` - Bot startup with graceful fallback, SIGTERM cleanup

## Decisions Made

- BotDispatcher subclass of TGDefaultDispatcher registers all handlers in override handle()
- Bot uses [weak self] captures in command handler closures to avoid retain cycles
- replyToChat helper sends response to the message sender's chat (not necessarily the configured chatId)
- Graceful fallback: if TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is missing, log a warning and skip bot startup

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

| File              | Location       | Stub                                           | Resolution              |
| ----------------- | -------------- | ---------------------------------------------- | ----------------------- |
| TelegramBot.swift | handleSessions | "Session listing will be available in Phase 7" | Phase 7 (File Watching) |
| TelegramBot.swift | handleDone     | "Session detach will be available in Phase 6"  | Phase 6 (Bot Commands)  |

These stubs are intentional placeholders documented in the plan. The commands respond with informative messages about when functionality will be available.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Bot infrastructure ready for Plan 02 to wire SummaryEngine and TTSEngine notifications
- TelegramFormatter available for any module needing HTML message formatting
- sendNotification() public API ready for use by other components

---

_Phase: 05-telegram-bot-core_
_Completed: 2026-03-26_
