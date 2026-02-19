# Plugin Authoring Guide

Essential guidance for creating cc-skills marketplace plugins.

## Shell Compatibility (Critical)

Claude Code's Bash tool on macOS may run through zsh, causing bash-specific syntax to fail.

### Required Pattern for Skill Command Files

All bash code blocks in `commands/*.md` files MUST use explicit bash invocation:

```bash
# ✅ CORRECT: Heredoc pattern for multi-line scripts
/usr/bin/env bash << 'SCRIPT_NAME'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if [[ -f "$PROJECT_DIR/.claude/config.json" ]]; then
    cat "$PROJECT_DIR/.claude/config.json" | python3 -m json.tool
else
    echo "(not found)"
fi
SCRIPT_NAME
```

```bash
# ✅ CORRECT: Single-line commands
/usr/bin/env bash -c 'GITHUB_TOKEN=$(gh auth token) some-command'
```

```bash
# ❌ WRONG: Direct bash syntax (fails on macOS zsh)
if [[ -f "$FILE" ]]; then
    echo "Found"
fi
```

### Why This Matters

| Syntax                 | Bash | Zsh            | Fix Required |
| ---------------------- | ---- | -------------- | ------------ |
| `[[ ]]`                | ✅   | ❌ parse error | Yes          |
| `if-then-else`         | ✅   | ❌ parse error | Yes          |
| `$(...)` in assignment | ✅   | ❌ parse error | Yes          |
| Simple `echo`, `cat`   | ✅   | ✅             | No           |

### Heredoc Naming Convention

Use descriptive heredoc names matching the command:

- `start.md` → `RU_START_SCRIPT`
- `status.md` → `RU_STATUS_SCRIPT`
- `config.md` → `PLUGIN_CONFIG_SHOW`

### Reference

- [ADR: Shell Command Portability](/docs/adr/2025-12-06-shell-command-portability-zsh.md)
- CLAUDE.md Shell Portability Section (see your local `~/.claude/CLAUDE.md`)
