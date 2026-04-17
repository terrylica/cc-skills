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

## Supergroup-First Methodology

The Bruntwork group (`-1003958083153`) is a **supergroup with Topics**. All messages to this group MUST target a specific topic — never post to the bare supergroup without a topic target.

**Why supergroup over basic chat:**

- **Server-global message IDs.** Every member sees the same `id=N` for each message. Both sides' Claude Code resolves citations identically — no viewer-qualifier needed, no cross-boundary ambiguity.
- **Topic namespaces.** Policies don't get buried between daily check-ins. Each subject has its own searchable thread with independent pins.
- **AI-agent addressability.** Claude Code can target reads/writes to specific topics via `reply_to_msg_id`, enabling precise routing: "post this bug report to Bug Reports" or "search Policies for the carve-out decision."
- **Emoji reactions as acknowledgment signals.** Reactions are programmatically readable via `message.reactions.results` — enables lightweight ACK checking without requiring a text reply.

**Topic selection discipline:** When composing a message, select the most specific topic from the Topic Registry below. Use General only as a fallback. Never cross-post the same message to multiple topics.

**Citation convention:** Bare `id=N` citations resolve identically for every member. When referencing a prior message, cite its ID. Claude Code on both sides can look it up autonomously via `client.get_messages(supergroup_id, ids=N)`.

**Sending to a topic via tg-cli.py:** Currently tg-cli.py does not have a `--reply-to` flag. For topic-targeted messages, use Direct Telethon with `reply_to=<root_msg_id>`. See the Topic Registry section for root_msg_id values.

**Sending to a topic via Direct Telethon:**

```python
await client.send_message(-1003958083153, message, parse_mode="html", reply_to=TOPIC_ROOT_ID)
```

## Usage: tg-cli.py (when session is valid)

> **When in doubt, USE `--html`.** If your message contains ANY of: `<b>`, `<i>`, `<code>`, `<pre>`, `<a href>`, bold headers, inline code, or markdown-style `**bold**` / `` `code` ``, you MUST either pass `--html` (and translate markdown → HTML tags first) or strip the decoration. Sending Telegram-style markdown without `--html` renders the asterisks and backticks literally to the recipient. For multi-section messages with headers, separators, and code spans — **always** use `--html`.
>
> Recovery pattern when you've already sent a mangled message: send a follow-up prefixed `Resend — earlier message rendered as raw markdown, readable version below:` then the correctly-HTML-formatted content. Do NOT silently edit if the message has been read (see "Editing Discipline" below).

```bash
/usr/bin/env bash << 'SEND_EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/tg-cli.py"

# Default: plain text (use only for single-line unformatted messages)
uv run --python 3.13 "$SCRIPT" send @username "Hello"

# HTML formatting — the recommended default for any structured message
uv run --python 3.13 "$SCRIPT" send --html -1003958083153 "<b>Bold header</b>

Body with <code>inline code</code> and <a href='https://example.com'>a link</a>."

# By chat ID (groups use negative IDs)
uv run --python 3.13 "$SCRIPT" send -1003958083153 "Hello group"

# Specific profile
uv run --python 3.13 "$SCRIPT" -p missterryli send @username "Hello"
SEND_EOF
```

**Long HTML messages**: when the body has multiple paragraphs, bullets, separators, or code blocks, prefer the "Direct Telethon" pattern below — it avoids shell-quoting hell on multi-line bodies and is what actually works reliably for operator-written messages with structure.

## Usage: Direct Telethon (for multi-message sequences, files, or when tg-cli.py fails)

When you need multi-message sequences, file attachments with captions, or tg-cli.py fails, use Telethon directly. For simple HTML messages, prefer `tg-cli.py send --html` above:

```bash
VIRTUAL_ENV="" uv run --python 3.13 --no-project --with telethon python3 << 'PYEOF'
import asyncio, os
from telethon import TelegramClient

SESSION = os.path.expanduser("~/.local/share/telethon/eon")
API_ID = 18256514
API_HASH = "4b812166a74fbd4eaadf5c4c1c855926"
CHAT_ID = -1003958083153  # negative for groups

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
CHAT_ID = -1003958083153

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
CHAT_ID = -1003958083153

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
| `eon` (default) | @EonLabsOperations | 90417581   |
| `missterryli`   | @missterryli       | 2124832490 |

## Known Group Chat IDs

| Group                  | Chat ID        | Type                                                           |
| ---------------------- | -------------- | -------------------------------------------------------------- |
| Terry & MD (Bruntwork) | -1003958083153 | Supergroup                                                     |
| Terry & MD (Bruntwork) | -1003958083153 | Legacy basic chat (pre-2026-04-16, read-only for old messages) |

## Topic Registry (Bruntwork Supergroup)

To send a message to a specific topic, pass `reply_to=<root_msg_id>` in `send_message()` or use `--reply-to` in tg-cli.py.

| Topic                      | root_msg_id | Scope                                                  |
| -------------------------- | ----------- | ------------------------------------------------------ |
| General                    | 1           | Catch-all, quick questions                             |
| Assignments & Deliverables | 2           | Task definitions, PR reviews, Block check-ins          |
| Daily Operations           | 3           | Commencement/disembarkation, shift status              |
| Onboarding & Access        | 4           | Repo access, SSH/Tailscale, tool provisioning          |
| Policy & Standards         | 5           | cc-skills carve-out, conventions, discipline           |
| Bug Reports & Incidents    | 6           | Merge conflicts, hook bugs, pipeline breaks            |
| Tool Setup & Config        | 7           | ccmax-monitor, FlowSurface, chronicle pipeline         |
| Knowledge Base & Learning  | 8           | KB pages, research material, skill references          |
| HR & Scheduling            | 9           | Shift hours, Bruntwork coordination                    |
| Session Monitor            | 185         | Real-time Claude Code session summaries (CC Nasim Bot) |

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
| `Unknown profile`                     | Invalid `-p` value                          | Use `eon` or `missterryli`                                            |
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
