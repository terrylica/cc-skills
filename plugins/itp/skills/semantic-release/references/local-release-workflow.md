**Skill**: [semantic-release](../SKILL.md)

# Local Release Workflow

Instructional workflow for executing local semantic-release. Follow these steps autonomously, resolving issues as encountered.

---

## Prerequisites Checklist

Before starting, verify each prerequisite. If any fails, resolve before proceeding.

| Check                       | Command                       | Expected                    | Resolution              |
| --------------------------- | ----------------------------- | --------------------------- | ----------------------- |
| gh CLI installed            | `command -v gh`               | Path to gh                  | `brew install gh`       |
| npx available               | `command -v npx`              | Path to npx                 | Install Node.js         |
| gh authenticated            | `gh auth status`              | "Logged in to github.com"   | `gh auth login`         |
| **gh account matches repo** | See Account Alignment section | Active account = repo owner | `gh auth switch`        |
| In git repo                 | `git rev-parse --git-dir`     | `.git`                      | Navigate to repo root   |
| On main branch              | `git branch --show-current`   | `main`                      | `git checkout main`     |
| Clean working directory     | `git status --porcelain`      | Empty output                | Commit or stash changes |

### Account Alignment Check (MANDATORY FIRST STEP)

**CRITICAL**: For multi-account GitHub setups, verify the active gh account matches the repository owner BEFORE any release operation. This check is non-negotiable and must be performed first.

**Detection sequence** (execute autonomously):

1. **Extract repository owner** from git remote URL:
   - Parse `git remote get-url origin` output
   - Handle SSH format: `git@github.com:OWNER/repo.git` → extract OWNER
   - Handle HTTPS format: `https://github.com/OWNER/repo.git` → extract OWNER

2. **Identify active gh account**:
   - Parse `gh auth status` output
   - Find the account marked "Active account: true"
   - Extract the account username

3. **Compare and resolve**:
   - If active account username ≠ repository owner → **MISMATCH DETECTED**
   - Switch to correct account: `gh auth switch --user <repo-owner>`
   - If account not available → prompt user: `gh auth login` for that account
   - After switch, verify: `gh auth status` shows correct account active

**Why this matters**: GitHub tokens are account-specific. A mismatched account causes "Repository not found" errors even when the repository exists, because the token lacks access permissions for that repository.

**Failure mode without this check**: Release silently fails or produces cryptic permission errors that don't indicate the root cause is account mismatch.

---

## Workflow Steps

### Step 1: Verify Prerequisites

Run each check from the Prerequisites Checklist. Resolve any failures before proceeding.

### Step 2: Verify Releasable Commits Exist

**MANDATORY**: Before proceeding, verify commits since last tag include version-bumping types (`feat:`, `fix:`, or `BREAKING CHANGE:`).

**Autonomous check sequence**:

1. Identify latest version tag
2. List commits since that tag
3. Scan commit messages for releasable prefixes
4. If NO releasable commits → **STOP** and inform user

**If no releasable commits found**:

- Inform user: "No version-bumping commits since last release"
- Advise: Use `feat:` or `fix:` prefix for changes that warrant a release
- Do NOT proceed with semantic-release (it will produce no output)

**Why this matters**: Running semantic-release without releasable commits wastes time and creates confusion. Validate first, release second.

### Step 3: Sync with Remote

**Pull with rebase**:

```bash
git pull --rebase origin main
```

**If pull fails**:

- Check network connectivity
- Verify remote exists: `git remote -v`
- If conflicts: resolve, `git add .`, `git rebase --continue`

**Push local commits**:

```bash
git push origin main
```

**If SSH push fails**, try HTTPS fallback:

```bash
# Derive HTTPS URL from SSH
git remote get-url origin
# git@github.com:user/repo.git → https://github.com/user/repo.git
git push https://github.com/user/repo.git main
```

### Step 4: Execute Release

Set environment and run:

```bash
export GIT_OPTIONAL_LOCKS=0
GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci
```

**For dry-run** (no changes):

```bash
GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci --dry-run
```

### Step 5: Verify Post-Release State

**Check for uncommitted changes**:

```bash
git status --porcelain
```

- **Empty output** → Release successful, state is pristine
- **Has output** → Unexpected changes; investigate what semantic-release modified

**Verify release created**:

```bash
gh release list --limit 1
```

---

## Issue Resolution

### "No GitHub token specified"

**Cause**: `GH_TOKEN` not set or gh CLI not authenticated

**Resolution**:

1. Verify: `gh auth status`
2. If not authenticated: `gh auth login`
3. Verify token retrieval: `gh auth token` (should output token)

### "Repository not found" (with valid repo URL)

**Cause**: gh CLI authenticated with wrong GitHub account for this repository. Common in multi-account setups where developer has personal, work, or organization accounts.

**Symptoms**:

- Repository URL is correct and repo exists
- SSH test shows different username than repo owner
- gh auth shows multiple accounts with wrong one active

**Resolution**:

1. Extract repo owner from remote URL
2. List available gh accounts to find matching account
3. Switch gh CLI to the account matching repository owner
4. Re-fetch token after account switch
5. If account not logged in, authenticate with `gh auth login` for that account

**Prevention**: Always verify account alignment as first pre-flight check before any release operation.

### "Permission denied (publickey)"

**Cause**: SSH key issue for git push

**Resolution**:

1. Test SSH: `ssh -T git@github.com`
2. Check SSH config: `cat ~/.ssh/config | grep -A5 github`
3. Add key to agent: `ssh-add ~/.ssh/id_ed25519`
4. Fallback: Use HTTPS push with gh token authentication (see Step 2)

### "Not on main branch"

**Cause**: Attempting release from non-main branch

**Resolution**:

1. Check current branch: `git branch --show-current`
2. Switch to main: `git checkout main`
3. Ensure main is up-to-date: `git pull --rebase origin main`

### "Working directory not clean"

**Cause**: Uncommitted changes prevent release

**Resolution options**:

1. **Commit changes**: `git add . && git commit -m "..."`
2. **Stash temporarily**: `git stash` (then `git stash pop` after release)
3. **Discard changes**: `git checkout -- .` (⚠️ destructive)

### "No release published"

**Cause**: No releasable commits since last tag

**Check commit types**:

```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

Only these trigger releases:

- `feat:` → minor bump
- `fix:` → patch bump
- `BREAKING CHANGE:` or `feat!:` → major bump

`docs:`, `chore:`, `style:`, `refactor:`, `test:` → no release

---

## Decision Tree

```
Start Release
    │
    ├── Prerequisites pass?
    │   ├── No → Resolve each failure, retry
    │   └── Yes ↓
    │
    ├── gh account matches repo owner?
    │   ├── No → Switch account, re-fetch token
    │   ├── Account not available → gh auth login for that account
    │   └── Yes ↓
    │
    ├── Releasable commits exist? (feat:/fix:/BREAKING)
    │   ├── No → STOP, inform user "no version-bumping commits"
    │   └── Yes ↓
    │
    ├── Working directory clean?
    │   ├── No → Commit, stash, or discard
    │   └── Yes ↓
    │
    ├── Pull succeeds?
    │   ├── No → Resolve conflicts or network issues
    │   └── Yes ↓
    │
    ├── Push succeeds (SSH)?
    │   ├── No → Try HTTPS with token auth
    │   └── Yes ↓
    │
    ├── Run semantic-release
    │   │
    │   ├── Token error? → Verify account alignment first
    │   ├── Repo not found? → Wrong account, switch and retry
    │   ├── No commits to release? → Inform user
    │   └── Success ↓
    │
    └── Verify pristine state
        ├── Unexpected changes → Investigate
        └── Clean → ✅ Complete
```

---

## Success Criteria

- [ ] All prerequisites verified (including account alignment)
- [ ] Releasable commits confirmed (feat:/fix:/BREAKING present)
- [ ] Remote synced (pull + push successful)
- [ ] semantic-release executed without error
- [ ] **Version incremented** (new tag > previous tag)
- [ ] New release visible: `gh release list --limit 1`
- [ ] Working directory pristine after release
