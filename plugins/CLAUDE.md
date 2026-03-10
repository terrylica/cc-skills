# Plugin Development Guide

Context for developing plugins in the cc-skills marketplace.

**Hub**: [Root CLAUDE.md](../CLAUDE.md) | **Sibling**: [docs/CLAUDE.md](../docs/CLAUDE.md)

## Plugin Discovery (Critical)

**SSoT**: `.claude-plugin/marketplace.json`

Creating a plugin directory without registering it results in "Plugin not found" error.

**Prevention checklist**:

- [ ] Plugin dir exists in `plugins/`
- [ ] Entry added to `.claude-plugin/marketplace.json`
- [ ] `bun scripts/validate-plugins.mjs` passes
- [ ] Pre-commit hook validates

**Detailed Reference**: [Validation Reference](/plugins/plugin-dev/skills/skill-architecture/references/validation-reference.md)

## Creating Plugins

```bash
# Recommended: Auto-registers in marketplace.json
/plugin-dev:create my-plugin

# Manual: Must add marketplace.json entry yourself
mkdir -p plugins/my-plugin/{skills,hooks,commands,scripts}
```

## Plugin Structure

```
plugins/my-plugin/
├── plugin.json           # Plugin manifest (optional)
├── README.md             # Plugin documentation
├── skills/               # Skill definitions
│   └── my-skill/
│       ├── SKILL.md      # Main skill content
│       └── references/   # Supporting docs
├── hooks/                # Hook scripts + hooks.json
└── scripts/              # Installation/management
```

## Link Conventions

| Link Target          | Format                  | Example                          |
| -------------------- | ----------------------- | -------------------------------- |
| Skill-internal files | Relative (`./`, `../`)  | `[Guide](./references/guide.md)` |
| Repo docs (ADRs)     | Repo-root (`/docs/...`) | `[ADR](/docs/adr/file.md)`       |
| External resources   | Full URL                | `[Docs](https://example.com)`    |

**Why**: Skill files are installed to `~/.claude/skills/`. Relative paths work there; absolute paths don't.

## Shell Compatibility

Claude Code's Bash tool may run through zsh on macOS. Wrap bash-specific syntax:

```bash
# Multi-line bash scripts
/usr/bin/env bash << 'SCRIPT_EOF'
if [[ -f "$FILE" ]]; then
    echo "Found"
fi
SCRIPT_EOF

# Single-line commands
/usr/bin/env bash -c 'VAR=$(command) && echo $VAR'
```

**Reference**: [Shell Portability ADR](/docs/adr/2025-12-06-shell-command-portability-zsh.md)

## Validation

Run before committing:

```bash
bun scripts/validate-plugins.mjs           # Validate only
bun scripts/validate-plugins.mjs --fix     # Show fix instructions
bun scripts/validate-plugins.mjs --strict  # Fail on warnings
```

## Hooks in Plugins

If your plugin includes hooks, see [Hooks Development Guide](/docs/HOOKS.md).

## All Plugins (25)

| Plugin                 | Purpose                                                                                                                          |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `asciinema-tools`      | Terminal recording automation: asciinema capture, launchd daemon, cast conversion ([CLAUDE.md](./asciinema-tools/CLAUDE.md))     |
| `calcom-commander`     | Cal.com + Telegram bot lifecycle ([CLAUDE.md](./calcom-commander/CLAUDE.md))                                                     |
| `devops-tools`         | DevOps automation: ClickHouse, Doppler, MLflow, Cloudflare, pueue, worktree mgmt ([CLAUDE.md](./devops-tools/CLAUDE.md))         |
| `doc-tools`            | Documentation: ASCII diagrams, markdown standards, LaTeX build, Pandoc PDF ([CLAUDE.md](./doc-tools/CLAUDE.md))                  |
| `dotfiles-tools`       | Chezmoi dotfile management via natural language workflows ([CLAUDE.md](./dotfiles-tools/CLAUDE.md))                              |
| `gemini-deep-research` | Gemini Deep Research via browser automation: Playwright CDP, 40k+ char reports ([CLAUDE.md](./gemini-deep-research/CLAUDE.md))   |
| `gh-tools`             | GitHub workflow automation: GFM link validation, WebFetch enforcement ([CLAUDE.md](./gh-tools/CLAUDE.md))                        |
| `gitnexus-tools`       | GitNexus knowledge graph: explore symbols, blast radius, dead code detection ([CLAUDE.md](./gitnexus-tools/CLAUDE.md))           |
| `git-town-workflow`    | Git-town workflow enforcement for fork-based development ([CLAUDE.md](./git-town-workflow/CLAUDE.md))                            |
| `gmail-commander`      | Gmail + Telegram bot lifecycle, email triage, voice digest ([CLAUDE.md](./gmail-commander/CLAUDE.md))                            |
| `itp`                  | Implement-The-Plan: ADR-driven 4-phase workflow ([CLAUDE.md](./itp/CLAUDE.md))                                                   |
| `itp-hooks`            | ITP workflow enforcement: Ruff linting, ADR/Spec sync ([CLAUDE.md](./itp-hooks/CLAUDE.md))                                       |
| `kokoro-tts`           | Local Kokoro TTS engine: MLX-Audio install, HTTP server, voice synthesis, diagnostics ([CLAUDE.md](./kokoro-tts/CLAUDE.md))      |
| `link-tools`           | Link validation: portability checks, lychee broken link detection, path linting ([CLAUDE.md](./link-tools/CLAUDE.md))            |
| `mise`                 | User-global mise workflow commands: release pipeline, task discovery ([CLAUDE.md](./mise/CLAUDE.md))                             |
| `mql5`                 | MQL5 development: indicator patterns, article extraction, Python workspace ([CLAUDE.md](./mql5/CLAUDE.md))                       |
| `plugin-dev`           | Plugin and skill development: structure validation, skill architecture meta-skill ([CLAUDE.md](./plugin-dev/CLAUDE.md))          |
| `productivity-tools`   | Productivity: Notion, iMessage, Google Drive, iTerm2, calendar, slash commands ([CLAUDE.md](./productivity-tools/CLAUDE.md))     |
| `quality-tools`        | Code quality: clone detection, E2E validation, performance profiling, pre-ship gates ([CLAUDE.md](./quality-tools/CLAUDE.md))    |
| `quant-research`       | Quantitative research: range bar SOTA evaluation, Sharpe ratios, ML prediction quality ([CLAUDE.md](./quant-research/CLAUDE.md)) |
| `ru`                   | Autonomous loop mode for any project ([CLAUDE.md](./ru/CLAUDE.md))                                                               |
| `rust-tools`           | SOTA Rust tooling: refactoring, profiling, benchmarking, testing, SIMD, dependency audit ([CLAUDE.md](./rust-tools/CLAUDE.md))   |
| `statusline-tools`     | Custom status line with git status indicators ([CLAUDE.md](./statusline-tools/CLAUDE.md))                                        |
| `tts-telegram-sync`    | TTS and Telegram bot lifecycle: Kokoro engine, voice audition ([CLAUDE.md](./tts-telegram-sync/CLAUDE.md))                       |

## Toolchain

**Bun-first** for JavaScript globals. See [Root CLAUDE.md](../CLAUDE.md#development-toolchain).

## Related Documentation

- [Plugin Authoring Guide](/docs/plugin-authoring.md)
- [ITP Plugin CLAUDE.md](/plugins/itp/CLAUDE.md)
- [Marketplace Installation Troubleshooting](/docs/troubleshooting/marketplace-installation.md)
