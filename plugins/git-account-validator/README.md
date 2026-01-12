# Git Account Validator Plugin

Multi-account GitHub authentication management for Claude Code.

**Status**: Hooks disabled (2026-01-12) — mise `[env]` now handles authentication pre-configuration.

## Current Architecture

This plugin's runtime validation hooks are **disabled**. Authentication is handled by:

1. **mise `[env]`** — Sets `GH_TOKEN`, `GITHUB_TOKEN`, `GH_CONFIG_DIR` per-directory
2. **Directory-based `.mise.toml`** — Automatic env var loading on directory entry
3. **Token files** — Stored in `~/.claude/.secrets/` (chmod 600)

```
    ✓ Current: Pre-configured Authentication

  ╔════════════════════════════════════════════╗
  ║   ~/.claude/.mise.toml                     ║
  ║   GH_TOKEN = terrylica's token             ║
  ╚════════════════════════════════════════════╝
                      │
                      │ sets env on dir entry
                      ∨
┌────────────┐  ┌────────────┐  ┌────────────┐
│    SSH     │  │ Git Config │  │   gh CLI   │
│ (terrylica)│  │ (terrylica)│  │ (terrylica)│  ← ALL ALIGNED
└────────────┘  └────────────┘  └────────────┘
                      │
                      ∨
              No runtime validation needed
              Authentication pre-configured
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "✓ Current: Pre-configured Authentication"; flow: south; }
[ ~/.claude/.mise.toml\nGH_TOKEN = terrylica's token ] { border: double; }
[ SSH\n(terrylica) ]
[ Git Config\n(terrylica) ]
[ gh CLI\n(terrylica) ]
[ No runtime validation needed\nAuthentication pre-configured ]
[ ~/.claude/.mise.toml\nGH_TOKEN = terrylica's token ] -- sets env on dir entry --> [ gh CLI\n(terrylica) ]
[ SSH\n(terrylica) ] -> [ No runtime validation needed\nAuthentication pre-configured ]
[ Git Config\n(terrylica) ] -> [ No runtime validation needed\nAuthentication pre-configured ]
[ gh CLI\n(terrylica) ] -> [ No runtime validation needed\nAuthentication pre-configured ]
```

</details>

## Why Hooks Were Disabled

The original hooks (`validate-gh-isolation.sh`, `validate-git-push.sh`) called `gh api user` on every Bash command containing "gh" or "git push". During rapid operations (e.g., disabling 36 workflows across 17 forks), this spawned hundreds of `gh` processes that caused system overload:

- Load average exceeded 130
- Fork failures: "resource temporarily unavailable"
- Required forced reboot to recover

**Root cause**: PreToolUse hooks that spawn network-calling processes don't scale with rapid tool invocations.

**Solution**: Pre-configure authentication via mise `[env]` instead of runtime validation.

## Setup Guide

### 1. Create Token Files

```bash
mkdir -p ~/.claude/.secrets
chmod 700 ~/.claude/.secrets

# For each account
gh auth login --hostname github.com  # Select account
gh auth token > ~/.claude/.secrets/gh-token-ACCOUNT
chmod 600 ~/.claude/.secrets/gh-token-*
```

### 2. Configure Per-Directory mise

```toml
# ~/.claude/.mise.toml
[env]
GH_TOKEN = "{{ read_file(path=config_root ~ '/.secrets/gh-token-terrylica') | trim }}"
GITHUB_TOKEN = "{{ read_file(path=config_root ~ '/.secrets/gh-token-terrylica') | trim }}"
GH_ACCOUNT = "terrylica"  # Human reference
```

```toml
# ~/eon/.mise.toml
[env]
GH_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/gh-token-terrylica') | trim }}"
GITHUB_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/gh-token-terrylica') | trim }}"
GH_ACCOUNT = "terrylica"
```

### 3. Shell Configuration

```bash
# ~/.zshenv - Shims PATH only (lightweight, no subprocess spawn)
export PATH="/Users/terryli/.local/share/mise/shims:$PATH"

# ~/.zshrc - Full activation for interactive shells
if command -v mise &> /dev/null; then
  eval "$(mise activate zsh)"
fi
```

**Critical**: Do NOT put `mise activate` in `.zshenv` — it spawns processes on every shell invocation, causing fork storms in rapid operations.

## Directory-Account Mapping

| Directory      | GitHub Account | Token File           |
| -------------- | -------------- | -------------------- |
| `~/.claude/`   | terrylica      | `gh-token-terrylica` |
| `~/eon/`       | terrylica      | `gh-token-terrylica` |
| `~/own/`       | account-2      | `gh-token-account-2` |
| `~/scripts/`   | account-2      | `gh-token-account-2` |
| `~/account-3/` | account-3      | `gh-token-account-3` |

## Verification

```bash
# Check mise sets correct token per directory
cd ~/.claude && echo $GH_ACCOUNT
cd ~/eon && echo $GH_ACCOUNT

# Verify gh CLI uses correct account
cd ~/.claude && gh api user --jq '.login'
cd ~/eon && gh api user --jq '.login'
```

## Legacy Hook Scripts (Reference Only)

The following scripts remain in `hooks/` for reference but are not executed:

| Script                     | Original Purpose                     |
| -------------------------- | ------------------------------------ |
| `validate-gh-isolation.sh` | Validated GH_CONFIG_DIR matches dir  |
| `validate-git-push.sh`     | Blocked HTTPS URLs, verified account |

These scripts called `gh api user` which was the root cause of process storms.

## Related Documentation

- [GitHub Multi-Account Authentication ADR](https://github.com/terrylica/claude-config/blob/main/docs/adr/2025-12-17-github-multi-account-authentication.md)
- [mise env centralized config ADR](/docs/adr/2025-12-08-mise-env-centralized-config.md)
- [Secrets Reference](/local/secrets-reference.md)

## Files

```
plugins/git-account-validator/
  plugin.json               # Plugin manifest
  README.md                 # This file
  hooks/
    hooks.json              # Hook config (empty - disabled)
    validate-gh-isolation.sh  # Legacy (not executed)
    validate-git-push.sh      # Legacy (not executed)
```
