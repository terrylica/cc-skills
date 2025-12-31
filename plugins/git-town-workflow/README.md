# Git-Town Workflow Plugin

**Prescriptive git-town workflow enforcement for fork-based development.**

## Philosophy

**Git-town is canonical. Raw git branch commands are forbidden.**

This plugin enforces idiomatic git-town usage through:
1. **Preflight checks** at every step
2. **AskUserQuestion gates** before destructive actions
3. **Claude Code hooks** that block forbidden commands
4. **Workflow commands** that guide through complex operations

## Commands

| Command | Purpose |
|---------|---------|
| `/git-town-workflow:fork` | Create/configure fork workflow |
| `/git-town-workflow:contribute` | Complete contribution cycle |
| `/git-town-workflow:setup` | Initialize git-town in repository |
| `/git-town-workflow:hooks` | Install/uninstall enforcement hooks |

## Quick Start

```bash
# 1. Install git-town
brew install git-town

# 2. Configure fork workflow
/git-town-workflow:fork

# 3. Install enforcement hooks
/git-town-workflow:hooks install

# 4. Start contributing
/git-town-workflow:contribute feat/my-feature
```

## What Gets Blocked

When hooks are installed, these commands are blocked:

| ❌ Blocked | ✅ Use Instead |
|-----------|----------------|
| `git checkout -b` | `git town hack` |
| `git pull` | `git town sync` |
| `git merge` | `git town sync` |
| `git push origin main` | `git town sync` |
| `git branch -d` | `git town delete` |
| `git rebase` | `git town sync` |

## What's Allowed

These raw git commands are still allowed:
- `git add` - Staging files
- `git commit` - Creating commits
- `git status` - Viewing status
- `git log` - Viewing history
- `git diff` - Viewing changes
- `git stash` - Stashing changes

## Fork Workflow

```
┌─────────────────────────────────────────────────────────┐
│                    FORK ARCHITECTURE                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   upstream (original)     origin (your fork)            │
│   github.com/org/repo     github.com/you/repo           │
│         │                       │                       │
│         │                       │                       │
│         ▼                       ▼                       │
│     ┌───────┐               ┌───────┐                   │
│     │ main  │◄─────────────►│ main  │                   │
│     └───────┘  git town     └───────┘                   │
│                  sync            │                      │
│                                  │                      │
│                                  ▼                      │
│                            ┌──────────┐                 │
│                            │ feature  │                 │
│                            └──────────┘                 │
│                                  │                      │
│                                  │ git town propose     │
│                                  ▼                      │
│                            ┌──────────┐                 │
│                            │   PR     │──► upstream     │
│                            └──────────┘                 │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## References

- [Git-Town Documentation](https://www.git-town.com/)
- [Cheatsheet](./references/cheatsheet.md)

## Installation

```bash
/plugin install cc-skills
```

Or manually add to `~/.claude/plugins/`.
