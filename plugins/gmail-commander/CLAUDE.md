# Gmail Commander Plugin

> Gmail + Telegram bot lifecycle — email triage, interactive commands, voice digest, 1Password OAuth.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [calcom-commander CLAUDE.md](../calcom-commander/CLAUDE.md)

**Skill**: [bot-process-control](./skills/bot-process-control/SKILL.md) — start/stop/restart/status/logs, launchd plist management, OAuth token diagnosis.

## Architecture

Two independent processes sharing `scripts/lib/`:

| Process    | Entry               | Trigger                  | Purpose                        |
| ---------- | ------------------- | ------------------------ | ------------------------------ |
| Bot Daemon | `scripts/bot.ts`    | launchd KeepAlive        | Interactive Telegram commands  |
| Digest     | `scripts/digest.ts` | launchd StartInterval 6h | Scheduled email triage + voice |

Gmail CLI (absorbed from gmail-tools): `scripts/gmail-cli/` — separate `package.json` + build process.

## Bot Commands (10 total)

| Command    | Description                                  |
| ---------- | -------------------------------------------- |
| `/inbox`   | Show recent inbox emails                     |
| `/search`  | Search emails (Gmail query syntax)           |
| `/read`    | Read email by ID                             |
| `/compose` | Compose a new email                          |
| `/reply`   | Reply to an email                            |
| `/abort`   | Cancel in-progress compose/reply at any step |
| `/drafts`  | List draft emails                            |
| `/digest`  | Run email digest now                         |
| `/status`  | Bot status and stats                         |
| `/help`    | Show all commands                            |

## OAuth Token Architecture

Two-layer token system:

```
Browser Auth (one-time, interactive)
  → Google issues: access_token (1h TTL) + refresh_token (7d TTL in Testing mode)
  → Saved to: ~/.claude/tools/gmail-tokens/<GMAIL_OP_UUID>.json

Hourly Refresher (automatic, launchd, no browser)
  → Swift binary: gmail-oauth-token-hourly-refresher
  → Reads: refresh_token from token JSON + client credentials from local cache
  → Writes: new access_token (+ expiry_date) back to token JSON
```

### Credential Cache (TCC Anti-Pattern Fix)

The hourly refresher uses a **two-file** strategy to avoid macOS TCC prompts:

| File                          | Contents                                 | Changes?                       |
| ----------------------------- | ---------------------------------------- | ------------------------------ |
| `<uuid>.json`                 | access_token, refresh_token, expiry_date | Every hour                     |
| `<uuid>.app-credentials.json` | client_id, client_secret                 | Never (static OAuth app creds) |

`client_id`/`client_secret` are fetched from 1Password **once** on first run and cached locally. All subsequent hourly runs read only local files → no `op` subprocess → no TCC prompt.

To force a fresh 1Password lookup (e.g., after rotating OAuth app credentials):

```bash
rm ~/.claude/tools/gmail-tokens/<uuid>.app-credentials.json
```

### Diagnosing `invalid_grant`

The refresh_token has a 7-day TTL in Google OAuth Testing mode. When it expires, the bot logs `invalid_grant`. Fix: delete the token file and re-auth via browser. See [bot-process-control SKILL.md](./skills/bot-process-control/SKILL.md#diagnosing-invalid_grant) for full diagnosis and fix steps.

## Environment Variables

| Variable                      | Required | Description                                                                               |
| ----------------------------- | -------- | ----------------------------------------------------------------------------------------- |
| `GMAIL_OP_UUID`               | Yes      | 1Password item UUID for OAuth credentials                                                 |
| `TELEGRAM_BOT_TOKEN`          | Yes      | Telegram bot token                                                                        |
| `TELEGRAM_CHAT_ID`            | Yes      | Authorized chat ID                                                                        |
| `HAIKU_MODEL`                 | Yes      | Claude model for triage (e.g. `claude-haiku-4-5-20251001`)                                |
| `OP_SERVICE_ACCOUNT_TOKEN`    | Yes      | 1Password service account (biometric-free)                                                |
| `AUDIT_DIR`                   | No       | Audit log directory (default: `~/own/amonic/logs/audit`, app-managed)                     |
| `BOT_STATE_FILE`              | No       | Bot state file path                                                                       |
| `GMAIL_OP_VAULT`              | No       | 1Password vault (default: `Claude Automation`)                                            |
| `GMAIL_COMMANDER_PROJECT_DIR` | No       | Project directory resolver; overrides auto-detection when running outside the plugin tree |
| `KOKORO_HOST`                 | No       | Kokoro TTS host for voice digest (default: `littleblack`)                                 |
| `KOKORO_PORT`                 | No       | Kokoro TTS port (default: `8090`)                                                         |

## Canonical Gmail draft builder + guard (2026-07-23)

**Every Gmail draft create/replace goes through `scripts/gmail-draft.ts`** — enforced by the
PreToolUse(Bash) hook `hooks/gmail-draft-guard.sh`, which BLOCKS ad-hoc drafts-API writes
(escape hatch: prefix the command with `GMAIL_DRAFT_ADHOC_OK=1`; read-only GET fetches pass).

**Why (regression 2026-07-23):** Gmail re-encodes ingested `text/plain` raw messages and
hard-folds long lines at ~72 columns, so ad-hoc drafts (python + MIMEText — often built from
markdown a formatter hook had already re-wrapped) show forced mid-paragraph line breaks in the
compose window. The builder is structurally immune: it unwraps blank-line-separated paragraphs
and produces `multipart/alternative` with a `text/html` part (source newlines never render — the
draft reflows exactly like one composed in Gmail's own editor).

```bash
bun $HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts \
  --account <tokenbase>            # token base name in ~/.claude/tools/gmail-tokens/
  --body <file.md>                 # body text; paragraphs unwrap, URLs auto-link
  --from 'Name <addr@gmail.com>' \
  [--reply-to <messageId>]         # derives Subject/In-Reply-To/References/threadId
  [--to a@b] [--cc c@d] [--subject '…'] [--replace <staleDraftId>]
# stdout: {"draftId":"…","threadId":"…","account":"…"}
```

Gotcha the builder also absorbs: Gmail's `drafts.update` rejects with `400 Message not a draft`
on threaded drafts — the tool always creates-then-deletes (`--replace`) instead of updating.

## Conventions

- **Hooks**: Use `$HOME`-based paths, never `$CLAUDE_PLUGIN_ROOT`
- **Skills**: Follow Suite Pattern (Template F) with mandatory preflight
- **CLI paths**: `$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail`
- **Sender alignment**: Auto-detect for replies, AskUserQuestion for new emails
- **Secrets**: `.mise.local.toml` (gitignored) in project directory

## Skills

- [bot-process-control](./skills/bot-process-control/SKILL.md)
- [email-triage](./skills/email-triage/SKILL.md)
- [gmail-access](./skills/gmail-access/SKILL.md)
- [health](./skills/health/SKILL.md)
- [interactive-bot](./skills/interactive-bot/SKILL.md)
- [setup](./skills/setup/SKILL.md)
