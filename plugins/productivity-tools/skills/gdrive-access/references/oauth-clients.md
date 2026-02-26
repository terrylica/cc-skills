# OAuth Client Setup Reference

This file documents how to configure OAuth clients for gdrive-tools.

## 1Password Item Structure

Your 1Password item should have these fields:

| Field           | Required | Description                 |
| --------------- | -------- | --------------------------- |
| `client_id`     | Yes      | Google OAuth Client ID      |
| `client_secret` | Yes      | Google OAuth Client Secret  |
| `redirect_uris` | No       | Default: `http://localhost` |

**Alternative field names** (for existing login items):

- `username` → maps to `client_id`
- `password` → maps to `client_secret`

## Configuration

Add to your project's `.mise.local.toml` (gitignored):

```toml
[env]
GDRIVE_OP_UUID = "<your-1password-item-uuid>"
# GDRIVE_OP_VAULT = "Employee"  # Optional, defaults to Employee
```

Or add to `~/.config/mise/config.local.toml` for global access across all projects.

## Finding Your UUID

```bash
# List items matching "drive" or "google" in Employee vault
op item list --vault Employee | grep -i "drive\|google\|oauth"

# Get item details
op item get <uuid> --vault Employee --format json | jq '.fields[] | {label, value}'
```

## Token Storage

OAuth tokens are stored at: `~/.claude/tools/gdrive-tokens/<uuid>.json`

- Each 1Password UUID gets its own token file
- Supports multi-account access (work/personal Google accounts)
- Created with `chmod 600` for security

## Troubleshooting

### Error 401: deleted_client

The OAuth client has been deleted in Google Cloud Console. Create a new one or use a different 1Password item.

### Access blocked: Authorization Error

1. Check OAuth consent screen is configured in Google Cloud Console
2. Verify the app is in "Testing" mode with your email as test user
3. Ensure Drive API is enabled in the project

### Missing fields error

Your 1Password item needs `client_id`/`client_secret` (or `username`/`password` as fallback).

## Creating New OAuth Credentials

See [gdrive-api-setup.md](./gdrive-api-setup.md) for step-by-step Google Cloud Console setup.
