---
name: booking-notify
description: Scheduled booking sync with Telegram notifications. Fetches new bookings, cancellations, and upcoming reminders. TRIGGERS - booking sync, booking digest, booking notifications, upcoming bookings, calendar sync, booking reminder.
allowed-tools: Read, Bash, Grep, Glob
---

# Booking Notifications (Scheduled Sync)

Automated booking sync running every 6h via launchd. Fetches recent bookings, detects changes, sends notifications to Telegram.

## Mandatory Preflight

### Step 1: Check Sync Script Exists

```bash
ls -la "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/sync.ts" 2>/dev/null || echo "SCRIPT_NOT_FOUND"
```

### Step 2: Verify Environment

```bash
echo "CALCOM_OP_UUID: ${CALCOM_OP_UUID:-NOT_SET}"
echo "TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:+SET}"
echo "TELEGRAM_CHAT_ID: ${TELEGRAM_CHAT_ID:-NOT_SET}"
echo "HAIKU_MODEL: ${HAIKU_MODEL:-NOT_SET}"
```

**All must be SET.** If any are NOT_SET, run the setup command first.

### Step 3: Verify Cal.com CLI Binary

```bash
ls -la "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/calcom-cli/calcom" 2>/dev/null || echo "BINARY_NOT_FOUND"
```

**If BINARY_NOT_FOUND**: Build it:

```bash
cd "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/calcom-cli" && bun install && bun run build
```

## Notification Categories

| Category     | Examples                                         |
| ------------ | ------------------------------------------------ |
| NEW BOOKING  | New interview scheduled, new consultation booked |
| CANCELLATION | Booking cancelled by attendee, host cancelled    |
| UPCOMING     | Booking starting in 1 hour, today's schedule     |
| RESCHEDULED  | Booking moved to new time, date changed          |

## Running Manually

```bash
cd ~/own/amonic && bun run "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/sync.ts"
```

## Sync Behavior

1. Fetches bookings from Cal.com API (last 6h window)
2. Compares against last-known state (file-based)
3. Detects new bookings, cancellations, and reschedules
4. Sends Telegram notification for each change
5. Updates state file for next sync cycle
6. Circuit breaker prevents cascade failures on API errors

## References

- [notification-templates.md](./references/notification-templates.md) — Telegram message templates
- [sync-config.md](./references/sync-config.md) — Sync interval and state management

## Post-Change Checklist

- [ ] YAML frontmatter valid (no colons in description)
- [ ] Trigger keywords current
- [ ] Path patterns use $HOME not hardcoded paths
