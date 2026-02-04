# Google Drive API OAuth Setup

Guide for creating OAuth credentials to access Google Drive API.

## Prerequisites

- Google Account
- Access to [Google Cloud Console](https://console.cloud.google.com/)
- 1Password CLI installed (`brew install 1password-cli`)

## Step 1: Create or Select Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click project dropdown (top-left) → **New Project**
3. Name: `gdrive-cli` (or any name)
4. Click **Create**

## Step 2: Enable Drive API

1. Go to **APIs & Services** → **Library**
2. Search for "Google Drive API"
3. Click **Google Drive API** → **Enable**

## Step 3: Configure OAuth Consent Screen

1. Go to **APIs & Services** → **OAuth consent screen**
2. Select **External** (unless you have Google Workspace)
3. Click **Create**
4. Fill in:
   - **App name**: `gdrive-cli`
   - **User support email**: Your email
   - **Developer contact**: Your email
5. Click **Save and Continue**
6. **Scopes**: Click **Add or Remove Scopes**
   - Add: `https://www.googleapis.com/auth/drive.readonly`
   - Click **Update** → **Save and Continue**
7. **Test users**: Add your email
8. Click **Save and Continue** → **Back to Dashboard**

## Step 4: Create OAuth Credentials

1. Go to **APIs & Services** → **Credentials**
2. Click **Create Credentials** → **OAuth client ID**
3. Application type: **Desktop app**
4. Name: `gdrive-cli-desktop`
5. Click **Create**
6. **Download JSON** (you'll need values from this)

## Step 5: Store in 1Password

Create a new item in 1Password with these fields:

| Field           | Value                                                  |
| --------------- | ------------------------------------------------------ |
| `client_id`     | From downloaded JSON (`client_id`)                     |
| `client_secret` | From downloaded JSON (`client_secret`)                 |
| `redirect_uris` | `http://localhost` (default)                           |
| `auth_uri`      | `https://accounts.google.com/o/oauth2/auth` (optional) |
| `token_uri`     | `https://oauth2.googleapis.com/token` (optional)       |

### Using 1Password CLI

```bash
# Create new item
op item create \
  --category=api_credential \
  --title="Google Drive API - gdrive-cli" \
  --vault="Employee" \
  'client_id[text]=YOUR_CLIENT_ID' \
  'client_secret[password]=YOUR_CLIENT_SECRET' \
  'redirect_uris[text]=http://localhost'

# Get the UUID
op item list --vault Employee | grep -i drive
```

## Step 6: Configure mise

Add the UUID to your project's `.mise.local.toml`:

```toml
[env]
GDRIVE_OP_UUID = "<uuid-from-step-5>"
```

Then reload:

```bash
mise trust && cd .
```

## Step 7: First Run Authorization

On first run, the CLI will:

1. Open your browser to Google OAuth consent
2. Ask you to authorize the app
3. Redirect to localhost (handled by CLI)
4. Store the token at `~/.claude/tools/gdrive-tokens/<uuid>.json`

```bash
# Test the connection
gdrive list <any-folder-id>
```

## Troubleshooting

### "Access blocked: This app's request is invalid"

- Ensure redirect URI matches: `http://localhost`
- Check OAuth consent screen is configured

### "This app isn't verified"

- Click **Advanced** → **Go to gdrive-cli (unsafe)**
- This is normal for personal OAuth apps

### "Token expired"

- The CLI handles refresh automatically
- If issues persist, delete token file and re-auth:

  ```bash
  rm ~/.claude/tools/gdrive-tokens/<uuid>.json
  gdrive list <folder-id>  # Will re-auth
  ```

### "1Password error"

- Ensure you're signed in: `op signin`
- Check vault name matches: `op vault list`
- Verify UUID exists: `op item get <uuid>`

## Security Notes

- OAuth tokens are stored with `chmod 600`
- Only `drive.readonly` scope is requested
- Credentials never leave 1Password (only accessed at runtime)
- Token file location: `~/.claude/tools/gdrive-tokens/`
