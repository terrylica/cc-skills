---
description: Set up asciinema chunker daemon with interactive wizard. Guides through PAT creation, Keychain storage, Pushover setup, and launchd installation. TRIGGERS - daemon setup, install chunker, configure backup.
allowed-tools: Bash, AskUserQuestion, Write, Read
argument-hint: "[--reinstall] [--skip-pushover]"
---

# /asciinema-tools:daemon-setup

Interactive wizard to set up the asciinema chunker daemon. This daemon runs independently of Claude Code CLI, using dedicated credentials stored in macOS Keychain.

## Why a Daemon?

| Problem with old approach     | Daemon solution                  |
| ----------------------------- | -------------------------------- |
| Uses `gh auth token` (shared) | Uses dedicated PAT from Keychain |
| Dies when terminal closes     | launchd keeps it running         |
| Silent push failures          | Logs + Pushover notifications    |
| Tied to Claude Code session   | Completely decoupled             |

## Execution

### Phase 1: Preflight Check

**Check required tools:**

```bash
/usr/bin/env bash << 'PREFLIGHT_EOF'
MISSING=()
for tool in asciinema zstd git curl jq; do
  command -v "$tool" &>/dev/null || MISSING+=("$tool")
done

# macOS-specific: security command for Keychain
if [[ "$(uname)" == "Darwin" ]]; then
  command -v security &>/dev/null || MISSING+=("security (macOS Keychain)")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "MISSING:${MISSING[*]}"
  exit 1
fi

echo "PREFLIGHT:OK"
PREFLIGHT_EOF
```

**If MISSING not empty, use AskUserQuestion:**

```
Question: "Missing required tools: {MISSING}. How would you like to proceed?"
Header: "Dependencies"
Options:
  - label: "Install via Homebrew (Recommended)"
    description: "Run: brew install {MISSING}"
  - label: "I'll install manually"
    description: "Pause setup and show install instructions"
  - label: "Abort setup"
    description: "Exit the setup wizard"
```

**If "Install via Homebrew"**: Run `brew install {MISSING}` and continue.

---

### Phase 2: Check Existing Installation

```bash
/usr/bin/env bash << 'CHECK_EXISTING_EOF'
PLIST_PATH="$HOME/Library/LaunchAgents/com.cc-skills.asciinema-chunker.plist"
DAEMON_RUNNING="false"

if [[ -f "$PLIST_PATH" ]]; then
  echo "PLIST_EXISTS:true"
  if launchctl list 2>/dev/null | grep -q "asciinema-chunker"; then
    DAEMON_RUNNING="true"
  fi
else
  echo "PLIST_EXISTS:false"
fi

echo "DAEMON_RUNNING:$DAEMON_RUNNING"

# Check if PAT already in Keychain
if security find-generic-password -s "asciinema-github-pat" -a "$USER" -w &>/dev/null 2>&1; then
  echo "PAT_EXISTS:true"
else
  echo "PAT_EXISTS:false"
fi
CHECK_EXISTING_EOF
```

**If PLIST_EXISTS=true, use AskUserQuestion:**

```
Question: "Existing daemon installation found. What would you like to do?"
Header: "Existing"
Options:
  - label: "Reinstall (keep credentials)"
    description: "Update daemon script and plist, keep Keychain credentials"
  - label: "Fresh install (reset everything)"
    description: "Remove existing credentials and start fresh"
  - label: "Cancel"
    description: "Exit without changes"
```

---

### Phase 3: GitHub PAT Setup

**Use AskUserQuestion:**

```
Question: "Do you already have a GitHub Fine-Grained PAT for asciinema backups?"
Header: "GitHub PAT"
Options:
  - label: "No, guide me through creating one (Recommended)"
    description: "Opens GitHub in browser with step-by-step instructions"
  - label: "Yes, I have a PAT ready"
    description: "I'll paste my existing PAT"
  - label: "What's a Fine-Grained PAT?"
    description: "Show explanation before proceeding"
```

**If "No, guide me through":**

1. Open browser:

```bash
open "https://github.com/settings/tokens?type=beta"
```

1. Display instructions:

```markdown
## Create GitHub Fine-Grained PAT

Follow these steps in the browser window that just opened:

1. Click **"Generate new token"**

2. **Token name**: `asciinema-chunker`

3. **Expiration**: 90 days (recommended) or custom
   - Longer expiration = less frequent token rotation
   - Shorter = more secure

4. **Repository access**: Click **"Only select repositories"**
   - Select your asciinema recording repositories
   - Example: `your-org/your-repository`

5. **Permissions** (expand "Repository permissions"):
   - **Contents**: Read and write ✓
   - **Metadata**: Read-only ✓

6. Click **"Generate token"**

7. **IMPORTANT**: Copy the token immediately!
   It starts with `github_pat_...`
   You won't be able to see it again.
```

**Use AskUserQuestion:**

```
Question: "Have you copied your new GitHub PAT?"
Header: "PAT Ready"
Options:
  - label: "Yes, I've copied it"
    description: "Proceed to enter the PAT"
  - label: "Not yet, still creating"
    description: "I need more time"
  - label: "I need help"
    description: "Show troubleshooting tips"
```

**If "Yes, I've copied it" - Use AskUserQuestion to get PAT:**

```
Question: "Paste your GitHub PAT (will be stored securely in macOS Keychain):"
Header: "PAT Input"
Options:
  - label: "Enter my PAT"
    description: "Use the 'Other' field below to paste your token"
```

User enters PAT via the "Other" option.

**Store in Keychain:**

```bash
/usr/bin/env bash << 'STORE_PAT_EOF'
PAT_VALUE="${1:?PAT required}"

# Store in Keychain (update if exists)
security add-generic-password \
  -s "asciinema-github-pat" \
  -a "$USER" \
  -w "$PAT_VALUE" \
  -U 2>/dev/null || \
security add-generic-password \
  -s "asciinema-github-pat" \
  -a "$USER" \
  -w "$PAT_VALUE"

echo "PAT stored in Keychain"
STORE_PAT_EOF
```

**Verify PAT works:**

```bash
/usr/bin/env bash << 'VERIFY_PAT_EOF'
PAT_VALUE="${1:?PAT required}"

RESPONSE=$(curl -s -H "Authorization: Bearer $PAT_VALUE" \
  https://api.github.com/user 2>&1)

if echo "$RESPONSE" | jq -e '.login' &>/dev/null; then
  USERNAME=$(echo "$RESPONSE" | jq -r '.login')
  echo "PAT_VALID:$USERNAME"
else
  ERROR=$(echo "$RESPONSE" | jq -r '.message // "Unknown error"')
  echo "PAT_INVALID:$ERROR"
fi
VERIFY_PAT_EOF
```

**If PAT_INVALID, use AskUserQuestion:**

```
Question: "PAT verification failed: {error}. What would you like to do?"
Header: "PAT Error"
Options:
  - label: "Try a different PAT"
    description: "Enter a new PAT"
  - label: "Check PAT permissions"
    description: "Review required permissions"
  - label: "Continue anyway (not recommended)"
    description: "Proceed without verification"
```

---

### Phase 4: Pushover Setup (Optional)

**Use AskUserQuestion:**

```
Question: "Enable Pushover notifications for push failures?"
Header: "Notifications"
Options:
  - label: "Yes, set up Pushover (Recommended)"
    description: "Get notified on your phone when backups fail"
  - label: "No, skip notifications"
    description: "Failures will only be logged to file"
  - label: "What is Pushover?"
    description: "Learn about Pushover notifications"
```

**If "What is Pushover?":**

```markdown
## What is Pushover?

Pushover is a notification service that sends real-time alerts to your phone.

**Why use it?**

- Know immediately when asciinema backups fail
- Don't discover backup failures hours later
- Works even when you're away from your computer

**Cost**: One-time $5 purchase per platform (iOS, Android, Desktop)

**Website**: https://pushover.net
```

Then loop back to the question.

**If "Yes, set up Pushover":**

1. Open browser:

```bash
open "https://pushover.net/apps/build"
```

1. Display instructions:

```markdown
## Create Pushover Application

1. Log in or create a Pushover account at pushover.net

2. Click **"Create an Application/API Token"**

3. Fill in the form:
   - **Name**: `asciinema-chunker`
   - **Type**: Script
   - **Description**: asciinema backup notifications

4. Click **"Create Application"**

5. Copy the **API Token/Key** (starts with `a...`)
```

**Use AskUserQuestion for App Token:**

```
Question: "Paste your Pushover App Token:"
Header: "App Token"
Options:
  - label: "Enter App Token"
    description: "Use the 'Other' field to paste your token"
```

**Use AskUserQuestion for User Key:**

```
Question: "Paste your Pushover User Key (from your Pushover dashboard, not the app token):"
Header: "User Key"
Options:
  - label: "Enter User Key"
    description: "Use the 'Other' field to paste your key"
```

**Store both in Keychain:**

```bash
/usr/bin/env bash << 'STORE_PUSHOVER_EOF'
APP_TOKEN="${1:?App token required}"
USER_KEY="${2:?User key required}"

security add-generic-password -s "asciinema-pushover-app" -a "$USER" -w "$APP_TOKEN" -U 2>/dev/null || \
security add-generic-password -s "asciinema-pushover-app" -a "$USER" -w "$APP_TOKEN"

security add-generic-password -s "asciinema-pushover-user" -a "$USER" -w "$USER_KEY" -U 2>/dev/null || \
security add-generic-password -s "asciinema-pushover-user" -a "$USER" -w "$USER_KEY"

echo "Pushover credentials stored in Keychain"
STORE_PUSHOVER_EOF
```

**Send test notification:**

```bash
/usr/bin/env bash << 'TEST_PUSHOVER_EOF'
APP_TOKEN="${1:?}"
USER_KEY="${2:?}"

RESPONSE=$(curl -s \
  --form-string "token=$APP_TOKEN" \
  --form-string "user=$USER_KEY" \
  --form-string "title=asciinema-chunker" \
  --form-string "message=Setup complete! Notifications are working." \
  --form-string "sound=cosmic" \
  https://api.pushover.net/1/messages.json)

if echo "$RESPONSE" | grep -q '"status":1'; then
  echo "TEST_OK"
else
  echo "TEST_FAILED:$RESPONSE"
fi
TEST_PUSHOVER_EOF
```

---

### Phase 5: Daemon Configuration

**Use AskUserQuestion:**

```
Question: "Configure chunking settings:"
Header: "Settings"
Options:
  - label: "Default (30s idle, zstd-3) (Recommended)"
    description: "Balanced chunking frequency and compression"
  - label: "Fast (15s idle, zstd-1)"
    description: "More frequent chunks, less compression"
  - label: "Compact (60s idle, zstd-6)"
    description: "Less frequent chunks, higher compression"
  - label: "Custom"
    description: "Enter specific values"
```

**If "Custom", use AskUserQuestion:**

```
Question: "Enter idle threshold in seconds (how long to wait before pushing a chunk):"
Header: "Idle"
Options:
  - label: "Enter value"
    description: "Recommended: 15-120 seconds"
```

Then:

```
Question: "Enter zstd compression level (1-19, higher = smaller files but slower):"
Header: "Compression"
Options:
  - label: "Enter value"
    description: "Recommended: 1-6 for real-time use"
```

---

### Phase 6: Install launchd Service

**Generate plist from template:**

```bash
/usr/bin/env bash << 'GENERATE_PLIST_EOF'
IDLE_THRESHOLD="${1:-30}"
ZSTD_LEVEL="${2:-3}"

TEMPLATE_PATH="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/asciinema-tools}/scripts/asciinema-chunker.plist.template"
DAEMON_PATH="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/asciinema-tools}/scripts/idle-chunker-daemon.sh"
PLIST_PATH="$HOME/Library/LaunchAgents/com.cc-skills.asciinema-chunker.plist"

# Validate required files exist
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "ERROR: Template not found at: $TEMPLATE_PATH"
  echo "Ensure asciinema-tools plugin is properly installed."
  exit 1
fi

if [[ ! -f "$DAEMON_PATH" ]]; then
  echo "ERROR: Daemon script not found at: $DAEMON_PATH"
  echo "Ensure asciinema-tools plugin is properly installed."
  exit 1
fi

if ! mkdir -p "$HOME/Library/LaunchAgents" 2>&1; then
  echo "ERROR: Cannot create LaunchAgents directory"
  exit 1
fi

if ! mkdir -p "$HOME/.asciinema/logs" 2>&1; then
  echo "ERROR: Cannot create logs directory at ~/.asciinema/logs"
  exit 1
fi

# Read template and substitute placeholders
sed \
  -e "s|{{HOME}}|$HOME|g" \
  -e "s|{{USER}}|$USER|g" \
  -e "s|{{DAEMON_PATH}}|$DAEMON_PATH|g" \
  -e "s|{{IDLE_THRESHOLD}}|$IDLE_THRESHOLD|g" \
  -e "s|{{ZSTD_LEVEL}}|$ZSTD_LEVEL|g" \
  "$TEMPLATE_PATH" > "$PLIST_PATH"

echo "PLIST_GENERATED:$PLIST_PATH"
GENERATE_PLIST_EOF
```

**Use AskUserQuestion:**

```
Question: "Ready to install the launchd service. This will:"
Header: "Install"
description: |
  - Install to: ~/Library/LaunchAgents/com.cc-skills.asciinema-chunker.plist
  - Start on login: Yes
  - Auto-restart on crash: Yes
  - Idle threshold: {idle}s
  - Compression: zstd-{level}
Options:
  - label: "Install and start now (Recommended)"
    description: "Install plist and start the daemon immediately"
  - label: "Install but don't start yet"
    description: "Install plist only, start manually later"
  - label: "Show plist file first"
    description: "Display the generated plist content"
```

**If "Show plist file first":**

Display plist content, then loop back to question.

**If "Install and start now":**

```bash
/usr/bin/env bash << 'INSTALL_DAEMON_EOF'
PLIST_PATH="$HOME/Library/LaunchAgents/com.cc-skills.asciinema-chunker.plist"

# Unload if already running (may fail if not loaded - that's expected)
if ! launchctl unload "$PLIST_PATH" 2>/dev/null; then
  echo "INFO: No existing daemon to unload (first install)"
fi

# Load and start
if launchctl load "$PLIST_PATH"; then
  echo "INSTALL_OK"
  sleep 2
  if launchctl list 2>/dev/null | grep -q "asciinema-chunker"; then
    echo "DAEMON_RUNNING"
  else
    echo "DAEMON_NOT_RUNNING"
  fi
else
  echo "INSTALL_FAILED"
fi
INSTALL_DAEMON_EOF
```

---

### Phase 7: Verification

**Check daemon status:**

```bash
/usr/bin/env bash << 'VERIFY_DAEMON_EOF'
HEALTH_FILE="$HOME/.asciinema/health.json"

# Wait for health file
sleep 3

if [[ -f "$HEALTH_FILE" ]]; then
  STATUS=$(jq -r '.status' "$HEALTH_FILE")
  MESSAGE=$(jq -r '.message' "$HEALTH_FILE")
  PID=$(jq -r '.pid' "$HEALTH_FILE")
  echo "HEALTH_STATUS:$STATUS"
  echo "HEALTH_MESSAGE:$MESSAGE"
  echo "HEALTH_PID:$PID"
else
  echo "HEALTH_FILE_MISSING"
fi

# Check launchctl
if launchctl list 2>/dev/null | grep -q "asciinema-chunker"; then
  echo "LAUNCHCTL_OK"
else
  echo "LAUNCHCTL_NOT_FOUND"
fi
VERIFY_DAEMON_EOF
```

**Use AskUserQuestion:**

```
Question: "Setup complete! Daemon status: {status}. What would you like to do next?"
Header: "Complete"
Options:
  - label: "Show health status"
    description: "Display daemon health information"
  - label: "View logs"
    description: "Show recent log entries"
  - label: "Done"
    description: "Exit setup wizard"
```

**If "Show health status":**

```bash
cat ~/.asciinema/health.json | jq .
```

**If "View logs":**

```bash
tail -20 ~/.asciinema/logs/chunker.log
```

---

## Final Success Message

```markdown
## ✓ Daemon Setup Complete

**Status**: Running
**PID**: {pid}
**Health file**: ~/.asciinema/health.json
**Logs**: ~/.asciinema/logs/chunker.log

### Quick Commands

| Command                          | Description         |
| -------------------------------- | ------------------- |
| `/asciinema-tools:daemon-status` | Check daemon health |
| `/asciinema-tools:daemon-logs`   | View logs           |
| `/asciinema-tools:daemon-stop`   | Stop daemon         |
| `/asciinema-tools:daemon-start`  | Start daemon        |

### Next Steps

1. Run `/asciinema-tools:bootstrap` to start a recording session
2. The daemon will automatically push chunks to GitHub
3. You'll receive Pushover notifications if pushes fail

The daemon is now completely independent of Claude Code CLI.
You can switch `gh auth` accounts freely without affecting backups.
```

## Troubleshooting

| Issue                  | Cause                          | Solution                               |
| ---------------------- | ------------------------------ | -------------------------------------- |
| Keychain access denied | macOS permission not granted   | Grant access in System Settings        |
| PAT test failed        | Token expired or invalid scope | Generate new token with `repo` scope   |
| launchctl load failed  | plist syntax error             | Check `plutil -lint <plist-path>`      |
| Daemon keeps stopping  | Script error or crash          | Check `/asciinema-tools:daemon-logs`   |
| Pushover not working   | Invalid credentials            | Re-run setup with correct app/user key |
| Health file missing    | Daemon not running             | Run `/asciinema-tools:daemon-start`    |
