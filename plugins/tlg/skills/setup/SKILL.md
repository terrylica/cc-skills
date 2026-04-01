---
name: setup
description: "Use when user needs to set up Telegram CLI for the first time, authenticate or log in to a Telegram account, re-authenticate a session, or configure 1Password credentials for Telegram access."
allowed-tools: Bash, Read, Write, AskUserQuestion
disable-model-invocation: false
---

# Telegram CLI Setup

One-time setup to authenticate personal Telegram accounts via MTProto.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Prerequisites

- 1Password CLI installed: `op --version`
- Telegram API credentials stored in 1Password vault `Claude Automation`

## Available Profiles

| Profile       | 1Password Item                   | Item UUID                    | Phone    |
| ------------- | -------------------------------- | ---------------------------- | -------- |
| `eon`         | Telegram API - ExampleOpsAccount | `<1password-item-id>` | +1 (CA)  |
| `personal` | Telegram API - personal (CN)  | `<1password-item-id>` | +86 (CN) |

## Setup Steps

### Step 1: Verify 1Password Access

```bash
/usr/bin/env bash << 'VERIFY_EOF'
op item get "<1password-item-id>" --vault "Claude Automation" --fields "App ID" 2>&1
op item get "<1password-item-id>" --vault "Claude Automation" --fields "App ID" 2>&1
VERIFY_EOF
```

### Step 2: Authenticate (INTERACTIVE - must run in terminal)

Each profile requires a one-time interactive auth. The user must run directly:

```bash
/usr/bin/env bash << 'AUTH_EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/send.py"

# Auth eon profile
uv run --python 3.13 "$SCRIPT" -p eon whoami

# Auth personal profile
uv run --python 3.13 "$SCRIPT" -p personal whoami
AUTH_EOF
```

Prompts for:

1. Phone number
2. Verification code (sent via Telegram)
3. 2FA password (if enabled)

### Step 3: Verify

```bash
/usr/bin/env bash << 'VERIFY_EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/send.py"
uv run --python 3.13 "$SCRIPT" -p eon whoami
uv run --python 3.13 "$SCRIPT" -p personal whoami
VERIFY_EOF
```

## Session Management

| File                                          | Purpose                           |
| --------------------------------------------- | --------------------------------- |
| `~/.local/share/telethon/eon.session`         | ExampleOpsAccount MTProto session |
| `~/.local/share/telethon/personal.session` | personal MTProto session       |

To re-authenticate (e.g., after revoking session in Telegram > Settings > Devices):

```bash
rm ~/.local/share/telethon/<profile>.session
# Then re-run whoami for that profile
```

## Adding New Profiles

Edit the `PROFILES` dict in `scripts/send.py`:

```python
PROFILES: dict[str, str] = {
    "eon": "<1password-item-id>",
    "personal": "<1password-item-id>",
    "newprofile": "<1password-item-uuid>",
}
```

Then store API credentials in 1Password vault `Claude Automation` with fields `App ID` and `App API Hash`.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If send.py's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
