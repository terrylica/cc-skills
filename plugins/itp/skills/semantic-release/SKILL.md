---
name: semantic-release
description: Automates semantic versioning and releases using Node.js semantic-release v25+ for all languages. Use when setting up automated releases, creating shareable configs, or configuring GitHub Actions.
---

# semantic-release

## Overview

Automate semantic versioning and release management using **semantic-release v25+ (Node.js)** following 2025 best practices. Works with **all languages** (JavaScript, TypeScript, Python, Rust, Go, C++, etc.) via the `@semantic-release/exec` plugin. Create shareable configurations for multi-repository setups, initialize individual projects with automated releases, and configure GitHub Actions workflows with OIDC trusted publishing.

**Important**: This skill uses semantic-release (Node.js) exclusively, NOT python-semantic-release, even for Python projects. Rationale: 23.5x larger community, 100x+ adoption, better future-proofing.

## When to Use This Skill

Invoke when:

- Setting up local releases for a new project (any language)
- Creating shareable semantic-release configuration for organization-wide use
- Migrating existing projects to 2025 semantic-release patterns
- Troubleshooting semantic-release setup or version bumps
- Setting up Python projects (use Node.js semantic-release, NOT python-semantic-release)
- Configuring GitHub Actions (optional backup, not recommended as primary due to speed)

## Why Node.js semantic-release

**22,900 GitHub stars** - Large, active community
**1.9M weekly downloads** - Proven adoption
**126,000 projects using it** - Battle-tested at scale
**35+ official plugins** - Rich ecosystem
**Multi-language support** - Works with any language via `@semantic-release/exec`

**Do NOT use python-semantic-release.** It has a 23.5x smaller community (975 vs 22,900 stars), ~100x less adoption, and is not affiliated with the semantic-release organization.

---

## Release Workflow Philosophy: Local-First

**Default approach: Run releases locally, not via GitHub Actions.**

### Why Local Releases

**Primary argument: GitHub Actions is slow**

- ⏱️ GitHub Actions: 2-5 minute wait for release to complete
- ⚡ Local release: Instant feedback and file updates
- 🔄 Immediate workflow continuity - no waiting for CI/CD

**Additional benefits:**

- ✅ **Instant local file sync** - `package.json`, `CHANGELOG.md`, tags updated immediately
- ✅ **No pull required** - Continue working without `git pull` after release
- ✅ **Dry-run testing** - `npm run release:dry` to preview changes before release
- ✅ **Offline capable** - Can release without CI/CD dependency
- ✅ **Faster iteration** - Debug release issues immediately, not through CI logs

### GitHub Actions: Optional Backup Only

GitHub Actions workflows are provided as **optional automation**, not the primary method:

- Use for team consistency if required
- Backup if local environment unavailable
- **Not recommended as primary workflow due to speed**

### Authentication Setup

```bash
gh auth login
# Browser authentication once
# Credentials stored in keyring
# All future releases: zero manual intervention
```

**This is the minimum manual intervention possible** for local semantic-release with GitHub plugin functionality.

### Multi-Account Authentication via mise [env]

For multi-account GitHub setups, use mise `[env]` to set per-directory GH_TOKEN:

```toml
# ~/your-project/.mise.toml
[env]
GH_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/gh-token-accountname') | trim }}"
GITHUB_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/gh-token-accountname') | trim }}"
```

This overrides gh CLI's global authentication, ensuring semantic-release uses the correct account for each directory.

See the [`mise-configuration` skill](../mise-configuration/SKILL.md#github-token-multi-account-patterns) for complete setup.

### Critical Standard: No Testing/Linting in GitHub Actions

**This standard applies to ALL GitHub Actions workflows, not just semantic-release.**

#### Forbidden Workflow Steps

GitHub Actions workflows must NEVER include:

❌ **Test execution**:

```yaml
# ❌ FORBIDDEN - Do not add to any workflow
- run: pytest
- run: npm test
- run: cargo test
- uses: actions/upload-test-results # Implies testing
```

❌ **Linting/Formatting**:

```yaml
# ❌ FORBIDDEN - Do not add to any workflow
- run: ruff check
- run: eslint .
- run: cargo clippy
- run: prettier --check
- run: mypy
```

#### Allowed Workflow Patterns

✅ **Semantic-release** (this workflow):

```yaml
- run: npm run release # Version, changelog, GitHub release only
```

✅ **Security scanning**:

```yaml
- run: npm audit signatures
- uses: github/codeql-action/analyze@v3
```

✅ **Deployment**:

```yaml
- run: docker build && docker push
- run: aws s3 sync ./build s3://bucket
```

✅ **Dependency updates**:

```yaml
- uses: dependabot/fetch-metadata@v2
```

#### Enforcement

**Documentation-based**: This standard is enforced through CLAUDE.md instructions, not pre-commit hooks.

When creating or modifying GitHub Actions workflows, Claude Code will check CLAUDE.md and this skill to ensure compliance.

---

## Separation of Concerns (4-Level Architecture)

semantic-release configuration follows a hierarchical, composable pattern:

**Level 1: Skill** - `${CLAUDE_PLUGIN_ROOT}/skills/semantic-release/` (Generic templates, system-wide tool)
**Level 2: User Config** - `~/semantic-release-config/` (`@username/semantic-release-config`)
**Level 3: Organization Config** - npm registry (`@company/semantic-release-config`)
**Level 4: Project Config** - `.releaserc.yml` in project root

### Configuration Precedence

```
Level 4 (Project) → overrides → Level 3 (Org) → overrides → Level 2 (User) → overrides → Defaults
```

---

## Conventional Commits Format

semantic-release analyzes commit messages to determine version bumps:

```
<type>(<scope>): <subject>
```

### Version Bump Rules (Default)

- `feat:` → MINOR version bump (0.1.0 → 0.2.0)
- `fix:` → PATCH version bump (0.1.0 → 0.1.1)
- `BREAKING CHANGE:` or `feat!:` → MAJOR version bump (0.1.0 → 1.0.0)
- `docs:`, `chore:`, `style:`, `refactor:`, `perf:`, `test:` → No version bump (by default)

### Release Notes Visibility (Important)

**Warning**: The `@semantic-release/release-notes-generator` (Angular preset) only includes these types in release notes:

- `feat:` → **Features** section
- `fix:` → **Bug Fixes** section
- `perf:` → **Performance Improvements** section

Other types (`docs:`, `chore:`, `refactor:`, etc.) trigger releases when configured but **do NOT appear in release notes**.

**Recommendation**: For documentation changes that should be visible in release notes, use:

```
fix(docs): description of documentation improvement
```

This ensures the commit appears in the "Bug Fixes" section while still being semantically accurate (fixing documentation gaps is a fix).

### Marketplace Plugin Configuration (Always Bump)

For Claude Code marketplace plugins, **every change requires a version bump** for users to receive updates.

**Option A: Shareable Config (if published)**

```yaml
# .releaserc.yml
extends: "@terryli/semantic-release-config/marketplace"
```

**Option B: Inline Configuration**

```yaml
# .releaserc.yml
plugins:
  - - "@semantic-release/commit-analyzer"
    - releaseRules:
        # Marketplace plugins require version bump for ANY change
        - { type: "docs", release: "patch" }
        - { type: "chore", release: "patch" }
        - { type: "style", release: "patch" }
        - { type: "refactor", release: "patch" }
        - { type: "test", release: "patch" }
        - { type: "build", release: "patch" }
        - { type: "ci", release: "patch" }
```

**Result after configuration:**

| Commit Type                                                        | Release Type       |
| ------------------------------------------------------------------ | ------------------ |
| `feat:`                                                            | minor (default)    |
| `fix:`, `perf:`, `revert:`                                         | patch (default)    |
| `docs:`, `chore:`, `style:`, `refactor:`, `test:`, `build:`, `ci:` | patch (configured) |

**Why marketplace plugins need this**: Plugin updates are distributed via version tags. Without a version bump, users running `/plugin update` see no changes even if content was modified.

### MANDATORY: Every Release Must Increment Version

**Pre-release validation**: Before running semantic-release, verify releasable commits exist since last tag. A release without version increment is invalid.

**Autonomous check sequence**:

1. List commits since last tag: compare HEAD against latest version tag
2. Identify commit types: scan for `feat:`, `fix:`, or `BREAKING CHANGE:` prefixes
3. If NO releasable commits found → **STOP** - do not proceed with release
4. Inform user: "No version-bumping commits since last release. Use `feat:` or `fix:` prefix for releasable changes."

**Commit type selection guidance**:

- Use `fix:` for any change that improves existing behavior (bug fixes, enhancements, documentation corrections that affect usage)
- Use `feat:` for new capabilities or significant additions
- Reserve `chore:`, `docs:`, `refactor:` for changes that truly don't warrant a release

**Why this matters**: A release without version increment creates confusion - users cannot distinguish between releases, package managers may cache old versions, and changelog entries become meaningless.

### Examples

**Feature (MINOR)**:

```
feat: add BigQuery data source support
```

**Bug Fix (PATCH)**:

```
fix: correct timestamp parsing for UTC offsets
```

**Breaking Change (MAJOR)**:

```
feat!: change API to require authentication

BREAKING CHANGE: All API calls now require API key in Authorization header.
```

---

## ADR/Design Spec Linking

Link Architecture Decision Records (ADRs) and Design Specs in release notes automatically.

### Quick Setup

**Step 1**: Set environment variable before running semantic-release:

```bash
export ADR_NOTES_SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}/skills/semantic-release/scripts/generate-adr-notes.mjs"
```

**Step 2**: Add to `.releaserc.yml` before `@semantic-release/changelog`:

```yaml
- - "@semantic-release/exec"
  - generateNotesCmd: 'node "$ADR_NOTES_SCRIPT" ${lastRelease.gitTag}'
```

**Why?** `@semantic-release/exec` uses lodash templates which interpret `${...}` as JavaScript. Using `$VAR` (no braces) bypasses lodash and lets bash expand it.

### How It Works

The script detects ADRs via:

1. **Git diff**: Files changed in `docs/adr/*.md` and `docs/design/*/spec.md`
2. **Commit parsing**: References like `ADR: 2025-12-06-slug` in commit messages

Full HTTPS URLs are generated (required for GitHub release pages).

See [ADR Release Linking](./references/adr-release-linking.md) for detailed configuration.

---

## Quick Start

### Step 1: Verify Account (HTTPS-First)

**CRITICAL**: For multi-account GitHub setups, verify GH_TOKEN is set for the current directory.

**Quick verification** (2025-12-19+):

```bash
# Verify git remote is HTTPS
git remote get-url origin
# Expected: https://github.com/...

# Verify GH_TOKEN is set via mise [env]
gh api user --jq '.login'
# Expected: correct account for this directory
```

**If remote is SSH** (legacy):

```bash
# Convert to HTTPS
git-ssh-to-https
```

**If wrong account**:

Check mise [env] configuration:

```bash
# Verify mise config
mise env | grep GH_TOKEN
```

See [Authentication Guide](./references/authentication.md) for HTTPS-first setup.

### Step 2: Initialize Project

```bash
cd /path/to/project
# Environment-agnostic path
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
"$PLUGIN_DIR/skills/semantic-release/scripts/init_project.sh" --user
# Or --org mycompany/semantic-release-config
# Or --inline
```

### Step 3: Run Release Locally

Follow the [Local Release Workflow](./references/local-release-workflow.md) for the complete process.

**One-time setup (recommended for macOS)**:

```bash
# Install globally to avoid macOS Gatekeeper issues with npx
npm install -g semantic-release @semantic-release/changelog @semantic-release/git @semantic-release/github @semantic-release/exec

# Clear quarantine (required on macOS after install or node upgrade)
xattr -r -d com.apple.quarantine ~/.local/share/mise/installs/node/
```

**Quick commands**:

```bash
# Dry-run first (no changes)
/usr/bin/env bash -c 'GITHUB_TOKEN=$(gh auth token) semantic-release --no-ci --dry-run'

# Create actual release
/usr/bin/env bash -c 'GITHUB_TOKEN=$(gh auth token) semantic-release --no-ci'
```

> **Note**: Use `semantic-release` directly (not `npx semantic-release`) to avoid macOS Gatekeeper blocking `.node` native modules. See [Troubleshooting](./references/troubleshooting.md#macos-gatekeeper-blocks-node-files).

**Files updated instantly**: `package.json`, `CHANGELOG.md`, Git tags, GitHub release.

The workflow guides you through:

- Prerequisites verification and resolution
- Remote sync with SSH→HTTPS fallback
- Issue diagnosis and autonomous resolution
- Post-release state verification

### Step 4: PyPI Publishing (Python Projects)

**For Python packages**: semantic-release handles versioning, use the [`pypi-doppler`](../pypi-doppler/SKILL.md) skill for local PyPI publishing.

**Quick setup**:

```bash
# Install Doppler CLI for secure token management
brew install dopplerhq/cli/doppler

# Store token in Doppler (one-time)
doppler secrets set PYPI_TOKEN='your-pypi-token' --project claude-config --config prd

# Copy publish script from pypi-doppler skill (environment-agnostic)
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
cp "$PLUGIN_DIR/skills/pypi-doppler/scripts/publish-to-pypi.sh" scripts/
chmod +x scripts/publish-to-pypi.sh

# After semantic-release creates GitHub release:
./scripts/publish-to-pypi.sh  # 30 seconds vs 3-5 minutes with GitHub Actions
```

See [`pypi-doppler` skill](../pypi-doppler/SKILL.md) for complete workflow with CI detection guards.

### Step 5: GitHub Actions (Optional)

**Only if you want CI/CD backup** (not recommended as primary due to 2-5 minute delay):

Repository Settings → Actions → General → Workflow permissions → Enable "Read and write permissions"

---

## Reference Documentation

For detailed information, see:

- [Authentication](./references/authentication.md) - **START HERE** - SSH keys, GitHub CLI web auth (avoid manual tokens)
- [Local Release Workflow](./references/local-release-workflow.md) - Step-by-step release process with issue resolution
- [Workflow Patterns](./references/workflow-patterns.md) - Personal, Team, and Standalone project patterns
- [Version Alignment](./references/version-alignment.md) - Git tags as SSoT, manifest patterns, runtime version access
- [2025 Updates](./references/2025-updates.md) - v25 changelog, Node.js 24+, OIDC trusted publishing, plugin versions
- [Python Projects with Node.js semantic-release](./references/python-projects-nodejs-semantic-release.md) - Complete guide for Python package automation with @semantic-release/exec
- [`pypi-doppler` skill](../pypi-doppler/SKILL.md) - Local PyPI publishing with Doppler credentials and CI detection guards
- [Monorepo Support](./references/monorepo-support.md) - pnpm/npm workspaces configuration
- [Troubleshooting](./references/troubleshooting.md) - Common issues and solutions
- [ADR Release Linking](./references/adr-release-linking.md) - Auto-link ADRs and Design Specs in release notes
- [Resources](./references/resources.md) - Scripts, templates, and asset documentation
