# mise Configuration Templates

Complete mise configuration templates for Gmail access.

## .mise.local.toml (Gitignored - User Creates)

This file is gitignored and contains your actual credentials. Create it in any project where you need Gmail access.

```toml
# Gmail API Configuration
# This file is gitignored - safe to store UUIDs

[env]
# 1Password UUID for Gmail OAuth credentials
# Find with: op item list --vault Employee | grep -i gmail
GMAIL_OP_UUID = "56pehbslb74al3yjyaelly5gx4"

# Optional: Override 1Password vault (default: Employee)
# GMAIL_OP_VAULT = "Personal"
```

## .mise.local.toml.example (Committed - Template)

Commit this template to your repository so others know how to configure Gmail access.

```toml
# Gmail API Configuration
# Copy this file to .mise.local.toml and fill in your values
# .mise.local.toml is gitignored - safe for secrets

[env]
# Required: 1Password UUID for Gmail OAuth credentials
# Find your UUID with: op item list --vault Employee | grep -i gmail
# Or ask Claude: "Help me set up Gmail access"
GMAIL_OP_UUID = "<your-1password-item-uuid>"

# Optional: Override 1Password vault (default: Employee)
# GMAIL_OP_VAULT = "Personal"
```

## .mise.toml Gmail Tasks (Optional - Committed)

Add these convenience tasks to your project's `.mise.toml` for quick Gmail access.

```toml
# Gmail convenience tasks
# Add to project's .mise.toml

[tasks.gmail]
description = "Gmail CLI - run with arguments"
run = "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail"

[tasks."gmail:list"]
description = "List recent emails"
run = "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail list -n 10"

[tasks."gmail:search"]
description = "Search emails (pass query as argument)"
run = "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail search"

[tasks."gmail:unread"]
description = "List unread emails"
run = "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail list -l UNREAD -n 20"
```

## .gitignore Entry

Ensure your project's `.gitignore` includes:

```gitignore
# mise local secrets
.mise.local.toml
```

## Multi-Account Setup

To use different Gmail accounts in different projects, create separate 1Password items for each account and set the appropriate `GMAIL_OP_UUID` in each project's `.mise.local.toml`.

### Example: Work vs Personal

**Work project** (`.mise.local.toml`):

```toml
[env]
GMAIL_OP_UUID = "work-gmail-oauth-uuid"
```

**Personal project** (`.mise.local.toml`):

```toml
[env]
GMAIL_OP_UUID = "personal-gmail-oauth-uuid"
GMAIL_OP_VAULT = "Personal"
```

Tokens are stored separately at `~/.claude/tools/gmail-tokens/<uuid>.json`, so there's no conflict between accounts.
