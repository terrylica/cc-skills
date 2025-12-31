# Git-Town Command Cheatsheet

**CANONICAL REFERENCE**: Use git-town commands, NOT raw git for branch operations.

---

## Daily Workflow Commands

| Task | Git-Town Command | ❌ Never Use |
|------|------------------|--------------|
| Create feature branch | `git town hack feature-name` | `git checkout -b` |
| Update current branch | `git town sync` | `git pull`, `git fetch`, `git merge` |
| Update all branches | `git town sync --all` | manual per-branch pulls |
| Switch branches | `git town switch` | `git checkout branch` |
| Create pull request | `git town propose` | GitHub web UI |
| Merge approved PR | `git town ship` | `git merge` + `git push` |
| Delete branch | `git town delete branch` | `git branch -d` |

---

## Stacked Changes (Multiple PRs)

| Task | Command |
|------|---------|
| Create child branch | `git town append child-name` |
| Create parent branch | `git town prepend parent-name` |
| Navigate up stack | `git town up` |
| Navigate down stack | `git town down` |
| View stack hierarchy | `git town branch` |
| Swap branch order | `git town swap` |
| Extract from stack | `git town detach` |

---

## Error Recovery

| Situation | Command |
|-----------|---------|
| Undo last git-town command | `git town undo` |
| Continue after conflict fix | `git town continue` |
| Skip conflicting branch | `git town skip` |
| Check current state | `git town status` |

---

## Branch Types

| Type | Purpose | Command |
|------|---------|---------|
| Feature | Your work | `git town hack` |
| Contribution | Someone else's branch | `git town contribute` |
| Observed | Watch-only | `git town observe` |
| Parked | Suspended sync | `git town park` |
| Prototype | Local-only | `git town prototype` |

---

## Fork-Specific Commands

```bash
# Sync with upstream (automatic if configured)
git town sync

# Check fork configuration
git town config

# View remote setup
git remote -v
```

---

## Configuration

```bash
# Interactive setup wizard
git town config setup

# Manual settings
git config git-town.main-branch main
git config git-town.sync-upstream true
git config git-town.dev-remote origin
git config git-town.sync-feature-strategy merge
```

---

## Quick Reference Card

```
┌──────────────────────────────────────────────────────────┐
│                    GIT-TOWN WORKFLOW                     │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ╔════════════╗    ╔════════════╗    ╔════════════╗     │
│  ║  1. SYNC   ║ →  ║  2. HACK   ║ →  ║  3. WORK   ║     │
│  ║            ║    ║            ║    ║            ║     │
│  ║ git town   ║    ║ git town   ║    ║ git add    ║     │
│  ║   sync     ║    ║   hack     ║    ║ git commit ║     │
│  ╚════════════╝    ╚════════════╝    ╚════════════╝     │
│        │                                    │            │
│        │                                    ▼            │
│        │           ╔════════════╗    ╔════════════╗     │
│        │           ║  5. SHIP   ║ ←  ║ 4. PROPOSE ║     │
│        │           ║            ║    ║            ║     │
│        │           ║ git town   ║    ║ git town   ║     │
│        └─────────► ║   ship     ║    ║  propose   ║     │
│                    ╚════════════╝    ╚════════════╝     │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  ✅ ALLOWED: git add, git commit, git status, git log    │
│  ❌ BLOCKED: git checkout -b, git pull, git merge        │
└──────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Not a git-town branch" | Run `git town hack` to create proper branch |
| Sync conflicts | Fix conflicts, run `git town continue` |
| Wrong parent | Run `git town set-parent correct-parent` |
| Stuck state | Run `git town status` to see options |
| Need to undo | Run `git town undo` |
