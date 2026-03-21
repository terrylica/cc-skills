---
name: list-dialogs
description: "List all Telegram chats, groups, and channels for your personal account. Use when user wants to see their Telegram contacts, find a chat ID, browse Telegram conversations. TRIGGERS - telegram dialogs, telegram chats, telegram contacts, find telegram chat, telegram chat id"
allowed-tools: Bash, Read, Grep, Glob
---

# List Telegram Dialogs

List all chats, groups, and channels visible to your personal Telegram account.

## Preflight

1. Session must exist: `~/.local/share/telethon/<profile>.session`
   - If missing, run `/tlg:setup` first

## Usage

```bash
/usr/bin/env bash << 'DIALOGS_EOF'
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}"

# Default profile
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" dialogs

# Specific profile
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" -p personal dialogs

# Filter results
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" dialogs | grep -i "search term"
DIALOGS_EOF
```

## Additional Commands

### Read Messages

```bash
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" read <chat_id> -n 10
```

### Account Info

```bash
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" whoami
```

## Output Format

```
Chat Name                                  (id: 1234567890)
```

Use the `id` value with `send-message` skill to send to that chat.
