---
name: run-full-release
description: "Run the current repo's mise release pipeline with auto-scaffolding. Handles GitHub releases (mandatory), PyPI publishing (if Python), and crates.io (if Rust). TRIGGERS - mise release, full release, version bump, release automation, mise run release."
allowed-tools: Read, Bash, Glob, Grep, Write, Edit, AskUserQuestion
argument-hint: "[--dry] [--status]"
model: haiku
---

# /mise:run-full-release

Run the current repo's mise release pipeline end-to-end with auto-scaffolding. **Automatically detects and handles**:

- ✅ **Mandatory**: GitHub releases + version tags via semantic-release
- 🐍 **Optional**: PyPI publishing (if `pyproject.toml` + `scripts/publish-to-pypi.sh` or `[tool.maturin]`)
- 🦀 **Optional**: Crates.io publishing (if `Cargo.toml` + `[workspace.package]`)

If no release tasks exist, audits the repo and scaffolds idiomatic release tasks first.

## Step 0: Pre-Release Sync

**ALWAYS pull from remote before starting any release work:**

```bash
git pull origin main
```

This prevents:

- Diverged branches causing push failures after semantic-release creates tags
- Missing commits from other contributors or CI bots
- Force-push situations that destroy remote state

## Step 1: Detect Release Tasks

```bash
mise tasks ls 2>/dev/null | grep -i release
```

## Step 2: Branch Based on Detection

### If release tasks FOUND → Execute

1. Check working directory cleanliness: `git status --porcelain`
2. **Check for unpushed commits:** `git log --oneline @{u}..HEAD 2>/dev/null`
   - If unpushed commits exist → `git push origin main` before proceeding
   - semantic-release needs all commits pushed to analyze and version correctly
3. **Reset lockfile drift** (caused by preflight commands like `uv run pytest`):
   - Check for modified lockfiles: `git diff --name-only | grep -E '(uv\.lock|package-lock\.json|Cargo\.lock|bun\.lockb|yarn\.lock|pnpm-lock\.yaml)$'`
   - If ONLY lockfiles are dirty and no other changes exist → `git checkout -- <lockfile>` to reset them
   - If lockfiles are dirty alongside intentional changes → reset lockfiles first, then handle remaining changes in step 4
   - **Rationale**: Lockfiles modified by `uv run`, `npm install`, etc. during preflight are artifacts, not intentional changes. They should never block or pollute a release.
4. **If working directory is dirty → Autonomously resolve ALL changes before releasing:**
   a. Run `git status --porcelain` and `git diff` to understand every pending change
   b. For each group of related changes:
   - Read the changed files to understand what was modified and why
   - Craft a conventional commit message (`fix:`, `feat:`, `chore:`, `docs:`) that accurately describes the change
   - Stage specific files (never `git add -A`) and commit
     c. For untracked files that should NOT be committed (e.g., work-in-progress from other branches):
   - Stash them: `git stash push -u -m "pre-release: description"`
     d. Verify working directory is clean: `git status --porcelain` should be empty
     e. Restore any stash after release: `git stash pop`

   **Commit guidelines:**
   - Group logically related files into a single commit
   - Use the repo's existing commit message style (check `git log --oneline -5`)
   - Never skip pre-commit hooks (`--no-verify`)
   - If unsure whether a change should be committed or stashed, review the file contents and decide based on whether it's a completed change or work-in-progress

5. **Post-release lockfile cleanup**: After release completes, check again for lockfile drift and reset:
   - `git diff --name-only | grep -E '(uv\.lock|package-lock\.json|Cargo\.lock|bun\.lockb|yarn\.lock|pnpm-lock\.yaml)$' | xargs -r git checkout --`
   - This catches lockfiles modified by release tasks themselves (e.g., version bumps triggering lockfile updates)

6. **Detect optional publishing capabilities:**

   Before executing release, check for PyPI and crates.io:

   ```bash
   # PyPI detection: check for publish-to-pypi.sh OR pyproject.toml
   HAS_PYPI=false
   if [[ -x "scripts/publish-to-pypi.sh" ]] || grep -q '^\[tool\.maturin\]\|^\[project\]' pyproject.toml 2>/dev/null; then
       HAS_PYPI=true
   fi

   # Crates.io detection: check for Cargo.toml with [workspace.package]
   HAS_CRATES=false
   if [[ -f "Cargo.toml" ]] && grep -q '^\[workspace\.package\]' Cargo.toml 2>/dev/null; then
       HAS_CRATES=true
   fi

   export HAS_PYPI HAS_CRATES
   ```

7. Route by flags:
   - `--dry` → `mise run release:dry`
   - `--status` → `mise run release:status`
   - No flags → `mise run release:full` (which includes release:pypi and/or release:crates if detected)

### If release tasks NOT FOUND → Audit & Scaffold

Conduct a thorough audit of the repository to scaffold idiomatic release tasks.

#### Audit Checklist

Run these checks to understand the repo's release needs:

```bash
# 1. Detect language/ecosystem
ls pyproject.toml Cargo.toml package.json setup.py setup.cfg 2>/dev/null

# 2. Detect existing mise config
ls .mise.toml mise.toml 2>/dev/null
cat .mise.toml 2>/dev/null | head -50

# 3. Detect existing release infrastructure
ls .releaserc.yml .releaserc.json .releaserc release.config.* 2>/dev/null
ls .github/workflows/*release* 2>/dev/null
ls Makefile 2>/dev/null && grep -i release Makefile 2>/dev/null

# 4. Detect credential patterns
grep -r "GH_TOKEN\|GITHUB_TOKEN\|UV_PUBLISH_TOKEN\|CARGO_REGISTRY_TOKEN\|NPM_TOKEN" .mise.toml mise.toml 2>/dev/null

# 5. Detect build requirements
grep -i "maturin\|zig\|cross\|docker\|wheel\|sdist" .mise.toml Cargo.toml pyproject.toml 2>/dev/null
```

#### Read Reference Templates

Read these files from the cc-skills marketplace for the canonical 5-phase release pattern:

```
Read: $HOME/.claude/plugins/marketplaces/cc-skills/docs/RELEASE.md
```

Also examine cc-skills' own release tasks as a working template:

```bash
ls $HOME/.claude/plugins/marketplaces/cc-skills/.mise/tasks/release/
```

#### Scaffold `.mise/tasks/release/`

Create the release task directory and files customized to THIS repo:

| Task         | Always                                          | Repo-Specific Additions                                     |
| ------------ | ----------------------------------------------- | ----------------------------------------------------------- |
| `_default`   | Help/navigation                                 | —                                                           |
| `preflight`  | Clean dir, auth, branch check, lockfile cleanup | Plugin validation, build tool checks                        |
| `version`    | semantic-release                                | Repo-specific `.releaserc.yml` plugins                      |
| `sync`       | Git push                                        | PyPI publish (if exists), crates.io publish (if Rust), sync |
| `pypi`       | (Optional)                                      | `scripts/publish-to-pypi.sh` via `uv publish` or `twine`    |
| `crates`     | (Optional)                                      | `cargo publish --workspace` (Rust 1.90+, native ordering)   |
| `verify`     | Tag + release check                             | Verify artifacts (wheels, packages, published versions)     |
| `postflight` | Clean git state, no unpushed, lockfile reset    | Repo-specific lockfile patterns, custom validations         |
| `full`       | Orchestrator (5-phase)                          | Include all repo-specific phases                            |
| `dry`        | `semantic-release --dry-run`                    | —                                                           |
| `status`     | Current version info                            | —                                                           |

**Lockfile cleanup** is mandatory in both `preflight` (after test/validation runs) and `full` (after all phases complete). Commands like `uv run`, `npm install`, `cargo build` during release phases modify lockfiles as an artifact — these must be reset to avoid polluting the working directory. The canonical one-liner:

```bash
# Reset lockfile drift (artifact from uv run, npm install, cargo build, etc.)
git diff --name-only | grep -E '^(uv\.lock|package-lock\.json|Cargo\.lock|bun\.lockb|yarn\.lock|pnpm-lock\.yaml)$' | xargs -r git checkout --
```

**Publishing Capability Detection:**

Before running release:

1. **PyPI**: Check if `scripts/publish-to-pypi.sh` exists OR `pyproject.toml` contains `[tool.maturin]` or `[project]` with name/version
   - If found → include `release:pypi` in `release:full` depends chain
   - Store as `HAS_PYPI=true` for conditional task execution

2. **Crates.io**: Check if `Cargo.toml` exists AND contains `[workspace.package]` with version
   - If found → include `release:crates` in `release:full` depends chain
   - Store as `HAS_CRATES=true` for conditional task execution

3. **GitHub Releases**: Mandatory (via `@semantic-release/github`)

#### Ensure SSoT via mise

- All credentials must be in `.mise.toml` `[env]` section (not hardcoded in scripts)
- All tool versions must be in `[tools]` section
- All thresholds/configs as env vars with fallback defaults
- Use `read_file()` template function for secrets (e.g., `GH_TOKEN`)

#### Task Orchestration (release:full)

The `release:full` task **must** use conditional task dependencies to handle optional PyPI/crates.io:

```bash
#!/usr/bin/env bash
#MISE description="Phase 5: Full release orchestration with conditional publishing and postflight validation"
#MISE depends=["release:preflight"]

set -euo pipefail

# Detect publishing capabilities
HAS_PYPI=false
if [[ -x "scripts/publish-to-pypi.sh" ]] || grep -q '^\[tool\.maturin\]\|^\[project\]' pyproject.toml 2>/dev/null; then
    HAS_PYPI=true
fi

HAS_CRATES=false
if [[ -f "Cargo.toml" ]] && grep -q '^\[workspace\.package\]' Cargo.toml 2>/dev/null; then
    HAS_CRATES=true
fi

# Phase 1: Version bump
echo "→ Phase 1: Versioning..."
mise run release:version

# Phase 2: Sync to main + conditional publishing
echo "→ Phase 2: Syncing..."
git push --follow-tags origin main

# Phase 2b: PyPI publishing (optional)
if [[ "$HAS_PYPI" == "true" ]]; then
    echo "→ Phase 2b: Publishing to PyPI..."
    if mise tasks list | grep -q 'release:pypi'; then
        mise run release:pypi || echo "⚠ PyPI publish failed (non-fatal)"
    else
        echo "⚠ release:pypi task not found (skipping)"
    fi
fi

# Phase 2c: Crates.io publishing (optional)
if [[ "$HAS_CRATES" == "true" ]]; then
    echo "→ Phase 2c: Publishing to crates.io..."
    if mise tasks list | grep -q 'release:crates'; then
        mise run release:crates || echo "⚠ Crates.io publish failed (non-fatal)"
    else
        echo "⚠ release:crates task not found (skipping)"
    fi
fi

# Phase 3: Verify
echo "→ Phase 3: Verifying..."
mise run release:verify

# Phase 4: Postflight (git state validation + lockfile cleanup)
echo "→ Phase 4: Postflight..."
mise run release:postflight

echo ""
echo "✓ Release complete!"
echo ""
```

**Publishing Flags**:

- Non-fatal: If PyPI or crates.io publishing fails, release continues (version tag still created)
- Verify phase reports which artifacts published successfully

#### After Scaffolding

Run `mise run release:full` with the newly created tasks.

## Publishing & Postflight Task Implementations

Detailed implementations for `release:pypi`, `release:crates`, and `release:postflight` are in [./references/task-implementations.md](./references/task-implementations.md). Key points:

- **`release:pypi`**: Triggers on `pyproject.toml` + `scripts/publish-to-pypi.sh` or `[tool.maturin]`. Credentials via `.mise.toml [env]`.
- **`release:crates`**: Uses native `cargo publish --workspace` (Rust 1.90+). Never hardcode crate lists.
- **`release:postflight`**: Resets lockfile drift, fails on uncommitted changes or unpushed commits.

## Known Issue - `@semantic-release/git` Untracked File Explosion

**Bug**: `@semantic-release/git` v10.x runs `git ls-files -m -o` **without `--exclude-standard`**, listing ALL untracked files including gitignored ones (`.venv/`, `.hypothesis/`, `target/`, etc.). In repos with large `.venv/` or `node_modules/`, this produces ~100MB of stdout that crashes the plugin.

**Root cause**: `node_modules/@semantic-release/git/lib/git.js` line 12:

```js
// BUG: Missing --exclude-standard
return (await execa("git", ["ls-files", "-m", "-o"], execaOptions)).stdout;
```

**Upstream issues**: [#345](https://github.com/semantic-release/git/issues/345), [#347](https://github.com/semantic-release/git/issues/347), [#107](https://github.com/semantic-release/git/issues/107)

**Fix**: Patch both local and global installations:

```bash
# Find all installations
find /opt/homebrew/lib/node_modules $(npm root -g 2>/dev/null) node_modules \
  -path "*/@semantic-release/git/lib/git.js" 2>/dev/null | while read f; do
  if ! grep -q 'exclude-standard' "$f"; then
    sed -i '' "s/\['ls-files', '-m', '-o'\]/['ls-files', '-m', '-o', '--exclude-standard']/" "$f"
    echo "Patched: $f"
  fi
done
```

**Note**: Patch is lost on `npm update` or `brew upgrade`. Re-apply after upgrades.

## Partial Semantic-Release Recovery

When semantic-release **partially succeeds** (bumps version files but fails before creating tag):

1. **Detect**: `Cargo.toml`/`package.json` has new version but `git tag -l vX.Y.Z` returns empty
2. **Commit artifacts**: `git add Cargo.toml CHANGELOG.md && git commit -m "chore(release): vX.Y.Z"`
3. **Push**: `git push origin main`
4. **Create tag manually**: `git tag -a vX.Y.Z -m "vX.Y.Z\n\n<release notes>"`
5. **Push tag**: `git push origin vX.Y.Z`
6. **Create GitHub release**: `gh release create vX.Y.Z --title "vX.Y.Z" --notes "<notes>"`
7. **Continue with publish**: `mise run release:crates` and/or `mise run release:pypi`

**Critical**: Do NOT re-run `semantic-release --no-ci` after a partial failure — it will try to bump the version AGAIN, potentially skipping a version number. Always recover manually.

## Post-Release Deploy Reminder

After publishing, deploy to production hosts if applicable:

```bash
# Example: deploy to remote host
mise run deploy:bigblack   # or whatever deploy task exists

# Verify on remote
ssh <host> "<deploy-dir>/.venv/bin/python3 -c 'import <pkg>; print(<pkg>.__version__)'"
```

Forgetting to deploy means production runs stale code while monitoring reports version drift.

## Error Recovery

| Error                                  | Resolution                                                               |
| -------------------------------------- | ------------------------------------------------------------------------ |
| `mise` not found                       | Install: `curl https://mise.run \| sh`                                   |
| No release tasks                       | Scaffold using audit above                                               |
| Working dir not clean                  | Review, commit, or stash all changes autonomously                        |
| Lockfile drift (uv.lock etc.)          | `git checkout -- uv.lock` (artifact, not intentional)                    |
| Unpushed commits                       | `git push origin main` before release                                    |
| Not on main branch                     | `git checkout main`                                                      |
| No releasable commits                  | Create a `feat:` or `fix:` commit first                                  |
| Missing GH_TOKEN                       | Add to `.mise.toml` `[env]` section                                      |
| semantic-release not configured        | Create `.releaserc.yml` (see cc-skills reference)                        |
| **semantic-release Errors**            |                                                                          |
| `@semantic-release/git` file explosion | Patch `git.js` (see Known Issue above)                                   |
| Partial bump (no tag created)          | Manual recovery (see Partial Semantic-Release Recovery above)            |
| `successCmd` failure (exit 1)          | Non-fatal if tag exists; check `git tag -l vX.Y.Z`                       |
| **PyPI-Specific Errors**               |                                                                          |
| `UV_PUBLISH_TOKEN` not set             | Add to `.mise.toml` [env]; store token in `~/.claude/.secrets/`          |
| `scripts/publish-to-pypi.sh` not found | Create using template (see Publishing Task Implementation above)         |
| `twine upload` 403 Forbidden           | Check PyPI token permissions (must be account-wide, not project)         |
| Package already exists on PyPI         | Non-fatal; release continues (tag still created on GitHub)               |
| **Crates.io-Specific Errors**          |                                                                          |
| `CARGO_REGISTRY_TOKEN` not set         | Add to `.mise.toml` [env]; get token from <https://crates.io/me>         |
| `cargo publish` timeout                | Retry with `mise run release:crates` (non-fatal, tag already set)        |
| Crate already published on crates.io   | Non-fatal; check version in `Cargo.toml` for next release                |
| Workspace publish order error          | Use `cargo publish --workspace` (Rust 1.90+) — handles ordering natively |
| Missing crate on crates.io             | Check `publish = false` — crate may need publishing or its dep does      |
| **Postflight Errors**                  |                                                                          |
| Uncommitted changes after release      | Release process left side-effects; commit or reset the changes           |
| Unpushed commits after release         | `git push origin main` — release tags reference remote commits           |
| Lockfile drift after release           | Auto-reset by postflight; if persistent, check build scripts             |
