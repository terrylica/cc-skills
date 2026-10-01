# CLAUDE.md

Claude Code skills marketplace: **39 plugins** with skills for ADR-driven development workflows.

**Architecture**: Link Farm + Hub-and-Spoke with Progressive Disclosure

## Documentation Hierarchy

```
CLAUDE.md (this file)                          ◄── Hub: Navigation + Essentials
    │
    ├── plugins/CLAUDE.md                      ◄── Spoke: Plugin development (all plugins listed)
    │       └── {plugin}/CLAUDE.md             ◄── Deep: Per-plugin SSoT
    │                                                (project/stack/conventions/architecture live here,
    │                                                 NOT duplicated in root)
    │           └── skills/{skill}/CLAUDE.md   ◄── Deepest: Per-skill SSoT (emerging — opt-in per skill)
    │                                                (file table, invariants, recent-change log,
    │                                                 edit conventions; sibling to SKILL.md)
    │
    └── docs/CLAUDE.md                         ◄── Spoke: Documentation standards
            ├── HOOKS.md                       ◄── Hook development patterns
            ├── RELEASE.md                     ◄── Release workflow
            ├── PLUGIN-LIFECYCLE.md            ◄── Plugin internals
            └── LESSONS.md                     ◄── Lessons learned (dated entries)
```

**Progressive disclosure rule**: each layer must add information the next-shallower layer didn't already cover. Don't restate plugin invariants in the root; don't restate skill invariants in the plugin. When the user asks Claude something specific, Claude follows links downward — so the deepest layer's freshness matters most.

## Navigation

### Spokes & Docs

| Topic                     | Document                                                                                                                     |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Installation              | [README.md](./README.md)                                                                                                     |
| Plugin Dev                | [plugins/CLAUDE.md](./plugins/CLAUDE.md)                                                                                     |
| Documentation             | [docs/CLAUDE.md](./docs/CLAUDE.md)                                                                                           |
| Hooks Dev                 | [docs/HOOKS.md](./docs/HOOKS.md)                                                                                             |
| Lessons Learned           | [docs/LESSONS.md](./docs/LESSONS.md)                                                                                         |
| Cargo TTY Fix             | [docs/cargo-tty-suspension-prevention.md](./docs/cargo-tty-suspension-prevention.md)                                         |
| Claude Code Proxy         | [devops-tools/skills/claude-code-proxy-patterns/SKILL.md](./plugins/devops-tools/skills/claude-code-proxy-patterns/SKILL.md) |
| Release                   | [docs/RELEASE.md](./docs/RELEASE.md)                                                                                         |
| Plugin Lifecycle          | [docs/PLUGIN-LIFECYCLE.md](./docs/PLUGIN-LIFECYCLE.md)                                                                       |
| Troubleshooting           | [docs/troubleshooting/](./docs/troubleshooting/)                                                                             |
| ADRs                      | [docs/adr/](./docs/adr/)                                                                                                     |
| Machine-readable CLI spec | [cli_spec.json](./cli_spec.json) — gen: `scripts/cli_spec.py`; tasks `moon run repo:cli-spec` / `repo:cli-spec-check`        |

### Plugin CLAUDE.md files

Every plugin carries its own CLAUDE.md with Hub+Sibling navigation links. Keep it that way: a new plugin ships one in the same commit that creates it. Access via `plugins/{name}/CLAUDE.md` or browse the full table in [plugins/CLAUDE.md](./plugins/CLAUDE.md).

### Machine-readable CLI spec (`cli_spec.json`)

Per the CLI-first + machine-readable-docs doctrine (`~/.claude/cli-first-machine-readable-docs-CLAUDE.md`), `scripts/cli_spec.py` emits a repo-root **`cli_spec.json`** (JSON Schema 2020-12) describing every Python `argparse` skill CLI — so an agent learns a skill script's flags without scraping `--help`. AST-based (parses each file, never imports it; excludes vendored/`.build`/`node_modules`), 35 CLIs across `plugins/*/skills/*/scripts/` + `scripts/`. Regenerate: `moon run repo:cli-spec`; drift+completeness gate: `moon run repo:cli-spec-check` (+ `scripts/test_cli_spec.py`, 9 tests).

Key plugin docs: [itp](./plugins/itp/CLAUDE.md) | [itp-hooks](./plugins/itp-hooks/CLAUDE.md) | [gh-tools](./plugins/gh-tools/CLAUDE.md) | [devops-tools](./plugins/devops-tools/CLAUDE.md) | [gmail-commander](./plugins/gmail-commander/CLAUDE.md) | [calcom-commander](./plugins/calcom-commander/CLAUDE.md)

## Essential Commands

| Task              | Command                            |
| ----------------- | ---------------------------------- |
| Full quality gate | `moon run repo:check`              |
| Validate plugins  | `bun scripts/validate-plugins.mjs` |
| Release (full)    | `moon run repo:release-full`       |
| Release (dry)     | `moon run repo:release-dry`        |
| List every task   | `moon query tasks`                 |
| Execute workflow  | `/itp:go feature-name -b`          |
| Setup env         | `/itp:setup`                       |
| Add plugin        | `/plugin-dev:create plugin-name`   |

`moon run repo:check` is the local-first gate that must pass before a push, enforced by the pre-push hook that `bash scripts/install-hooks.sh` installs (run it once per clone; it keeps the global account check, and `PREPUSH_GATE_OK="<reason>"` is the stated-reason bypass). Its fan-out is the `deps` list of `check` in `moon.yml` (`moon task repo:check` prints it), not a list kept here. Task targets are `repo:<name>` with a hyphen. `.prototools` is the only toolchain manifest here; jdx/mise is not used, and a second toolchain file must never be added (two files pinning the same tool is the drift that broke every bun-backed hook on 2026-09-03).

## Directory Structure

```
cc-skills/
├── .claude-plugin/marketplace.json  ← Plugin registry (SSoT)
├── plugins/                         ← Marketplace plugins (each has CLAUDE.md)
│   ├── itp/                         ← Core 4-phase workflow
│   ├── itp-hooks/                   ← Workflow enforcement + code correctness
│   ├── gemini-deep-research/        ← Gemini Deep Research browser automation
│   ├── gmail-commander/             ← Gmail CLI + shared bot code (1Password OAuth)
│   ├── macro-keyboard/              ← Karabiner remap for cheap 3-key pads (skill-level CLAUDE.mds)
│   └── ...                          ← the rest (full table: plugins/CLAUDE.md)
├── docs/
│   ├── adr/                         ← Architecture Decision Records
│   ├── design/                      ← Implementation specs
│   ├── HOOKS.md                     ← Hook development patterns
│   ├── RELEASE.md                   ← Release workflow
│   ├── PLUGIN-LIFECYCLE.md          ← Plugin internals
│   └── LESSONS.md                   ← Lessons learned
└── tasks/                           ← moon task scripts (release/, commits/, hooks/, audits, tests/)
```

## Key Files

| File                                       | Purpose                                                                |
| ------------------------------------------ | ---------------------------------------------------------------------- |
| `.claude-plugin/marketplace.json`          | Plugin registry (SSoT)                                                 |
| `release.config.cjs`                       | semantic-release config (body-preserving release notes)                |
| `scripts/validate-plugins.mjs`             | Plugin validation                                                      |
| `scripts/cc-plugin-root`                   | Resolve a plugin's live install path (see below)                       |
| `scripts/commit-message-exposure-guard.ts` | Commit-msg exposure guard (blocks credentials, reminds on identifiers) |
| `scripts/sync-hooks-to-settings.sh`        | Prunes legacy cc-skills hook entries from `settings.json`              |
| `scripts/sync-commands-to-settings.sh`     | Command synchronization                                                |

## Skills resolve plugin paths with `cc-plugin-root`, never `$CLAUDE_PLUGIN_ROOT`

`CLAUDE_PLUGIN_ROOT` is substituted only inside plugin manifests and hook/MCP subprocess environments; in a SKILL.md it is an empty string. A skill resolves its own files with `"$(cc-plugin-root <plugin>)/…"`. Enforced by **skill-plugin-root-guard** (escape `SKILL-PLUGIN-ROOT-OK`) → [spoke](./plugins/itp-hooks/docs/skill-plugin-root-guard.md)

## Common Plugin Patterns (reuse registry)

Recurring architectural patterns across the plugins. This is a **pointer registry** for new-plugin authors — the exemplars are the SSoT, not this table.

| Pattern                    | What it is                                                                                                                                       | Exemplars to copy                                                                                                                                |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| **setup + health skills**  | Every service-backed plugin ships a `setup` (install/verify deps) and a `health` (subsystem diagnostic) skill                                    | [calcom-commander](./plugins/calcom-commander/CLAUDE.md), [gmail-commander](./plugins/gmail-commander/CLAUDE.md)                                 |
| **Credential resolution**  | SCS ladder first (self-custody `vault`/Keychain); 1Password only for company-shared, never client-confidential                                   | [gmail-commander](./plugins/gmail-commander/CLAUDE.md)                                                                                           |
| **Per-skill CLAUDE.md**    | A skill large enough to mix "what to do when invoked" with "what to know before editing" gets its own CLAUDE.md sibling to SKILL.md              | [macro-keyboard](./plugins/macro-keyboard/CLAUDE.md) (first adopter)                                                                             |
| **Plugin path resolution** | A skill resolves its own scripts via `"$(cc-plugin-root <plugin>)/…"` — rule above, [spoke](./plugins/itp-hooks/docs/skill-plugin-root-guard.md) | [notes-commander draft-park](./plugins/notes-commander/skills/draft-park/SKILL.md), [pushover-commander](./plugins/pushover-commander/CLAUDE.md) |

> These are **conventions to adopt, not code to extract** — per-plugin isolation (own `package.json`/`tsconfig.json`, own installer) is intentional. Only `diff`-proven byte-identical logic is real duplication.

## Development Toolchain

**Bun-first**: JavaScript global packages are installed with `bun add -g`.

```bash
bun add -g prettier          # Install
bun update -g                # Upgrade all
bun pm ls -g                 # List
```

**Toolchain pins auto-bump to latest, unattended.** `com.terryli.proto-toolchain-autoupdate` runs at 07:23, 13:23 and 19:23 local and rewrites `.prototools` here — and in every repo under `~/eon`, `~/own`, `~/vj` — to the latest published version of each pinned tool, committing each change. Nothing gates it: **no test suite runs against the new versions before the commit lands**, so a red gate the morning after a green night is a toolchain bump until proven otherwise. Check `git log -- .prototools` first; `git revert` the bump to confirm, then hold the pin deliberately if the newer version is genuinely broken. Log: `~/.local/state/proto-autoupdate/autoupdate.log`. It pushes a notification only when something changed or failed.

## Lessons Learned

See [docs/LESSONS.md](./docs/LESSONS.md).
