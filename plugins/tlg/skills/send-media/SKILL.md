---
name: send-media
description: "Use when user wants to send or upload a file, photo, video, voice note, or document on Telegram via their personal account."
allowed-tools: Bash, Read, Grep, Glob
---

# Send Media on Telegram

Send files, photos, videos, voice notes, and documents from your personal Telegram account.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Preflight

1. Session must exist: `~/.local/share/telethon/<profile>.session`
   - If missing, run `/tlg:setup` first

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/send.py"

# Send a photo/image (auto-detected)
uv run --python 3.13 "$SCRIPT" send-file @username /path/to/photo.jpg

# Send with caption
uv run --python 3.13 "$SCRIPT" send-file 2124832490 /path/to/image.png -c "Check this out"

# Send as voice note (.ogg recommended)
uv run --python 3.13 "$SCRIPT" send-file @username /path/to/audio.ogg --voice

# Send as round video note
uv run --python 3.13 "$SCRIPT" send-file @username /path/to/clip.mp4 --video-note

# Force send as document (no preview)
uv run --python 3.13 "$SCRIPT" send-file @username /path/to/image.png --document

# Send with specific profile
uv run --python 3.13 "$SCRIPT" -p missterryli send-file @username /path/to/file.pdf
EOF
```

## Parameters

| Parameter      | Type       | Description                       |
| -------------- | ---------- | --------------------------------- |
| recipient      | string/int | Username, phone, or chat ID       |
| file           | path       | Local file path                   |
| `-c/--caption` | string     | Caption text                      |
| `--voice`      | flag       | Send as voice note                |
| `--video-note` | flag       | Send as round video               |
| `--document`   | flag       | Force document (no media preview) |

## Supported Formats

Telethon auto-detects media type by extension. Override with flags.

| Type     | Extensions     | Notes                                |
| -------- | -------------- | ------------------------------------ |
| Photo    | jpg, png, webp | Compressed by Telegram               |
| Video    | mp4, mov, avi  | Use `--document` to skip compression |
| Audio    | mp3, m4a, flac | Sent as audio player                 |
| Voice    | ogg (opus)     | Requires `--voice` flag              |
| Document | pdf, zip, any  | Sent as file attachment              |

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If send.py's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
