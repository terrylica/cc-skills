---
name: setup
description: Gmail Commander setup wizard - Gmail OAuth via a 1Password item, build the Gmail CLI from its lockfile, verify access. The Telegram bot and digest are deployed elsewhere and are not installed here.
allowed-tools: Bash, Read, Write, AskUserQuestion, Edit
disable-model-invocation: false
---

# Gmail Commander Setup

Set up interactive Gmail access on this machine: find the OAuth credentials in 1Password, build the Gmail CLI, and prove it can read the intended mailbox.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Scope — what this wizard does NOT do

The interactive Telegram bot and the scheduled digest run unattended in a **private Restate deployment on an always-on Mac mini**, not on a workstation. This wizard installs no launchd jobs, launcher scripts or daemon env files, and it must not: the laptop jobs were retired on 2026-09-24, and a second bot poller on the same token breaks the deployed one. Provisioning the deployment (bot token, chat ID, Gmail refresh token, model settings) is done through its own repository's runbook. What the deployment needs from this plugin is listed in the [plugin CLAUDE.md](../../CLAUDE.md#the-contract-the-deployment-depends-on).

## Prerequisites Check

```bash
command -v op && echo "OK 1Password CLI" || echo "MISSING: brew install 1password-cli"
command -v proto && echo "OK proto" || echo "MISSING: brew install proto"
command -v bun && echo "OK bun" || echo "MISSING: proto install bun"
```

## Phase 1: Gmail OAuth Setup

### Step 1: Check if already configured

```bash
echo "GMAIL_OP_UUID: ${GMAIL_OP_UUID:-NOT_SET}"
```

If already set, use AskUserQuestion to ask if user wants to reconfigure.

### Step 2: Discover 1Password items

```bash
op item list --vault Employee --format json | jq -r '.[] | select(.title | test("gmail|oauth"; "i")) | "\(.id)\t\(.title)"'
```

### Step 3: Present options

Use AskUserQuestion with discovered items or guide new credential creation.

### Step 4: Supply the UUID

Use the item **UUID**, not its title — the token cache is keyed by UUID. Pass it per command (`GMAIL_OP_UUID=<selected-uuid> gmail list -n 1`) or `export GMAIL_OP_UUID=<selected-uuid>` in the current shell. Per-command is safest when different projects use different mailboxes. See [env-setup.md](../gmail-access/references/env-setup.md).

## Phase 2: Build the Gmail CLI

The binary is built from the committed lockfile so every machine resolves the same dependency tree:

```bash
cd "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli" && bun install --frozen-lockfile && bun run build
```

If `--frozen-lockfile` fails, package.json and `bun.lock` disagree. Do not delete the lockfile to get past it; report the mismatch.

## Phase 3: Verification

```bash
GMAIL_CLI="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail"
"$GMAIL_CLI" list -n 1 2>&1 | head -5
```

The first run opens a browser for Google OAuth consent. Sign in with the account that the chosen 1Password item belongs to, then confirm with the user that the listed message comes from the intended mailbox.

## Success Criteria

1. `GMAIL_OP_UUID` resolves to a 1Password item UUID (in the shell or on the command line)
2. `scripts/gmail-cli/gmail` exists and was built with `--frozen-lockfile`
3. `gmail list -n 1` returns a message from the intended mailbox
4. No `gmail-commander` launchd job exists locally (`launchctl list | grep -F gmail-commander` prints nothing)

## No OAuth Credentials?

Direct user to: [gmail-api-setup.md](../gmail-access/references/gmail-api-setup.md)

---

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path (Glob for this skill's name) before editing. All corrections target THIS file and its sibling references/ — never other documentation.
1. **What failed?** — Fix the instruction that caused it. If it could recur, add it as an anti-pattern.
2. **What worked better than expected?** — Promote it to recommended practice. Document why.
3. **What drifted?** — Any script, reference, or external dependency that no longer matches reality gets fixed now.
4. **Log it.** — Every change gets an evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
