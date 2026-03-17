---
name: setup
description: "First-time Telegram CLI setup - authenticate your personal account and configure 1Password credentials. TRIGGERS - telegram setup, telegram auth, telegram login, configure telegram cli"
allowed-tools: Bash, Read, Write, AskUserQuestion
disable-model-invocation: true
---

# Telegram CLI Setup

One-time setup to authenticate your personal Telegram account via MTProto.

## Prerequisites

- 1Password CLI installed: `op --version`
- Telegram API credentials stored in 1Password vault `Claude Automation`
  - Item: `Telegram API - ExampleOpsAccount`
  - Fields: `App ID` (text), `App API Hash` (concealed)
  - Get credentials from: <https://my.telegram.org> → API development tools

## Setup Steps

### Step 1: Verify 1Password Access

```bash
op item get "<1password-item-id>" --vault "Claude Automation" --fields "App ID" 2>&1
```

If this fails, ensure 1Password CLI is authenticated.

### Step 2: First-Time Authentication (INTERACTIVE — must run in terminal)

This step requires interactive terminal input. The user must run this command directly:

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/telegram-cli}"
uv run --python 3.13 "$PLUGIN_DIR/scripts/send.py" dialogs
```

Prompts for:

1. Phone number (e.g., `+16043008878`)
2. Verification code (sent via Telegram)
3. 2FA password (if enabled)

Session saved to `~/.local/share/telethon/session.session`.

### Step 3: Verify

After auth, the dialogs command should list all your chats without prompting.

## Session Management

| File                                      | Purpose                   |
| ----------------------------------------- | ------------------------- |
| `~/.local/share/telethon/session.session` | Persisted MTProto session |

To re-authenticate (e.g., after revoking session in Telegram settings):

```bash
rm ~/.local/share/telethon/session.session
# Then re-run the dialogs command above
```

## Credential Reference

| Source    | Item                               | Vault               |
| --------- | ---------------------------------- | ------------------- |
| 1Password | `Telegram API - ExampleOpsAccount` | `Claude Automation` |
| Item UUID | `<1password-item-id>`       | —                   |
