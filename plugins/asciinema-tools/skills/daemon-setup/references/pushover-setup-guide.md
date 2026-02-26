# Pushover Setup Guide

## Phase 4: Pushover Setup (Optional)

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

## Store Credentials in Keychain

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

## Test Notification

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
