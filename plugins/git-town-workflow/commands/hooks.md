---
allowed-tools: Read, Write, Edit, Bash(cat:*), Bash(jq:*), Grep, Glob, AskUserQuestion
argument-hint: "[install|uninstall|status]"
description: "Install/uninstall hooks that enforce git-town over raw git commands in Claude Code. Blocks forbidden git commands. TRIGGERS - enforce git-town, install hooks, git-town hooks, prevent raw git."
---

<!-- ⛔⛔⛔ MANDATORY: READ THIS ENTIRE FILE BEFORE ANY ACTION ⛔⛔⛔ -->

# Git-Town Enforcement Hooks — Installation

**This command installs Claude Code hooks that BLOCK forbidden raw git commands.**

## What Gets Blocked

| Forbidden Command      | Reason                     | Replacement       |
| ---------------------- | -------------------------- | ----------------- |
| `git checkout -b`      | Creates untracked branches | `git town hack`   |
| `git pull`             | Bypasses sync workflow     | `git town sync`   |
| `git merge`            | Manual merges break flow   | `git town sync`   |
| `git push origin main` | Direct main push dangerous | `git town sync`   |
| `git branch -d`        | Manual branch deletion     | `git town delete` |
| `git rebase`           | Complex, use git-town      | `git town sync`   |

## What's Allowed

| Allowed Command | Reason                                      |
| --------------- | ------------------------------------------- |
| `git add`       | Staging files (git-town doesn't replace)    |
| `git commit`    | Creating commits (git-town doesn't replace) |
| `git status`    | Viewing status (read-only)                  |
| `git log`       | Viewing history (read-only)                 |
| `git diff`      | Viewing changes (read-only)                 |
| `git stash`     | Stashing changes (utility)                  |
| `git remote`    | Remote management (setup only)              |
| `git config`    | Configuration (setup only)                  |

---

## Hook Definition

The following hook will be added to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/env bash -c 'CMD=\"$CLAUDE_TOOL_INPUT_command\"; case \"$CMD\" in \"git checkout -b\"*|\"git checkout -B\"*) echo \"BLOCKED: Use git town hack instead of git checkout -b\"; exit 1;; \"git pull\"*) echo \"BLOCKED: Use git town sync instead of git pull\"; exit 1;; \"git merge\"*) echo \"BLOCKED: Use git town sync or git town ship instead of git merge\"; exit 1;; \"git push origin main\"*|\"git push origin master\"*) echo \"BLOCKED: Use git town sync instead of pushing to main\"; exit 1;; \"git branch -d\"*|\"git branch -D\"*) echo \"BLOCKED: Use git town delete instead of git branch -d\"; exit 1;; \"git rebase\"*) echo \"BLOCKED: Use git town sync (rebase strategy) instead of git rebase\"; exit 1;; esac'"
          }
        ]
      }
    ]
  }
}
```

---

## Installation

### Step 1: Check Current Settings

```bash
/usr/bin/env bash -c 'cat ~/.claude/settings.json 2>/dev/null || echo "{}"'
```

### Step 2: AskUserQuestion Confirmation

```
AskUserQuestion with questions:
- question: "Install git-town enforcement hooks to block forbidden raw git commands?"
  header: "Install Hooks"
  options:
    - label: "Yes, install hooks (Recommended)"
      description: "Blocks: git checkout -b, git pull, git merge, git push main"
    - label: "No, don't install"
      description: "I want to use raw git commands freely"
    - label: "Show what will be blocked"
      description: "Display full list of blocked commands"
  multiSelect: false
```

### Step 3: Merge Hook into Settings

**Read existing settings, merge hooks, write back:**

```bash
/usr/bin/env bash << 'INSTALL_HOOK_EOF'
SETTINGS_FILE="$HOME/.claude/settings.json"

# Create file if doesn't exist
if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo '{}' > "$SETTINGS_FILE"
fi

# Read existing settings
EXISTING=$(cat "$SETTINGS_FILE")

# Define the new hook
NEW_HOOK='{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "/usr/bin/env bash -c '\''CMD=\"$CLAUDE_TOOL_INPUT_command\"; case \"$CMD\" in \"git checkout -b\"*|\"git checkout -B\"*) echo \"BLOCKED: Use git town hack instead of git checkout -b\"; exit 1;; \"git pull\"*) echo \"BLOCKED: Use git town sync instead of git pull\"; exit 1;; \"git merge\"*) echo \"BLOCKED: Use git town sync or git town ship instead of git merge\"; exit 1;; \"git push origin main\"*|\"git push origin master\"*) echo \"BLOCKED: Use git town sync instead of pushing to main\"; exit 1;; \"git branch -d\"*|\"git branch -D\"*) echo \"BLOCKED: Use git town delete instead of git branch -d\"; exit 1;; \"git rebase\"*) echo \"BLOCKED: Use git town sync (rebase strategy) instead of git rebase\"; exit 1;; esac'\''"
    }
  ]
}'

# Merge using jq
echo "$EXISTING" | jq --argjson hook "$NEW_HOOK" '
  .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$hook] | unique_by(.matcher + (.hooks[0].command // "")))
' > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

echo "✅ Hook installed successfully"
cat "$SETTINGS_FILE" | jq '.hooks'

INSTALL_HOOK_EOF
```

### Step 4: Verify Installation

```bash
/usr/bin/env bash -c 'cat ~/.claude/settings.json | jq ".hooks.PreToolUse"'
```

---

## Uninstallation

### Step 1: Confirm Uninstall

```
AskUserQuestion with questions:
- question: "Remove git-town enforcement hooks?"
  header: "Uninstall"
  options:
    - label: "Yes, remove hooks"
      description: "Allow raw git commands again"
    - label: "No, keep hooks"
      description: "Keep enforcement active"
  multiSelect: false
```

### Step 2: Remove Hook

```bash
/usr/bin/env bash << 'UNINSTALL_HOOK_EOF'
SETTINGS_FILE="$HOME/.claude/settings.json"

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "No settings file found"
    exit 0
fi

# Remove git-town enforcement hook
cat "$SETTINGS_FILE" | jq '
  .hooks.PreToolUse = [.hooks.PreToolUse[]? | select(.matcher != "Bash" or (.hooks[0].command | contains("git town") | not))]
' > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

echo "✅ Hook removed successfully"

UNINSTALL_HOOK_EOF
```

---

## Status Check

### Show Current Hook Status

```bash
/usr/bin/env bash << 'STATUS_HOOK_EOF'
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "=== GIT-TOWN ENFORCEMENT HOOK STATUS ==="

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "❌ No settings file found"
    echo "   Run: /git-town-workflow:hooks install"
    exit 0
fi

# Check if hook exists
HOOK_EXISTS=$(cat "$SETTINGS_FILE" | jq '[.hooks.PreToolUse[]? | select(.hooks[0].command | contains("git town"))] | length')

if [[ "$HOOK_EXISTS" -gt 0 ]]; then
    echo "✅ Git-town enforcement hook is ACTIVE"
    echo ""
    echo "Blocked commands:"
    echo "  - git checkout -b → use git town hack"
    echo "  - git pull → use git town sync"
    echo "  - git merge → use git town sync"
    echo "  - git push origin main → use git town sync"
    echo "  - git branch -d → use git town delete"
    echo "  - git rebase → use git town sync"
else
    echo "❌ Git-town enforcement hook is NOT installed"
    echo "   Run: /git-town-workflow:hooks install"
fi

STATUS_HOOK_EOF
```

---

## Arguments

- `install` - Install enforcement hooks
- `uninstall` - Remove enforcement hooks
- `status` - Show current hook status

## Examples

```bash
# Install hooks
/git-town-workflow:hooks install

# Check status
/git-town-workflow:hooks status

# Remove hooks
/git-town-workflow:hooks uninstall
```

## Troubleshooting

| Issue                   | Cause                     | Solution                            |
| ----------------------- | ------------------------- | ----------------------------------- |
| jq not found            | jq not installed          | `brew install jq`                   |
| Settings file not found | ~/.claude/ doesn't exist  | Create with `mkdir -p ~/.claude`    |
| Hook not blocking       | Session not restarted     | Restart Claude Code session         |
| Invalid JSON error      | Corrupted settings.json   | Check JSON syntax or restore backup |
| Hook still active       | Multiple hooks registered | Uninstall and reinstall to dedupe   |
