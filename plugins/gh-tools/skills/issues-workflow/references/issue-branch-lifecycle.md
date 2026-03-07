# Issue-Branch-PR Lifecycle Reference

**Parent**: [Issues Workflow SKILL.md](../SKILL.md#issue-branch-pr-lifecycle)

## Closing Keywords — Complete Specification

GitHub recognizes these keywords in PR bodies and commit messages. On merge to the default branch, referenced issues are automatically closed.

### Supported Keywords

All keywords are case-insensitive and work with `#N` or `owner/repo#N` syntax:

- `close`, `closes`, `closed`
- `fix`, `fixes`, `fixed`
- `resolve`, `resolves`, `resolved`

### Placement Rules

| Location           | Auto-closes? | Notes                              |
| ------------------ | ------------ | ---------------------------------- |
| PR body            | Yes          | Most reliable — always use this    |
| Commit message     | Yes          | Only when merged to default branch |
| PR title           | No           | Never triggers auto-close          |
| PR comment         | No           | Never triggers auto-close          |
| Issue body/comment | No           | Creates a reference link only      |

### Multiple Issues

```markdown
Closes #1, closes #2, fixes #3
```

Each issue needs its own keyword. `Closes #1, #2, #3` only closes `#1`.

### Cross-Repo Closing

```markdown
Closes terrylica/other-repo#42
```

Requires push access to the target repository.

## `gh issue develop` — Branch-from-Issue

Creates a branch linked to an issue with automatic PR-issue association.

### Command Reference

```bash
# Basic (auto-names branch from issue title)
gh issue develop <number>

# With checkout
gh issue develop <number> --checkout

# Custom branch name
gh issue develop <number> --name <branch-name> --checkout

# Specify base branch
gh issue develop <number> --base main --checkout
```

### What Happens

1. Creates branch on remote (and optionally checks out locally)
2. Links branch to issue (visible in issue sidebar → "Development")
3. PRs from this branch auto-link to the issue
4. Merging the PR auto-closes the issue

### Comparison: `develop` vs Closing Keywords

| Feature         | `gh issue develop`    | Closing keywords          |
| --------------- | --------------------- | ------------------------- |
| Branch naming   | Auto from issue title | Manual                    |
| Issue-PR link   | Automatic             | Automatic                 |
| Cross-repo      | Same repo only        | Cross-repo with push      |
| Multiple issues | One branch per issue  | One PR closes many issues |
| Requires gh CLI | Yes                   | No (just text in body)    |

**Recommendation**: Use both. `gh issue develop` for branch creation, closing keywords in PR body for explicitness.

## Local-First Automation Policy

**No GitHub Actions for testing or linting.** All quality gates run locally:

- `mise run check-full` (fmt + lint + test + deny)
- `cargo nextest run` (Rust tests)
- `pytest` (Python tests)
- `ruff check` / `clippy` (linting)

GitHub Actions are reserved for: semantic-release, CodeQL, Dependabot, deployment.

See: [GitHub Actions ADR](/docs/adr/2025-11-21-github-actions-no-testing-linting.md)

## Complete Workflow Example

```bash
# 1. Create parent issue with sub-issues
gh issue create --title "feat: consumer API for flowsurface" \
  --body "Parent tracker for consumer-facing API.

Sub-issues:
- [ ] Forming bar push (#214)
- [ ] Checkpoint push (#215)
- [ ] Gap-fill endpoint (#216)
- [ ] Ariadne endpoint (#217)" \
  --label "type:epic"

# 2. Branch from parent issue
gh issue develop 213 --name feat/consumer-api --checkout

# 3. Implement across multiple commits
git add -A && git commit -m "feat: forming bar push via SSE (#214)"
git add -A && git commit -m "feat: checkpoint push (#215)"

# 4. Create PR with bulk auto-close
gh pr create --title "feat: consumer API for flowsurface (#213)" \
  --body "Closes #213
Closes #214
Closes #215
Closes #216
Closes #217"

# 5. Squash merge + delete branch
gh pr merge --squash --delete-branch

# 6. All 5 issues auto-close on merge

# 7. Prune local stale branches
git fetch --prune
git branch -vv | grep ': gone]' | awk '{print $1}' | xargs git branch -d
```
