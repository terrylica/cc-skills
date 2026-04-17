---
name: send-media
description: "Use when user wants to send or upload a file, photo, video, voice note, or document on Telegram via their personal account."
allowed-tools: Bash, Read, Grep, Glob
---

# Send Media on Telegram

Send files, photos, videos, voice notes, and documents from your personal Telegram account.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Preflight

Check session is **authorized** (not just that the file exists):

```bash
VIRTUAL_ENV="" uv run --python 3.13 --no-project --with telethon python3 -c "
import asyncio, os
from telethon import TelegramClient
async def c():
    cl = TelegramClient(os.path.expanduser('~/.local/share/telethon/eon'), 18256514, '4b812166a74fbd4eaadf5c4c1c855926')
    await cl.connect()
    print('OK' if await cl.is_user_authorized() else 'EXPIRED')
    await cl.disconnect()
asyncio.run(c())
"
```

If `EXPIRED`, run `/tlg:setup` first (uses 3-step non-interactive auth pattern).

## Usage: tg-cli.py (simple cases)

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/tg-cli.py"

# Send a photo/image (auto-detected)
uv run --python 3.13 "$SCRIPT" send-file @username /path/to/photo.jpg

# Send with caption
uv run --python 3.13 "$SCRIPT" send-file -1003958083153 /path/to/image.png -c "Check this out"

# Force send as document (no preview)
uv run --python 3.13 "$SCRIPT" send-file @username /path/to/image.png --document
EOF
```

## Usage: Direct Telethon (preferred for HTML captions and multi-file sends)

When you need HTML-formatted captions or need to send multiple files in sequence, bypass `tg-cli.py` and use Telethon directly. This pattern was proven reliable:

```bash
VIRTUAL_ENV="" uv run --python 3.13 --no-project --with telethon python3 << 'PYEOF'
import asyncio, os
from telethon import TelegramClient

SESSION = os.path.expanduser("~/.local/share/telethon/eon")
API_ID = 18256514
API_HASH = "4b812166a74fbd4eaadf5c4c1c855926"
CHAT_ID = -1003958083153  # negative for groups

CAPTION = """<b>File Title</b>

<pre>
- Item one
- Item two
- Item three
</pre>"""

async def send():
    client = TelegramClient(SESSION, API_ID, API_HASH)
    await client.connect()

    # Single file with HTML caption
    await client.send_file(CHAT_ID, "/path/to/file.md",
                           caption=CAPTION, parse_mode='html')

    # Multiple files in sequence
    files = ["/path/to/file1.md", "/path/to/file2.md"]
    captions = ["<b>First file</b>", "<b>Second file</b>"]
    for f, c in zip(files, captions):
        await client.send_file(CHAT_ID, f, caption=c, parse_mode='html')

    print("All files sent.")
    await client.disconnect()

asyncio.run(send())
PYEOF
```

## Parameters (tg-cli.py)

| Parameter      | Type       | Description                            |
| -------------- | ---------- | -------------------------------------- |
| recipient      | string/int | Username, phone, or chat ID            |
| file           | path       | Local file path                        |
| `-c/--caption` | string     | Caption text (plain text only via CLI) |
| `--voice`      | flag       | Send as voice note                     |
| `--video-note` | flag       | Send as round video                    |
| `--document`   | flag       | Force document (no media preview)      |

## Supported Formats

Telethon auto-detects media type by extension. Override with flags.

| Type     | Extensions        | Notes                                |
| -------- | ----------------- | ------------------------------------ |
| Photo    | jpg, png, webp    | Compressed by Telegram               |
| Video    | mp4, mov, avi     | Use `--document` to skip compression |
| Audio    | mp3, m4a, flac    | Sent as audio player                 |
| Voice    | ogg (opus)        | Requires `--voice` flag              |
| Document | pdf, zip, md, any | Sent as file attachment              |

## Anti-Patterns (NEVER DO)

| Anti-Pattern                                                       | Why It Fails                                                              |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------- |
| Running `uv run` without `VIRTUAL_ENV=""` when using inline python | Broken `.venv` in cwd causes uv to fail even with `--no-project`          |
| Using `tg-cli.py send-file` with HTML in `-c` caption              | CLI caption is plain text — use direct Telethon for `parse_mode='html'`   |
| Checking only session file existence in preflight                  | Session file can exist but be expired — must check `is_user_authorized()` |

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If tg-cli.py's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
