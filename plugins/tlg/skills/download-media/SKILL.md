---
name: download-media
description: "Download media files (photos, videos, documents) from Telegram messages. TRIGGERS - telegram download, download telegram, telegram save, telegram get file, telegram export media"
allowed-tools: Bash, Read, Grep, Glob
---

# Download Telegram Media

Download photos, videos, documents, and other media from Telegram messages.

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/send.py"

# Step 1: Find message ID with media
uv run --python 3.13 "$SCRIPT" read <chat> -n 10

# Step 2: Download by message ID
uv run --python 3.13 "$SCRIPT" download <chat> <message_id>

# Download to specific directory
uv run --python 3.13 "$SCRIPT" download 2124832490 471931 -o /tmp/downloads
EOF
```

## Parameters

| Parameter     | Type       | Description                         |
| ------------- | ---------- | ----------------------------------- |
| chat          | string/int | Chat containing the message         |
| message_id    | int        | ID of message with media            |
| `-o/--output` | path       | Output directory (default: current) |

## Workflow

1. Use `read <chat> -n N` to browse messages and find IDs
2. Messages with media show `[media/service]` in text
3. Use `download <chat> <id>` to save the file

## Error Handling

| Error               | Cause              | Fix                         |
| ------------------- | ------------------ | --------------------------- |
| `message not found` | Invalid message ID | Check with `read` first     |
| `has no media`      | Text-only message  | Choose a message with media |
