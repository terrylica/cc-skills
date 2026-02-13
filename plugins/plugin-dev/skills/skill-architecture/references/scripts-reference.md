**Skill**: [Skill Architecture](../SKILL.md)

# Scripts Reference

This document covers scripts available in the cc-skills repository for plugin and skill development.

## Script Naming Conventions

**Recommended**: `snake_case` for all new scripts.

| Language   | Convention   | Example                                     |
| ---------- | ------------ | ------------------------------------------- |
| TypeScript | `kebab-case` | `validate-skill.ts`, `validate-links.ts`    |
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

## Plugin-Dev Scripts (TypeScript Validators)

Located in `plugins/plugin-dev/scripts/`:

### validate-skill.ts

**Purpose**: Main validator orchestrating all skill checks.

```bash
bun run plugins/plugin-dev/scripts/validate-skill.ts <skill-path> [options]

Options:
  --fix             Show fix suggestions for violations
  --interactive     Generate AskUserQuestion JSON for clarifications
  -v, --verbose     Show all checks including passed ones
  --strict          Treat warnings as errors
  --project-local   Relaxed link rules (auto-detected for .claude/skills/)
  --skip-bash       Skip bash compatibility checks (for documentation skills)
```

**Validation Checks**:

- YAML frontmatter format and required fields
- Name format (`^[a-z][a-z0-9-]*$`)
- Description quality (length, triggers)
- Link portability (context-aware, see below)
- Bash compatibility (heredoc wrappers required)
- Line count (progressive disclosure)

**Context-Aware Validation**:

| Context             | Link Policy                                | Bash Policy             |
| ------------------- | ------------------------------------------ | ----------------------- |
| Marketplace plugin  | Only `./`, `/docs/adr/*`, `/docs/design/*` | Heredoc required        |
| Project-local skill | Any `/...` repo path allowed               | Same (or `--skip-bash`) |

Project-local skills are auto-detected from paths containing `.claude/skills/`.

### validate-links.ts

**Purpose**: Validates internal markdown links for portability.

```bash
bun run plugins/plugin-dev/scripts/validate-links.ts <skill-path>
```

**Link Policy**:

- ALLOWED: `./relative/path.md`, `/docs/adr/*`, `/docs/design/*`
- FORBIDDEN: `/docs/guides/*`, `/plugins/*`, any other `/...` paths
- FIX: Copy external files into skill's `references/` directory

### fix-bash-blocks.ts

**Purpose**: Automatically wraps bash code blocks with heredoc for zsh compatibility.

```bash
bun run plugins/plugin-dev/scripts/fix-bash-blocks.ts <path> [--dry]
```

Generates context-aware EOF markers (e.g., `PREFLIGHT_EOF`, `SETUP_EOF`) based on block content.

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

## Shared Library Pattern

When multiple scripts in a plugin share common functionality, extract it into a shared library to reduce duplication and ensure consistent behavior.

### Structure

```
scripts/
├── lib/
│   └── common.sh         # Shared functions (sourced, not executed)
├── action-a.sh           # Sources lib/common.sh
├── action-b.sh           # Sources lib/common.sh
└── action-c.sh           # Sources lib/common.sh
```

### Source Convention

Each script sources the shared library relative to its own location:

```bash
/usr/bin/env bash << 'SOURCE_LIB_EOF'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
SOURCE_LIB_EOF
```

### What Belongs in the Shared Library

| Function Type        | Example                               | Why Shared                              |
| -------------------- | ------------------------------------- | --------------------------------------- |
| Logging              | `app_log()` with consistent format    | All scripts need uniform log output     |
| Lock management      | `acquire_lock()`, `release_lock()`    | Prevents race conditions across scripts |
| Cleanup handlers     | `cleanup()` with trap integration     | Ensures resources are released on exit  |
| Config loading       | Read env vars with defaults           | Consistent defaults across all scripts  |
| Detection heuristics | Language detection, platform checks   | Same logic needed in multiple contexts  |
| Process management   | `kill_existing()`, `wait_for_ready()` | Consistent process lifecycle handling   |

### Design Guidelines

1. **Configurable defaults**: Use `VAR="${VAR:-default_value}"` so callers can override
2. **No side effects on source**: Sourcing the library should only define functions, not execute code
3. **Prefix internal variables**: Use underscore prefix (`_INTERNAL_VAR`) to avoid collisions with caller variables
4. **Document the public API**: Comment which functions are intended for callers vs internal helpers
5. **One library per concern**: If the shared code grows large, split into `lib/logging.sh`, `lib/locking.sh`, etc.
6. **Trap-safe cleanup**: Use `trap cleanup EXIT` in individual scripts, not in the library (callers own their own trap chain)

---

## Creating New Plugins

Use the `/plugin-dev:create` command instead of manual scaffolding:

```bash
/plugin-dev:create my-new-plugin
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
