---
name: cleanup-deleted
description: "Use when user wants to clean up Telegram by purging deleted or ghost accounts from their dialog list and contacts, removing spam ghosts that clutter the chat list, or doing general Telegram housekeeping."
allowed-tools: Bash, Read, Grep, Glob
---

# Cleanup Deleted Telegram Accounts

Scan and purge deleted/ghost accounts from your Telegram dialog list and contacts. These are accounts that were deleted by their owners or banned by Telegram but still appear as "Deleted Account" in your chat list.

The script uses 3 progressively aggressive deletion methods because Telegram's dialog cache can be stubborn:

1. **delete_dialog** — standard removal
2. **DeleteHistoryRequest** — force-clear the conversation history
3. **Block + Unblock + delete** — resets Telegram's peer state cache, then deletes

After the first pass, it re-scans for survivors and retries with method 3.

## Preflight

1. Session must exist: `~/.local/share/telethon/<profile>.session`
   - If missing, run `/tlg:setup` first

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/cleanup_deleted.py"

# Scan only (no deletions)
uv run --python 3.13 "$SCRIPT" --dry-run

# Clean all profiles
uv run --python 3.13 "$SCRIPT"

# Clean specific profile
uv run --python 3.13 "$SCRIPT" -p eon

# Clean multiple specific profiles
uv run --python 3.13 "$SCRIPT" -p eon personal
EOF
```

## Parameters

| Parameter      | Type | Description                      |
| -------------- | ---- | -------------------------------- |
| `-p/--profile` | list | Profiles to clean (default: all) |
| `--dry-run`    | flag | Scan and report without deleting |

## What Gets Cleaned

| Source                      | Action                                        |
| --------------------------- | --------------------------------------------- |
| Regular dialogs             | Deleted user chats removed                    |
| Archived dialogs (folder=1) | Deleted user chats removed                    |
| Contact list                | Deleted contacts removed                      |
| Stubborn ghosts             | Block+unblock forces cache reset, then delete |

## Recommended Cadence

Run monthly or whenever you notice "Deleted Account" entries appearing in your chat list. Spam accounts that message you and later get banned by Telegram are the primary source.
