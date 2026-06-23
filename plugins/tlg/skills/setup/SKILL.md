---
name: setup
description: user needs to set up Telegram CLI for the first time, authenticate or log in to a Telegram account, re-authenticate an expired session, or configure a profile.
allowed-tools: Bash, Read, Write, AskUserQuestion
disable-model-invocation: false
---

# Telegram CLI Setup

One-time (or re-)authentication of a personal Telegram account for the GramJS CLI.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Engine + session model (read first)

The CLI uses **GramJS** (MTProto). Each profile's login is a **GramJS StringSession**
stored at `~/.local/share/gramjs/<profile>.session`. The Telegram API id/hash come
from 1Password at runtime. (Historical note: this replaced the Telethon/`uv`
implementation in 2026-06; old `~/.local/share/telethon/*.session` files are not
reused — accounts log in once more here.)

```bash
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/tg-cli.ts"
```

## Profiles

| Profile       | 1Password Item                   | Item UUID                    | Phone        |
| ------------- | -------------------------------- | ---------------------------- | ------------ |
| `eon`         | Telegram API - EonLabsOperations | `iqwxow2iidycaethycub7agfmm` | +16043008878 |
| `missterryli` | Telegram API - missterryli (CN)  | `dk456cs3v2fjilppernryoro5a` | +86 (CN)     |

## Prerequisites

- `bun` available, and deps installed once: `cd "$(dirname "$SCRIPT")" && bun install`
- 1Password CLI (`op`) signed in; the item above present in the `Claude Automation` vault.

## Auth is non-interactive (3 steps)

The Bash tool has no stdin, so the CLI never prompts. Authentication is split into
`send-code` (requests the code) and `sign-in` (submits it). Get the code from the
user with **AskUserQuestion** between the two steps.

### Step 0 — check current state (no SMS sent)

```bash
bun "$SCRIPT" check-auth eon    # exit 0 + JSON if authorized; exit 1 if not
```

If it reports `authorized: true`, you're done. Otherwise continue.

### Step 1 — request a login code

```bash
bun "$SCRIPT" send-code eon
# → JSON: { "status": "code_sent", "phone": "...", "phone_code_hash": "<HASH>", ... }
```

Telegram delivers the code to the account's **Telegram app first**, then SMS. The
code **expires within a couple of minutes** — move straight to Step 2.

### Step 2 — get the code from the user (AskUserQuestion)

Ask the user for the digits (they type them in the "Other" box). Also ask whether
they have two-factor (cloud password) enabled.

### Step 3 — sign in with the code

```bash
bun "$SCRIPT" sign-in eon --code <CODE> --hash <HASH>
# 2FA enabled? add: --password '<cloud password>'
# → JSON: { "authorized": true, "user_id": ..., "username": ..., "session_file": ... }
```

Run `sign-in` **once** per code — a failed/duplicate attempt invalidates the code
(`PHONE_CODE_EXPIRED`); if that happens, redo Step 1 for a fresh code.

### Step 4 — verify

```bash
bun "$SCRIPT" whoami -p eon
```

## Anti-Patterns (NEVER DO)

| Anti-Pattern                                         | Why It Fails                                                             |
| ---------------------------------------------------- | ------------------------------------------------------------------------ |
| Expecting an interactive login prompt                | The CLI never reads stdin; use `send-code` + `sign-in`                   |
| Running `sign-in` twice with the same code           | The first attempt consumes it → `PHONE_CODE_EXPIRED`; request anew       |
| Dawdling between `send-code` and `sign-in`           | Codes expire in ~minutes; collect the code immediately and sign in       |
| Reusing an old `~/.local/share/telethon` session     | Wrong format/engine — GramJS sessions live under `~/.local/share/gramjs` |
| Checking only file existence for "is it authorized?" | A session file can exist but be expired — use `check-auth`               |

## Session Management

| File                                        | Purpose                         |
| ------------------------------------------- | ------------------------------- |
| `~/.local/share/gramjs/eon.session`         | EonLabsOperations StringSession |
| `~/.local/share/gramjs/missterryli.session` | missterryli StringSession       |

Sessions expire when revoked in Telegram → Settings → Devices, or after prolonged
inactivity. When expired, `check-auth` reports `authorized: false`; rerun the 3-step flow.

## Adding New Profiles

Add the profile to the `PROFILES` map in `scripts/tg-cli.ts` and store credentials in
the `Claude Automation` 1Password vault with fields `App ID`, `App API Hash`, and
`Phone Number`. (Override per-invocation with `TELEGRAM_API_ID`/`TELEGRAM_API_HASH`
env vars to skip 1Password.)

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did `check-auth` confirm an authorized session?** If not, fix the step/error that blocked it.
2. **Did the CLI's auth interface drift?** If `send-code`/`sign-in` flags changed, update the commands above.
3. **Was a workaround needed?** Capture it here so the next setup doesn't rediscover it.

Only update if the issue is real and reproducible — not speculative.
