# mise Setup Guide

Step-by-step guide to configure Gmail access using mise.

## Prerequisites

1. **mise installed**: `curl https://mise.run | sh`
2. **1Password CLI installed**: `brew install 1password-cli`
3. **1Password authenticated**: `op signin`

## Quick Setup

### Step 1: Find Your 1Password UUID

```bash
# List all items in Employee vault containing "gmail" or "oauth"
op item list --vault Employee --format json | jq '.[] | select(.title | test("gmail|oauth"; "i")) | {id, title}'
```

Example output:

```json
{
  "id": "56pehbslb74al3yjyaelly5gx4",
  "title": "Gmail API - dental-quizzes OAuth Client"
}
```

Copy the `id` value - this is your UUID.

### Step 2: Create .mise.local.toml

In your project directory:

```bash
cat > .mise.local.toml << 'EOF'
[env]
GMAIL_OP_UUID = "YOUR-UUID-HERE"
EOF
```

Replace `YOUR-UUID-HERE` with your actual UUID.

### Step 3: Ensure .gitignore

Add to `.gitignore` if not already present:

```bash
echo ".mise.local.toml" >> .gitignore
```

### Step 4: Trust and Reload

```bash
mise trust
cd .  # Reload environment
```

### Step 5: Verify

```bash
echo $GMAIL_OP_UUID  # Should show your UUID
gmail list -n 1      # Should list one email (will prompt OAuth on first run)
```

## First-Time OAuth

On first run, Gmail CLI will:

1. Retrieve OAuth credentials from 1Password
2. Open browser for Google OAuth consent
3. Start local server to receive callback
4. Save token to `~/.claude/tools/gmail-tokens/<uuid>.json`

After initial OAuth, subsequent runs use the saved token (auto-refreshes when expired).

## Troubleshooting

### "GMAIL_OP_UUID environment variable not set"

Run the setup steps above, or ask Claude: "Help me set up Gmail access"

### "1Password error: ..."

Ensure 1Password CLI is authenticated:

```bash
op signin
```

### "OAuth error: access_denied"

The Google OAuth consent screen was denied. Try again and approve access.

### "Authorization timeout"

OAuth flow didn't complete within 2 minutes. Run the command again.

### Token refresh fails

Delete the token and re-authenticate:

```bash
rm ~/.claude/tools/gmail-tokens/<your-uuid>.json
gmail list -n 1  # Will prompt OAuth again
```

## Environment Variables Reference

| Variable         | Required | Default    | Description                               |
| ---------------- | -------- | ---------- | ----------------------------------------- |
| `GMAIL_OP_UUID`  | Yes      | -          | 1Password item UUID for OAuth credentials |
| `GMAIL_OP_VAULT` | No       | `Employee` | 1Password vault name                      |
