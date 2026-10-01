---
name: interactive-bot
description: Gmail Commander Telegram bot - slash commands, inline keyboards, compose and reply flow, AI free-text routing. Built by buildBot() in this plugin and run by a private Restate deployment. TRIGGERS - telegram bot, bot commands, inbox bot
allowed-tools: Read, Bash, Grep, Glob
---

# Interactive Bot

Gmail Commander Telegram bot — slash commands for email access + AI-powered free-text routing. This skill explains what the bot does and where its code lives; operating the running bot is covered by [bot-process-control](../bot-process-control/SKILL.md).

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Where it runs

The bot runs in a **private Restate tenant on an always-on Mac mini**. The tenant imports `buildBot()` from `scripts/bot.ts`, owns its own durable Telegram `getUpdates` chain, and feeds each update into the returned grammY bot through `bot.handleUpdate()`. There is no workstation daemon; the laptop launchd job was retired on 2026-09-24.

Do **not** start `scripts/bot.ts` directly with the production bot token to "test" it. Telegram allows one `getUpdates` consumer per token, so a second poller breaks the deployed bot with `409 Conflict`. Test against a separate bot token, or exercise the code by importing `buildBot()`.

## Mandatory Preflight

### Step 1: Check the bot code exists and still exports `buildBot`

```bash
PLUGIN="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander"
ls -la "$PLUGIN/scripts/bot.ts" 2>/dev/null || echo "SCRIPT_NOT_FOUND"
grep -n "export async function buildBot" "$PLUGIN/scripts/bot.ts" || echo "buildBot EXPORT MISSING — the deployment depends on it"
```

## Bot Commands (Sidebar Menu)

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

## Two-Tier Command System

**Tier 1 — Deterministic**: Slash commands call the Gmail CLI directly (through `scripts/lib/gmail-client.ts`, which runs the binary named by `GMAIL_CLI_BIN`).

**Tier 2 — Intelligent**: Free-text messages route through the Agent SDK (`HAIKU_MODEL`) with 4 Gmail MCP tools (list, search, read, draft).

## Safety Controls

- **Mutex**: 1 agent query at a time
- **Timeout**: `AGENT_TIMEOUT_MS` per query (2-minute default)
- **Circuit Breaker**: 3 failures in a row disables the agent for 10 minutes
- **Anti-contamination**: Skill contamination detection on all agent responses
- **Auth Guard**: Only responds to the authorized `TELEGRAM_CHAT_ID`

## Source Map

| Concern                                  | File                                                                     |
| ---------------------------------------- | ------------------------------------------------------------------------ |
| Wiring, compose/reply session flow       | [`scripts/bot.ts`](../../scripts/bot.ts) (`buildBot()`)                  |
| Command list and handlers                | [`scripts/lib/commands.ts`](../../scripts/lib/commands.ts)               |
| Inline-keyboard callbacks, session store | [`scripts/lib/callbacks.ts`](../../scripts/lib/callbacks.ts)             |
| Free-text routing, MCP tools             | [`scripts/lib/agent-router.ts`](../../scripts/lib/agent-router.ts)       |
| Email rendering, HTML escaping           | [`scripts/lib/telegram-format.ts`](../../scripts/lib/telegram-format.ts) |
| Message chunking (4096-char limit)       | [`scripts/lib/telegram-chunk.ts`](../../scripts/lib/telegram-chunk.ts)   |

## Post-Change Checklist

- [ ] YAML frontmatter valid (no colons in description)
- [ ] Trigger keywords current
- [ ] Path patterns use $HOME not hardcoded paths
- [ ] `buildBot()` still starts no transport and takes no PID lock on import

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
