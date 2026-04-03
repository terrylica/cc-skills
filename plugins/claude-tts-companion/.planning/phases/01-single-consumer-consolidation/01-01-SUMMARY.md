---
phase: 01-single-consumer-consolidation
plan: 01
subsystem: infra
tags: [telegram-bot, notification-watcher, bun, single-consumer]

# Dependency graph
requires: []
provides:
  - "Companion is sole consumer of ~/.claude/notifications/ JSON files"
  - "Bun bot retains all command handlers (/prompt, /sessions, Q&A)"
affects: [02-message-id-edit-infrastructure, 06-qa-enhancements]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Deprecation via @deprecated JSDoc + NOTIF-01 reference (file retained as reference)"

key-files:
  created: []
  modified:
    - "~/.claude/automation/claude-telegram-sync/src/main.ts"
    - "~/.claude/automation/claude-telegram-sync/src/claude-sync/notification-watcher.ts"

key-decisions:
  - "Retained notification-watcher.ts with deprecation header rather than deleting (preserves reference for notification format)"

patterns-established:
  - "NOTIF-01 traceability: deprecation notices reference the requirement ID"

requirements-completed: [NOTIF-01]

# Metrics
duration: 2min
completed: 2026-04-02
---

# Phase 1 Plan 1: Remove Bun Bot Notification Watcher Summary

**Bun bot notification watcher removed; companion is sole consumer of session-end notifications with zero duplicate messages**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-03T03:53:30Z
- **Completed:** 2026-04-03T03:55:27Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Removed watchNotifications import, startup call, and shutdown cleanup from main.ts
- Added deprecation header to notification-watcher.ts referencing NOTIF-01
- Verified Bun bot starts cleanly without notification watcher (no "Watching for Stop hook notifications" log)
- Confirmed commands.ts exports (lastSessionBox, registerNotificationButtons) remain intact for Q&A handler

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove notification watcher from Bun bot main.ts** - `996a91d` (feat)
2. **Task 2: Deprecate notification-watcher.ts and verify Bun bot starts** - `17c9dbd` (chore)

## Files Created/Modified

- `~/.claude/automation/claude-telegram-sync/src/main.ts` - Removed watcher import/call/stop, added companion reference comment
- `~/.claude/automation/claude-telegram-sync/src/claude-sync/notification-watcher.ts` - Added @deprecated JSDoc header with NOTIF-01 reference

## Decisions Made

- Retained notification-watcher.ts with deprecation header rather than deleting it -- preserves reference for the notification format, processing logic, and dedup patterns that the companion reimplements

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - no stubs or placeholders introduced.

## Next Phase Readiness

- Phase 2 (Message ID & Edit Infrastructure) can proceed: companion is now the sole notification consumer
- Phase 6 (Q&A Enhancements) can proceed: Bun bot Q&A handler unaffected by watcher removal
- The Bun bot's notification-watcher.ts can be deleted in a future cleanup phase once the companion fully replaces all its functionality

## Self-Check: PASSED

- 01-01-SUMMARY.md: FOUND
- Commit 996a91d (Task 1): FOUND
- Commit 17c9dbd (Task 2): FOUND

---

_Phase: 01-single-consumer-consolidation_
_Completed: 2026-04-02_
