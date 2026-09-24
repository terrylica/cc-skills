---
name: setup
description: Full Gmail Commander setup wizard - Gmail OAuth, Telegram bot, launchd services. Discovers 1Password items, writes the daemon env file.
allowed-tools: Bash, Read, Write, AskUserQuestion, Edit
disable-model-invocation: false
---

# Gmail Commander Setup

Complete setup wizard for Gmail CLI access, Telegram bot, and launchd services.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Prerequisites Check

```bash
# Check required tools
command -v op && echo "OK 1Password CLI" || echo "MISSING: brew install 1password-cli"
command -v proto && echo "OK proto" || echo "MISSING: brew install proto"
command -v bun && echo "OK bun" || echo "MISSING: proto install bun"
command -v ffmpeg && echo "OK ffmpeg" || echo "OPTIONAL: brew install ffmpeg (for voice digest)"
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

### Step 4: Write the daemon env file

`~/own/amonic/.env.launchd` (gitignored, hand-maintained) is the SSoT for daemon env; the launcher scripts source it. For interactive use, `export GMAIL_OP_UUID=<selected-uuid>` in the current shell instead.

```bash
# Add to ~/own/amonic/.env.launchd (replace any existing GMAIL_OP_UUID line)
echo "export GMAIL_OP_UUID='<selected-uuid>'" >> ~/own/amonic/.env.launchd
```

### Step 5: Build Gmail CLI

```bash
cd "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli" && bun install && bun run build
```

### Step 6: Test Gmail access

```bash
"$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail" list -n 1
```

## Phase 2: Telegram Bot Setup

### Step 1: Check Telegram config

```bash
echo "TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:+SET}"
echo "TELEGRAM_CHAT_ID: ${TELEGRAM_CHAT_ID:-NOT_SET}"
```

If NOT_SET, guide user through BotFather setup:

1. Message @BotFather on Telegram
2. Send `/newbot` and follow prompts
3. Copy the token
4. Get chat ID: message the bot, then check `https://api.telegram.org/bot<TOKEN>/getUpdates`

### Step 2: Add to the daemon env file

```bash
# Append bot config to ~/own/amonic/.env.launchd
cat >> ~/own/amonic/.env.launchd << 'EOF'
export TELEGRAM_BOT_TOKEN='<bot-token>'
export TELEGRAM_CHAT_ID='<chat-id>'
EOF
```

## Phase 3: launchd Service Installation

### Step 1: Create launcher scripts

```bash
mkdir -p ~/own/amonic/bin ~/own/amonic/logs

# Bot launcher
cat > ~/own/amonic/bin/gmail-commander-bot << 'SCRIPT'
#!/bin/zsh
set -euo pipefail
# .env.launchd is hand-maintained and is the SSoT for daemon secrets.
source "$HOME/own/amonic/.env.launchd"
cd "$HOME/own/amonic"
exec "$HOME/.proto/shims/bun" run "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/bot.ts"
SCRIPT
chmod +x ~/own/amonic/bin/gmail-commander-bot

# Digest launcher
cat > ~/own/amonic/bin/gmail-commander-digest << 'SCRIPT'
#!/bin/zsh
set -euo pipefail
# .env.launchd is hand-maintained and is the SSoT for daemon secrets.
source "$HOME/own/amonic/.env.launchd"
cd "$HOME/own/amonic"
exec "$HOME/.proto/shims/bun" run "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/digest.ts"
SCRIPT
chmod +x ~/own/amonic/bin/gmail-commander-digest
```

### Step 2: Install launchd plists

Use AskUserQuestion to confirm before installing launchd services.

```bash
# Copy plist templates (from bot-process-control SKILL.md) to LaunchAgents
# launchctl load ~/Library/LaunchAgents/com.terryli.gmail-commander-bot.plist
# launchctl load ~/Library/LaunchAgents/com.terryli.gmail-commander-digest.plist
```

## Phase 4: Verification

```bash
# Run health check
echo "=== Gmail CLI ==="
"$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail" list -n 1 2>&1 | head -5

echo ""
echo "=== Bot Process ==="
pgrep -fl gmail-commander || echo "Not running"

echo ""
echo "=== launchd ==="
launchctl list | grep gmail-commander || echo "Not registered"
```

## Success Criteria

1. `echo $GMAIL_OP_UUID` shows a UUID
2. Gmail CLI returns email data
3. `echo $TELEGRAM_BOT_TOKEN` is set
4. Bot responds to /help in Telegram
5. launchd jobs are loaded (optional)

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
