# Gmail Commander Plugin

> Gmail CLI + draft builder for interactive use, plus the shared Telegram bot code that an unattended deployment imports. 1Password OAuth.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [calcom-commander CLAUDE.md](../calcom-commander/CLAUDE.md)

**Skill**: [bot-process-control](./skills/bot-process-control/SKILL.md) — where the bot and digest actually run, how to check them, and what never to start on a workstation.

**Skill**: [mailbox-consolidation](./skills/mailbox-consolidation/SKILL.md) — folding consumer Gmail and other-tenant mailboxes into one shared Workspace inbox: the mechanism per source, the routing-rule spam default that silently drops copies, and forward-first-then-final-import.

## Where things run

Nothing in this plugin runs as a background job on a workstation any more. The laptop launchd jobs `com.example.gmail-commander-bot` and `com.example.gmail-commander-digest` were retired on 2026-09-24; do not recreate them, and do not add launchd templates back to this plugin.

| Component           | Where it runs                                                                  | Entry point in this plugin                      |
| ------------------- | ------------------------------------------------------------------------------ | ----------------------------------------------- |
| Gmail CLI (`gmail`) | Interactively, wherever an agent or the operator calls it                      | `scripts/gmail-cli/` (compiled to `gmail`)      |
| Draft builder       | Interactively                                                                  | `scripts/gmail-draft.ts`                        |
| Interactive bot     | A private Restate tenant on an always-on Mac mini (`GmailBot`, `GmailBotChat`) | `scripts/bot.ts` → `buildBot()`, `scripts/lib/` |
| Scheduled digest    | The same tenant (`GmailDigest`), with its own implementation                   | none — see below                                |
| OAuth token minting | The same tenant (`GmailAuth`), from a refresh token held in its secret store   | none                                            |

The tenant is deployed from a **private repository**, and every operational task for it — deploy, restart, logs, secret rotation, OAuth re-consent — follows that repository's runbook. This public plugin deliberately carries no host names, deploy commands or credential locations for it.

### The contract the deployment depends on

The deployment bundles this plugin's code at deploy time and ships the CLI binary, so the following are load-bearing. Changing them changes what runs in production, silently, on the next deploy:

- `scripts/bot.ts` exports `buildBot()`, which returns `{ bot, state, config }` with every command, callback and the compose/reply session flow registered, and starts no transport. The tenant owns its own durable `getUpdates` chain and feeds each update in through `bot.handleUpdate()`.
- Importing `scripts/bot.ts` must never take the PID lock or start polling. `main()` is guarded by `import.meta.main` for exactly that reason: Telegram permits one `getUpdates` consumer per token, and a second poller makes both unreliable (the tenant pages on the resulting `409 Conflict`).
- `scripts/lib/*` is imported through `bot.ts` (bot factory, commands, callbacks, state, audit, Gmail client, formatting, chunking, agent router, circuit breaker, triage). Keep every export behaviour-identical.
- `scripts/lib/gmail-client.ts` shells out to the `gmail` binary. `GMAIL_CLI_BIN` points it at the shipped copy; without it the default is the marketplace path, which exists only on a workstation.
- `scripts/gmail-cli/` is shipped as a directory. Build the binary from the committed lockfile (`bun install --frozen-lockfile && bun run build`) so every build resolves the same dependency tree.

The scheduled digest does **not** use this plugin's code.

## Bot Commands (10 total)

SSoT: `BOT_COMMANDS` in [`scripts/lib/commands.ts`](./scripts/lib/commands.ts).

| Command    | Description                                  |
| ---------- | -------------------------------------------- |
| `/inbox`   | Show recent inbox emails                     |
| `/search`  | Search emails (Gmail query syntax)           |
| `/read`    | Read email by ID                             |
| `/compose` | Compose a new email                          |
| `/reply`   | Reply to an email                            |
| `/abort`   | Cancel in-progress compose/reply at any step |
| `/drafts`  | List draft emails                            |
| `/digest`  | Triage the last N hours now (default 6)      |
| `/status`  | Bot status and stats                         |
| `/help`    | Show all commands                            |

## OAuth Token Architecture (interactive CLI)

Two-layer token system for the CLI on a workstation:

```
Browser Auth (one-time, interactive)
  → Google issues: access_token (1h TTL) + refresh_token (7d TTL in Testing mode)
  → Saved to: ~/.claude/tools/gmail-tokens/<GMAIL_OP_UUID>.json

Silent refresh (automatic, no browser)
  → The CLI refreshes an expired access_token itself on the next call
  → An optional operator-local hourly refresher can keep the cached token warm
```

### Credential Cache (TCC Anti-Pattern Fix)

The CLI uses a **two-file** strategy so repeated calls never prompt:

| File                          | Contents                                 | Changes?                       |
| ----------------------------- | ---------------------------------------- | ------------------------------ |
| `<uuid>.json`                 | access_token, refresh_token, expiry_date | On every refresh               |
| `<uuid>.app-credentials.json` | client_id, client_secret                 | Never (static OAuth app creds) |

`client_id`/`client_secret` are fetched from 1Password **once** on first run and cached locally. Subsequent runs read only local files → no `op` subprocess → no TCC prompt.

To force a fresh 1Password lookup (e.g., after rotating OAuth app credentials):

```bash
rm ~/.claude/tools/gmail-tokens/<uuid>.app-credentials.json
```

### Diagnosing `invalid_grant`

When the refresh token expires, the CLI reports `invalid_grant`. Fix for the CLI: move the token file aside and re-consent via browser — see [gmail-access SKILL.md](./skills/gmail-access/SKILL.md#diagnosing-invalid_grant). The deployment holds its own refresh token; renewing that one is a runbook task in the private repository.

## Environment Variables

| Variable                   | Read by                          | Required | Description                                                                |
| -------------------------- | -------------------------------- | -------- | -------------------------------------------------------------------------- |
| `GMAIL_OP_UUID`            | CLI, `lib/gmail-client.ts`       | Yes      | 1Password item UUID for OAuth credentials; also names the token cache file |
| `GMAIL_OP_VAULT`           | CLI                              | No       | 1Password vault (default: `Employee`)                                      |
| `OP_SERVICE_ACCOUNT_TOKEN` | `op` (first run only)            | No       | 1Password service account for biometric-free `op read`                     |
| `TELEGRAM_BOT_TOKEN`       | `lib/bot-factory.ts`, formatting | Bot      | Telegram bot token                                                         |
| `TELEGRAM_CHAT_ID`         | `lib/bot-factory.ts`, formatting | Bot      | The one authorized chat ID                                                 |
| `HAIKU_MODEL`              | `lib/agent-router.ts`, commands  | Bot      | Claude model for triage and free-text routing                              |
| `GMAIL_CLI_BIN`            | `lib/gmail-client.ts`            | No       | Path to the `gmail` binary (default: the marketplace path)                 |
| `CLAUDE_BIN`               | agent router, commands           | No       | Explicit `claude` executable for the Agent SDK                             |
| `AGENT_TIMEOUT_MS`         | `lib/agent-router.ts`            | No       | Per-query timeout for free-text routing                                    |
| `AUDIT_DIR`                | `bot.ts`, `lib/audit.ts`         | No       | NDJSON audit log directory                                                 |
| `BOT_STATE_FILE`           | `bot.ts`, `lib/state.ts`         | No       | Bot state file path                                                        |

In the deployment these are injected from its own secret store at deploy time. None of them belongs in a workstation env file on the bot's behalf.

## Canonical Gmail draft builder + guard

**Every Gmail draft create/replace goes through `scripts/gmail-draft.ts`** — enforced by the PreToolUse(Bash) hook `hooks/gmail-draft-guard.sh`, which BLOCKS ad-hoc drafts-API writes (escape hatch: prefix the command with `GMAIL_DRAFT_ADHOC_OK=1`; read-only GET fetches pass).

→ **Four guards now stand between a composed message and a draft** (builder enforcement, mojibake detection, a builder test gate, and a post-write read-back). What each is _observed_ to do, how two of them were caught silently not working, and the both-directions checks to re-run after touching any of them: [`docs/draft-integrity-guards.md`](./docs/draft-integrity-guards.md).

**Why:** Gmail hard-folds ingested `text/plain` at about 72 columns, so ad-hoc drafts show mid-paragraph breaks. The builder sends `multipart/alternative` with a `text/html` part, so the draft reflows like one composed in Gmail.

**Write emphasis in Markdown; it arrives as rich text.** In the body file, `**bold**`, `*italic*` or `_italic_`, and `` `code` `` become real bold, italic and code in the HTML part, and the plain-text part drops the markers. Identifiers stay literal (`snake_case_name`, `2*3*4`). Never hand-write HTML or leave asterisks for the recipient to read.

```bash
bun $HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts \
  --account <tokenbase>            # token base name in ~/.claude/tools/gmail-tokens/
  --body <file.md>                 # body text; paragraphs unwrap, URLs auto-link
  --from 'Name <addr@example.com>' \
  [--reply-to <messageId>]         # derives Subject/In-Reply-To/References/threadId
  [--to a@b] [--cc c@d] [--subject '…'] [--replace <staleDraftId>]
# stdout: {"draftId":"…","threadId":"…","account":"…"}
```

## Nothing here sends mail: send guard and the token directory

**No tool in this plugin sends Gmail, and none may be written ad hoc.** A human sends every draft from Gmail, where the From line is visible. `hooks/gmail-send-guard.ts` denies direct calls to the send endpoints and raw reads of the cached OAuth tokens in `~/.claude/tools/gmail-tokens/`, on Bash, Write, Edit, MultiEdit, Read and Grep. A message sent without a From header goes out under the account's **default** send-as identity, and on 2026-10-08 that was the wrong identity on both accounts a raw send used.

To see which mailbox each cached token owns, its send-as aliases and which one is the default, run the sanctioned reader (it never prints a token):

```bash
bun $HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-accounts.ts [--account <tokenbase>] [--json]
```

What the guard catches, what it allows, its escape token and its known gaps: [`docs/gmail-send-guard.md`](./docs/gmail-send-guard.md).

Gotcha the builder also absorbs: Gmail's `drafts.update` rejects with `400 Message not a draft` on threaded drafts — the tool always creates-then-deletes (`--replace`) instead of updating.

## Hooks

| Hook                         | Event                                                 | Purpose                                                             |
| ---------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------- |
| `gmail-draft-guard.sh`       | PreToolUse (Bash)                                     | Blocks ad-hoc drafts-API writes; drafts go through `gmail-draft.ts` |
| `gmail-mojibake-detector.sh` | PreToolUse (Bash)                                     | Blocks drafts whose Subject or body carries UTF-8-as-Latin-1 bytes  |
| `gmail-send-guard.ts`        | PreToolUse (Bash, Write, Edit, MultiEdit, Read, Grep) | Denies direct Gmail sends and raw reads of the cached OAuth tokens  |

## Conventions

- **Hooks**: Use `$HOME`-based paths, never `$CLAUDE_PLUGIN_ROOT`
- **Skills**: Follow Suite Pattern (Template F) with mandatory preflight
- **CLI paths**: `$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail`
- **CLI build**: from the committed `scripts/gmail-cli/bun.lock` with `bun install --frozen-lockfile && bun run build`; the compiled binary itself is gitignored
- **Sender alignment**: Auto-detect for replies, AskUserQuestion for new emails

## Skills

- [bot-process-control](./skills/bot-process-control/SKILL.md)
- [email-triage](./skills/email-triage/SKILL.md)
- [gmail-access](./skills/gmail-access/SKILL.md)
- [health](./skills/health/SKILL.md)
- [interactive-bot](./skills/interactive-bot/SKILL.md)
- [mailbox-consolidation](./skills/mailbox-consolidation/SKILL.md)
- [setup](./skills/setup/SKILL.md)
