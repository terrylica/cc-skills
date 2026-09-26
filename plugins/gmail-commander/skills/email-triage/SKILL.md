---
name: email-triage
description: Gmail Commander email triage - the three-category Haiku prompt and parser in lib/triage.ts, run on demand by the bot's /digest command. The scheduled digest runs in a private deployment with its own implementation. TRIGGERS - email digest, triage emails, digest categories
allowed-tools: Read, Bash, Grep, Glob
---

# Email Triage

How Gmail Commander sorts recent email into what needs attention, and where each digest actually comes from.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Two different digests — do not confuse them

| Digest                      | Trigger                                  | Code                                                                    |
| --------------------------- | ---------------------------------------- | ----------------------------------------------------------------------- |
| On-demand `/digest [hours]` | A user sends it to the bot (default 6 h) | This plugin: `scripts/lib/commands.ts` + `scripts/lib/triage.ts`        |
| Scheduled digest            | Several times a day, unattended          | The private deployment's `GmailDigest` service — its own implementation |

The scheduled digest runs in a **private Restate tenant on an always-on Mac mini** and does not import this plugin's triage code. Its schedule, prompt, alerting and failures are operated through that deployment's own repository runbook.

This plugin no longer ships a scheduled digest entry point: the laptop launchd job `com.terryli.gmail-commander-digest` was retired on 2026-09-24, and its `scripts/digest.ts` (with the Kokoro podcast-style voice briefing in `scripts/lib/tts-client.ts`) was removed on 2026-09-26 once nothing imported it. Do not recreate either.

## Mandatory Preflight

### Step 1: Check the triage code exists

```bash
PLUGIN="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander"
ls -la "$PLUGIN/scripts/lib/triage.ts" 2>/dev/null || echo "TRIAGE_NOT_FOUND"
```

### Step 2: Verify the Gmail CLI binary (the triage input comes from it)

```bash
ls -la "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail" 2>/dev/null || echo "BINARY_NOT_FOUND"
```

**If BINARY_NOT_FOUND**: Build it from the committed lockfile:

```bash
cd "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli" && bun install --frozen-lockfile && bun run build
```

## Three-Category Triage System

| Category          | Examples                                                          |
| ----------------- | ----------------------------------------------------------------- |
| SYSTEM & SECURITY | Exchange alerts, 2FA codes, password resets, new device logins    |
| WORK              | Deadlines, invoices, contracts, GitHub PRs, professional requests |
| PERSONAL & FAMILY | Friends/family messages, appointments, vehicle service, health    |

Urgency levels within each: CRITICAL > HIGH > MEDIUM > LOW. When nothing qualifies, the model answers exactly `NO_SIGNIFICANT_EMAILS` and the bot reports a quiet window.

## Pipeline (`/digest [hours]`)

1. `fetchRecentEmails(hours)` runs `gmail search newer_than:<hours>h -n 50 --json` through `GMAIL_CLI_BIN`.
2. `formatEmailsForTriage()` renders the messages; `ANTI_SKILL_PREFIX` is prepended so the model ignores any skill or tool listings in its context.
3. One Agent SDK call with `TRIAGE_SYSTEM_PROMPT` on `HAIKU_MODEL` (no tools, one turn).
4. `isSkillContaminated()` discards a response that role-plays a skill instead of triaging.
5. `parseTriageResponse()` turns the text into typed items, and `formatDigestHtml()` renders them with the category and urgency emoji maps.

## Source Map

| Concern                                  | File                                                                     |
| ---------------------------------------- | ------------------------------------------------------------------------ |
| System prompt, anti-skill prefix, parser | [`scripts/lib/triage.ts`](../../scripts/lib/triage.ts)                   |
| `/digest` command handler                | [`scripts/lib/commands.ts`](../../scripts/lib/commands.ts)               |
| Category/urgency emoji maps, digest HTML | [`scripts/lib/telegram-format.ts`](../../scripts/lib/telegram-format.ts) |
| Gmail fetch                              | [`scripts/lib/gmail-client.ts`](../../scripts/lib/gmail-client.ts)       |

## Post-Change Checklist

- [ ] YAML frontmatter valid (no colons in description)
- [ ] Trigger keywords current
- [ ] Path patterns use $HOME not hardcoded paths
- [ ] `lib/triage.ts` exports unchanged in shape (the bot and its deployment import them)

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
