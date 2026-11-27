---
name: list-dialogs
description: "Use when the user wants to list Telegram chats, groups, channels or contacts, find a chat ID, browse conversations, or check account info via whoami."
allowed-tools: Bash, Read, Grep, Glob
---

# List Telegram Dialogs

List all chats, groups, and channels visible to your personal Telegram account.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Preflight

1. Session must exist: `~/.local/share/gramjs/<profile>.session`
   - If missing, run `/tlg:setup` first

## Usage

```bash
/usr/bin/env bash << 'DIALOGS_EOF'
ROOT="$(cc-plugin-root tlg)"
SCRIPT="$ROOT/scripts/tg-cli.ts"

# Default profile
bun "$SCRIPT" dialogs

# Specific profile
bun "$SCRIPT" -p personal dialogs

# Filter results
bun "$SCRIPT" dialogs | grep -i "search term"
DIALOGS_EOF
```

## Additional Commands

### Read Messages

`read` returns the **full text** of every message by default. Multi-line bodies are indented under the header so the message stays visually grouped. No truncation.

```bash
# Full text (default — recommended)
bun "$SCRIPT" read <chat_id> -n 10

# Short scan listing — truncate each body to N chars (\n flattened to "⏎")
bun "$SCRIPT" read <chat_id> -n 50 --preview 200
```

Use `--preview N` only when you're scanning many messages and want a single-line summary per row. For routine reading, omit it — long messages deserve to be read in full, not silently cut at 200 chars (the prior default, which forced repeated manual workarounds when content mattered).

### What a listed line shows

`read`, `search` and `thread` print one line per message (`scripts/message-format.ts`):

```
[2026-11-26 11:59:51 PCT] (id:812) Ann Lee: ↩805 好的，我明白
    ❝只看第三张图❞
[2026-11-26 11:40:02 PCT] (id:806) Carol: album:13975… (edited) [fwd from Bob] [photo] caption text
```

| Marker                  | Meaning (Telegram field)                                                                                           |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `↩N`                    | This message **replies to** message N (`replyTo.replyToMsgId`). `↩N@channel:C`: the parent is in another chat.      |
| `❝…❞` on the next line  | The part of message N the sender **selected and quoted** (`replyTo.quoteText`), not the whole parent.              |
| `topic:T`               | The message sits in forum topic T. A message that only sits in a topic is not shown as a reply to the topic root. |
| `album:G`               | One item of an album; the album's other items are separate messages with the same G (usually adjacent ids).       |
| `(edited)`              | Edited after sending (`editDate`).                                                                                |
| `[fwd from X]`, `[fwd]` | Forwarded; X is the origin's name or peer, `[fwd]` when Telegram names none.                                      |
| `[photo]`, `[document]` | The media kind, shown **beside** a caption too (`MessageMedia*`). `[web page]` is only a link preview.            |
| `[service: …]`          | A service message (pin, join, title change: `MessageAction*`).                                                    |

Times are the machine's local zone with its label (e.g. PCT); `--utc` prints UTC.

### Context around one message, and what a reply answers

```bash
bun "$SCRIPT" read <chat> --around 812 -n 20   # 20 messages centred on 812 (marked ▶)
bun "$SCRIPT" read <chat> --after 805 -n 30    # the 30 messages after 805
bun "$SCRIPT" read <chat> --before 805 -n 30   # the 30 messages before it
bun "$SCRIPT" read <chat> --topic 5 -n 20         # one forum topic
bun "$SCRIPT" read <chat> -n 50 --json            # the same records as dump, as JSON

bun "$SCRIPT" thread <chat> 812                # climb the ↩ chain: oldest first, ending at 812 (▶)
bun "$SCRIPT" thread <chat> 812 --replies      # also the later replies to it (scans the next 300 messages)
```

`--around ID -n N` lists the target, about N/2 older and N/2 newer messages (N+1 lines). `--topic 1` (a forum's General topic) is not a real thread and has not been checked live: read the whole chat instead. Counts (`-n`, `--depth`, `--scan`) must be at least 1, because GramJS reads 0 as "no limit".

`thread` stops at a message that replies to nothing, a forum topic's root, a deleted parent, a parent in another chat, a cycle, or `--depth` (default 20), and says which. When someone quotes or replies to an old message you do not recognise, run `thread` on their message before answering: the quoted part (`❝…❞`) and the chain show what they are answering.

In private chats and basic groups, message ids are numbered across the whole account, not per chat, so neighbouring ids are not neighbouring messages: use `--around`, never id ± k.

### Account Info

```bash
bun "$SCRIPT" whoami
```

## Output Format

```
Chat Name                                  (id: 1234567890)
```

Use the `id` value with `send-message` skill to send to that chat.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If tg-cli.ts's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
