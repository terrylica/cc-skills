# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Architecture**: Link Farm + Hub-and-Spoke with Progressive Disclosure

## Repository Overview

Claude Code skills marketplace: **20 plugins** with **42 skills** for ADR-driven development workflows.

**Key Documentation**:

- [README.md](./README.md) - Installation, plugins, terminology
- [plugins/itp/README.md](./plugins/itp/README.md) - Core /itp:go workflow
- `docs/adr/` - Architecture Decision Records (MADR 4.0)
- `docs/design/` - Implementation specifications (1:1 with ADRs)

## Essential Commands

| Task                 | Command                            |
| -------------------- | ---------------------------------- |
| Release (dry-run)    | `npm run release:dry`              |
| Release (production) | `npm run release`                  |
| Format files         | `prettier --write .`               |
| Execute workflow     | `/itp:go feature-name -b`          |
| Setup environment    | `/itp:setup`                       |
| Manage ITP hooks     | `/itp:hooks install`               |
| **Validate plugins** | `bun scripts/validate-plugins.mjs` |
| Add new plugin       | `/plugin-dev:create plugin-name`   |
| Start autonomous     | `/ralph:start`                     |
| Stop autonomous      | `/ralph:stop`                      |
| View loop config     | `/ralph:config show`               |
| Add encouraged item  | `/ralph:encourage <phrase>`        |
| Add forbidden item   | `/ralph:forbid <phrase>`           |
| Remove guidance item | `/ralph:encourage --remove` or `/ralph:forbid --remove` |

## Troubleshooting

| Issue                                                                   | Reference                                                                                     |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Plugin marketplace installation failures (clone errors, network issues) | [Marketplace Installation Troubleshooting](/docs/troubleshooting/marketplace-installation.md) |
| Plugin not found after creation                                         | [Validation](#validation) - ensure marketplace.json entry exists                              |

## Plugin Discovery (Critical)

<!-- ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md (lesson learned) -->

**How Claude Code finds plugins**: The **single source of truth** is `.claude-plugin/marketplace.json`.

```
.claude-plugin/
└── marketplace.json    ← Plugin catalog (REQUIRED for /plugin install)
```

**Common Mistake**: Creating `plugins/my-plugin/` without adding entry to `marketplace.json` results in:

```
Plugin "my-plugin" not found in any marketplace
```

**Prevention**: See [Validation](#validation) section below.

**Detailed Reference**: [Plugin Manifest Validation](./plugins/plugin-dev/skills/skill-architecture/references/validation-reference.md#plugin-manifest-validation)

## Validation

Run before committing plugin changes:

```bash
bun scripts/validate-plugins.mjs           # Validate only (5x faster)
bun scripts/validate-plugins.mjs --fix     # Show fix instructions
bun scripts/validate-plugins.mjs --strict  # Fail on warnings too
```

**What it validates**:

| Check                  | Error Level | Description                              |
| ---------------------- | ----------- | ---------------------------------------- |
| Directory registration | ❌ Error    | Plugin dirs must have marketplace entry  |
| Required fields        | ❌ Error    | name, description, version, source, etc. |
| Source/hooks paths     | ❌ Error    | Referenced files must exist              |

**Pre-commit hook** (auto-installed): Blocks commits with unregistered plugins.

**Install hook on new clone**: `./scripts/install-hooks.sh`

## Architecture

**Directory Structure**:

```
cc-skills/
├── .claude-plugin/
│   └── marketplace.json    ← Plugin registry (20 entries)
├── plugins/                ← 20 marketplace plugins
│   ├── itp/                ← Core workflow
│   ├── ralph/              ← Autonomous loop mode (RSSI)
│   ├── skill-architecture/ ← Meta-skill for skill creation
│   ├── alpha-forge-worktree/ ← Git worktree management
│   └── ...
├── docs/
│   ├── adr/                ← Architecture Decision Records
│   └── design/             ← Implementation specs (1:1 with ADRs)
└── scripts/
    ├── validate-plugins.mjs ← Plugin validation
    └── install-hooks.sh     ← Hook installer
```

**Core Plugin**: `plugins/itp/` - 4-phase ADR-driven workflow:

1. Preflight: Create ADR + design spec
2. Phase 1: Implementation
3. Phase 2: Format + push
4. Phase 3: Release

## Development Patterns

**Workflow**: All features use `/itp:go` which creates ADR in `docs/adr/` and spec in `docs/design/`.

**Adding Plugins**: Use `/plugin-dev:create plugin-name` - handles marketplace.json registration automatically.

**Link Conventions**: Marketplace plugins use context-specific paths:

| Link Target             | Format                  | Example                          |
| ----------------------- | ----------------------- | -------------------------------- |
| Skill-internal files    | Relative (`./`, `../`)  | `[Guide](./references/guide.md)` |
| Repo docs (ADRs, specs) | Repo-root (`/docs/...`) | `[ADR](/docs/adr/file.md)`       |
| External resources      | Full URL                | `[Docs](https://example.com)`    |

**Why**: Skill-internal files must use relative paths (absolute paths break when installed to `~/.claude/skills/`). ADRs and design specs are NOT bundled with installed plugins, so `/docs/` paths serve as source repo references.

**Release**: Semantic-release with conventional commits. ALL commit types trigger patch releases (marketplace constraint). Post-release automatically syncs `~/.claude/plugins/cache/` — no manual `/plugin update` needed.

## Key Files

| File                              | Purpose                                              |
| --------------------------------- | ---------------------------------------------------- |
| `.claude-plugin/marketplace.json` | **Plugin registry** (must register all plugins here) |
| `plugin.json`                     | Root plugin manifest                                 |
| `.releaserc.yml`                  | Semantic-release config                              |
| `scripts/validate-plugins.mjs`    | Plugin validation (pre-commit)                       |
| `plugins/itp/commands/go.md`      | Core workflow definition                             |
| `plugins/itp-hooks/hooks/`        | PreToolUse/PostToolUse enforcement                   |
| `plugins/ralph/hooks/`            | RSSI autonomous loop hooks (Stop + 2 PreToolUse)     |

## Hooks Development

**Key Insight**: PostToolUse hook stdout is only visible to Claude when JSON contains `"decision": "block"`.

| Output Format                  | Claude Visibility |
| ------------------------------ | ----------------- |
| Plain text                     | ❌ Not visible    |
| JSON without `decision: block` | ❌ Not visible    |
| JSON with `decision: block`    | ✓ Visible         |

**Pattern for hooks that communicate with Claude**:

```bash
# PostToolUse hook - use JSON with decision:block
jq -n --arg reason "[HOOK] Your message" '{decision: "block", reason: $reason}'
exit 0
```

**Detailed Reference**: [PostToolUse Hook Visibility ADR](./docs/adr/2025-12-17-posttooluse-hook-visibility.md)

**Related ADRs**:

- [PreToolUse/PostToolUse Hooks](./docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md) - Architecture
- [ITP Hooks Settings Installer](./docs/adr/2025-12-07-itp-hooks-settings-installer.md) - Installation

## Recent Lessons Learned

**2025-12-17: PostToolUse Hook Visibility** ([ADR](./docs/adr/2025-12-17-posttooluse-hook-visibility.md))

Created chezmoi sync reminder hook that executed correctly but output wasn't visible to Claude. Debug logging confirmed hook ran. Root cause: PostToolUse hooks require `"decision": "block"` in JSON output for Claude to see the reason. Fix: Changed from plain text to JSON with `decision: block`.

**2025-12-15: Plugin Discovery Issue** ([ADR](./docs/adr/2025-12-14-alpha-forge-worktree-management.md))

Created `plugins/alpha-forge-worktree/` but forgot to register in `marketplace.json`. Result: `/plugin install` failed with "not found". Fix: Enhanced `validate-plugins.mjs` and added pre-commit hook.

**Prevention checklist**:

- [ ] Plugin dir exists in `plugins/`
- [ ] Entry added to `.claude-plugin/marketplace.json`
- [ ] `bun scripts/validate-plugins.mjs` passes
- [ ] Commit succeeds (pre-commit hook validates)
