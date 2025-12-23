**Skill**: [semantic-release](../SKILL.md)

# Local Release Workflow (Canonical)

**Single source of truth** for executing semantic-release locally. This 4-phase workflow ensures reliable, repeatable releases with automatic push.

```
PREFLIGHT ──► SYNC ──► RELEASE ──► POSTFLIGHT
```

---

## Quick Reference

**Recommended**: Use npm scripts for automatic push handling:

```bash
npm run release:dry   # Preview changes (no modifications)
npm run release       # Execute release (auto-pushes via successCmd + postrelease)
```

**Alternative**: All-in-one shell function (add to `~/.zshrc`):

```bash
release() {
    # PHASE 1: PREFLIGHT
    command -v gh &>/dev/null || { echo "FAIL: gh CLI not installed"; return 1; }
    command -v semantic-release &>/dev/null || { echo "FAIL: semantic-release not installed globally"; return 1; }
    gh api user --jq '.login' &>/dev/null || { echo "FAIL: GH_TOKEN not set"; return 1; }
    git rev-parse --git-dir &>/dev/null || { echo "FAIL: Not a git repo"; return 1; }

    local branch=$(git branch --show-current)
    [[ "$branch" == "main" ]] || { echo "FAIL: Not on main (on: $branch)"; return 1; }
    [[ -z "$(git status --porcelain)" ]] || { echo "FAIL: Working directory not clean"; git status --short; return 1; }

    # Check for releasable commits
    local last_tag=$(git describe --tags --abbrev=0 2>/dev/null)
    if [[ -n "$last_tag" ]]; then
        if ! git log "${last_tag}..HEAD" --oneline | grep -qE "^[a-f0-9]+ (feat|fix|BREAKING)"; then
            echo "FAIL: No releasable commits since $last_tag"
            echo "Use feat: or fix: prefix for version-bumping changes"
            return 1
        fi
    fi
    echo "PREFLIGHT: OK"

    # PHASE 2: SYNC
    git pull --rebase origin main --quiet || { echo "FAIL: Pull failed"; return 1; }
    git push origin main --quiet || { echo "FAIL: Push failed"; return 1; }
    echo "SYNC: OK"

    # PHASE 3: RELEASE
    export GIT_OPTIONAL_LOCKS=0
    GITHUB_TOKEN=$(gh auth token) semantic-release --no-ci "$@"
    local rc=$?
    [[ $rc -ne 0 ]] && { echo "FAIL: semantic-release exited with code $rc"; return $rc; }
    echo "RELEASE: OK"

    # PHASE 4: POSTFLIGHT
    [[ -n $(git status --porcelain) ]] && { echo "WARN: Unexpected uncommitted changes"; git status --short; }
    git fetch origin main:refs/remotes/origin/main --no-tags
    echo "POSTFLIGHT: OK (tracking refs updated)"

    echo ""
    echo "Latest release:"
    gh release list --limit 1
}
```

---

## Phase 1: Preflight

**Purpose**: Validate all prerequisites before any git operations.

### 1.1 Tooling Check

| Check                   | Command                       | Expected   | Resolution                                                 |
| ----------------------- | ----------------------------- | ---------- | ---------------------------------------------------------- |
| gh CLI installed        | `command -v gh`               | Path to gh | `brew install gh`                                          |
| semantic-release global | `command -v semantic-release` | Path       | See [Troubleshooting](#macos-gatekeeper-blocks-node-files) |
| In git repo             | `git rev-parse --git-dir`     | `.git`     | Navigate to repo root                                      |
| On main branch          | `git branch --show-current`   | `main`     | `git checkout main`                                        |
| Clean working directory | `git status --porcelain`      | Empty      | Commit or stash                                            |

### 1.2 Authentication Check (HTTPS-First)

**Primary method** (per authentication.md 2025-12-19+):

```bash
# Verify HTTPS remote
git remote get-url origin
# Expected: https://github.com/...

# Verify GH_TOKEN active via mise [env]
gh api user --jq '.login'
# Expected: correct account for this directory
```

**If remote is SSH** (legacy):

```bash
git-ssh-to-https  # Convert to HTTPS-first
```

**Multi-account verification**:

```bash
# SSH test (for comparison)
ssh -T git@github.com 2>&1
# "Hi <username>! You've successfully authenticated..."

# gh account
gh auth status 2>&1 | grep -B1 "Active account: true" | head -1

# If mismatch: switch account
gh auth switch --user <expected-username>
```

### 1.3 Releasable Commits Validation

**MANDATORY**: Verify version-bumping commits exist before proceeding.

```bash
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
git log "${LAST_TAG}..HEAD" --oneline | grep -E "^[a-f0-9]+ (feat|fix|BREAKING)"
```

**If no releasable commits**:

- STOP immediately
- Inform user: "No version-bumping commits since last release"
- Only `feat:`, `fix:`, or `BREAKING CHANGE:` trigger releases

---

## Phase 2: Sync

**Purpose**: Synchronize local and remote before release.

### 2.1 Pull with Rebase

```bash
git pull --rebase origin main
```

**If conflicts**: Resolve, `git add .`, `git rebase --continue`

### 2.2 Push Local Commits

```bash
git push origin main
```

**If push fails** (SSH permission issues):

1. Check ControlMaster cache (see [Troubleshooting](#controlmaster-cache-issues))
2. With HTTPS-first, this should rarely happen

---

## Phase 3: Release

**Purpose**: Execute semantic-release with proper environment.

### 3.1 Dry-Run (Recommended First)

```bash
npm run release:dry
# Or:
/usr/bin/env bash -c 'GITHUB_TOKEN=$(gh auth token) semantic-release --no-ci --dry-run'
```

### 3.2 Execute Release

```bash
npm run release
# Or:
/usr/bin/env bash -c 'export GIT_OPTIONAL_LOCKS=0 && GITHUB_TOKEN=$(gh auth token) semantic-release --no-ci'
```

**What happens**:

1. `@semantic-release/commit-analyzer` - Determines version bump
2. `@semantic-release/release-notes-generator` - Generates changelog content
3. `@semantic-release/exec` - Runs generateNotesCmd, prepareCmd
4. `@semantic-release/changelog` - Updates CHANGELOG.md
5. `@semantic-release/git` - Creates commit + tag locally
6. `@semantic-release/exec` - **successCmd pushes via `git push --follow-tags`**
7. `@semantic-release/github` - Creates GitHub release via API

> **Note**: Use global `semantic-release` install, not `npx`, to avoid macOS Gatekeeper issues.

---

## Phase 4: Postflight

**Purpose**: Verify success and update local state.

### 4.1 Verify Pristine State

```bash
git status --porcelain
# Expected: empty (no uncommitted changes)
```

### 4.2 Verify Release Created

```bash
gh release list --limit 1
# Should show new version
```

### 4.3 Update Local Tracking Refs

**IMPORTANT**: Even with successCmd push, local tracking refs may be stale.

```bash
git fetch origin main:refs/remotes/origin/main --no-tags
```

**Why**: Shell prompts, IDE git integrations, and status lines rely on local tracking refs. Without this update, they show incorrect ahead/behind counts.

### 4.4 Verify Sync

```bash
git status -sb
# Expected: ## main...origin/main (no ahead/behind counts)
```

---

## Success Criteria

- [ ] All prerequisites verified
- [ ] HTTPS-first authentication confirmed
- [ ] Releasable commits validated
- [ ] Remote synced (pull + push)
- [ ] semantic-release executed without error
- [ ] **Version incremented** (new tag > previous)
- [ ] Release visible: `gh release list --limit 1`
- [ ] Working directory pristine
- [ ] Local tracking refs updated (no stale indicators)

---

## Troubleshooting

### No GitHub Token Specified

**Cause**: `GITHUB_TOKEN` not set or gh not authenticated

**Resolution**:

1. `gh auth status` - verify authenticated
2. `gh auth login` - if not authenticated
3. `gh auth token` - verify token retrieval works

### Repository Not Found (Valid URL)

**Cause**: gh CLI authenticated with wrong account (common in multi-account setups)

**Resolution**:

1. `gh api user --jq '.login'` - check active account
2. `gh auth switch --user <correct-account>` - switch if needed
3. If account not logged in: `gh auth login` for that account

### Permission Denied (publickey)

**Cause**: SSH key issue

**Resolution**:

1. `ssh -T git@github.com` - test SSH
2. Check `~/.ssh/config` for GitHub configuration
3. `ssh-add ~/.ssh/id_ed25519` - ensure key loaded
4. Check ControlMaster cache (next section)

### ControlMaster Cache Issues

**Cause**: SSH caches connections by hostname, not identity. Multi-account setups get wrong cached connection.

**Detection**:

```bash
# Compare these outputs:
ssh -o ControlMaster=no -T git@github.com  # Fresh connection
ssh -T git@github.com                       # Cached connection
# If different → stale cache
```

**Resolution**:

```bash
ssh -O exit git@github.com  # Kill cached connection
# Or:
rm -f ~/.ssh/control-git@github.com:22
```

**Prevention** (add to `~/.ssh/config`):

```sshconfig
Host github.com
    ControlMaster no
```

### macOS Gatekeeper Blocks .node Files

**Cause**: macOS Sequoia blocks unsigned native modules when using `npx`

**Resolution**:

```bash
# Install globally
npm install -g semantic-release @semantic-release/changelog \
  @semantic-release/git @semantic-release/github @semantic-release/exec

# Clear quarantine (one-time)
xattr -r -d com.apple.quarantine ~/.local/share/mise/installs/node/
```

### No Release Published

**Cause**: No releasable commits since last tag

**Check**:

```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

Only these trigger releases:

- `feat:` → minor
- `fix:` → patch
- `BREAKING CHANGE:` or `feat!:` → major

`docs:`, `chore:`, etc. → no release (unless configured in .releaserc.yml)

### Stale Ahead/Behind Indicators

**Symptom**: After release, prompt shows `↑:N` but actually in sync

**Cause**: Local tracking refs not updated after API push

**Resolution**:

```bash
git fetch origin main:refs/remotes/origin/main --no-tags
```

**Prevention**: Always run Phase 4 (Postflight), or use `npm run release` which runs `postrelease` automatically.

---

## Migration from Pre-v7.10 Projects

Projects initialized before v7.10 lack automatic push. Add manually:

**1. Add successCmd to `.releaserc.yml`** (after @semantic-release/git):

```yaml
# After @semantic-release/git entry
- - "@semantic-release/exec"
  - successCmd: "/usr/bin/env bash -c 'git push --follow-tags origin main'"
```

**2. Add postrelease to `package.json`**:

```bash
npm pkg set scripts.postrelease="git fetch origin main:refs/remotes/origin/main --no-tags || true"
```
