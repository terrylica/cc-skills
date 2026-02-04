# Google Drive Tools

Google Drive API client for Claude Code CLI, powered by Bun/TypeScript.

## Installation

This plugin is part of the [cc-skills](https://github.com/terrylica/cc-skills) marketplace.

```bash
claude plugin marketplace add terrylica/cc-skills
```

## Quick Start

```bash
# List files in a folder
gdrive list <folder_id>

# List files with details
gdrive list <folder_id> --verbose

# Download a single file
gdrive download <file_id> -o output_file.pdf

# Download entire folder
gdrive sync <folder_id> -o ./output_dir

# Search files
gdrive search "name contains 'training'"
```

## Setup

Google Drive access requires configuration via mise environment variables.

### Automatic Setup

Ask Claude Code: "Help me set up Google Drive access"

Or run: `/gdrive-tools:setup`

### Manual Setup

1. **Find your 1Password UUID**:

   ```bash
   op item list --vault Employee | grep -i drive
   ```

2. **Add to .mise.local.toml**:

   ```toml
   [env]
   GDRIVE_OP_UUID = "<your-uuid>"
   ```

3. **Reload mise**:

   ```bash
   mise trust && cd .
   ```

4. **Test**:

   ```bash
   gdrive list <folder_id>
   ```

## Skills

| Skill           | Description                          |
| --------------- | ------------------------------------ |
| `gdrive-access` | List, download, and sync Drive files |

## Commands

| Command               | Description              |
| --------------------- | ------------------------ |
| `/gdrive-tools:setup` | Interactive setup wizard |

## Environment Variables

| Variable          | Required | Default    | Description                               |
| ----------------- | -------- | ---------- | ----------------------------------------- |
| `GDRIVE_OP_UUID`  | Yes      | -          | 1Password item UUID for OAuth credentials |
| `GDRIVE_OP_VAULT` | No       | `Employee` | 1Password vault name                      |

## Architecture

- **Runtime**: Bun (native TypeScript execution)
- **API**: `@googleapis/drive` (lightweight Drive-only package)
- **Auth**: OAuth2 with 1Password credential storage
- **Tokens**: `~/.claude/tools/gdrive-tokens/<uuid>.json`

## Documentation

- [SKILL.md](skills/gdrive-access/SKILL.md) - Main skill documentation
- [gdrive-api-setup.md](skills/gdrive-access/references/gdrive-api-setup.md) - OAuth credentials setup

## License

MIT
