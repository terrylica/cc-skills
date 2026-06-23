---
name: send-message
description: user wants to send a text message on Telegram as their personal account via MTProto, text someone, or message a contact by username, phone, or.
allowed-tools: Bash, Read, Grep, Glob
---

# Send Telegram Message

Send a message from your personal Telegram account (not a bot) via MTProto.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Preflight

Before sending, verify the session is **authorized** (not just that the file exists):

```bash
bun "$SCRIPT" check-auth
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

**Sending to a topic via tg-cli.ts:** use the `--reply-to` flag with the topic's root_msg_id. See the Topic Registry section below for root_msg_id values.

```bash
bun "$SCRIPT" send --html --reply-to 5 -1003958083153 "<b>Policy update</b> ..."
```

## Auto-split for long messages

Telegram's hard limit is 4096 post-parsing chars per message. **tg-cli.ts `send` and `draft` both auto-split** messages exceeding ~3900 plain chars into multiple sequential posts, preserving HTML formatting and section structure.

**Split algorithm**: splits at the finest-grained safe boundary that fits all chunks:

1. `\n\n━━━━━━━━━━━━━━\n\n` (major section separator, preferred)
2. `\n━━━━━━━━━━━━━━\n` (section separator)
3. `\n\n` (paragraph break)
4. `\n` (line break)
5. Hard character split (last resort — prints warning; may break tags)

Each continuation chunk gets a `<i>(Part N/M)</i>` header prepended so recipients see the sequence clearly. All parts share the same `--reply-to` target so a multi-part post stays in one topic thread.

**You do NOT need to manually split messages anymore.** Compose the full HTML as one string, pass to `send`, and the splitter handles it.

**Size-aware authoring guidance**: prefer messages that fit in one post (≤ 3900 plain chars) — splits add visual overhead with part headers. If a message is naturally larger (e.g., a pinned reference), let the splitter do its job. Structure with `━━━━━━━━━━━━━━` separators so split boundaries land cleanly between logical sections.

## Usage: tg-cli.ts (when session is valid)

> **When in doubt, USE `--html`.** If your message contains ANY of: `<b>`, `<i>`, `<code>`, `<pre>`, `<a href>`, bold headers, inline code, or markdown-style `**bold**` / `` `code` ``, you MUST either pass `--html` (and translate markdown → HTML tags first) or strip the decoration. Sending Telegram-style markdown without `--html` renders the asterisks and backticks literally to the recipient. For multi-section messages with headers, separators, and code spans — **always** use `--html`.
>
> Recovery pattern when you've already sent a mangled message: send a follow-up prefixed `Correction — earlier message rendered as raw text, corrected version below:` then the correctly-HTML-formatted content. Do NOT silently edit if the message has been read (see "Editing Discipline" below).

```bash
/usr/bin/env bash << 'SEND_EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/tg-cli.ts"

# Default: plain text (use only for single-line unformatted messages)
bun "$SCRIPT" send @username "Hello"

# HTML formatting — the recommended default for any structured message
bun "$SCRIPT" send --html -1003958083153 "<b>Bold header</b>

Body with <code>inline code</code> and <a href='https://example.com'>a link</a>."

# By chat ID (groups use negative IDs)
bun "$SCRIPT" send -1003958083153 "Hello group"

# Specific profile
bun "$SCRIPT" -p missterryli send @username "Hello"

# Edit a message by ID
bun "$SCRIPT" edit -1003958083153 12345 "<b>Updated text</b>"

# Delete a message by ID
bun "$SCRIPT" delete -1003958083153 12345
SEND_EOF
```

**Long HTML messages**: `tg-cli.ts send --html` auto-splits at the 3900-plain-char threshold. Compose the full HTML as one string and let the splitter handle it. See "Auto-split for long messages" above.

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

## Telegram HTML Formatting Reference

GramJS uses HTML, not Markdown:

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

To send a message to a specific topic, pass `reply_to=<root_msg_id>` in `send_message()` or use `--reply-to` in tg-cli.ts.

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

| Anti-Pattern                                        | Why It Fails                                                         |
| --------------------------------------------------- | -------------------------------------------------------------------- |
| Running `bun "$SCRIPT"` without checking auth first | If session expired, auth will fail                                   |
| Checking only session file existence in preflight   | Session file can exist but be expired — must check with `check-auth` |
| Using plain text for formatted messages             | GramJS uses HTML, not Markdown. Use `--html` flag for formatting     |

## Error Handling

| Error                     | Cause                   | Fix                                                         |
| ------------------------- | ----------------------- | ----------------------------------------------------------- |
| `Unknown profile`         | Invalid `-p` value      | Use `eon` or `missterryli`                                  |
| `Cannot find any entity`  | Bad username/ID         | Verify with `dialogs` command or use `find-user` to resolve |
| `message cannot be empty` | Empty string passed     | Provide message text                                        |
| `Session expired`         | Session no longer valid | Run `/tlg:setup` to re-authenticate non-interactively       |

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If tg-cli.ts's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
