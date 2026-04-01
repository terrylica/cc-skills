---
name: list-dialogs
description: "Use when user wants to list all Telegram chats, groups, and channels, see their contacts, find a chat ID, browse conversations, or check account info via whoami."
allowed-tools: Bash, Read, Grep, Glob
---

# List Telegram Dialogs

List all chats, groups, and channels visible to your personal Telegram account.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Preflight

1. Session must exist: `~/.local/share/telethon/<profile>.session`
   - If missing, run `/tlg:setup` first

## Usage

```bash
/usr/bin/env bash << 'DIALOGS_EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/send.py"

# Default profile
uv run --python 3.13 "$SCRIPT" dialogs

# Specific profile
uv run --python 3.13 "$SCRIPT" -p missterryli dialogs

# Filter results
uv run --python 3.13 "$SCRIPT" dialogs | grep -i "search term"
DIALOGS_EOF
```

## Additional Commands

### Read Messages

```bash
uv run --python 3.13 "$SCRIPT" read <chat_id> -n 10
```

### Account Info

```bash
uv run --python 3.13 "$SCRIPT" whoami
```

## Output Format

```
Chat Name                                  (id: 1234567890)
```

Use the `id` value with `send-message` skill to send to that chat.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If send.py's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
