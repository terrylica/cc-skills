---
name: setup
description: Interactive Gmail access setup wizard. Discovers 1Password items, helps select OAuth credentials, and configures mise environment.
---

# Gmail Tools Setup

Interactive setup for Gmail CLI access.

## Prerequisites Check

First, verify required tools are installed:

```bash
# Check 1Password CLI
command -v op && echo "✓ 1Password CLI installed" || echo "✗ Install: brew install 1password-cli"

# Check mise
command -v mise && echo "✓ mise installed" || echo "✗ Install: curl https://mise.run | sh"
```

## Discovery Flow

### Step 1: Check if already configured

```bash
echo "GMAIL_OP_UUID: ${GMAIL_OP_UUID:-<not set>}"
```

If already set, ask user if they want to reconfigure.

### Step 2: Discover 1Password items

```bash
op item list --vault Employee --format json | jq -r '.[] | select(.title | test("gmail|oauth"; "i")) | "\(.id)\t\(.title)"'
```

### Step 3: Present options

Use AskUserQuestion to let user select from discovered items, or choose to create new credentials.

### Step 4: Configure .mise.local.toml

After selection, either:

- Create `.mise.local.toml` with `GMAIL_OP_UUID`
- Or show the configuration for manual addition

### Step 5: Reload and test

```bash
mise trust
cd .
gmail list -n 1
```

## No OAuth Credentials?

If user needs to create new OAuth credentials, direct them to:

- [references/gmail-api-setup.md](../skills/gmail-access/references/gmail-api-setup.md)

## Success Criteria

Setup is complete when:

1. `echo $GMAIL_OP_UUID` shows a UUID
2. `gmail list -n 1` returns email data (may prompt OAuth on first run)
