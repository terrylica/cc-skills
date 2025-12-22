# ADR: Skill Bash Compatibility Enforcement

**Date**: 2025-12-22
**Status**: Implemented
**Related**: [Shell Command Portability](/docs/adr/2025-12-06-shell-command-portability-zsh.md)

## Context

The `asciinema-streaming-backup` skill experienced 4 shell compatibility failures during execution on macOS:

```
(eval):52: bad substitution           # declare -A (associative arrays)
(eval):14: condition expected: \!     # \!= wrong escape
bash: -c: line 13: syntax error       # bash-specific patterns in zsh
```

**Root cause**: Claude Code's Bash tool on macOS runs through zsh by default. Bash-specific syntax fails silently or with cryptic errors.

**Gap identified**: The skill-architecture plugin lacked bash compatibility enforcement during skill creation, allowing authors to write non-portable bash code.

## Decision

Enforce heredoc wrappers for all bash code blocks in skill files:

```bash
/usr/bin/env bash << 'SCRIPT_NAME_EOF'
# All bash-specific syntax works inside heredoc
declare -A MAP
if [[ "$var" =~ pattern ]]; then
  echo "${BASH_REMATCH[1]}"
fi
SCRIPT_NAME_EOF
```

### Prohibited Patterns

| Pattern          | Issue                   | Fix                     |
| ---------------- | ----------------------- | ----------------------- |
| `declare -A`     | Bash 4+ only            | Parallel indexed arrays |
| `grep -oP`       | Perl regex not portable | `grep -oE` + awk        |
| `\!=` in `[[ ]]` | Unnecessary escape      | Use `!=` directly       |
| `$'\n'`          | ANSI-C quoting          | Literal newlines        |

### Enforcement Level

- **Warn only** - Print violations during validation, don't block commits
- **No auto-fix** - Manual fixes ensure authors understand the pattern

## Implementation

1. **New reference**: `plugins/skill-architecture/references/bash-compatibility.md`
2. **Updated validator**: `plugins/skill-architecture/scripts/validate_links.py` with `validate_bash_blocks()`
3. **Updated checklist**: Bash compatibility section in skill-architecture SKILL.md
4. **Updated workflow**: Step 4.1 in creation-workflow.md

## Consequences

### Positive

- All future skills automatically validated for bash compatibility
- Clear documentation and examples for skill authors
- 194 bash blocks fixed across 62 files for macOS compatibility

### Negative

- Additional step in skill creation workflow
- Authors must understand heredoc pattern

### Scope

Fixed 194 bash blocks across 62 files in all plugins, including:

- itp: commands + skills (go, setup, plugin-add, semantic-release, etc.)
- devops-tools: 10+ skills (asciinema, doppler, mlflow, session-recovery)
- dotfiles-tools: chezmoi-workflows + references
- alpha-forge-worktree: worktree-manager skill
- notification-tools: dual-channel-watchexec
- itp-hooks: hooks-development skill
- skill-architecture: references (path-patterns, bash-compatibility)

## References

- [Shell Command Portability ADR](/docs/adr/2025-12-06-shell-command-portability-zsh.md)
- [Plugin Authoring Guide](/docs/plugin-authoring.md)
- [Bash Compatibility Reference](/plugins/skill-architecture/references/bash-compatibility.md)
