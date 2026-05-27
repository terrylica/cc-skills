---
name: setup
description: user needs to set up Telegram CLI for the first time, authenticate or log in to a Telegram account, re-authenticate a session, or configure.
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

| Profile       | 1Password Item                   | Item UUID                    | Phone        |
| ------------- | -------------------------------- | ---------------------------- | ------------ |
| `eon`         | Telegram API - EonLabsOperations | `iqwxow2iidycaethycub7agfmm` | +16043008878 |
| `missterryli` | Telegram API - missterryli (CN)  | `dk456cs3v2fjilppernryoro5a` | +86 (CN)     |

## CRITICAL: Authentication Must Be Non-Interactive

`tg-cli.py whoami` uses `client.start()` which calls `input()` for phone/code. **This always fails in Claude Code** because Bash tool has no stdin. Never attempt interactive auth via the Bash tool or the `!` prefix.

### Correct Pattern: 3-Step Non-Interactive Auth

**Step 1: Fetch credentials from 1Password and delete expired session**

```bash
/usr/bin/env bash << 'STEP1_EOF'
PROFILE="eon"  # or "missterryli"
ITEM_UUID="iqwxow2iidycaethycub7agfmm"  # match profile

API_ID=$(op item get "$ITEM_UUID" --vault "Claude Automation" --fields "App ID")
API_HASH=$(op item get "$ITEM_UUID" --vault "Claude Automation" --fields "App API Hash" --reveal)
PHONE=$(op item get "$ITEM_UUID" --vault "Claude Automation" --fields "Phone Number")

echo "API_ID=$API_ID"
echo "PHONE=$PHONE"

# Delete expired session
rm -f ~/.local/share/telethon/${PROFILE}.session
STEP1_EOF
```

**Step 2: Send verification code request (non-interactive)**

```bash
VIRTUAL_ENV="" uv run --python 3.14 --no-project --with telethon python3 << 'PYEOF'
import asyncio, json, os
from telethon import TelegramClient

SESSION = os.path.expanduser("~/.local/share/telethon/eon")
API_ID = 18256514       # from Step 1
API_HASH = "..."        # from Step 1
PHONE = "+16043008878"  # from Step 1

async def request_code():
    client = TelegramClient(SESSION, API_ID, API_HASH)
    await client.connect()
    result = await client.send_code_request(PHONE)
    print(json.dumps({"phone_code_hash": result.phone_code_hash, "status": "code_sent"}))
    await client.disconnect()

asyncio.run(request_code())
PYEOF
```

Then use **AskUserQuestion** to get the verification code from the user.

**Step 3: Complete auth with the code (non-interactive)**

```bash
VIRTUAL_ENV="" uv run --python 3.14 --no-project --with telethon python3 << 'PYEOF'
import asyncio, os
from telethon import TelegramClient

SESSION = os.path.expanduser("~/.local/share/telethon/eon")
API_ID = 18256514
API_HASH = "..."
PHONE = "+16043008878"
CODE = "12345"                          # from AskUserQuestion
HASH = "abc123..."                      # phone_code_hash from Step 2

async def complete_auth():
    client = TelegramClient(SESSION, API_ID, API_HASH)
    await client.connect()
    await client.sign_in(phone=PHONE, code=CODE, phone_code_hash=HASH)
    me = await client.get_me()
    print(f"Authenticated as: {me.first_name} (@{me.username})")
    await client.disconnect()

asyncio.run(complete_auth())
PYEOF
```

### Anti-Patterns (NEVER DO)

| Anti-Pattern                                    | Why It Fails                                                                           |
| ----------------------------------------------- | -------------------------------------------------------------------------------------- |
| `uv run "$SCRIPT" -p eon whoami` for fresh auth | `client.start()` calls `input()` — EOFError in Claude Code                             |
| Telling user to run `! command` in prompt       | The `!` prefix also has no stdin for interactive prompts                               |
| Telling user to "open a separate terminal"      | Breaks the autonomous workflow — user has to leave Claude Code                         |
| Running `uv run` without `VIRTUAL_ENV=""`       | If cwd has a broken `.venv` symlink, uv inspects it and fails even with `--no-project` |
| Checking only session file existence            | Session file can exist but be expired (`is_user_authorized()` returns `False`)         |

## Preflight: Check Session Validity

Before any tlg operation, check if the session is still authorized:

```bash
VIRTUAL_ENV="" uv run --python 3.14 --no-project --with telethon python3 << 'PYEOF'
import asyncio, os
from telethon import TelegramClient

SESSION = os.path.expanduser("~/.local/share/telethon/eon")
API_ID = 18256514
API_HASH = "4b812166a74fbd4eaadf5c4c1c855926"

async def check():
    client = TelegramClient(SESSION, API_ID, API_HASH)
    await client.connect()
    authed = await client.is_user_authorized()
    if authed:
        me = await client.get_me()
        print(f"OK: {me.first_name} (@{me.username})")
    else:
        print("EXPIRED: session needs re-authentication")
    await client.disconnect()

asyncio.run(check())
PYEOF
```

If `EXPIRED`, run the 3-step non-interactive auth above. Do NOT fall through to `tg-cli.py` — it will EOFError.

## Session Management

| File                                          | Purpose                           |
| --------------------------------------------- | --------------------------------- |
| `~/.local/share/telethon/eon.session`         | EonLabsOperations MTProto session |
| `~/.local/share/telethon/missterryli.session` | missterryli MTProto session       |

Sessions expire when: revoked in Telegram Settings > Devices, or after prolonged inactivity. When expired, `is_user_authorized()` returns `False` but the session file still exists — always check auth state, not just file existence.

## Adding New Profiles

Edit the `PROFILES` dict in `scripts/tg-cli.py` and store credentials in 1Password vault `Claude Automation` with fields `App ID`, `App API Hash`, and `Phone Number`.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If tg-cli.py's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
