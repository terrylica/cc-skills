# Environment Setup Guide

How the Gmail CLI gets `GMAIL_OP_UUID` and the other variables it reads. Every component reads plain process environment variables; nothing loads a per-directory config file for you (jdx/mise, which used to, is retired and not used).

## Prerequisites

1. **1Password CLI installed**: `brew install 1password-cli`
2. **1Password authenticated**: `op signin`, or `OP_SERVICE_ACCOUNT_TOKEN` exported for biometric-free access

## Step 1: Find Your 1Password UUID

```bash
# List all items in Employee vault containing "gmail" or "oauth"
op item list --vault Employee --format json | jq '.[] | select(.title | test("gmail|oauth"; "i")) | {id, title}'
```

Example output:

```json
{
  "id": "56pehbslb74al3yjyaelly5gx4",
  "title": "Gmail API - project-f OAuth Client"
}
```

Copy the `id` value — this is your UUID. Use the item **UUID**, not its title: the token cache is keyed by UUID (`~/.claude/tools/gmail-tokens/<uuid>.json`).

## Step 2: Supply It to the Process That Needs It

| Consumer            | Where `GMAIL_OP_UUID` comes from                                                                                           |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Interactive CLI use | Pass it on the command line (`GMAIL_OP_UUID=<uuid> gmail list -n 1`) or `export GMAIL_OP_UUID=<uuid>` in the current shell |

Passing the UUID per command is the safest choice when different projects use different accounts, because nothing selects an account from the working directory any more.

The Telegram bot and the scheduled digest do not read anything from this machine: they run in a private deployment that injects its own variables from its own secret store. The laptop launchd jobs and the `.env.launchd` file they sourced were retired on 2026-09-24; do not recreate them.

## Step 3: Verify

```bash
echo "${GMAIL_OP_UUID:-NOT_SET}"
GMAIL_CLI="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail"
"$GMAIL_CLI" list -n 1      # lists one email (prompts OAuth on first run)
```

## First-Time OAuth

On first run, the Gmail CLI will:

1. Retrieve OAuth credentials from 1Password
2. Open a browser for Google OAuth consent
3. Start a local server to receive the callback
4. Save the token to `~/.claude/tools/gmail-tokens/<uuid>.json`

After the initial OAuth, runs use the saved token (auto-refreshed when expired).

## Multi-Account Use

Create a separate 1Password item per Gmail account and pass the matching UUID per command. Tokens are stored separately at `~/.claude/tools/gmail-tokens/<uuid>.json`, so accounts do not conflict.

```bash
GMAIL_OP_UUID=work-gmail-oauth-uuid "$GMAIL_CLI" list -n 5
GMAIL_OP_UUID=personal-gmail-oauth-uuid GMAIL_OP_VAULT=Personal "$GMAIL_CLI" list -n 5
```

## Troubleshooting

### "GMAIL_OP_UUID environment variable not set"

Supply it as in Step 2, or ask Claude: "Help me set up Gmail access".

### "1Password error: ..."

Ensure the 1Password CLI is authenticated: `op signin`.

### "OAuth error: access_denied"

The Google OAuth consent screen was denied. Try again and approve access.

### "Authorization timeout"

The OAuth flow did not complete within 2 minutes. Run the command again.

### Token refresh fails

Delete the token and re-authenticate:

```bash
rm ~/.claude/tools/gmail-tokens/<your-uuid>.json
GMAIL_OP_UUID=<your-uuid> "$GMAIL_CLI" list -n 1  # prompts OAuth again
```

## Environment Variables Reference

| Variable         | Required | Default    | Description                               |
| ---------------- | -------- | ---------- | ----------------------------------------- |
| `GMAIL_OP_UUID`  | Yes      | -          | 1Password item UUID for OAuth credentials |
| `GMAIL_OP_VAULT` | No       | `Employee` | 1Password vault name                      |
