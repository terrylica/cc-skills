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

# HTML formatting (bold, italic, code, etc.)
uv run --python 3.13 "$SCRIPT" send --html -5111414203 "<b>Bold</b> and <code>code</code>"

# Specific profile
uv run --python 3.13 "$SCRIPT" -p personal send @username "Hello"
SEND_EOF
```

## Usage: Direct Telethon (for multi-message sequences, files, or when tg-cli.py fails)

When you need multi-message sequences, file attachments with captions, or tg-cli.py fails, use Telethon directly. For simple HTML messages, prefer `tg-cli.py send --html` above:

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

### Editing Discipline — unread vs. read

**The core principle**: edit silently only when you are confident the recipient has NOT read the message yet. Once someone has seen a message, editing it risks creating a false record and confusing them (they remember the original text; the chat now shows different text).

| Situation                                                                                                          | Action                                                                  |
| ------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| You sent a message <30s ago in an active async chat and nobody has touched Telegram since                          | **Edit is safe** — iterate freely                                       |
| You just sent a message with a typo or factual error and the recipient has not responded                           | **Edit is safe** — they likely have not read it yet                     |
| The recipient has replied to your message                                                                          | **Do NOT edit silently** — send a supplement                            |
| The recipient has read the message but not yet replied (you see read receipts or their typing indicator came/went) | **Do NOT edit silently** — send a supplement                            |
| You're not sure whether the recipient has read it                                                                  | **Default to supplement** — safer than confusing them                   |
| The message has been cited or quoted by others in the chat                                                         | **Do NOT edit** — the citation is now stale context; supplement instead |

**Supplement pattern** (when edit is unsafe):

```
Correction on my previous message: <specific change>
```

or

```
Update to what I said above: <new info that supersedes>
```

Make the supplement self-contained so a reader scrolling back understands without having to cross-reference.

**Why this matters**: silent edits of read messages are one of the most confusing UX anti-patterns in chat systems. The recipient remembers "Terry told me X", sees "X'" now, and wonders if their memory is wrong or if they're being gaslit. Edits are a privilege to use before observation, not to rewrite history.

**How to tell if it's been read**: Telegram's MTProto exposes read receipts in 1:1 and small group chats via `messages.readHistoryOutbox` updates, but in large groups this is unreliable. The safest heuristic is time + activity: if more than ~60 seconds have elapsed and/or the recipient has been active in the chat, assume they saw it.

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

### Horizontal separator rules (enforced convention)

Use `━` (U+2501) for horizontal rules between sections in long messages.

**Length rule**: **14 characters preferred, 22 characters absolute maximum.**

- **Preferred**: `━━━━━━━━━━━━━━` (14 × `━`)
- **Acceptable ceiling**: `━━━━━━━━━━━━━━━━━━━━━━` (22 × `━`, = 14 + 8)
- **Never exceed** 22 characters — longer separators look visually unbalanced on mobile clients and push body content off-screen.

Rationale: Telegram's mobile client reflows body text but does NOT wrap separator lines of box-drawing characters. A 28-char separator forces horizontal scrolling on narrow phones; 14 char fits cleanly in every viewport and still reads as a clear section break. If you need more visual weight, use a heading (`<b>...</b>`) above the separator rather than making the separator longer.

Emojis are supported but user may prefer decorations without emojis — use `<pre>` blocks and box-drawing characters instead.

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

| Anti-Pattern                                           | Why It Fails                                                                       |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| Running `uv run "$SCRIPT"` without checking auth first | If session expired, `client.start()` calls `input()` — EOFError                    |
| Running `uv run` without `VIRTUAL_ENV=""`              | Broken `.venv` symlink in cwd causes uv to fail even with `--no-project`           |
| Checking only session file existence in preflight      | Session file can exist but be expired — must check `is_user_authorized()`          |
| Using Markdown parse mode                              | Telethon MTProto uses HTML, not Markdown. Use `--html` flag or `parse_mode='html'` |

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
