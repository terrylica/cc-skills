---
name: run-full-release
description: "Run the current repo's mise release pipeline, or bootstrap one if missing. Use when user wants to release, version bump, publish a package, or set up release automation for a new repo. Detects ecosystem (Python/Rust/Node/mixed) and scaffolds individualized mise release tasks."
allowed-tools: Read, Bash, Glob, Grep, Write, Edit, AskUserQuestion
argument-hint: "[--dry] [--status]"
---

# /mise:run-full-release

Run the current repo's mise release pipeline — or bootstrap one if it doesn't exist yet.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Step 1: Detect Existing Release Tasks

```bash
mise tasks ls 2>/dev/null | grep -i release
```

**If tasks exist** → skip to [Step 3: Execute](#step-3-execute).
**If tasks NOT found** → continue to Step 2.

## Step 2: Bootstrap Release Workflow

This step scaffolds an individualized release pipeline for THIS repo. Every repo is different — do not copy templates verbatim. Audit first, then scaffold what fits.

### 2a. Audit the Repository

Run all of these to understand what this repo needs:

```bash
# Ecosystem detection
ls pyproject.toml Cargo.toml package.json setup.py 2>/dev/null

# Existing mise config
cat .mise.toml 2>/dev/null || cat mise.toml 2>/dev/null

# Existing release infra (semantic-release, Makefile, GitHub Actions)
ls .releaserc* release.config.* 2>/dev/null
ls .github/workflows/*release* 2>/dev/null
grep -i release Makefile 2>/dev/null

# Credentials already configured
grep -E 'GH_TOKEN|GITHUB_TOKEN|UV_PUBLISH_TOKEN|CARGO_REGISTRY_TOKEN|NPM_TOKEN' .mise.toml mise.toml 2>/dev/null
```

### 2b. Read the Reference Implementation

Read cc-skills' own release tasks as a working example — adapt, don't copy:

```bash
ls $HOME/.claude/plugins/marketplaces/cc-skills/.mise/tasks/release/
```

Also read: `$HOME/.claude/plugins/marketplaces/cc-skills/docs/RELEASE.md`

### 2c. Scaffold `.mise/tasks/release/`

Create only the tasks this repo actually needs. The 5-phase pattern is:

| Phase         | Task         | Purpose                                          | Required? |
| ------------- | ------------ | ------------------------------------------------ | --------- |
| 1. Preflight  | `preflight`  | Clean dir, auth, branch check                    | Always    |
| 2. Version    | `version`    | `semantic-release` (or repo-specific versioning) | Always    |
| 3. Publish    | `pypi`       | `uv publish` or custom script                    | If Python |
|               | `crates`     | `cargo publish --workspace` (Rust 1.90+)         | If Rust   |
|               | `npm`        | `npm publish`                                    | If Node   |
| 4. Verify     | `verify`     | Tag exists, release exists, artifacts published  | Always    |
| 5. Postflight | `postflight` | Clean git state, no unpushed, lockfile reset     | Always    |

**Orchestrator**: `full` task chains the phases with `depends = [...]`.

**Key rules**:

- Credentials in `.mise.toml` `[env]`, not hardcoded in scripts
- Tool versions in `.mise.toml` `[tools]`
- Lockfile drift reset in both `preflight` and `postflight` (build artifacts, not intentional changes)
- `--dry` and `--status` convenience tasks

### 2d. Known Issues

**`@semantic-release/git` untracked file explosion**: v10.x runs `git ls-files -m -o` without `--exclude-standard`. Patch after install:

```bash
find $(npm root -g 2>/dev/null) node_modules \
  -path "*/@semantic-release/git/lib/git.js" 2>/dev/null | while read f; do
  grep -q 'exclude-standard' "$f" || \
    sed -i '' "s/\['ls-files', '-m', '-o'\]/['ls-files', '-m', '-o', '--exclude-standard']/" "$f"
done
```

**Partial semantic-release failure** (version bumped, no tag): Do NOT re-run semantic-release. Manually create tag + GitHub release, then continue with publish tasks.

**Cargo workspace lockfile cascade** (Rust workspaces with `version.workspace = true`): the perl-based version bump in `prepareCmd` only touches `Cargo.toml`, but the workspace version cascades into every member crate's entry in `Cargo.lock`. The `@semantic-release/git` plugin only stages files listed in `assets`, so without an explicit cargo invocation + `Cargo.lock` in assets, the lockfile stays at the old version. Symptoms: `release:preflight` fails with `M Cargo.lock` after a successful `release:version`, blocking `cargo publish`. Fix in `.releaserc.yml`:

```yaml
- - "@semantic-release/exec"
  - prepareCmd: |
      perl -i -pe 's/^version = ".*"/version = "${nextRelease.version}"/' Cargo.toml
      cargo update --workspace --offline 2>/dev/null \
        || cargo metadata --format-version=1 --offline >/dev/null 2>&1 \
        || true

- - "@semantic-release/git"
  - assets:
      - Cargo.toml
      - Cargo.lock # ← critical: capture the cascading version bump
    message: "chore(release): ${nextRelease.version} [skip ci]"
```

`--offline` keeps the sync local (no registry hit). The `|| true` fallback prevents `prepareCmd` from blocking the release if neither cargo command can run; if the lockfile actually needed sync, the next preflight will catch it.

**mise `depends` runs in parallel** (`release:full` deps `[preflight, version]`): preflight and version race. If version dirties the working tree (e.g. lockfile cascade above), preflight may report failure mid-stream while version still completes, leaving an irreversible tag + GitHub release without `release:crates`/`verify`/`postflight` having run. Recovery: fix the dirty state, then run the remaining phases manually (`release:crates` → `release:verify` → `release:postflight`) — do NOT re-run `release:full`, which would attempt another semantic-release pass.

## Step 3: Execute

```bash
# Pre-release sync
git pull origin main

# Check for unpushed commits
git log --oneline @{u}..HEAD

# Route by flags
mise run release:full    # default
mise run release:dry     # --dry
mise run release:status  # --status
```

If working directory is dirty: commit related changes or stash WIP first. Reset lockfile drift if present:

```bash
git diff --name-only | grep -E '(uv\.lock|package-lock\.json|Cargo\.lock|bun\.lockb)$' | xargs -r git checkout --
```

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
