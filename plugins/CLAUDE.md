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
├── README.md             # Plugin documentation (user-facing)
├── CLAUDE.md             # Per-plugin SSoT for maintainers — invariants, conventions, recent changes
├── skills/               # Skill definitions
│   └── my-skill/
│       ├── SKILL.md      # User-invocable skill content (loaded when skill fires)
│       ├── CLAUDE.md     # (Optional) per-skill SSoT for maintainers — file table, edit policy,
│       │                 #   critical invariants, recent-change log. Add when SKILL.md starts
│       │                 #   mixing "what to do when invoked" with "what to know before editing".
│       │                 #   First adopter: macro-keyboard's 3 skills.
│       └── references/   # Supporting docs (loaded on-demand by SKILL.md)
├── hooks/                # Hook scripts + hooks.json
└── scripts/              # Installation/management
```

**Why both README.md and CLAUDE.md at the plugin level**: README.md is for end-users browsing GitHub; CLAUDE.md is for future Claude sessions (and maintainers) who need to know the load-bearing invariants, recent design decisions, and "don't touch this" rules that don't belong in marketing copy. The user once put it: "the nested CLAUDE.md is even more important than the README file."

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

## All Plugins (34)

Each plugin's CLAUDE.md is its own SSoT for purpose, stack, and conventions. Listed alphabetically by directory name; follow the link for details. To verify this list matches reality: `comm -3 <(grep -oE '\[([a-z0-9-]+)\]\(\./[a-z0-9-]+/CLAUDE\.md\)' plugins/CLAUDE.md | sed -E 's/\[([a-z0-9-]+)\].*/\1/' | sort) <(ls -1 plugins/ | grep -v -e node_modules -e CLAUDE.md | sort)` (empty output = aligned).

- [agent-reach](./agent-reach/CLAUDE.md)
- [asciinema-tools](./asciinema-tools/CLAUDE.md)
- [autonomous-loop](./autonomous-loop/CLAUDE.md)
- [calcom-commander](./calcom-commander/CLAUDE.md)
- [chronicle-share](./chronicle-share/CLAUDE.md)
- [claude-tts-companion](./claude-tts-companion/CLAUDE.md)
- [cli-anything](./cli-anything/CLAUDE.md)
- [crucible](./crucible/CLAUDE.md)
- [devops-tools](./devops-tools/CLAUDE.md)
- [doc-tools](./doc-tools/CLAUDE.md)
- [dotfiles-tools](./dotfiles-tools/CLAUDE.md)
- [floating-clock](./floating-clock/CLAUDE.md)
- [gemini-deep-research](./gemini-deep-research/CLAUDE.md)
- [gh-tools](./gh-tools/CLAUDE.md)
- [git-town-workflow](./git-town-workflow/CLAUDE.md)
- [gitnexus-tools](./gitnexus-tools/CLAUDE.md)
- [gmail-commander](./gmail-commander/CLAUDE.md)
- [itp](./itp/CLAUDE.md)
- [itp-hooks](./itp-hooks/CLAUDE.md)
- [kokoro-tts](./kokoro-tts/CLAUDE.md)
- [link-tools](./link-tools/CLAUDE.md)
- [macro-keyboard](./macro-keyboard/CLAUDE.md) — also has skill-level CLAUDE.mds (first plugin to adopt the deeper layer; see [macro-keyboard/CLAUDE.md](./macro-keyboard/CLAUDE.md#skills) for the per-skill table)
- [media-tools](./media-tools/CLAUDE.md)
- [mise](./mise/CLAUDE.md)
- [mql5](./mql5/CLAUDE.md)
- [plugin-dev](./plugin-dev/CLAUDE.md)
- [productivity-tools](./productivity-tools/CLAUDE.md)
- [quality-tools](./quality-tools/CLAUDE.md)
- [quant-research](./quant-research/CLAUDE.md)
- [rust-tools](./rust-tools/CLAUDE.md)
- [ssh-tunnel-companion](./ssh-tunnel-companion/CLAUDE.md)
- [statusline-tools](./statusline-tools/CLAUDE.md)
- [tlg](./tlg/CLAUDE.md)
- [tts-tg-sync](./tts-tg-sync/CLAUDE.md)

## Toolchain

**Bun-first** for JavaScript globals. See [Root CLAUDE.md](../CLAUDE.md#development-toolchain).

## Related Documentation

- [Plugin Authoring Guide](/docs/plugin-authoring.md)
- [ITP Plugin CLAUDE.md](/plugins/itp/CLAUDE.md)
- [Marketplace Installation Troubleshooting](/docs/troubleshooting/marketplace-installation.md)
