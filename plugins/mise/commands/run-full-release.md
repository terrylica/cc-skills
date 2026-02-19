---
name: run-full-release
description: "Run the current repo's mise release pipeline with auto-scaffolding. TRIGGERS - mise release, full release, version bump, release automation, mise run release."
allowed-tools: Read, Bash, Glob, Grep, Write, Edit, AskUserQuestion
argument-hint: "[--dry] [--status]"
model: haiku
---

# /mise:run-full-release

Run the current repo's mise release pipeline. Self-bootstrapping: if no release tasks exist, audit the repo and scaffold idiomatic release tasks first.

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

6. Route by flags:
   - `--dry` → `mise run release:dry`
   - `--status` → `mise run release:status`
   - No flags → `mise run release:full`

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

Read these files from the cc-skills marketplace for the canonical 4-phase release pattern:

```
Read: $HOME/.claude/plugins/marketplaces/cc-skills/docs/RELEASE.md
```

Also examine cc-skills' own release tasks as a working template:

```bash
ls $HOME/.claude/plugins/marketplaces/cc-skills/.mise/tasks/release/
```

#### Scaffold `.mise/tasks/release/`

Create the release task directory and files customized to THIS repo:

| Task        | Always                        | Repo-Specific Additions                                 |
| ----------- | ----------------------------- | ------------------------------------------------------- |
| `_default`  | Help/navigation               | —                                                       |
| `preflight` | Clean dir, auth, branch check | Plugin validation, build tool checks                    |
| `version`   | semantic-release              | Repo-specific `.releaserc.yml` plugins                  |
| `sync`      | Git push                      | PyPI publish, marketplace sync, cache clear, hook sync  |
| `verify`    | Tag + release check           | Verify artifacts (wheels, packages, published versions) |
| `full`      | Orchestrator (`depends`)      | Include all repo-specific phases                        |
| `dry`       | `semantic-release --dry-run`  | —                                                       |
| `status`    | Current version info          | —                                                       |

#### Ensure SSoT via mise

- All credentials must be in `.mise.toml` `[env]` section (not hardcoded in scripts)
- All tool versions must be in `[tools]` section
- All thresholds/configs as env vars with fallback defaults
- Use `read_file()` template function for secrets (e.g., `GH_TOKEN`)

#### After Scaffolding

Run `mise run release:full` with the newly created tasks.

## Error Recovery

| Error                           | Resolution                                            |
| ------------------------------- | ----------------------------------------------------- |
| `mise` not found                | Install: `curl https://mise.run \| sh`                |
| No release tasks                | Scaffold using audit above                            |
| Working dir not clean           | Review, commit, or stash all changes autonomously     |
| Lockfile drift (uv.lock etc.)   | `git checkout -- uv.lock` (artifact, not intentional) |
| Unpushed commits                | `git push origin main` before release                 |
| Not on main branch              | `git checkout main`                                   |
| No releasable commits           | Create a `feat:` or `fix:` commit first               |
| Missing GH_TOKEN                | Add to `.mise.toml` `[env]` section                   |
| semantic-release not configured | Create `.releaserc.yml` (see cc-skills reference)     |
