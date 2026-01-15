# Plugin Lifecycle and Configuration

Understanding how Claude Code manages plugins, marketplaces, and their configuration files.

---

## Architecture Overview

```
~/.claude/plugins/
├── known_marketplaces.json      ← Registry of added marketplaces
├── installed_plugins.json       ← Registry of installed plugins
├── settings.json (parent dir)   ← Hooks configuration (loaded at runtime)
├── marketplaces/                ← Cloned marketplace repositories
│   ├── cc-skills/
│   ├── claude-plugins-official/
│   └── ...
└── cache/                       ← Plugin cache (versions, temp files)
    ├── cc-skills/
    └── ...
```

---

## Configuration Files

### known_marketplaces.json

**Purpose**: Registry of all added marketplaces. Claude Code reads this to know where to find plugins.

<!-- SSoT-OK: Example JSON structure for documentation -->

**Structure**:

```json
{
  "cc-skills": {
    "source": {
      "source": "github",
      "repo": "terrylica/cc-skills"
    },
    "installLocation": "/Users/username/.claude/plugins/marketplaces/cc-skills",
    "lastUpdated": "2026-01-14T00:00:00.000Z"
  }
}
```

**Critical Rules**:

| Field             | Type   | Rule                                                            |
| ----------------- | ------ | --------------------------------------------------------------- |
| `installLocation` | string | **MUST be absolute path** - JSON does NOT expand `$HOME` or `~` |
| `source.repo`     | string | GitHub `owner/repo` format                                      |
| `lastUpdated`     | string | ISO 8601 timestamp                                              |

**When Modified**:

- `claude plugin marketplace add` - adds entry
- `claude plugin marketplace remove` - removes entry
- `claude plugin marketplace update` - updates `lastUpdated`

---

### installed_plugins.json

**Purpose**: Registry of installed plugins with versions and paths.

<!-- SSoT-OK: Example JSON structure for documentation -->

**Structure**:

```json
{
  "itp@cc-skills": {
    "name": "itp",
    "marketplace": "cc-skills",
    "installPath": "/Users/username/.claude/plugins/marketplaces/cc-skills/plugins/itp",
    "version": "<version>",
    "installedAt": "2026-01-14T00:00:00.000Z",
    "gitCommitSha": "8d9b4ab..."
  }
}
```

**Critical Rules**:

| Field          | Type   | Rule                                                            |
| -------------- | ------ | --------------------------------------------------------------- |
| `installPath`  | string | **MUST be absolute path** - JSON does NOT expand `$HOME` or `~` |
| `version`      | string | From plugin's `plugin.json` or marketplace's `marketplace.json` |
| `gitCommitSha` | string | Exact commit at installation time                               |

**When Modified**:

- `claude plugin install` - adds/updates entry
- `claude plugin uninstall` - removes entry

---

### settings.json (Hooks)

**Purpose**: Runtime configuration including hooks. **Only hooks in settings.json are loaded** - hooks.json files in plugins are NOT automatically loaded.

**Location**: `~/.claude/settings.json`

**Hooks Structure**:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hook.mjs"
          }
        ]
      }
    ],
    "PostToolUse": [...],
    "Stop": [...]
  }
}
```

**Critical Rules**:

| Aspect       | Rule                                                                     |
| ------------ | ------------------------------------------------------------------------ |
| Hook paths   | **MUST be absolute paths** - `$HOME` and `${VAR}` are NOT expanded       |
| Hook loading | Only settings.json hooks are loaded; plugin hooks.json files are ignored |
| Hook sync    | Run `sync-hooks-to-settings.sh` after adding plugins with hooks          |

---

## Plugin Discovery Flow

```
1. User runs: claude plugin marketplace add owner/repo
   └── Claude Code clones repo to ~/.claude/plugins/marketplaces/NAME/
   └── Adds entry to known_marketplaces.json (with absolute installLocation)

2. User runs: claude plugin install PLUGIN@MARKETPLACE
   └── Claude Code reads known_marketplaces.json to find marketplace location
   └── Reads marketplace's .claude-plugin/marketplace.json for plugin list
   └── Finds plugin source path (e.g., ./plugins/itp)
   └── Registers plugin in installed_plugins.json (with absolute installPath)
   └── Caches plugin in ~/.claude/plugins/cache/MARKETPLACE/PLUGIN/

3. User starts Claude Code session
   └── Claude Code reads installed_plugins.json
   └── Loads skill definitions from each plugin's SKILL.md files
   └── Makes slash commands available (e.g., /itp:go)

4. Hooks are loaded separately
   └── Claude Code reads ~/.claude/settings.json
   └── Loads hooks from "hooks" section
   └── Plugin hooks.json files are NOT automatically loaded
```

---

## Common Issues and Solutions

### Issue: Literal `$HOME` folders created

**Cause**: JSON configs contain literal `$HOME` instead of absolute paths.

**Solution**: See [Troubleshooting: Literal $HOME Folders](/docs/troubleshooting/marketplace-installation.md#7-literal-home-folders-created-environment-variable-not-expanded)

### Issue: Orphaned marketplace (directory exists but not registered)

**Cause**: `known_marketplaces.json` was deleted or corrupted.

**Solution**: See [Troubleshooting: Orphaned Marketplaces](/docs/troubleshooting/marketplace-installation.md#8-orphaned-marketplaces-directory-exists-but-not-registered)

### Issue: Hooks not working

**Cause**: Hooks must be explicitly synced to settings.json.

**Solution**:

```bash
# Sync hooks from marketplace to settings.json
~/.claude/plugins/marketplaces/cc-skills/scripts/sync-hooks-to-settings.sh

# Restart Claude Code
```

### Issue: Plugin shows in installed_plugins.json but commands not available

**Cause**: Cache out of sync or session not restarted.

**Solution**:

```bash
# Clear cache for specific marketplace
rm -rf ~/.claude/plugins/cache/MARKETPLACE_NAME/PLUGIN_NAME

# Reinstall plugin
claude plugin install PLUGIN@MARKETPLACE

# Restart Claude Code
```

---

## Environment Variable Expansion Rules

| Context                   | `$HOME` Expanded? | `${VAR}` Expanded? | Notes                           |
| ------------------------- | ----------------- | ------------------ | ------------------------------- |
| JSON config files         | NO                | NO                 | JSON is literal text            |
| Bash scripts              | YES               | YES                | Shell expands variables         |
| Python with `shell=True`  | YES               | YES                | Via shell                       |
| Python with `shell=False` | NO                | NO                 | Use `os.path.expanduser()`      |
| YAML files                | DEPENDS           | DEPENDS            | Tool-specific                   |
| TOML files (mise)         | YES               | YES                | `{{env.HOME}}` or `{{env.VAR}}` |

**Rule**: Never use `$HOME`, `~`, or `${VAR}` in JSON files. Always use absolute paths.

---

## Marketplace Configuration Files

### .claude-plugin/marketplace.json (in marketplace repo)

**Purpose**: Plugin registry within a marketplace. Claude Code reads this to discover available plugins.

<!-- SSoT-OK: Example JSON structure for documentation -->

**Structure**:

```json
{
  "name": "cc-skills",
  "version": "<version>",
  "description": "...",
  "owner": "terrylica",
  "plugins": [
    {
      "name": "itp",
      "description": "...",
      "version": "<version>",
      "source": "./plugins/itp",
      "category": "development"
    }
  ]
}
```

**Critical Rules**:

| Field    | Rule                                                           |
| -------- | -------------------------------------------------------------- |
| `source` | Relative path from marketplace root (e.g., `./plugins/itp`)    |
| `source` | **NO trailing slashes** - `./plugins/itp` not `./plugins/itp/` |

### plugin.json (in each plugin directory)

**Purpose**: Individual plugin metadata.

<!-- SSoT-OK: Example JSON structure for documentation -->

**Structure**:

```json
{
  "name": "itp",
  "version": "<version>",
  "description": "...",
  "author": {
    "name": "Author Name",
    "url": "https://github.com/username"
  }
}
```

---

## Related Documentation

- [Troubleshooting: Marketplace Installation](/docs/troubleshooting/marketplace-installation.md)
- [Hook Development](/docs/HOOKS.md)
- [Plugin Authoring](/docs/plugin-authoring.md)
- [ADR: Hook Settings Installer](/docs/adr/2025-12-07-itp-hooks-settings-installer.md)
