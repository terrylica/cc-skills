# Git Account Validator Plugin

Pre-push validation for multi-account GitHub authentication. Prevents pushing to the wrong GitHub account when using SSH with directory-based key selection.

## Problem Solved

When using multiple GitHub accounts with SSH Match directives, several issues can cause pushes to the wrong account:

1. **HTTPS URLs bypass SSH config** - Git credential helper uses a different auth path
2. **SSH ControlMaster caching** - Cached connections use the first account that connected
3. **Human error** - Easy to forget which account applies to which directory

## How It Works

This plugin intercepts `git push` commands via PreToolUse hook and validates:

1. **URL Format**: Blocks HTTPS URLs (must use SSH for multi-account support)
2. **Account Match**: Verifies SSH authentication matches `git config credential.username`

### Before: Without Validation

```
 ⏮️ Before: No Validation

   ╭──────────────────╮
   │   Claude Code    │
   ╰──────────────────╯
     │
     │
     ∨
   ┏━━━━━━━━━━━━━━━━━━┓
   ┃     git push     ┃
   ┗━━━━━━━━━━━━━━━━━━┛
     │
     │ HTTPS bypasses
     │ SSH config
     ∨
   ╔══════════════════╗
   ║  Wrong Account   ║
   ║ (silent failure) ║
   ╚══════════════════╝
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: No Validation"; flow: south; }
[ Claude Code ] { shape: rounded; }
[ git push ] { border: bold; }
[ Wrong Account\n(silent failure) ] { border: double; }

[ Claude Code ] -> [ git push ]
[ git push ] -- HTTPS bypasses\nSSH config --> [ Wrong Account\n(silent failure) ]
```

</details>

### After: With Validation

```
        ⏭️ After: With Validation

                        ╭─────────────────╮
                        │   Claude Code   │
                        ╰─────────────────╯
                          │
                          │
                          ∨
                        ┌─────────────────┐
                        │    git push     │
                        └─────────────────┘
                          │
                          │
                          ∨
                        ┏━━━━━━━━━━━━━━━━━┓
                        ┃ PreToolUse Hook ┃
                        ┗━━━━━━━━━━━━━━━━━┛
                          │
                          │
                          ∨
╔═════════╗  is HTTPS   ┌─────────────────┐
║ BLOCKED ║ <────────── │   HTTPS Check   │
╚═════════╝             └─────────────────┘
  ∧                       │
  │                       │ is SSH
  │                       ∨
  │         mismatch    ┌─────────────────┐
  └──────────────────── │  Account Check  │
                        └─────────────────┘
                          │
                          │ match
                          ∨
                        ╭─────────────────╮
                        │     Allowed     │
                        ╰─────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: With Validation"; flow: south; }
[ Claude Code ] { shape: rounded; }
[ git push ]
[ PreToolUse Hook ] { border: bold; }
[ HTTPS Check ]
[ Account Check ]
[ BLOCKED ] { border: double; }
[ Allowed ] { shape: rounded; }

[ Claude Code ] -> [ git push ]
[ git push ] -> [ PreToolUse Hook ]
[ PreToolUse Hook ] -> [ HTTPS Check ]
[ HTTPS Check ] -- is HTTPS --> [ BLOCKED ]
[ HTTPS Check ] -- is SSH --> [ Account Check ]
[ Account Check ] -- mismatch --> [ BLOCKED ]
[ Account Check ] -- match --> [ Allowed ]
```

</details>

## Requirements

### Git Configuration

Your `~/.gitconfig` must use `includeIf` to set per-directory credentials:

```gitconfig
[includeIf "gitdir:/Users/you/work/"]
    path = ~/.gitconfig-work

[includeIf "gitdir:/Users/you/personal/"]
    path = ~/.gitconfig-personal
```

Each included file must set `credential.username`:

```gitconfig
# ~/.gitconfig-work
[user]
    name = work-account
    email = you@work.com
[credential]
    username = work-account
```

### SSH Configuration

Your `~/.ssh/config` must use Match directives for directory-based key selection:

```sshconfig
# Work account
# NOTE: Use `pwd` not `$PWD` - $PWD may be empty in non-interactive shells
# Match both github.com (port 22) and ssh.github.com (port 443 fallback)
Match host github.com,ssh.github.com exec "pwd | grep -q '/work/'"
    User git
    IdentityFile ~/.ssh/id_work
    IdentitiesOnly yes

# Personal account
Match host github.com,ssh.github.com exec "pwd | grep -q '/personal/'"
    User git
    IdentityFile ~/.ssh/id_personal
    IdentitiesOnly yes

# Disable ControlMaster for all GitHub endpoints (multi-account safety)
Host github.com ssh.github.com
    User git
    ControlMaster no
```

## Installation

The plugin is installed at `~/.claude/plugins/local/git-account-validator/`.

The hook is registered in `~/.claude/settings.json` under `hooks.PreToolUse`.

## Blocking Behavior

### HTTPS URL Detected

```
BLOCKED: HTTPS remote URL detected

Current URL: https://github.com/owner/repo.git

HTTPS URLs bypass SSH multi-account configuration and can push
to the wrong account. Please switch to SSH:

Run: git remote set-url origin git@github.com:owner/repo.git
```

### Account Mismatch Detected

```
BLOCKED: GitHub account mismatch detected

Directory:     /Users/you/personal/project
Expected user: personal-account (from git config)
SSH auth user: work-account

This would push to the WRONG GitHub account!

Possible causes:
  1. SSH ControlMaster cached a connection from different directory
  2. SSH config Match directive not matching current directory
  3. Remote URL using wrong host alias

Solutions:
  1. Close cached SSH connections: ssh -O exit git@github.com
  2. Use explicit host alias: git@github.com-personal-account:owner/repo.git
  3. Check SSH config Match directives in ~/.ssh/config
```

## Technical Details

### Why Bypass ControlMaster?

SSH ControlMaster caches connections by **hostname**, not by identity file. This means:

1. You push from `~/work/` - SSH connects as `work-account`
2. Connection cached for 10 minutes
3. You push from `~/personal/` - SSH reuses cached `work-account` connection!

The validation script uses `ssh -o ControlMaster=no` to bypass the cache and get the true authentication result for the current directory.

### Exit Codes

- `0`: Validation passed, allow push
- `2`: Hard block (cannot be bypassed)

## Files

```
~/.claude/plugins/local/git-account-validator/
  plugin.json                 # Plugin manifest
  README.md                   # This file
  hooks/
    hooks.json                # Hook configuration
    validate-git-push.sh      # Validation script
```

## Troubleshooting

### "No credential.username in git config"

Add `[credential] username = your-github-username` to your directory-specific gitconfig file.

### SSH validation times out

Check that GitHub is reachable: `ssh -T git@github.com`

### ControlMaster keeps using wrong account

Close all cached connections: `ssh -O exit git@github.com`

Or disable ControlMaster for github.com in `~/.ssh/config`:

```sshconfig
Host github.com
    ControlMaster no
```
