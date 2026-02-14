---
name: setup
description: Full Gmail Commander setup wizard - Gmail OAuth, Telegram bot, launchd services. Discovers 1Password items, configures mise environment, installs launchd plists.
---

# Gmail Commander Setup

Complete setup wizard for Gmail CLI access, Telegram bot, and launchd services.

## Prerequisites Check

```bash
# Check required tools
command -v op && echo "OK 1Password CLI" || echo "MISSING: brew install 1password-cli"
command -v mise && echo "OK mise" || echo "MISSING: curl https://mise.run | sh"
command -v bun && echo "OK bun" || echo "MISSING: curl -fsSL https://bun.sh/install | bash"
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

### Step 4: Configure .mise.local.toml

```bash
# Add to .mise.local.toml in project directory
cat >> .mise.local.toml << 'EOF'
[env]
GMAIL_OP_UUID = "<selected-uuid>"
EOF
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

### Step 2: Add to .mise.local.toml

```bash
# Append bot config
cat >> .mise.local.toml << 'EOF'
TELEGRAM_BOT_TOKEN = "<bot-token>"
TELEGRAM_CHAT_ID = "<chat-id>"
EOF
```

## Phase 3: launchd Service Installation

### Step 1: Create launcher scripts

```bash
mkdir -p ~/own/amonic/bin ~/own/amonic/logs

# Bot launcher
cat > ~/own/amonic/bin/gmail-commander-bot << 'SCRIPT'
#!/bin/bash
set -euo pipefail
eval "$(/Users/terryli/.local/bin/mise activate bash)"
cd /Users/terryli/own/amonic
exec bun run "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/bot.ts"
SCRIPT
chmod +x ~/own/amonic/bin/gmail-commander-bot

# Digest launcher
cat > ~/own/amonic/bin/gmail-commander-digest << 'SCRIPT'
#!/bin/bash
set -euo pipefail
eval "$(/Users/terryli/.local/bin/mise activate bash)"
cd /Users/terryli/own/amonic
exec bun run "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/digest.ts"
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

Direct user to: [gmail-api-setup.md](../skills/gmail-access/references/gmail-api-setup.md)
