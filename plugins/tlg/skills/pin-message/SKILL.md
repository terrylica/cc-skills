---
name: pin-message
description: "Use when user wants to pin or unpin a message in a Telegram chat, group, or channel, or manage pinned messages."
allowed-tools: Bash, Read, Grep, Glob
---

# Pin/Unpin Telegram Messages

Pin or unpin messages in chats, groups, and channels.

## Preflight

1. Session must exist: `~/.local/share/telethon/<profile>.session`
   - If missing, run `/tlg:setup` first

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/send.py"

# Pin a message (with notification)
uv run --python 3.13 "$SCRIPT" pin <chat> <message_id>

# Pin silently (no notification)
uv run --python 3.13 "$SCRIPT" pin <chat> <message_id> --silent

# Unpin a specific message
uv run --python 3.13 "$SCRIPT" pin <chat> <message_id> --unpin

# Unpin all messages
uv run --python 3.13 "$SCRIPT" pin <chat> --unpin
EOF
```

## Parameters

| Parameter  | Type       | Description                                     |
| ---------- | ---------- | ----------------------------------------------- |
| chat       | string/int | Chat/group/channel                              |
| message_id | int        | Message to pin (omit with --unpin to unpin all) |
| `--unpin`  | flag       | Unpin instead of pin                            |
| `--silent` | flag       | Pin without sending notification                |
