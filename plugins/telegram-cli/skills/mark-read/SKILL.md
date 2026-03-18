---
name: mark-read
description: "Mark Telegram chats as read, clear unread badges and mentions. TRIGGERS - telegram mark read, telegram read receipt, telegram clear unread, telegram acknowledge"
allowed-tools: Bash, Read, Grep, Glob
---

# Mark Telegram Chat as Read

Mark all messages in a chat as read, clearing unread badges and mentions.

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/telegram-cli}/scripts/send.py"

# Mark a chat as read
uv run --python 3.13 "$SCRIPT" mark-read <chat_id_or_username>

# Examples
uv run --python 3.13 "$SCRIPT" mark-read 2124832490
uv run --python 3.13 "$SCRIPT" mark-read @username
EOF
```

## Parameters

| Parameter | Type       | Description          |
| --------- | ---------- | -------------------- |
| chat      | string/int | Chat to mark as read |
