# CLAUDE.md

Claude Code skills marketplace: **19 plugins** with skills for ADR-driven development workflows.

**Architecture**: Link Farm + Hub-and-Spoke with Progressive Disclosure

## Navigation

| Topic           | Document                                         |
| --------------- | ------------------------------------------------ |
| Installation    | [README.md](./README.md)                         |
| Plugin Dev      | [plugins/CLAUDE.md](./plugins/CLAUDE.md)         |
| Documentation   | [docs/CLAUDE.md](./docs/CLAUDE.md)               |
| Hooks Dev       | [docs/HOOKS.md](./docs/HOOKS.md)                 |
| Release         | [docs/RELEASE.md](./docs/RELEASE.md)             |
| ITP Workflow    | [plugins/itp/README.md](./plugins/itp/README.md) |
| Troubleshooting | [docs/troubleshooting/](./docs/troubleshooting/) |
| ADRs            | [docs/adr/](./docs/adr/)                         |
| Resume Context  | [docs/RESUME.md](./docs/RESUME.md)               |

## Essential Commands

| Task             | Command                            |
| ---------------- | ---------------------------------- |
| Validate plugins | `bun scripts/validate-plugins.mjs` |
| Release (full)   | `mise run release_full`            |
| Release (dry)    | `mise run release_dry`             |
| Execute workflow | `/itp:go feature-name -b`          |
| Setup env        | `/itp:setup`                       |
| Add plugin       | `/plugin-dev:create plugin-name`   |
| Autonomous mode  | `/ralph:start` / `/ralph:stop`     |

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
├── .claude-plugin/marketplace.json  ← Plugin registry
├── plugins/                         ← 19 marketplace plugins
│   ├── itp/                         ← Core workflow
│   ├── ralph/                       ← Autonomous loop (RSSI)
│   └── ...
├── docs/
│   ├── adr/                         ← Architecture decisions
│   ├── design/                      ← Implementation specs
│   ├── HOOKS.md                     ← Hook development
│   └── RELEASE.md                   ← Release workflow
└── .mise/tasks/                     ← Release automation
```

## Key Files

| File                                | Purpose                 |
| ----------------------------------- | ----------------------- |
| `.claude-plugin/marketplace.json`   | Plugin registry (SSoT)  |
| `.releaserc.yml`                    | semantic-release config |
| `scripts/validate-plugins.mjs`      | Plugin validation       |
| `scripts/sync-hooks-to-settings.sh` | Hook synchronization    |

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

**2026-01-22**: Polars preference hook enforces Polars over Pandas (PreToolUse dialog + PostToolUse backup). [ADR](/docs/adr/2026-01-22-polars-preference-hook.md)

**2026-01-22**: posttooluse-reminder migrated from bash to TypeScript/Bun (33 tests). [Design Spec](/docs/design/2026-01-10-uv-reminder-hook/spec.md)

**2026-01-12**: gh CLI must use Homebrew, not mise (iTerm2 tab spawning). [ADR](/docs/adr/2026-01-12-mise-gh-cli-incompatibility.md)

**2026-01-11**: Use `--body-file` for `gh issue create` body content. [ADR](/docs/adr/2026-01-11-gh-issue-body-file-guard.md)

**2026-01-10**: uv-reminder hook detects pip and venv activation, suggests uv. [ADR](/docs/adr/2026-01-10-uv-reminder-hook.md)

**2026-01-03**: WebFetch to github.com soft-blocked; use `gh` CLI. [ADR](/docs/adr/2026-01-03-gh-tools-webfetch-enforcement.md)
