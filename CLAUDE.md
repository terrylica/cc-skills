# CLAUDE.md

Claude Code skills marketplace: **19 plugins** with skills for ADR-driven development workflows.

**Architecture**: Link Farm + Hub-and-Spoke with Progressive Disclosure

## Navigation

| Topic            | Document                                              |
| ---------------- | ----------------------------------------------------- |
| Installation     | [README.md](./README.md)                              |
| Plugin Dev       | [plugins/CLAUDE.md](./plugins/CLAUDE.md)              |
| Hooks Dev        | [docs/HOOKS.md](./docs/HOOKS.md)                      |
| Release          | [docs/RELEASE.md](./docs/RELEASE.md)                  |
| ITP Workflow     | [plugins/itp/README.md](./plugins/itp/README.md)      |
| Troubleshooting  | [docs/troubleshooting/](./docs/troubleshooting/)      |
| ADRs             | [docs/adr/](./docs/adr/)                              |

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

| File                              | Purpose                     |
| --------------------------------- | --------------------------- |
| `.claude-plugin/marketplace.json` | Plugin registry (SSoT)      |
| `.releaserc.yml`                  | semantic-release config     |
| `scripts/validate-plugins.mjs`    | Plugin validation           |
| `scripts/sync-hooks-to-settings.sh` | Hook synchronization      |

## Link Conventions

| Context             | Format      | Example                          |
| ------------------- | ----------- | -------------------------------- |
| Skill-internal      | Relative    | `[Guide](./references/guide.md)` |
| Repo docs           | Repo-root   | `[ADR](/docs/adr/file.md)`       |
| External            | Full URL    | `[Docs](https://example.com)`    |

## Recent Lessons Learned

**2025-12-17**: PostToolUse hooks require `"decision": "block"` in JSON for Claude visibility. [ADR](/docs/adr/2025-12-17-posttooluse-hook-visibility.md)

**2025-12-15**: Plugin dirs must be registered in marketplace.json. [ADR](/docs/adr/2025-12-14-alpha-forge-worktree-management.md)
