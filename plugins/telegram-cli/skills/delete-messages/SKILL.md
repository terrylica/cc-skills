---
name: delete-messages
description: "Delete messages from Telegram chats. Supports deleting for everyone or self only. TRIGGERS - telegram delete, delete telegram message, telegram remove message, telegram unsend"
allowed-tools: Bash, Read, Grep, Glob
---

# Delete Telegram Messages

Delete one or multiple messages from a chat. By default deletes for everyone.

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/telegram-cli}/scripts/send.py"

# Delete for everyone (default)
uv run --python 3.13 "$SCRIPT" delete <chat> <message_id>

# Delete multiple messages
uv run --python 3.13 "$SCRIPT" delete <chat> 12345,12346,12347

# Delete only for yourself
uv run --python 3.13 "$SCRIPT" delete <chat> <message_id> --self-only

# Find message IDs first
uv run --python 3.13 "$SCRIPT" read <chat> -n 10
EOF
```

## Parameters

| Parameter     | Type       | Description                                      |
| ------------- | ---------- | ------------------------------------------------ |
| chat          | string/int | Chat containing messages                         |
| message_ids   | string     | Message ID(s), comma-separated                   |
| `--self-only` | flag       | Delete only for yourself (default: for everyone) |

## Workflow

1. Use `read <chat> -n N` to find message IDs
2. Delete by ID: `delete <chat> <ids>`

## Anti-Patterns

- **Cannot delete others' messages** in private chats after 48 hours
- **Admin required** to delete others' messages in groups
