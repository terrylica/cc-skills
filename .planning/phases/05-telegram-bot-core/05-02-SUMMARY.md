---
phase: 05-telegram-bot-core
plan: 02
subsystem: telegram
tags:
  [
    session-notification,
    tts-dispatch,
    karaoke-subtitles,
    arc-summary,
    tail-brief,
    minimax,
  ]

# Dependency graph
requires:
  - phase: 05-telegram-bot-core
    provides: "TelegramBot actor with long polling and 7 command handlers"
  - phase: 04-ai-summary
    provides: "SummaryEngine with arcSummary, tailBrief, singleTurnSummary"
  - phase: 03-tts-engine
    provides: "TTSEngine with synthesizeWithTimestamps and play"
  - phase: 02-subtitle-overlay
    provides: "SubtitlePanel with showUtterance karaoke display"
provides:
  - "sendSessionNotification method wiring SummaryEngine + TTS + karaoke"
  - "dispatchTTS method for synthesize + play + subtitle display"
  - "TelegramBot init accepting SummaryEngine, TTSEngine, SubtitlePanel"
  - "main.swift bot lifecycle with all subsystem references"
affects: [06-bot-commands, 07-file-watching]

# Tech tracking
tech-stack:
  added: []
  patterns:
    [
      async let concurrent summary generation,
      DispatchQueue.main.async for @MainActor SubtitlePanel access,
      completion-handler-based TTS dispatch from non-actor context,
      conditional subtitle demo fallback when bot disabled,
    ]

key-files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift

key-decisions:
  - "async let for concurrent arcSummary + tailBrief (wall-clock halved vs sequential)"
  - "DispatchQueue.main.async for SubtitlePanel access (respects @MainActor isolation)"
  - "Subtitle demo only when bot is disabled (dev mode fallback)"
  - "TTS greeting from arcSummary prepended to tailBrief text for full audio"

patterns-established:
  - "Subsystem injection: TelegramBot accepts SummaryEngine, TTSEngine, SubtitlePanel at init"
  - "Conditional feature: subtitle demo only shown when TELEGRAM_BOT_TOKEN not set"

requirements-completed: [BOT-03, BOT-04]

# Metrics
duration: 2min
completed: 2026-03-26
---

# Phase 05 Plan 02: Bot Notification Wiring Summary

**Session notification pipeline: TelegramBot -> concurrent arcSummary + tailBrief -> HTML message + TTS karaoke dispatch via SubtitlePanel**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-26T16:55:47Z
- **Completed:** 2026-03-26T16:57:30Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- sendSessionNotification generates concurrent Arc Summary + Tail Brief, sends HTML notification, dispatches TTS with karaoke
- dispatchTTS synthesizes with word timestamps and drives SubtitlePanel.showUtterance on main thread
- main.swift creates SummaryEngine, passes all three subsystems to TelegramBot
- Graceful fallback: subtitle demo shown only when bot token not configured

## Task Commits

Each task was committed atomically:

1. **Task 1: Add session notification + TTS dispatch methods to TelegramBot** - `1d239949` (feat)
2. **Task 2: Wire TelegramBot into main.swift and verify build** - `4731ce47` (feat)

## Files Created/Modified

- `plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift` - Added summaryEngine/ttsEngine/subtitlePanel properties, sendSessionNotification, dispatchTTS, updated /health
- `plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift` - Create SummaryEngine, pass subsystems to TelegramBot, replace TTS demo with conditional subtitle demo

## Decisions Made

- Used `async let` for concurrent arcSummary + tailBrief generation (halves wall-clock time)
- DispatchQueue.main.async for SubtitlePanel access (respects @MainActor isolation without requiring await MainActor.run)
- TTS greeting from Arc Summary prepended to Tail Brief text for cohesive audio narrative
- Subtitle demo only shown when bot is disabled (no token = dev mode), replaced full TTS demo

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

| File              | Location       | Stub                                           | Resolution              |
| ----------------- | -------------- | ---------------------------------------------- | ----------------------- |
| TelegramBot.swift | handleSessions | "Session listing will be available in Phase 7" | Phase 7 (File Watching) |
| TelegramBot.swift | handleDone     | "Session detach will be available in Phase 6"  | Phase 6 (Bot Commands)  |

These stubs were documented in Plan 01 and remain intentional placeholders.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 5 complete: TelegramBot has full notification pipeline (summary + TTS + karaoke)
- Ready for Phase 6 (Bot Commands) to implement /done session detach and other interactive commands
- Ready for Phase 7 (File Watching) to call sendSessionNotification when sessions end

---

_Phase: 05-telegram-bot-core_
_Completed: 2026-03-26_
