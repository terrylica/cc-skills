# Gmail API OAuth Setup Guide

How to create Google Cloud OAuth credentials for Gmail API access.

## Prerequisites

- Google Cloud account
- Access to Google Cloud Console

## Step 1: Create or Select a Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click the project dropdown (top left)
3. Click "New Project" or select an existing project
4. Give it a name (e.g., "Gmail CLI Access")

## Step 2: Enable Gmail API

1. Go to [APIs & Services > Library](https://console.cloud.google.com/apis/library)
2. Search for "Gmail API"
3. Click on "Gmail API"
4. Click "Enable"

## Step 3: Configure OAuth Consent Screen

1. Go to [APIs & Services > OAuth consent screen](https://console.cloud.google.com/apis/credentials/consent)
2. Select "External" (unless you have Google Workspace)
3. Click "Create"
4. Fill in required fields:
   - App name: "Gmail CLI"
   - User support email: Your email
   - Developer contact: Your email
5. Click "Save and Continue"
6. On Scopes page, click "Add or Remove Scopes"
7. Find and select: `https://www.googleapis.com/auth/gmail.readonly`
8. Click "Update" then "Save and Continue"
9. On Test users page, click "Add Users"
10. Add your Gmail address
11. Click "Save and Continue"

## Step 4: Create OAuth Client ID

1. Go to [APIs & Services > Credentials](https://console.cloud.google.com/apis/credentials)
2. Click "Create Credentials" > "OAuth client ID"
3. Select "Desktop app" as application type
4. Give it a name (e.g., "Gmail CLI Desktop")
5. Click "Create"
6. Click "Download JSON" to download credentials

## Step 5: Add to 1Password

1. Open 1Password
2. Create new item in Employee vault (or your preferred vault)
3. Set title: "Gmail API - [project-name] OAuth Client"
4. Add these fields from the downloaded JSON:

| Field Label     | JSON Key                                                  |
| --------------- | --------------------------------------------------------- |
| `client_id`     | `installed.client_id`                                     |
| `client_secret` | `installed.client_secret`                                 |
| `auth_uri`      | `installed.auth_uri`                                      |
| `token_uri`     | `installed.token_uri`                                     |
| `redirect_uris` | `installed.redirect_uris[0]` (usually `http://localhost`) |

1. Save the item
2. Note the item's UUID (visible in URL or via `op item get "item-name" --format json | jq '.id'`)

## Step 6: Configure mise

Add the UUID to your project's `.mise.local.toml`:

```toml
[env]
GMAIL_OP_UUID = "<your-item-uuid>"
```

## Security Notes

### Read-Only Access

The Gmail CLI uses `gmail.readonly` scope, which only allows reading emails. It cannot:

- Send emails
- Delete emails
- Modify labels
- Access drafts

### Token Storage

OAuth tokens are stored locally at `~/.claude/tools/gmail-tokens/<uuid>.json` with chmod 600 (owner read/write only).

### Credential Storage

OAuth client credentials are stored in 1Password, never in plain text files or repositories.

### Test Users

While your OAuth consent screen is in "Testing" mode, only users added as test users can authenticate. To allow any user, you must submit the app for verification (not needed for personal use).

## Expanding Access

To send emails or modify Gmail, you would need to:

1. Add additional scopes in OAuth consent screen
2. Update the Gmail CLI code to request those scopes
3. Re-authenticate (delete existing token, run again)

Available scopes:

- `gmail.readonly` - Read messages and settings
- `gmail.send` - Send messages only
- `gmail.compose` - Create, read, update drafts; send messages
- `gmail.modify` - Full access except permanent deletion
- `mail.google.com` - Full access (avoid unless necessary)
