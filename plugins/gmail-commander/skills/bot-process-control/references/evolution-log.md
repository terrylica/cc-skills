# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-09-26: Rewritten for the private deployment

**Trigger**: The bot and digest moved to a private Restate tenant on an always-on Mac mini, and the laptop launchd jobs `com.terryli.gmail-commander-bot` and `com.terryli.gmail-commander-digest` were retired on 2026-09-24. This skill still shipped both plists and told agents to `launchctl load`/`unload` them, and to restart the bot with them after an OAuth fix.

**Fix**: Removed the plist templates and every launchctl start/stop/restart recipe. The skill now says where each service runs (`GmailBot`, `GmailBotChat`, `GmailDigest`, `GmailAuth`), that operations follow the private repository's runbook, how to confirm nothing runs locally (read-only), how to check the deployed bot from Telegram with `/status`, and why `scripts/bot.ts` must never be run with the production token (one `getUpdates` consumer per token, `409 Conflict`).

**Files**: `SKILL.md`

---

## 2026-02-26: Initial Evolution Log

**Status**: Skill is in use and maintained. Track improvements here.

### Purpose

This evolution log tracks updates to the skill. Each entry should note:

- What changed (content, structure, tooling)
- Why it changed (bug fix, feature request, best practice)
- Files affected

### How to Use

1. When updating SKILL.md or references, add an entry here with the date
2. Keep entries reverse-chronological (newest first)
3. Link to ADRs or GitHub issues when relevant
4. Reference specific line changes when helpful

---
