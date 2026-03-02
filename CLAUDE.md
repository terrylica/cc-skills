# CLAUDE.md

Claude Code skills marketplace: **23 plugins** with skills for ADR-driven development workflows.

**Architecture**: Link Farm + Hub-and-Spoke with Progressive Disclosure

## Documentation Hierarchy

```
CLAUDE.md (this file)                  ◄── Hub: Navigation + Essentials
    │
    ├── plugins/CLAUDE.md              ◄── Spoke: Plugin development (all 23 plugins listed)
    │       ├── {plugin}/CLAUDE.md     ◄── Deep: Each of the 23 plugins has its own CLAUDE.md
    │       └── (see Navigation table below for key plugin docs)
    │
    └── docs/CLAUDE.md                 ◄── Spoke: Documentation standards
            ├── HOOKS.md               ◄── Hook development patterns
            ├── RELEASE.md             ◄── Release workflow
            ├── PLUGIN-LIFECYCLE.md    ◄── Plugin internals
            └── LESSONS.md             ◄── Lessons learned (extracted from root)
```

## Navigation

### Spokes & Docs

| Topic             | Document                                                                                                                     |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Installation      | [README.md](./README.md)                                                                                                     |
| Plugin Dev        | [plugins/CLAUDE.md](./plugins/CLAUDE.md)                                                                                     |
| Documentation     | [docs/CLAUDE.md](./docs/CLAUDE.md)                                                                                           |
| Hooks Dev         | [docs/HOOKS.md](./docs/HOOKS.md)                                                                                             |
| Lessons Learned   | [docs/LESSONS.md](./docs/LESSONS.md)                                                                                         |
| Cargo TTY Fix     | [docs/cargo-tty-suspension-prevention.md](./docs/cargo-tty-suspension-prevention.md)                                         |
| Claude Code Proxy | [devops-tools/skills/claude-code-proxy-patterns/SKILL.md](./plugins/devops-tools/skills/claude-code-proxy-patterns/SKILL.md) |
| Release           | [docs/RELEASE.md](./docs/RELEASE.md)                                                                                         |
| Plugin Lifecycle  | [docs/PLUGIN-LIFECYCLE.md](./docs/PLUGIN-LIFECYCLE.md)                                                                       |
| Troubleshooting   | [docs/troubleshooting/](./docs/troubleshooting/)                                                                             |
| ADRs              | [docs/adr/](./docs/adr/)                                                                                                     |
| Resume Context    | [docs/RESUME.md](./docs/RESUME.md)                                                                                           |

### Plugin CLAUDE.md Files (23/23)

All 23 plugins have their own CLAUDE.md with Hub+Sibling navigation links. Access via `plugins/{name}/CLAUDE.md` or browse the full table in [plugins/CLAUDE.md](./plugins/CLAUDE.md).

Key plugin docs: [itp](./plugins/itp/CLAUDE.md) | [itp-hooks](./plugins/itp-hooks/CLAUDE.md) | [gh-tools](./plugins/gh-tools/CLAUDE.md) | [devops-tools](./plugins/devops-tools/CLAUDE.md) | [gmail-commander](./plugins/gmail-commander/CLAUDE.md) | [tts-telegram-sync](./plugins/tts-telegram-sync/CLAUDE.md) | [calcom-commander](./plugins/calcom-commander/CLAUDE.md)

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
├── plugins/                         ← 23 marketplace plugins (each has CLAUDE.md)
│   ├── itp/                         ← Core 4-phase workflow
│   ├── itp-hooks/                   ← Workflow enforcement + code correctness
│   ├── ru/                          ← RU autonomous loop mode
│   ├── mise/                        ← User-global mise workflow commands
│   ├── gmail-commander/             ← Gmail bot + CLI (1Password OAuth)
│   └── ...                          ← 18 more plugins
├── docs/
│   ├── adr/                         ← Architecture Decision Records
│   ├── design/                      ← Implementation specs (1:1 with ADRs)
│   ├── HOOKS.md                     ← Hook development patterns
│   ├── RELEASE.md                   ← Release workflow
│   ├── PLUGIN-LIFECYCLE.md          ← Plugin internals
│   └── LESSONS.md                   ← Lessons learned
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

## Lessons Learned

See [docs/LESSONS.md](./docs/LESSONS.md).
