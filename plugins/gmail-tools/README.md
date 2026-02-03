# Gmail Tools

Gmail API client for Claude Code CLI, powered by Bun/TypeScript.

## Installation

This plugin is part of the [cc-skills](https://github.com/terrylica/cc-skills) marketplace.

```bash
claude plugin marketplace add terrylica/cc-skills
```

## Quick Start

```bash
# List recent emails
gmail list -n 10

# Search emails
gmail search "from:someone@example.com"

# Read specific email
gmail read <message_id>

# Export to JSON
gmail export -q "label:inbox" -o emails.json -n 100
```

## Setup

Gmail access requires configuration via mise environment variables.

### Automatic Setup

Ask Claude Code: "Help me set up Gmail access"

Or run: `/gmail-tools:setup`

### Manual Setup

1. **Find your 1Password UUID**:

   ```bash
   op item list --vault Employee | grep -i gmail
   ```

2. **Add to .mise.local.toml**:

   ```toml
   [env]
   GMAIL_OP_UUID = "<your-uuid>"
   ```

3. **Reload mise**:

   ```bash
   mise trust && cd .
   ```

4. **Test**:

   ```bash
   gmail list -n 1
   ```

## Skills

| Skill          | Description                   |
| -------------- | ----------------------------- |
| `gmail-access` | Read and search Gmail via CLI |

## Commands

| Command              | Description              |
| -------------------- | ------------------------ |
| `/gmail-tools:setup` | Interactive setup wizard |

## Environment Variables

| Variable         | Required | Default    | Description                               |
| ---------------- | -------- | ---------- | ----------------------------------------- |
| `GMAIL_OP_UUID`  | Yes      | -          | 1Password item UUID for OAuth credentials |
| `GMAIL_OP_VAULT` | No       | `Employee` | 1Password vault name                      |

## Architecture

- **Runtime**: Bun (native TypeScript execution)
- **API**: `@googleapis/gmail` (lightweight Gmail-only package)
- **Auth**: OAuth2 with 1Password credential storage
- **Tokens**: `~/.claude/tools/gmail-tokens/<uuid>.json`

## Documentation

- [SKILL.md](skills/gmail-access/SKILL.md) - Main skill documentation
- [mise-templates.md](skills/gmail-access/references/mise-templates.md) - Configuration templates
- [mise-setup.md](skills/gmail-access/references/mise-setup.md) - Setup guide
- [gmail-api-setup.md](skills/gmail-access/references/gmail-api-setup.md) - OAuth credentials setup

## License

MIT
