**Skill**: [Skill Architecture](../SKILL.md)

# Scripts Reference

This document covers scripts available in the cc-skills repository for plugin and skill development.

## Script Naming Conventions

**Recommended**: `snake_case` for all new scripts.

| Language   | Convention   | Example                                     |
| ---------- | ------------ | ------------------------------------------- |
| Python     | `snake_case` | `validate_links.py`, `verify_compliance.sh` |
| Shell      | `snake_case` | `init_project.sh`, `create_org_config.sh`   |
| JavaScript | `kebab-case` | `validate-plugins.mjs`, `sync-versions.mjs` |

**Note**: Some legacy scripts use `kebab-case` (e.g., `publish-to-pypi.sh`, `install-dependencies.sh`). These are preserved for backwards compatibility. New scripts should use `snake_case`.

## Repository-Level Scripts

Located in `/scripts/` at repository root:

### validate-plugins.mjs

**Purpose**: Validates marketplace.json entries against actual plugin directories.

```bash
node scripts/validate-plugins.mjs           # Validate only
node scripts/validate-plugins.mjs --fix     # Show fix instructions
node scripts/validate-plugins.mjs --strict  # Fail on warnings too
```

**Validation Checks**:

- Plugin directories must have marketplace.json entry
- Required fields: name, description, version, source, etc.
- Referenced source/hooks paths must exist

### sync-versions.mjs

**Purpose**: Synchronizes version numbers across all manifest files.

```bash
node scripts/sync-versions.mjs <version>
```

Auto-discovers plugins from marketplace.json and updates:

- `plugin.json`
- `package.json`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json` (all plugin entries)

### install-hooks.sh

**Purpose**: Installs pre-commit hooks for plugin validation.

```bash
./scripts/install-hooks.sh
```

Installs git pre-commit hook that runs `validate-plugins.mjs` before each commit.

## Skill-Architecture Plugin Scripts

Located in `plugins/skill-architecture/scripts/`:

### validate_links.py

**Purpose**: Validates internal markdown links for portability.

```bash
uv run plugins/skill-architecture/scripts/validate_links.py <path>
```

Ensures links use relative paths (`./`, `../`) for cross-installation compatibility.

### verify-compliance.sh

**Purpose**: Validates skill conformance to structural patterns.

```bash
bash plugins/skill-architecture/scripts/verify-compliance.sh <path/to/skill>
```

**Validation Checks**:

- S1: SKILL.md ≤200 lines (progressive disclosure)
- S2: Proper reference structure
- S3: Description format compliance

## ITP Plugin Scripts

Located in `plugins/itp/scripts/`:

### manage-hooks.sh

**Purpose**: Install/uninstall ITP hooks to settings.json.

```bash
bash plugins/itp/scripts/manage-hooks.sh install
bash plugins/itp/scripts/manage-hooks.sh uninstall
bash plugins/itp/scripts/manage-hooks.sh status
```

### install-dependencies.sh

**Purpose**: Install ITP workflow dependencies.

```bash
bash plugins/itp/scripts/install-dependencies.sh --check   # Check only
bash plugins/itp/scripts/install-dependencies.sh --install # Install missing
```

## Skill-Specific Scripts

### PyPI Publishing

Located in `plugins/itp/skills/pypi-doppler/scripts/`:

```bash
bash plugins/itp/skills/pypi-doppler/scripts/publish-to-pypi.sh
```

**LOCAL-ONLY** publishing with CI detection guards.

### Semantic Release

Located in `plugins/itp/skills/semantic-release/scripts/`:

```bash
bash plugins/itp/skills/semantic-release/scripts/init_project.sh
bash plugins/itp/skills/semantic-release/scripts/init_user_config.sh
bash plugins/itp/skills/semantic-release/scripts/create_org_config.sh
```

## Creating New Plugins

Use the `/itp:plugin-add` command instead of manual scaffolding:

```bash
/itp:plugin-add my-new-plugin
```

This command:

1. Creates plugin directory structure
2. Registers in marketplace.json
3. Creates ADR and design spec
4. Sets up validation

## Troubleshooting

### "Plugin not found in marketplace"

Run validation to identify unregistered plugins:

```bash
node scripts/validate-plugins.mjs --fix
```

### "Permission denied"

Make scripts executable:

```bash
chmod +x scripts/*.sh
chmod +x plugins/*/scripts/*.sh
```

### Pre-commit hook not running

Reinstall hooks:

```bash
./scripts/install-hooks.sh
```
