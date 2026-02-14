---
name: setup
description: Full Cal.com Commander setup wizard - Cal.com API, Telegram bot, Supabase DB, GCP project, launchd services. Discovers 1Password items, configures mise environment, installs launchd plists.
---

# Cal.com Commander Setup

Complete setup wizard for Cal.com CLI access, Telegram bot, Supabase database, and launchd services.

## Prerequisites Check

```bash
# Check required tools
command -v op && echo "OK 1Password CLI" || echo "MISSING: brew install 1password-cli"
command -v mise && echo "OK mise" || echo "MISSING: curl https://mise.run | sh"
command -v bun && echo "OK bun" || echo "MISSING: curl -fsSL https://bun.sh/install | bash"
command -v gcloud && echo "OK gcloud" || echo "OPTIONAL: brew install google-cloud-sdk"
command -v supabase && echo "OK supabase" || echo "OPTIONAL: brew install supabase/tap/supabase"
```

## Phase 1: Cal.com API Setup

### Step 1: Check if already configured

```bash
echo "CALCOM_OP_UUID: ${CALCOM_OP_UUID:-NOT_SET}"
```

If already set, use AskUserQuestion to ask if user wants to reconfigure.

### Step 2: Discover 1Password items

```bash
op item list --vault "Claude Automation" --format json | jq -r '.[] | select(.title | test("calcom|cal.com|calendar"; "i")) | "\(.id)\t\(.title)"'
```

### Step 3: Present options

Use AskUserQuestion with discovered items or guide new API key creation.

### Step 4: Configure .mise.local.toml

```bash
# Add to .mise.local.toml in project directory
cat >> .mise.local.toml << 'EOF'
[env]
CALCOM_OP_UUID = "<selected-uuid>"
EOF
```

### Step 5: Build Cal.com CLI

```bash
cd "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/calcom-cli" && bun install && bun run build
```

### Step 6: Test Cal.com access

```bash
"$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/calcom-cli/calcom" event-types list
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

## Phase 3: GCP + Supabase Setup

### Step 1: Check GCP configuration

```bash
echo "CALCOM_GCP_PROJECT: ${CALCOM_GCP_PROJECT:-NOT_SET}"
echo "CALCOM_GCP_ACCOUNT: ${CALCOM_GCP_ACCOUNT:-NOT_SET}"
echo "SUPABASE_PROJECT_REF: ${SUPABASE_PROJECT_REF:-NOT_SET}"
```

If NOT_SET, guide user through:

1. GCP project creation: `gcloud projects create <project-id>`
2. Enable APIs: Cloud Run, Artifact Registry, Cloud Build
3. Link billing account
4. Supabase project creation via CLI or dashboard
5. Store all references in `.mise.local.toml`

### Step 2: Generate Cal.com secrets (if needed)

```bash
# Generate 3 secrets
NEXTAUTH_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -hex 32)
CRON_API_KEY=$(openssl rand -hex 32)

echo "NEXTAUTH_SECRET: $NEXTAUTH_SECRET"
echo "CALENDSO_ENCRYPTION_KEY: $ENCRYPTION_KEY"
echo "CRON_API_KEY: $CRON_API_KEY"
```

Store in 1Password Claude Automation vault.

## Phase 4: launchd Service Installation

### Step 1: Create launcher scripts

```bash
mkdir -p ~/own/amonic/bin ~/own/amonic/logs

# Bot launcher
cat > ~/own/amonic/bin/calcom-commander-bot << 'SCRIPT'
#!/bin/bash
set -euo pipefail
eval "$(/Users/terryli/.local/bin/mise activate bash)"
cd /Users/terryli/own/amonic
exec bun run "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/bot.ts"
SCRIPT
chmod +x ~/own/amonic/bin/calcom-commander-bot

# Sync launcher
cat > ~/own/amonic/bin/calcom-commander-sync << 'SCRIPT'
#!/bin/bash
set -euo pipefail
eval "$(/Users/terryli/.local/bin/mise activate bash)"
cd /Users/terryli/own/amonic
exec bun run "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/sync.ts"
SCRIPT
chmod +x ~/own/amonic/bin/calcom-commander-sync
```

### Step 2: Install launchd plists

Use AskUserQuestion to confirm before installing launchd services.

```bash
# Copy plist templates to LaunchAgents
# launchctl load ~/Library/LaunchAgents/com.terryli.calcom-commander-bot.plist
# launchctl load ~/Library/LaunchAgents/com.terryli.calcom-commander-sync.plist
```

## Phase 5: Verification

```bash
# Run health check
echo "=== Cal.com CLI ==="
"$HOME/.claude/plugins/marketplaces/cc-skills/plugins/calcom-commander/scripts/calcom-cli/calcom" event-types list 2>&1 | head -5

echo ""
echo "=== Bot Process ==="
pgrep -fl calcom-commander || echo "Not running"

echo ""
echo "=== launchd ==="
launchctl list | grep calcom-commander || echo "Not registered"

echo ""
echo "=== Supabase ==="
DATABASE_URL=$(op read "$SUPABASE_DB_URL_REF" 2>/dev/null) && psql "$DATABASE_URL" -c "SELECT 1" 2>&1 | head -3 || echo "DB not configured"
```

## Success Criteria

1. `echo $CALCOM_OP_UUID` shows a UUID
2. Cal.com CLI returns event type data
3. `echo $TELEGRAM_BOT_TOKEN` is set
4. Bot responds to /help in Telegram
5. Supabase DB is accessible
6. launchd jobs are loaded (optional)

## No API Credentials?

Direct user to: [calcom-api-setup.md](../skills/calcom-access/references/calcom-api-setup.md)
