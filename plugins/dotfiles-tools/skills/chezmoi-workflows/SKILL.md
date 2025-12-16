---
name: chezmoi-workflows
description: Manages dotfiles with chezmoi via natural language. Use when user mentions dotfiles, config sync, chezmoi, track changes, sync dotfiles, check status, or push changes.
allowed-tools: Read, Edit, Bash
---

# Chezmoi Workflows

Execute common chezmoi operations via natural language prompts without requiring user to memorize commands or use shell aliases.

## Workflow Model

AI-Assisted:

- User edits configuration files normally with any editor
- User prompts Claude Code with natural language
- Claude Code executes all chezmoi/git operations
- No shell complexity or command memorization needed

## Architecture

Two-State System:

- **Source State**: `$(chezmoi source-path)` (git repository, default: `~/.local/share/chezmoi`)
- **Target State**: `~/` (home directory)
- **Remote**: GitHub dotfiles repository (private)

**Note**: Source path is configurable via `sourceDir` in `~/.config/chezmoi/chezmoi.toml`

---

## Quick Start

### Track Changes

**User says**: "I edited [file]. Track the changes."

**Workflow**:

1. Verify drift: `chezmoi status`
2. Show changes: `chezmoi diff [file]`
3. Add to source state: `chezmoi add [file]` (auto-commits)
4. Verify commit: `chezmoi git -- log -1 --oneline`
5. Push to remote: `chezmoi git -- push`

### Sync from Remote

**User says**: "Sync my dotfiles from remote."

**Workflow**:

1. Pull and apply: `chezmoi update`
2. Verify: `chezmoi verify` (exit code 0)

### Push to Remote

**User says**: "Push my dotfile changes to GitHub."

**Workflow**:

1. Check drift: `chezmoi status`
2. Re-add all: `chezmoi re-add`
3. Push: `chezmoi git -- push`

---

## SLO Validation

After operations, validate Service Level Objectives:

1. **Availability**: `chezmoi verify` (exit code 0)
2. **Correctness**: `chezmoi diff` (empty output)
3. **Observability**: `chezmoi managed` (shows all tracked files)
4. **Maintainability**: `git log` (preserves change history)

Report SLO status to user after major operations.

---

## Reference Documentation

For detailed information, see:

- [Prompt Patterns](./references/prompt-patterns.md) - All 6 natural language patterns with examples
- [Configuration](./references/configuration.md) - chezmoi.toml settings and template handling
- [Secret Detection](./references/secret-detection.md) - Fail-fast secret detection and resolution

**Official Documentation**: <https://www.chezmoi.io/reference/>

**Version Compatibility**:

- Chezmoi 2.66.1+ (macOS + Linux)
- Git 2.51.1+
- Platform: macOS (primary), Linux (secondary)
