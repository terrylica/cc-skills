---
name: send-message
description: "Use when user wants to send a text message on Telegram as their personal account via MTProto, text someone, or message a contact by username, phone, or chat ID."
allowed-tools: Bash, Read, Grep, Glob
---

# Send Telegram Message

Send a message from your personal Telegram account (not a bot) via MTProto.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Preflight

Before sending, verify:

1. Session exists at `~/.local/share/telethon/<profile>.session`
   - If missing, run `/tlg:setup` first
2. 1Password CLI available: `op --version`

## Usage

```bash
/usr/bin/env bash << 'SEND_EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/send.py"

# Default profile (eon)
uv run --python 3.13 "$SCRIPT" send @username "Hello"

# By chat ID
uv run --python 3.13 "$SCRIPT" send 2124832490 "Hello"

# Specific profile
uv run --python 3.13 "$SCRIPT" -p missterryli send @username "Hello"
SEND_EOF
```

## Profiles

| Profile         | Account            | User ID    |
| --------------- | ------------------ | ---------- |
| `eon` (default) | @EonLabsOperations | 90417581   |
| `missterryli`   | @missterryli       | 2124832490 |

## Parameters

| Parameter      | Type       | Description                                                 |
| -------------- | ---------- | ----------------------------------------------------------- |
| `-p/--profile` | string     | Account profile (default: eon)                              |
| recipient      | string/int | Username (@user), phone (+1234567890), or chat ID (integer) |
| message        | string     | Message text (cannot be empty)                              |

## Error Handling

| Error                     | Cause               | Fix                           |
| ------------------------- | ------------------- | ----------------------------- |
| `Unknown profile`         | Invalid `-p` value  | Use `eon` or `missterryli`    |
| `Cannot find any entity`  | Bad username/ID     | Verify with `dialogs` command |
| `message cannot be empty` | Empty string passed | Provide message text          |

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If send.py's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
