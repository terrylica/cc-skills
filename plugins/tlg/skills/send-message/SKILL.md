---
name: send-message
description: "Use when user wants to send a text message on Telegram as their personal account via MTProto, text someone, or message a contact by username, phone, or chat ID."
allowed-tools: Bash, Read, Grep, Glob
---

# Send Telegram Message

Send a message from your personal Telegram account (not a bot) via MTProto.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Preflight

Before sending, verify the session is **authorized** (not just that the file exists):

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

## Usage: tg-cli.py (when session is valid)

```bash
/usr/bin/env bash << 'SEND_EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/tg-cli.py"

# Default profile (eon)
uv run --python 3.13 "$SCRIPT" send @username "Hello"

# By chat ID (groups use negative IDs)
uv run --python 3.13 "$SCRIPT" send -5111414203 "Hello group"

# Specific profile
uv run --python 3.13 "$SCRIPT" -p personal send @username "Hello"
SEND_EOF
```

## Usage: Direct Telethon (preferred for HTML formatting, files, or when tg-cli.py fails)

When you need HTML parse mode, multi-message sequences, or file attachments with captions, bypass `tg-cli.py` and use Telethon directly. This was proven more reliable in practice:

```bash
VIRTUAL_ENV="" uv run --python 3.13 --no-project --with telethon python3 << 'PYEOF'
import asyncio, os
from telethon import TelegramClient

SESSION = os.path.expanduser("~/.local/share/telethon/eon")
API_ID = 18256514
API_HASH = "4b812166a74fbd4eaadf5c4c1c855926"
CHAT_ID = -5111414203  # negative for groups

MSG = """<b>Bold title</b>
<i>Italic subtitle</i>

<pre>
Preformatted block
</pre>

<code>inline code</code>

Normal text with <b>decorations</b>."""

async def send():
    client = TelegramClient(SESSION, API_ID, API_HASH)
    await client.connect()
    await client.send_message(CHAT_ID, MSG, parse_mode='html')
    print("Sent.")
    await client.disconnect()

asyncio.run(send())
PYEOF
```

### Sending files with captions

```bash
VIRTUAL_ENV="" uv run --python 3.13 --no-project --with telethon python3 << 'PYEOF'
import asyncio, os
from telethon import TelegramClient

SESSION = os.path.expanduser("~/.local/share/telethon/eon")
API_ID = 18256514
API_HASH = "4b812166a74fbd4eaadf5c4c1c855926"
CHAT_ID = -5111414203

CAPTION = """<b>File Title</b>

Description of the file contents."""

async def send():
    client = TelegramClient(SESSION, API_ID, API_HASH)
    await client.connect()
    await client.send_file(CHAT_ID, "/path/to/file.md", caption=CAPTION, parse_mode='html')
    print("File sent.")
    await client.disconnect()

asyncio.run(send())
PYEOF
```

### Editing a previously sent message

```bash
VIRTUAL_ENV="" uv run --python 3.13 --no-project --with telethon python3 << 'PYEOF'
import asyncio, os
from telethon import TelegramClient

SESSION = os.path.expanduser("~/.local/share/telethon/eon")
API_ID = 18256514
API_HASH = "4b812166a74fbd4eaadf5c4c1c855926"
CHAT_ID = -5111414203

async def edit():
    client = TelegramClient(SESSION, API_ID, API_HASH)
    await client.connect()
    # Get recent messages to find the one to edit
    async for msg in client.iter_messages(CHAT_ID, limit=10, from_user='me'):
        print(f"ID: {msg.id} | {msg.text[:80] if msg.text else '(file)'}...")
    # Edit by message ID:
    # await client.edit_message(CHAT_ID, msg_id, new_text, parse_mode='html')
    await client.disconnect()

asyncio.run(edit())
PYEOF
```

### Deleting messages

```bash
# Delete specific messages by ID
await client.delete_messages(CHAT_ID, [msg_id1, msg_id2])
```

## Telegram HTML Formatting Reference

Telegram supports a subset of HTML (not Markdown in MTProto):

| Tag                             | Renders As        |
| ------------------------------- | ----------------- |
| `<b>text</b>`                   | **Bold**          |
| `<i>text</i>`                   | _Italic_          |
| `<u>text</u>`                   | Underline         |
| `<s>text</s>`                   | ~~Strikethrough~~ |
| `<code>text</code>`             | `Inline code`     |
| `<pre>text</pre>`               | Code block        |
| `<a href="url">text</a>`        | Hyperlink         |
| `<tg-spoiler>text</tg-spoiler>` | Spoiler           |

Use `━` (U+2501) for horizontal rules. Emojis are supported but user may prefer decorations without emojis — use `<pre>` blocks and box-drawing characters instead.

## Profiles

| Profile         | Account            | User ID    |
| --------------- | ------------------ | ---------- |
| `eon` (default) | @ExampleOpsAccount | 90417581   |
| `personal`   | @personal       | 2124832490 |

## Known Group Chat IDs

| Group                  | Chat ID     |
| ---------------------- | ----------- |
| Terry & MD (Bruntwork) | -5111414203 |

## Anti-Patterns (NEVER DO)

| Anti-Pattern                                           | Why It Fails                                                              |
| ------------------------------------------------------ | ------------------------------------------------------------------------- |
| Running `uv run "$SCRIPT"` without checking auth first | If session expired, `client.start()` calls `input()` — EOFError           |
| Running `uv run` without `VIRTUAL_ENV=""`              | Broken `.venv` symlink in cwd causes uv to fail even with `--no-project`  |
| Checking only session file existence in preflight      | Session file can exist but be expired — must check `is_user_authorized()` |
| Using Markdown parse mode                              | Telethon MTProto uses HTML, not Markdown. Use `parse_mode='html'`         |

## Error Handling

| Error                                 | Cause                                       | Fix                                                                   |
| ------------------------------------- | ------------------------------------------- | --------------------------------------------------------------------- |
| `Unknown profile`                     | Invalid `-p` value                          | Use `eon` or `personal`                                            |
| `Cannot find any entity`              | Bad username/ID                             | Verify with `dialogs` command or use direct Telethon `iter_dialogs()` |
| `message cannot be empty`             | Empty string passed                         | Provide message text                                                  |
| `EOFError: EOF when reading a line`   | Session expired, `client.start()` triggered | Run `/tlg:setup` to re-authenticate non-interactively                 |
| `Broken symlink at .venv/bin/python3` | cwd has corrupt venv                        | Prepend `VIRTUAL_ENV=""` to the command                               |

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If tg-cli.py's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
