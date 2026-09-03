# CLAUDE.md

Claude Code skills marketplace: **41 plugins** with skills for ADR-driven development workflows.

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
| Migration (v23)           | [docs/MIGRATING-TO-V23.md](./docs/MIGRATING-TO-V23.md)                                                                       |
| Plugin Lifecycle          | [docs/PLUGIN-LIFECYCLE.md](./docs/PLUGIN-LIFECYCLE.md)                                                                       |
| Troubleshooting           | [docs/troubleshooting/](./docs/troubleshooting/)                                                                             |
| ADRs                      | [docs/adr/](./docs/adr/)                                                                                                     |
| Machine-readable CLI spec | [cli_spec.json](./cli_spec.json) — gen: `scripts/cli_spec.py`; tasks `moon run repo:cli-spec` / `repo:cli-spec-check`        |

### Plugin CLAUDE.md Files (41/41)

Every plugin carries its own CLAUDE.md with Hub+Sibling navigation links. Keep it that way: a new plugin ships one in the same commit that creates it. Access via `plugins/{name}/CLAUDE.md` or browse the full table in [plugins/CLAUDE.md](./plugins/CLAUDE.md).

**Emerging deeper layer**: skill-level CLAUDE.mds (one per skill, sibling to `SKILL.md`) are appearing where a skill is large enough that maintainers need a separate compass from the user-invocable instructions. First adopter: [`plugins/macro-keyboard/skills/{configure-macro-keyboard,emit-fn-key-on-macos,diagnose-hid-keycodes}/CLAUDE.md`](./plugins/macro-keyboard/CLAUDE.md). Add one to your skill if SKILL.md is starting to mix "what to do when invoked" with "what to know before editing".

**Active project (SSoT):** [plugins/claude-tts-companion/CLAUDE.md](./plugins/claude-tts-companion/CLAUDE.md) — project/stack/conventions/architecture for the Swift macOS companion binary. Critical invariants (e.g., _do not replace afplay with AVAudioPlayer_) live there, not here.

### Machine-readable CLI spec (`cli_spec.json`)

Per the cross-repo CLI-first + machine-readable-docs doctrine (`~/.claude/cli-first-machine-readable-docs-CLAUDE.md`; cc-skills is repo 2 of the 4-repo rollout), `scripts/cli_spec.py` emits a repo-root **`cli_spec.json`** (JSON Schema 2020-12) describing every Python `argparse` skill CLI — so an agent learns a skill script's flags without scraping `--help`. AST-based (parses each file, never imports it; excludes vendored/`.build`/`node_modules`), 37 CLIs across `plugins/*/skills/*/scripts/` + `scripts/`. Regenerate: `moon run repo:cli-spec`; drift+completeness gate: `moon run repo:cli-spec-check` (+ `scripts/test_cli_spec.py`, 9 tests).

Key plugin docs: [itp](./plugins/itp/CLAUDE.md) | [itp-hooks](./plugins/itp-hooks/CLAUDE.md) | [gh-tools](./plugins/gh-tools/CLAUDE.md) | [devops-tools](./plugins/devops-tools/CLAUDE.md) | [gmail-commander](./plugins/gmail-commander/CLAUDE.md) | [tts-tg-sync](./plugins/tts-tg-sync/CLAUDE.md) | [calcom-commander](./plugins/calcom-commander/CLAUDE.md) | [claude-tts-companion](./plugins/claude-tts-companion/CLAUDE.md)

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
| Autonomous loop   | `/itp:go feature-name -b`          |

`moon run repo:check` is the local-first gate that must pass before a push — it fans out to `repo:lint`, `repo:test`, `repo:test-hooks`, `repo:cli-spec-check` and `repo:verify-doc-counts`. Task targets are `repo:<name>` with a hyphen. `.prototools` is the only toolchain manifest here and jdx/mise is neither installed nor used; the former `.mise.toml` was deleted because its `[tools]` block pinned bun 1.3 against `.prototools`' 1.4.0 — two toolchain files disagreeing about the same tool, which is the exact drift that silently broke every bun-backed hook on 2026-09-03.

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
├── .claude-plugin/marketplace.json  ← Plugin registry (SSoT, 41 plugins)
├── plugins/                         ← 41 marketplace plugins (each has CLAUDE.md)
│   ├── claude-tts-companion/        ← Swift macOS binary (active project)
│   ├── itp/                         ← Core 4-phase workflow
│   ├── itp-hooks/                   ← Workflow enforcement + code correctness
│   ├── gemini-deep-research/        ← Gemini Deep Research browser automation
│   ├── gmail-commander/             ← Gmail bot + CLI (1Password OAuth)
│   ├── macro-keyboard/              ← Karabiner remap for cheap 3-key pads (skill-level CLAUDE.mds)
│   └── ...                          ← the rest (full table: plugins/CLAUDE.md)
├── docs/
│   ├── adr/                         ← Architecture Decision Records
│   ├── design/                      ← Implementation specs (33 of 59 ADRs have one)
│   ├── HOOKS.md                     ← Hook development patterns
│   ├── RELEASE.md                   ← Release workflow
│   ├── PLUGIN-LIFECYCLE.md          ← Plugin internals
│   └── LESSONS.md                   ← Lessons learned
└── tasks/                     ← Release automation (5 phases + postflight)
```

## Key Files

| File                                       | Purpose                                                                |
| ------------------------------------------ | ---------------------------------------------------------------------- |
| `.claude-plugin/marketplace.json`          | Plugin registry (SSoT)                                                 |
| `release.config.cjs`                       | semantic-release config (body-preserving release notes)                |
| `scripts/validate-plugins.mjs`             | Plugin validation                                                      |
| `scripts/cc-plugin-root`                   | Resolve a plugin's live install path (see below)                       |
| `scripts/commit-message-exposure-guard.ts` | Commit-msg exposure guard (blocks credentials, reminds on identifiers) |
| `scripts/sync-hooks-to-settings.sh`        | Hook synchronization                                                   |
| `scripts/sync-commands-to-settings.sh`     | Command synchronization                                                |

## Skills resolve plugin paths with `cc-plugin-root`, never `$CLAUDE_PLUGIN_ROOT`

`CLAUDE_PLUGIN_ROOT` is **not** a shell variable. Claude Code substitutes the exact literal
`${CLAUDE_PLUGIN_ROOT}` inside plugin _manifests_ (`hooks/hooks.json`, `.mcp.json`, `.lsp.json`) and
injects it into hook/MCP _subprocess_ environments — it never reaches the Bash tool, and a SKILL.md
body is served to the model verbatim. A skill that references it gets an empty string.

```bash
SCRIPT="$(cc-plugin-root <plugin-name>)/skills/<skill>/run.sh"   # in a SKILL.md
"command": "bun ${CLAUDE_PLUGIN_ROOT}/hooks/handler.ts"           # in hooks.json — braced, correct
```

`scripts/cc-plugin-root` reads `~/.claude/plugins/installed_plugins.json`, so it returns the version
Claude Code actually loaded; `/itp:setup` links it into `~/.local/bin/`. Never glob the version cache
— it retains orphaned versions. Enforced by **skill-plugin-root-guard**; escape `SKILL-PLUGIN-ROOT-OK`.

→ [spoke](./plugins/itp-hooks/docs/skill-plugin-root-guard.md)

## Link Conventions

| Context        | Format    | Example                          |
| -------------- | --------- | -------------------------------- |
| Skill-internal | Relative  | `[Guide](./references/guide.md)` |
| Repo docs      | Repo-root | `[ADR](/docs/adr/file.md)`       |
| External       | Full URL  | `[Docs](https://example.com)`    |

## Common Plugin Patterns (reuse registry)

Recurring architectural patterns across the 41 plugins. This is a **pointer registry** for new-plugin authors — the exemplars are the SSoT, not this table.

Historical context, **not** current guidance: [docs/deduplication-analysis.md](./docs/deduplication-analysis.md) is a dated 2026-03-02 audit of a 23-plugin repo that argues the opposite of the rule below — it recommends extracting shared patterns into common modules. It was cited here as a "deeper dive", which read as endorsement. Measured 2026-09-02 and recorded so nobody re-litigates it: `md5` across all 125 files in the 14 per-plugin `lib/` and `_lib/` directories found **zero** byte-identical pairs. There is no code duplication to extract; the similarity is conventional, not literal.

| Pattern                    | What it is                                                                                                                                       | Exemplars to copy                                                                                                                                              |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **setup + health skills**  | Every service-backed plugin ships a `setup` (install/verify deps) and a `health` (subsystem diagnostic) skill                                    | [calcom-commander](./plugins/calcom-commander/CLAUDE.md), [gmail-commander](./plugins/gmail-commander/CLAUDE.md), [kokoro-tts](./plugins/kokoro-tts/CLAUDE.md) |
| **Credential resolution**  | SCS ladder first (self-custody `vault`/Keychain); 1Password only for company-shared, never client-confidential                                   | [gmail-commander](./plugins/gmail-commander/CLAUDE.md)                                                                                                         |
| **Per-skill CLAUDE.md**    | A skill large enough to mix "what to do when invoked" with "what to know before editing" gets its own CLAUDE.md sibling to SKILL.md              | [macro-keyboard](./plugins/macro-keyboard/CLAUDE.md) (first adopter)                                                                                           |
| **Plugin path resolution** | A skill resolves its own scripts via `"$(cc-plugin-root <plugin>)/…"` — rule above, [spoke](./plugins/itp-hooks/docs/skill-plugin-root-guard.md) | [notes-commander draft-park](./plugins/notes-commander/skills/draft-park/SKILL.md), [pushover-commander](./plugins/pushover-commander/CLAUDE.md)               |

> These are **conventions to adopt, not code to extract** — per-plugin isolation (own `package.json`/`tsconfig.json`, own installer) is intentional and validated (graph audit rejected "dedupe the boilerplate" as a false positive). Only `diff`-proven byte-identical logic is real duplication.

## Development Toolchain

**Bun-First Policy** (2025-01-12): JavaScript global packages installed via `bun add -g`.

```bash
bun add -g prettier          # Install
bun update -g                # Upgrade all
bun pm ls -g                 # List
```

**Toolchain pins auto-bump to latest, unattended.** `com.terryli.proto-toolchain-autoupdate` runs at 07:23, 13:23 and 19:23 local and rewrites `.prototools` here — and in every repo under `~/eon`, `~/own`, `~/vj` — to the latest published version of each pinned tool, committing each change. Nothing gates it: **no test suite runs against the new versions before the commit lands**, so a red gate the morning after a green night is a toolchain bump until proven otherwise. Check `git log -- .prototools` first; `git revert` the bump to confirm, then hold the pin deliberately if the newer version is genuinely broken. Log: `~/.local/state/proto-autoupdate/autoupdate.log`. It pushes a notification only when something changed or failed.

Two things this replaced, both worth remembering. An earlier version of this line advertised a `com.terryli.mise_autoupgrade` job running every 2 hours that **did not exist** — no `launchctl` entry, no plist, and mise is not installed at all — so it promised self-maintenance the repo never had. And the obvious implementation of the replacement is a trap: `proto outdated --update --latest` reports tools as outdated, exits 0, and **writes nothing** (measured on 0.61.2, with and without `--yes`, with and without `-c local`). The routine drives `proto pin <tool> <version>` explicitly instead, because that one actually writes.

## Lessons Learned

See [docs/LESSONS.md](./docs/LESSONS.md).

## Active Project

**[claude-tts-companion](./plugins/claude-tts-companion/CLAUDE.md)** — the Swift macOS companion binary (Telegram bot + Kokoro TTS + subtitle overlay) has its own CLAUDE.md as the SSoT. Project description, constraints, stack, conventions, architecture, and critical invariants live there. **Do not duplicate them here** — a second copy drifts out of sync with the SSoT; the model path and the audio-playback description are the fields that rot first.

Quick hand-off: read `plugins/claude-tts-companion/CLAUDE.md` when the user mentions TTS, karaoke subtitles, Telegram bot, session notifications, `tts_kokoro.sh`, or anything under `plugins/claude-tts-companion/`.
