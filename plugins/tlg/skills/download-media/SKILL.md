---
name: download-media
description: "Use when user wants to download, save, or extract media files such as photos, videos, and documents from Telegram messages."
allowed-tools: Bash, Read, Grep, Glob
---

# Download Telegram Media

Download photos, videos, documents, and other media from Telegram messages.

## Preflight

1. Session must exist: `~/.local/share/telethon/<profile>.session`
   - If missing, run `/tlg:setup` first

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/send.py"

# Step 1: Find message ID with media
uv run --python 3.13 "$SCRIPT" read <chat> -n 10

# Step 2: Download by message ID
uv run --python 3.13 "$SCRIPT" download <chat> <message_id>

# Download to specific directory
uv run --python 3.13 "$SCRIPT" download 2124832490 471931 -o ./downloads
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

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If send.py's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
