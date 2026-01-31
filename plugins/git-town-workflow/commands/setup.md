---
allowed-tools: Read, Write, Edit, Bash(git town:*), Bash(git config:*), Bash(git remote:*), Bash(which:*), Bash(brew:*), Bash(gh:*), Grep, Glob, AskUserQuestion, TodoWrite
argument-hint: "[--check]"
description: "Initialize git-town in current repository with fork-aware configuration. One-time setup. TRIGGERS - git-town setup, initialize git-town, configure git-town, git town init."
---

<!-- ⛔⛔⛔ MANDATORY: READ THIS ENTIRE FILE BEFORE ANY ACTION ⛔⛔⛔ -->

# Git-Town Setup — One-Time Configuration

**Run this ONCE per repository to configure git-town.**

## Prerequisites

1. git-town installed (`brew install git-town`)
2. GitHub CLI authenticated (`gh auth login`)
3. Repository cloned with remotes configured

---

## Phase 0: Preflight

### Step 0.1: Create TodoWrite

```
TodoWrite with todos:
- "[Setup] Check git-town installation" | in_progress
- "[Setup] Check GitHub CLI" | pending
- "[Setup] Detect repository configuration" | pending
- "[Setup] GATE - Confirm setup options" | pending
- "[Setup] Run git-town interactive setup" | pending
- "[Setup] Configure fork-specific settings" | pending
- "[Setup] Verify configuration" | pending
- "[Setup] Install enforcement hooks" | pending
```

### Step 0.2: Check Dependencies

```bash
/usr/bin/env bash << 'CHECK_DEPS_EOF'
echo "=== DEPENDENCY CHECK ==="

# git-town
if which git-town &>/dev/null; then
    echo "✅ git-town: $(git-town --version)"
else
    echo "❌ git-town: NOT INSTALLED"
    echo "   Run: brew install git-town"
fi

# gh CLI
if which gh &>/dev/null; then
    echo "✅ gh CLI: $(gh --version | head -1)"
    if gh auth status &>/dev/null; then
        echo "✅ gh auth: authenticated"
    else
        echo "❌ gh auth: NOT authenticated"
        echo "   Run: gh auth login"
    fi
else
    echo "❌ gh CLI: NOT INSTALLED"
    echo "   Run: brew install gh"
fi

# git
echo "✅ git: $(git --version)"

CHECK_DEPS_EOF
```

### Step 0.3: Detect Repository

```bash
/usr/bin/env bash << 'DETECT_REPO_EOF'
echo "=== REPOSITORY DETECTION ==="

# Check if in git repo
if ! git rev-parse --git-dir &>/dev/null; then
    echo "❌ FATAL: Not in a git repository"
    exit 1
fi

# Remotes
echo "--- Remotes ---"
git remote -v

# Branches
echo "--- Branches ---"
git branch -a | head -10

# Current git-town config
echo "--- Current git-town config ---"
git town config 2>/dev/null || echo "(not configured)"

# Main branch detection
echo "--- Main branch ---"
git config init.defaultBranch 2>/dev/null || echo "main (default)"

DETECT_REPO_EOF
```

---

## Phase 1: GATE — Configuration Options

```
AskUserQuestion with questions:
- question: "How should git-town sync branches?"
  header: "Sync Strategy"
  options:
    - label: "Merge (Recommended for most teams)"
      description: "git town sync uses merge commits"
    - label: "Rebase (Clean history)"
      description: "git town sync uses rebase"
  multiSelect: false
```

```
AskUserQuestion with questions:
- question: "What's the main branch in this repository?"
  header: "Main Branch"
  options:
    - label: "main"
      description: "Modern default"
    - label: "master"
      description: "Legacy default"
    - label: "Other"
      description: "Custom main branch name"
  multiSelect: false
```

```
AskUserQuestion with questions:
- question: "Is this a fork of another repository?"
  header: "Fork Setup"
  options:
    - label: "Yes, configure fork workflow"
      description: "Enable upstream sync, set dev-remote to origin"
    - label: "No, single-origin repository"
      description: "Standard setup without upstream"
  multiSelect: false
```

---

## Phase 2: Run git-town Setup

### Step 2.1: Interactive Setup (if preferred)

```bash
git town config setup
```

### Step 2.2: Programmatic Setup

```bash
/usr/bin/env bash << 'SETUP_EOF'
# Set main branch
git config git-town.main-branch main  # or master

# Set sync strategy
git config git-town.sync-feature-strategy merge  # or rebase

# Enable push for new branches
git config git-town.push-new-branches true

# Set push hook (prompt before push)
git config git-town.push-hook true

# For forks: enable upstream sync
if git remote get-url upstream &>/dev/null; then
    git config git-town.sync-upstream true
    git config git-town.dev-remote origin
    echo "✅ Fork workflow configured"
fi

SETUP_EOF
```

---

## Phase 3: Verify Configuration

```bash
/usr/bin/env bash -c 'git town config'
```

**Expected output for fork workflow:**

```
Branches:
  main branch: main
  perennial branches: (none)
  ...

Hosting:
  hosting platform: github
  dev-remote: origin
  ...

Sync:
  sync-feature-strategy: merge
  sync-upstream: true
  ...
```

---

## Phase 4: Install Enforcement Hooks

```
AskUserQuestion with questions:
- question: "Install Claude Code hooks to enforce git-town usage?"
  header: "Enforcement"
  options:
    - label: "Yes, install hooks (Recommended)"
      description: "Blocks: git checkout -b, git pull, git merge"
    - label: "No, skip hooks"
      description: "Allow raw git commands"
  multiSelect: false
```

If "Yes": Run `/git-town-workflow:hooks install`

---

## Post-Setup Checklist

```
✅ git-town installed and configured
✅ Main branch identified
✅ Sync strategy set
✅ Fork workflow configured (if applicable)
✅ Enforcement hooks installed (optional)

Next steps:
- Start contributing: /git-town-workflow:contribute feat/my-feature
- View branch hierarchy: git town branch
- Sync all branches: git town sync --all
```

---

## Arguments

- `--check` - Only verify current setup, don't change anything

## Examples

```bash
# Full setup wizard
/git-town-workflow:setup

# Check current configuration
/git-town-workflow:setup --check
```

## Troubleshooting

| Issue                 | Cause                        | Solution                            |
| --------------------- | ---------------------------- | ----------------------------------- |
| git-town not found    | git-town not installed       | `brew install git-town`             |
| gh auth failed        | GitHub CLI not authenticated | `gh auth login`                     |
| Not in a git repo     | Missing .git directory       | Run from within a git repository    |
| No remotes configured | Repo has no remotes          | `git remote add origin <url>`       |
| Upstream not found    | Fork not configured          | Run `/git-town-workflow:fork` first |
| Config not persisting | Git config scope issue       | Check `--global` vs `--local` scope |
