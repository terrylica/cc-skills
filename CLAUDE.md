# CLAUDE.md

Claude Code skills marketplace: **22 plugins** with skills for ADR-driven development workflows.

**Architecture**: Link Farm + Hub-and-Spoke with Progressive Disclosure

## Documentation Hierarchy

```
CLAUDE.md (this file)           ◄── Hub: Navigation + Essentials
    │
    ├── plugins/CLAUDE.md       ◄── Spoke: Plugin development
    │       ├── itp-hooks/CLAUDE.md  ◄── Deep: Hook reference
    │       └── gh-tools/CLAUDE.md   ◄── Deep: GitHub CLI enforcement
    │
    └── docs/CLAUDE.md          ◄── Spoke: Documentation standards
            ├── HOOKS.md             ◄── Hook development patterns
            ├── RELEASE.md           ◄── Release workflow
            └── PLUGIN-LIFECYCLE.md  ◄── Plugin internals
```

## Navigation

| Topic            | Document                                                   |
| ---------------- | ---------------------------------------------------------- |
| Installation     | [README.md](./README.md)                                   |
| Plugin Dev       | [plugins/CLAUDE.md](./plugins/CLAUDE.md)                   |
| Documentation    | [docs/CLAUDE.md](./docs/CLAUDE.md)                         |
| Hooks Dev        | [docs/HOOKS.md](./docs/HOOKS.md)                           |
| gh-tools         | [plugins/gh-tools/CLAUDE.md](./plugins/gh-tools/CLAUDE.md) |
| Release          | [docs/RELEASE.md](./docs/RELEASE.md)                       |
| Plugin Lifecycle | [docs/PLUGIN-LIFECYCLE.md](./docs/PLUGIN-LIFECYCLE.md)     |
| ITP Workflow     | [plugins/itp/README.md](./plugins/itp/README.md)           |
| Troubleshooting  | [docs/troubleshooting/](./docs/troubleshooting/)           |
| ADRs             | [docs/adr/](./docs/adr/)                                   |
| Resume Context   | [docs/RESUME.md](./docs/RESUME.md)                         |

## Essential Commands

| Task             | Command                            |
| ---------------- | ---------------------------------- |
| Validate plugins | `bun scripts/validate-plugins.mjs` |
| Release (full)   | `mise run release:full`            |
| Release (dry)    | `mise run release:dry`             |
| Execute workflow | `/itp:go feature-name -b`          |
| Setup env        | `/itp:setup`                       |
| Add plugin       | `/plugin-dev:create plugin-name`   |
| Autonomous mode  | `/ru:start` / `/ru:stop`           |

## Plugin Discovery

**SSoT**: `.claude-plugin/marketplace.json`

```bash
# Validate before commit
bun scripts/validate-plugins.mjs
```

Missing marketplace.json entry = "Plugin not found". See [plugins/CLAUDE.md](./plugins/CLAUDE.md).

## Directory Structure

```
cc-skills/
├── .claude-plugin/marketplace.json  ← Plugin registry (SSoT)
├── plugins/                         ← 22 marketplace plugins
│   ├── itp/                         ← Core 4-phase workflow
│   ├── itp-hooks/                   ← Workflow enforcement + code correctness
│   ├── ru/                          ← RU autonomous loop mode
│   ├── mise/                        ← User-global mise workflow commands
│   ├── gmail-commander/             ← Gmail bot + CLI (1Password OAuth)
│   ├── gdrive-tools/                ← Google Drive API (1Password OAuth)
│   └── ...                          ← 16 more plugins
├── docs/
│   ├── adr/                         ← Architecture Decision Records
│   ├── design/                      ← Implementation specs (1:1 with ADRs)
│   ├── HOOKS.md                     ← Hook development patterns
│   ├── RELEASE.md                   ← Release workflow
│   └── PLUGIN-LIFECYCLE.md          ← Plugin internals
└── .mise/tasks/                     ← Release automation
```

## Key Files

| File                                   | Purpose                 |
| -------------------------------------- | ----------------------- |
| `.claude-plugin/marketplace.json`      | Plugin registry (SSoT)  |
| `.releaserc.yml`                       | semantic-release config |
| `scripts/validate-plugins.mjs`         | Plugin validation       |
| `scripts/sync-hooks-to-settings.sh`    | Hook synchronization    |
| `scripts/sync-commands-to-settings.sh` | Command synchronization |

## Link Conventions

| Context        | Format    | Example                          |
| -------------- | --------- | -------------------------------- |
| Skill-internal | Relative  | `[Guide](./references/guide.md)` |
| Repo docs      | Repo-root | `[ADR](/docs/adr/file.md)`       |
| External       | Full URL  | `[Docs](https://example.com)`    |

## Development Toolchain

**Bun-First Policy** (2025-01-12): JavaScript global packages installed via `bun add -g`.

```bash
bun add -g prettier          # Install
bun update -g                # Upgrade all
bun pm ls -g                 # List
```

**Auto-upgrade**: `com.terryli.mise_autoupgrade` runs every 2 hours.

## Recent Lessons Learned

**2026-02-05**: gh-issue-title-reminder hook added - maximizes 256-char GitHub issue titles. [gh-tools CLAUDE.md](./plugins/gh-tools/CLAUDE.md#github-issue-title-optimization-2026-02-05)

**2026-02-04**: gdrive-tools plugin added for Google Drive API access with 1Password OAuth.

**2026-01-24**: Code correctness hooks check silent failures only - NO unused imports (F401). [itp-hooks CLAUDE.md](./plugins/itp-hooks/CLAUDE.md#code-correctness-philosophy)

**2026-01-22**: posttooluse-reminder migrated from bash to TypeScript/Bun (33 tests). [Design Spec](/docs/design/2026-01-10-uv-reminder-hook/spec.md)

**2026-01-12**: gh CLI must use Homebrew, not mise (iTerm2 tab spawning). [ADR](/docs/adr/2026-01-12-mise-gh-cli-incompatibility.md)

**2026-01-11**: Use `--body-file` for `gh issue create` body content. [ADR](/docs/adr/2026-01-11-gh-issue-body-file-guard.md)

**2026-01-10**: uv-reminder hook detects pip and venv activation, suggests uv. [ADR](/docs/adr/2026-01-10-uv-reminder-hook.md)
