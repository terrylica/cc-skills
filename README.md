# cc-skills

Claude Code Skills Marketplace: Meta-skills, foundational tools, and self-revising autonomous-loop primitives for Claude Code.

[![Plugins](https://img.shields.io/badge/plugins-36-green.svg)](#plugins)
[![Version](https://img.shields.io/github/package-json/v/terrylica/cc-skills.svg)](./CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-yellow.svg)](./LICENSE)

## Plugins

> Generated from `.claude-plugin/marketplace.json` (the SSoT). Run `bun scripts/validate-plugins.mjs` to verify the table reflects reality.

| Plugin                                                  | Description                                                                                                                                                                                                                                                          | Category      |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| [agent-reach](./plugins/agent-reach/)                   | Give your AI agent eyes to see the entire internet. Search and read 15+ platforms with auto-update preflight: Twitter/X, Reddit, YouTube, GitHub, Bilibili, XiaoHongShu, Douyin, Weibo, WeChat, Xiaoyuzhou Podcast, LinkedIn, V2EX, RSS, Exa web search.             | productivity  |
| [asciinema-tools](./plugins/asciinema-tools/)           | Terminal recording automation: asciinema capture, launchd daemon for background chunking, Keychain PAT storage, Pushover notifications, cast conversion, and semantic analysis                                                                                       | utilities     |
| [autoloop](./plugins/autoloop/)                         | Self-revising LOOP_CONTRACT.md pattern for long-horizon autonomous work. Dynamic pacing via ScheduleWakeup + Monitor fallback. Commands: /autoloop:start, /autoloop:status, /autoloop:stop                                                                           | automation    |
| [calcom-commander](./plugins/calcom-commander/)         | Cal.com + Telegram bot lifecycle - booking management, interactive commands, scheduled sync, Agent SDK routing, 1Password API key                                                                                                                                    | productivity  |
| [chronicle-share](./plugins/chronicle-share/)           | Producer-side session chronicle sharing pipeline: bundle -> sanitize -> Cloudflare R2 -> presigned URL (skeleton, not yet functional)                                                                                                                                | devops        |
| [clarify-prompts](./plugins/clarify-prompts/)           | Stop-hook nudge that asks Claude to invoke AskUserQuestion (in plain non-technical terms) when the just-finished turn left ambiguity unresolved. Self-suppresses for autoloop sessions, subagents, and turns that already asked.                                     | automation    |
| [claude-tts-companion](./plugins/claude-tts-companion/) | Real-time karaoke subtitles synced with TTS playback — unified macOS accessory app replacing telegram-bot + kokoro-tts-server + subtitle prototype                                                                                                                   | productivity  |
| [cli-anything](./plugins/cli-anything/)                 | Reference guide for CLI-Anything: auto-generate production-ready agent-controllable CLI harnesses for any GUI app via 7-phase pipeline. Covers all validated commands, per-app examples (GIMP, Blender, LibreOffice, Inkscape), testing, and HARNESS.md methodology. | development   |
| [crucible](./plugins/crucible/)                         | Self-evolving research methodology: 18 universal principles for LLM-driven investigation, distilled from a 376-turn session with 1 positive + 17 null campaigns.                                                                                                     | ai            |
| [devops-tools](./plugins/devops-tools/)                 | DevOps automation: ClickHouse, Doppler, MLflow, Cloudflare Workers, pueue orchestration, notifications, session recovery, MiniMax consensus analysis                                                                                                                 | devops        |
| [doc-tools](./plugins/doc-tools/)                       | Comprehensive documentation tooling: ASCII diagrams, markdown standards, LaTeX build, Pandoc PDF, glossary management, plotext financial charts                                                                                                                      | documentation |
| [dotfiles-tools](./plugins/dotfiles-tools/)             | Chezmoi dotfile management via natural language workflows                                                                                                                                                                                                            | utilities     |
| [floating-clock](./plugins/floating-clock/)             | macOS floating clock overlay with profile-based aesthetics, controlled via SwiftBar control center                                                                                                                                                                   | utilities     |
| [gemini-deep-research](./plugins/gemini-deep-research/) | Run Gemini Deep Research via browser automation (claude-in-chrome MCP). Submit prompts, monitor progress, retrieve final reports.                                                                                                                                    | research      |
| [gh-tools](./plugins/gh-tools/)                         | GitHub workflow automation with intelligent GFM link validation, fork intelligence, and issue creation tooling                                                                                                                                                       | development   |
| [git-town-workflow](./plugins/git-town-workflow/)       | Prescriptive git-town workflow enforcement for fork-based development                                                                                                                                                                                                | devops        |
| [gitnexus-tools](./plugins/gitnexus-tools/)             | GitNexus CLI integration: knowledge-graph reindex, blast-radius impact analysis, dead-code detection, structured exploration                                                                                                                                         | development   |
| [gmail-commander](./plugins/gmail-commander/)           | Gmail bot + CLI lifecycle: 1Password OAuth, scheduled email triage via Agent SDK Haiku, interactive Telegram bot                                                                                                                                                     | productivity  |
| [itp](./plugins/itp/)                                   | Implement-The-Plan workflow: ADR-driven 4-phase development with preflight, implementation, and release                                                                                                                                                              | productivity  |
| [itp-hooks](./plugins/itp-hooks/)                       | ITP workflow enforcement + code correctness: PreToolUse / PostToolUse / Stop hooks for SSoT principles, file-size guard, type checks, ASCII art blocking, ty/oxlint/biome lint, autoloop stall guard                                                                 | enforcement   |
| [kokoro-tts](./plugins/kokoro-tts/)                     | Kokoro TTS engine: install, server lifecycle, synthesis, health checks, and real-time audio architecture for macOS Apple Silicon                                                                                                                                     | productivity  |
| [link-tools](./plugins/link-tools/)                     | Link validation: portability checks, broken link detection, path policy linting                                                                                                                                                                                      | quality       |
| [macro-keyboard](./plugins/macro-keyboard/)             | Karabiner remap for cheap 3-key USB-C/Bluetooth macro pads + HID diagnostic + Fn-key emit utilities                                                                                                                                                                  | utilities     |
| [media-tools](./plugins/media-tools/)                   | Download YouTube audio and push to BookPlayer for offline listening                                                                                                                                                                                                  | productivity  |
| [minimax](./plugins/minimax/)                           | MiniMax M-series production wiring patterns — API client templates verified across multi-iteration campaigns                                                                                                                                                         | ai            |
| [mise](./plugins/mise/)                                 | User-global mise workflow commands: env status, list-repo-tasks, run-full-release, SR&ED commit                                                                                                                                                                      | productivity  |
| [mql5](./plugins/mql5/)                                 | MQL5 development: indicator patterns, mql5.com article extraction, Python workspace, MT5 tick collection ops, FXView Parquet consumer                                                                                                                                | trading       |
| [plugin-dev](./plugins/plugin-dev/)                     | Plugin development: skill architecture, plugin validation, silent failure auditing, TodoWrite templates                                                                                                                                                              | development   |
| [productivity-tools](./plugins/productivity-tools/)     | Slash command generation, Notion (SDK + CLI), iMessage queries, iTerm2 layouts, calendar event manager, Google Drive access                                                                                                                                          | productivity  |
| [quality-tools](./plugins/quality-tools/)               | Code quality and validation: clone detection, dead-code, multi-agent E2E + performance profiling, ClickHouse architect, refactoring guide                                                                                                                            | quality       |
| [quant-research](./plugins/quant-research/)             | Quantitative research: SOTA range bar metrics, Sharpe ratios, ML prediction quality, WFO epochs                                                                                                                                                                      | trading       |
| [rust-tools](./plugins/rust-tools/)                     | Rust dependency audit + SOTA Rust arsenal reference                                                                                                                                                                                                                  | development   |
| [ssh-tunnel-companion](./plugins/ssh-tunnel-companion/) | macOS launchd companion for SSH tunnels (Tailscale + CF Access) — see plugin's CLAUDE.md for the SSoT on tunnel architecture                                                                                                                                         | devops        |
| [statusline-tools](./plugins/statusline-tools/)         | Custom Claude Code status line with git status indicators + global ignore patterns + session-info reporter                                                                                                                                                           | utilities     |
| [tlg](./plugins/tlg/)                                   | Telegram operations toolkit: messages, channels, dialogs, members, media, search, dump, drafting, cleanup                                                                                                                                                            | productivity  |
| [tts-tg-sync](./plugins/tts-tg-sync/)                   | TTS + Telegram sync stack: bot process control, voice quality audition, settings tuning, full-stack bootstrap, diagnostic resolver                                                                                                                                   | productivity  |

## Installation

### Prerequisites

| Requirement | Check              | Install                                                                                 |
| ----------- | ------------------ | --------------------------------------------------------------------------------------- |
| Claude Code | `claude --version` | [Getting Started Guide](https://docs.anthropic.com/en/docs/claude-code/getting-started) |

### Quick Start (Recommended)

Run these commands in your **terminal** (not inside Claude Code):

```bash
# 1. Add the cc-skills marketplace
claude plugin marketplace add terrylica/cc-skills

# 2. Install all 36 plugins (one-liner, alphabetically ordered to match marketplace.json)
for p in agent-reach asciinema-tools autoloop calcom-commander chronicle-share clarify-prompts claude-tts-companion cli-anything crucible devops-tools doc-tools dotfiles-tools floating-clock gemini-deep-research gh-tools git-town-workflow gitnexus-tools gmail-commander itp itp-hooks kokoro-tts link-tools macro-keyboard media-tools minimax mise mql5 plugin-dev productivity-tools quality-tools quant-research rust-tools ssh-tunnel-companion statusline-tools tlg tts-tg-sync; do
  claude plugin install "$p@cc-skills"
done

# 3. Sync hooks to settings.json (requires cloning the repo)
git clone https://github.com/terrylica/cc-skills.git /tmp/cc-skills
/tmp/cc-skills/scripts/sync-hooks-to-settings.sh

# 4. Restart Claude Code to activate hooks
claude
```

### Step-by-Step Installation

#### Step 1: Add the Marketplace

```bash
claude plugin marketplace add terrylica/cc-skills
```

This clones the marketplace to `~/.claude/plugins/marketplaces/cc-skills/`.

**Verify installation:**

```bash
claude plugin marketplace list
# Should show: cc-skills - Source: GitHub (terrylica/cc-skills)
```

#### Step 2: Install Individual Plugins

Use the install one-liner above, or pick the plugins you need from the [Plugins table](#plugins). Examples:

```bash
# Workflow + dev essentials
claude plugin install itp@cc-skills
claude plugin install itp-hooks@cc-skills
claude plugin install plugin-dev@cc-skills
claude plugin install gh-tools@cc-skills
claude plugin install link-tools@cc-skills

# Autonomous loop primitives
claude plugin install autoloop@cc-skills
claude plugin install clarify-prompts@cc-skills

# DevOps + quality
claude plugin install devops-tools@cc-skills
claude plugin install quality-tools@cc-skills
claude plugin install doc-tools@cc-skills

# Media / productivity (optional, install on demand)
claude plugin install asciinema-tools@cc-skills
claude plugin install productivity-tools@cc-skills
claude plugin install statusline-tools@cc-skills
```

The full alphabetical list is in `.claude-plugin/marketplace.json` — `jq -r '.plugins[].name' .claude-plugin/marketplace.json` enumerates all 36.

#### Step 3: Sync Hooks

Hooks provide pre/post tool use enforcement and session events. They must be explicitly synced to `~/.claude/settings.json`:

```bash
# Clone the repository (if not already cloned)
git clone https://github.com/terrylica/cc-skills.git ~/cc-skills-temp

# Run the hook sync script
~/cc-skills-temp/scripts/sync-hooks-to-settings.sh
# Output: ✓ Hooks synced: PreToolUse=7, PostToolUse=3, Stop=5
```

#### Step 4: Restart Claude Code

**Hooks require a restart** to take effect:

```bash
# Exit any running Claude Code sessions, then:
claude
```

### Verify Installation

```bash
# Check marketplace is registered
claude plugin marketplace list

# Inside Claude Code, verify commands are available
# Type "/" and look for itp:go, plugin-dev:create, etc.
```

## Updating the Marketplace

When new versions are released:

```bash
# Update the marketplace repository
cd ~/.claude/plugins/marketplaces/cc-skills
git pull

# Reinstall updated plugins (or specific ones)
claude plugin install itp@cc-skills

# Re-sync hooks
./scripts/sync-hooks-to-settings.sh  # From the repo directory
```

## Troubleshooting

### "Source path does not exist" Error

**Cause**: Marketplace repository is out of sync or has stale data.

**Fix**:

```bash
# Update the marketplace
cd ~/.claude/plugins/marketplaces/cc-skills
git pull

# Retry installation
claude plugin install plugin-name@cc-skills
```

### Slash Commands Not Appearing

**Cause**: Plugins installed but commands not discovered.

**Fix**:

1. Verify plugin is installed:

   ```bash
   # Check installed_plugins.json
   cat ~/.claude/plugins/installed_plugins.json | grep "cc-skills"
   ```

2. Restart Claude Code (fresh session required)

3. If still not working, clear cache and reinstall:

   ```bash
   rm -rf ~/.claude/plugins/cache/cc-skills
   claude plugin install plugin-name@cc-skills
   ```

### Hooks Not Working

**Cause**: Hooks not synced to settings.json.

**Fix**:

```bash
# Sync hooks
cd /path/to/cc-skills
./scripts/sync-hooks-to-settings.sh

# Restart Claude Code
```

**Verify hooks are registered:**

```bash
cat ~/.claude/settings.json | jq '.hooks | keys'
# Should show: ["PreToolUse", "PostToolUse", "Stop"]
```

### "Plugin not found" After Adding Marketplace

**Cause**: Known Claude Code issue with SSH clone failures.

**Fix**:

```bash
# Remove and re-add with explicit clone
claude plugin marketplace remove cc-skills
rm -rf ~/.claude/plugins/marketplaces/cc-skills

# Clone manually via HTTPS
git clone https://github.com/terrylica/cc-skills.git ~/.claude/plugins/marketplaces/cc-skills

# Re-add to known_marketplaces.json
# Add this entry to ~/.claude/plugins/known_marketplaces.json:
# "cc-skills": {
#   "source": {"source": "github", "repo": "terrylica/cc-skills"},
#   "installLocation": "$HOME/.claude/plugins/marketplaces/cc-skills",
#   "lastUpdated": "2026-01-13T00:00:00.000Z"
# }
```

### Version Mismatch

**Cause**: Cache has old plugin version.

**Fix**:

```bash
# Check current cached version
ls ~/.claude/plugins/cache/cc-skills/itp/

# Clear specific plugin cache
rm -rf ~/.claude/plugins/cache/cc-skills/itp

# Reinstall
claude plugin install itp@cc-skills
```

## Architecture

### Directory Structure

```
~/.claude/plugins/
├── known_marketplaces.json      # Registered marketplaces
├── installed_plugins.json       # Installed plugins with versions
├── marketplaces/
│   └── cc-skills/               # Cloned marketplace repository
│       ├── .claude-plugin/
│       │   └── marketplace.json # Plugin registry (SSoT)
│       └── plugins/
│           ├── itp/
│           ├── plugin-dev/
│           └── ...
└── cache/
    └── cc-skills/               # Cached plugin copies
        ├── itp/
        │   └── <version>/       # Version-specific cache
        └── ...
```

### Key Files

| File                                        | Purpose                                                |
| ------------------------------------------- | ------------------------------------------------------ |
| `~/.claude/plugins/known_marketplaces.json` | Marketplace registry with source and install locations |
| `~/.claude/plugins/installed_plugins.json`  | Installed plugins with versions and paths              |
| `~/.claude/settings.json`                   | User settings including hooks configuration            |
| `.claude-plugin/marketplace.json`           | Plugin registry for this marketplace (SSoT)            |

### Marketplace Configuration

The `known_marketplaces.json` entry for cc-skills:

```json
{
  "cc-skills": {
    "source": {
      "source": "github",
      "repo": "terrylica/cc-skills"
    },
    "installLocation": "$HOME/.claude/plugins/marketplaces/cc-skills",
    "lastUpdated": "<timestamp>"
  }
}
```

## For Plugin Developers

### Critical Schema Requirements

Based on compatibility with Claude Code's plugin loader:

#### 1. Source Paths (marketplace.json)

**DO NOT** use trailing slashes in `source` paths:

```json
// CORRECT
"source": "./plugins/itp"

// WRONG - causes "Source path does not exist" error
"source": "./plugins/itp/"
```

#### 2. Author Field (plugin.json)

The `author` field **must** be an object, not a string:

```json
// CORRECT
"author": {
  "name": "Your Name",
  "url": "https://github.com/username"
}

// WRONG - causes validation error
"author": "Your Name"
```

#### 3. No Custom Fields (plugin.json)

Only standard fields are allowed. These cause validation errors:

```json
// WRONG - unrecognized keys
"commands_dir": "commands",
"references_dir": "references",
"scripts_dir": "scripts"
```

### Valid plugin.json Example

```json
{
  "name": "my-plugin",
  "version": "<version>",
  "description": "Plugin description (min 10 chars)",
  "keywords": ["keyword1", "keyword2"],
  "author": {
    "name": "Your Name",
    "url": "https://github.com/username"
  }
}
```

### Valid marketplace.json Entry

```json
{
  "name": "my-plugin",
  "description": "Plugin description",
  "version": "<version>",
  "source": "./plugins/my-plugin",
  "category": "development",
  "author": {
    "name": "Your Name",
    "url": "https://github.com/username"
  },
  "keywords": ["keyword1", "keyword2"],
  "strict": false
}
```

### Testing Your Plugin

```bash
# Validate marketplace structure
bun scripts/validate-plugins.mjs

# Check for schema errors
bun scripts/validate-plugins.mjs --fix
```

## Terminology

Understanding the architectural hierarchy:

| Term          | Definition                                                                                    | Location             | Example                      |
| ------------- | --------------------------------------------------------------------------------------------- | -------------------- | ---------------------------- |
| **Plugin**    | Marketplace-installable container with metadata, commands, and optional bundled skills        | `~/.claude/plugins/` | `itp`, `gh-tools`            |
| **Skill**     | Executable agent with SKILL.md frontmatter; can be standalone or bundled within a plugin      | `~/.claude/skills/`  | `graph-easy`, `pypi-doppler` |
| **Command**   | Slash command (`/plugin:command`) defined in `.md` file within plugin's `commands/` directory | Plugin's `commands/` | `/itp:setup`                 |
| **Reference** | Supporting documentation in `references/` directory; not directly executable                  | `references/`        | `error-handling.md`          |

**Hierarchy**:

```
Plugin (Container)
├── commands/           → Slash commands (/plugin:command)
├── skills/             → Bundled skills (copied to ~/.claude/skills/ on install)
│   └── skill-name/
│       ├── SKILL.md    → Skill definition (frontmatter + instructions)
│       ├── scripts/    → Executable helpers
│       └── references/ → Supporting docs
├── hooks/              → Hook definitions (hooks.json)
├── scripts/            → Plugin-level utilities
└── references/         → Plugin-level documentation
```

**Key distinctions**:

- **install** → Acquire packages/tools via package manager (`brew install`, `npm install`)
- **setup** → Verify environment post-installation (`/itp:setup` checks dependencies)
- **init** → Create initial directory structure (one-time scaffolding)
- **configure** → Adjust settings in config files (iterative customization)

## Plugin Dependencies

Some plugins use skills from other plugins. Install dependencies first for full functionality.

| Plugin       | Depends On  | Skills Used                                   |
| ------------ | ----------- | --------------------------------------------- |
| `plugin-dev` | `itp`       | implement-plan-preflight, code-hardcode-audit |
| `doc-tools`  | `itp`       | graph-easy, adr-graph-easy-architect          |
| `itp`        | `doc-tools` | ascii-diagram-validator                       |

**Note:** `doc-tools` and `itp` have a circular dependency (both provide diagram tools). Install both for full functionality.

Run `bun scripts/validate-plugins.mjs --deps` to see the full dependency graph.

## Slash Command Naming Convention

Marketplace plugin commands display with the `plugin:command` format:

| Display Format | Meaning                       |
| -------------- | ----------------------------- |
| `/itp:go`      | Plugin `itp`, command `go`    |
| `/itp:setup`   | Plugin `itp`, command `setup` |

**Why the colon format?**

- **Display**: Claude Code always shows the full `plugin:command` namespace in autocomplete and command lists
- **Invocation**: You may type `/go`, `/setup`, or `/hooks` directly if no naming conflicts exist with other installed plugins
- **Clarity**: The namespace identifies which plugin provides each command

**Important edge case**: When the command name equals the plugin name (e.g., `/foo:foo`), you **must** use the full format. Typing `/foo` alone is interpreted as the plugin prefix, not the command.

## Repository Structure

```text
cc-skills/
├── .claude-plugin/
│   └── marketplace.json          # Plugin registry (36 plugins) — SSoT
├── plugins/                      # 36 marketplace plugins (each with its own CLAUDE.md)
│   ├── autoloop/                 # Self-revising LOOP_CONTRACT pattern (.autoloop/<slug>--<hash>/ layout)
│   ├── itp/                      # ADR-driven 4-phase development workflow
│   ├── itp-hooks/                # Workflow enforcement + code-correctness hooks
│   ├── clarify-prompts/          # Stop-hook nudge for ambiguous turns (autoloop-aware)
│   ├── plugin-dev/               # Plugin / skill architecture meta-tools
│   ├── gh-tools/                 # GitHub workflow + GFM link validation
│   ├── doc-tools/                # ASCII diagrams, markdown standards, LaTeX, Pandoc
│   ├── quality-tools/            # Clone detection, E2E validation, profiling, refactor guide
│   ├── devops-tools/             # ClickHouse, Doppler, MLflow, pueue, session recovery
│   ├── claude-tts-companion/     # Swift macOS karaoke-subtitles companion
│   ├── kokoro-tts/               # Kokoro TTS engine (install / server / synthesis)
│   ├── tts-tg-sync/              # TTS + Telegram sync stack
│   ├── tlg/                      # Telegram operations toolkit
│   ├── ssh-tunnel-companion/     # macOS launchd companion for SSH tunnels
│   ├── floating-clock/           # macOS floating clock overlay
│   ├── macro-keyboard/           # Karabiner remap for 3-key macro pads
│   ├── …                         # 20 more — see Plugins table for the full set
├── scripts/
│   ├── sync-hooks-to-settings.sh    # Hook synchronization (called by release:sync)
│   ├── sync-commands-to-settings.sh # Command synchronization
│   ├── validate-plugins.mjs         # Plugin validation
│   └── marketplace.schema.json      # JSON Schema for marketplace.json
├── .mise/tasks/release/             # Release automation (6 phases — see below)
├── docs/                            # ADRs, design docs, lessons-learned, troubleshooting
├── .autoloop/                       # autoloop campaign storage (gitignored)
│   └── <campaign-slug>--<short-hash>/
│       ├── CONTRACT.md              # Live LOOP_CONTRACT
│       ├── PROVENANCE.md            # Owner+history index
│       └── state/                   # heartbeat.json + revision-log
├── package.json                     # semantic-release
└── README.md
```

## Release Workflow (for maintainers)

This marketplace uses semantic-release with mise task automation:

```bash
# Check release status
mise run release:status

# Full release workflow (preflight → version → sync → verify)
mise run release:full

# Dry run (no changes)
mise run release:dry

# Manual hook sync only
mise run release:hooks

# Sync marketplace to ~/.claude after release
mise run release:sync
```

### Release Phases

`mise run release:full` runs all five phases in sequence (six counting postflight). Each is also independently invokable.

| Phase | Task                 | Description                                                                                      |
| ----- | -------------------- | ------------------------------------------------------------------------------------------------ |
| 1     | `release:preflight`  | Validate clean working dir, GH_TOKEN presence, plugin manifests, releasable conventional commits |
| 1.5   | `release:presync`    | Mirror current main HEAD to ~/.claude marketplace clone so the live env reflects pending changes |
| 2     | `release:version`    | Run semantic-release (version bump + CHANGELOG + git tag + GitHub release)                       |
| 3     | `release:sync`       | Update marketplace repo, sync hooks/commands to settings.json, populate plugin cache             |
| 4     | `release:verify`     | Verify git tag, GitHub release, marketplace, hooks files, runtime artifact consistency           |
| 5     | `release:postflight` | Reset lockfile drift, confirm clean working dir, confirm all commits pushed                      |

Run `mise tasks ls | grep -i release` for the complete list (also includes `release:status`, `release:dry`, `release:hooks`, `release:clean`).

## Available Plugins

### itp

**Implement-The-Plan workflow: ADR-driven 4-phase development.**

Execute approved plans from Claude Code's Plan Mode through a structured workflow:

- **Preflight**: ADR + Design Spec creation with graph-easy diagrams
- **Phase 1**: Implementation with engineering standards
- **Phase 2**: Format & Push to GitHub
- **Phase 3**: Release via the repo's mise release pipeline, optionally Publish (PyPI)

**Commands**: `/itp:go`, `/itp:setup`, `/itp:hooks` (release runs via `/mise:run-full-release`)

**Bundled Skills**: adr-code-traceability, adr-graph-easy-architect, bootstrap-monorepo, code-hardcode-audit, graph-easy, impl-standards, implement-plan-preflight, mise-configuration, mise-tasks, pypi-doppler

### plugin-dev

**Plugin and skill development: structure validation, silent failure auditing, skill architecture meta-skill.**

- **skill-architecture** - Meta-skill for creating skills (YAML frontmatter, TodoWrite templates)
- **plugin-validator** - Validate plugin structure, manifests, and detect silent script failures

**Commands**: `/plugin-dev:create`

### autoloop

**Self-revising LOOP_CONTRACT.md pattern for long-horizon autonomous work.** Replaces the previously-shipped `ru` plugin (removed 2026-04 per [ADR](./docs/adr/2026-04-20-remove-ru-plugin.md)) and renames the post-Ralph "autonomous-loop" plugin to a shorter slug.

Features:

- **Per-campaign storage layout**: contracts live at `<cwd>/.autoloop/<slug>--<short-hash>/CONTRACT.md` with sibling `state/` dir and `PROVENANCE.md` ledger
- **Multi-campaign coexistence** in one cwd via slug+hash directory naming (no collisions when multiple Claude sessions run in the same branch+folder)
- **Auto-migration** on first `/autoloop:start` for any directory containing a legacy `LOOP_CONTRACT.md`
- **schema_version 2 frontmatter** with self-describing provenance: `loop_id`, `campaign_slug`, `created_in_session`, `created_at_cwd`, `created_at_git_branch`, `created_at_git_commit`, mirrored owner state, expected-cadence hint
- **5-step identification decision tree** in every contract so any AI agent (offline or live) can answer "is this mine, reclaimable, or hands-off?" without consulting the registry
- **Atomic ownership**: registry at `~/.claude/loops/registry.json` is the SSoT; flock-serialized writes; PID-reuse defense via `owner_start_time_us`; generation counter for TOCTOU defense
- **Stall-guard hook** in `itp-hooks` (`stop-loop-stall-guard.ts`) detects firings that ended without a valid waker and forces a rewake

**Commands**: `/autoloop:start`, `/autoloop:status`, `/autoloop:stop`, `/autoloop:setup`, `/autoloop:reclaim`, `/autoloop:doctor`

**Plugin doc**: [plugins/autoloop/CLAUDE.md](./plugins/autoloop/CLAUDE.md) — architecture, 6 catastrophic pitfalls, troubleshooting playbook.

### gh-tools

**GitHub workflow automation with intelligent GFM link validation.**

- Detects broken repository-relative links
- Auto-fixes common link patterns
- Integrates with `gh` CLI workflows

### link-tools

**Link validation: portability checks, broken link detection, path policy linting.**

- **link-validator** - Validates relative path usage for cross-installation compatibility
- **link-validation** - Broken link detection with path policy linting (on-demand)

### devops-tools

**Doppler credentials, Firecrawl self-hosted, ML pipelines, MLflow queries, notifications, and session recovery.**

17 bundled skills: clickhouse-cloud-management, clickhouse-pydantic-config, claude-code-proxy-patterns, disk-hygiene, distributed-job-safety, doppler-workflows, doppler-secret-validation, dual-channel-watchexec, firecrawl-research-patterns, ml-data-pipeline-architecture, ml-failfast-validation, mlflow-python, project-directory-migration, pueue-job-orchestration, python-logging-best-practices, session-chronicle, session-recovery

### doc-tools

**Comprehensive documentation: ASCII diagrams, markdown standards, LaTeX build, Pandoc PDF generation.**

Nine bundled skills: ascii-diagram-validator, documentation-standards, glossary-management, latex-build, latex-setup, latex-tables, pandoc-pdf-generation, plotext-financial-chart, terminal-print

### quality-tools

**Code quality and validation tools: clone detection, E2E validation, profiling, schema testing.**

Six bundled skills: clickhouse-architect, code-clone-assistant, multi-agent-e2e-validation, multi-agent-performance-profiling, schema-e2e-validation, symmetric-dogfooding

### itp-hooks

**ITP workflow enforcement via PreToolUse and PostToolUse hooks.**

- Hard block on manual ASCII art
- Ruff Python linting reminders
- Graph-easy skill reminders
- ADR/Design Spec sync reminders

### statusline-tools

**Custom Claude Code status line with git status indicators.**

- Git status indicators (modified, deleted, staged, untracked)
- Remote tracking (ahead/behind commits)

**Commands**: `/statusline-tools:setup`

### Other Plugins

For everything not detailed above, see the [Plugins table](#plugins) and the per-plugin `CLAUDE.md` (the SSoT for purpose, stack, and conventions). The full list is enumerable via:

```bash
jq -r '.plugins[] | "\(.name) — \(.description)"' .claude-plugin/marketplace.json
```

## Known Issues

### Claude Code Plugin Ecosystem Issues

| Issue                                                            | Description                                                     | Workaround                          |
| ---------------------------------------------------------------- | --------------------------------------------------------------- | ----------------------------------- |
| [#14929](https://github.com/anthropics/claude-code/issues/14929) | Commands from directory-based local marketplaces not discovered | Use GitHub-based marketplace source |
| SSH clone failures                                               | Silent failure when adding marketplace via SSH                  | Use HTTPS clone manually            |

### This Marketplace

| Issue                                | Status | Notes                               |
| ------------------------------------ | ------ | ----------------------------------- |
| Circular dependency: doc-tools ↔ itp | Known  | Install both for full functionality |

## Contributing

1. Fork the repository
2. Create a plugin in `plugins/your-plugin/`
3. Add entry to `.claude-plugin/marketplace.json`
4. Ensure `plugin.json` follows the schema (see [For Plugin Developers](#for-plugin-developers))
5. Run `bun scripts/validate-plugins.mjs`
6. Submit a pull request

## License

MIT
