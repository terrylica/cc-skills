---
name: forward-message
description: "Use when user wants to forward, relay, or copy Telegram messages from one chat to another, supporting both single and batch forwarding."
allowed-tools: Bash, Read, Grep, Glob
---

# Forward Telegram Messages

Forward one or multiple messages between chats.

## Preflight

1. Session must exist: `~/.local/share/telethon/<profile>.session`
   - If missing, run `/tlg:setup` first

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/send.py"

# Forward single message
uv run --python 3.13 "$SCRIPT" forward <from_chat> <message_id> <to_chat>

# Forward multiple messages (comma-separated IDs)
uv run --python 3.13 "$SCRIPT" forward 2124832490 471920,471921 90417581

# Get message IDs first with read command
uv run --python 3.13 "$SCRIPT" read <chat> -n 5
EOF
```

## Workflow

1. Use `read` to find message IDs: `read <chat> -n 10`
2. Forward by ID: `forward <from> <id> <to>`

## Parameters

| Parameter   | Type       | Description                    |
| ----------- | ---------- | ------------------------------ |
| from_chat   | string/int | Source chat                    |
| message_ids | string     | Message ID(s), comma-separated |
| to_chat     | string/int | Destination chat               |
