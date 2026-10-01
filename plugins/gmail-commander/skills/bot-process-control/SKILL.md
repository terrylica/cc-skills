---
name: bot-process-control
description: Gmail Commander bot and digest process control - they run unattended in a private Restate deployment, never as workstation launchd jobs. Where they run, how to check them, what not to start locally. TRIGGERS - bot start, bot stop, bot restart, bot status, gmail bot down
allowed-tools: Read, Bash, Grep, Glob
---

# Bot Process Control

Where the Gmail Commander bot and scheduled digest run, how to tell whether they are healthy, and what must never be started on a workstation.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Where the processes live

Neither process runs on a workstation. Both run in a **private Restate tenant on an always-on Mac mini**, deployed from a private repository:

| Service        | Role                                                                                                |
| -------------- | --------------------------------------------------------------------------------------------------- |
| `GmailBot`     | Owns the Telegram `getUpdates` chain (one durable, self-re-arming poll) and dispatches each update  |
| `GmailBotChat` | Runs one update through the grammY bot built by this plugin's `buildBot()`, in per-chat order       |
| `GmailDigest`  | Scheduled email digest to Telegram, several times a day (its own implementation, not this plugin's) |
| `GmailAuth`    | Mints Gmail access tokens on demand from a refresh token held in the deployment's secret store      |

**Starting, stopping, restarting, deploying, reading logs, rotating secrets and OAuth re-consent are all done through that repository's runbook.** This public skill intentionally carries no host names, deploy commands or credential paths for it. If you do not have access to that repository, stop and ask the operator.

The laptop launchd jobs `com.terryli.gmail-commander-bot` and `com.terryli.gmail-commander-digest` were **retired on 2026-09-24**. Do not recreate their plists, launcher scripts or env files.

## Mandatory Preflight

### Step 1: Confirm nothing is running locally (read-only)

```bash
echo "=== Local gmail-commander launchd jobs (expected: none) ==="
launchctl list | grep -F gmail-commander || echo "none"

echo ""
echo "=== Local gmail-commander plists (expected: none) ==="
ls ~/Library/LaunchAgents 2>/dev/null | grep -F gmail-commander || echo "none"

echo ""
echo "=== Local standalone bot process (expected: none) ==="
pgrep -fl "gmail-commander/scripts/bot.ts" || echo "none"
```

If any of these finds something, **report it to the operator instead of loading, unloading or killing it yourself**: a live local poller competes with the tenant for the same bot token.

### Step 2: Check the deployed bot from the user's side

The one check that needs no deployment access: send `/status` to the bot in its Telegram chat. A reply with uptime and counters means `GmailBotChat` is handling updates. No reply within a minute means the poll chain or the tenant is down — escalate through the runbook.

## Never start a second poller

`scripts/bot.ts` still has a standalone long-polling `main()`, guarded by `import.meta.main` so that importing `buildBot()` never polls. **Do not run it with the production bot token.** Telegram allows exactly one `getUpdates` consumer per token; a second one makes Telegram answer `409 Conflict` and both pollers become unreliable, and the tenant pages the operator when it sees that conflict.

The standalone entry point exists for other installations of this public plugin, with their own bot token. It takes a PID lock at `/tmp/gmail-commander-bot.pid` and reads the variables listed in the [plugin CLAUDE.md](../../CLAUDE.md#environment-variables). This plugin no longer ships process-supervisor templates for it.

## Telegram Commands

| Command  | Description                             |
| -------- | --------------------------------------- |
| /inbox   | Show recent inbox emails                |
| /search  | Search emails (Gmail query syntax)      |
| /read    | Read email by ID                        |
| /compose | Compose a new email                     |
| /reply   | Reply to an email                       |
| /abort   | Cancel current compose/reply action     |
| /drafts  | List draft emails                       |
| /digest  | Triage the last N hours now (default 6) |
| /status  | Bot status and stats                    |
| /help    | Show all commands                       |

> **Note**: `/abort` cancels any in-progress compose or reply session. Works at any step in the flow.

## OAuth failures in the deployment

When Google rejects the deployment's refresh token (`invalid_grant`), `GmailAuth` pages the operator. Recovery needs a browser consent on a workstation and a secret update in the deployment, both described in the private runbook. The CLI's own `invalid_grant` recovery on a workstation is a different token and is covered in [gmail-access](../gmail-access/SKILL.md#diagnosing-invalid_grant).

## Post-Change Checklist

- [ ] YAML frontmatter valid (no colons in description)
- [ ] Trigger keywords current
- [ ] Path patterns use $HOME not hardcoded paths
- [ ] No launchd templates, host names or credential paths reintroduced
- [ ] `buildBot()` contract in the plugin CLAUDE.md still matches `scripts/bot.ts`

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
