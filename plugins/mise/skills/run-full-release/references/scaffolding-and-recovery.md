**Skill**: [run-full-release](../SKILL.md)

# Scaffolding & Recovery

Reference for repos without release tasks, error recovery, and known issues.

---

## If Release Tasks NOT FOUND → Audit & Scaffold

Conduct a thorough audit of the repository to scaffold idiomatic release tasks.

### Audit Checklist

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

### Read Reference Templates

Read these files from the cc-skills marketplace for the canonical 5-phase release pattern:

```
Read: $HOME/.claude/plugins/marketplaces/cc-skills/docs/RELEASE.md
```

Also examine cc-skills' own release tasks as a working template:

```bash
ls $HOME/.claude/plugins/marketplaces/cc-skills/.mise/tasks/release/
```

### Scaffold `.mise/tasks/release/`

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

**Lockfile cleanup** is mandatory in both `preflight` and `full`. Commands like `uv run`, `npm install`, `cargo build` during release phases modify lockfiles as an artifact — these must be reset:

```bash
git diff --name-only | grep -E '^(uv\.lock|package-lock\.json|Cargo\.lock|bun\.lockb|yarn\.lock|pnpm-lock\.yaml)$' | xargs -r git checkout --
```

### Task Orchestration (release:full)

The `release:full` task **must** use conditional task dependencies to handle optional PyPI/crates.io. See [task-implementations.md](./task-implementations.md) for full code.

### Ensure SSoT via mise

- All credentials must be in `.mise.toml` `[env]` section (not hardcoded in scripts)
- All tool versions must be in `[tools]` section
- Use `read_file()` template function for secrets (e.g., `GH_TOKEN`)

After scaffolding, run `mise run release:full` with the newly created tasks.

---

## Publishing & Postflight Task Implementations

Detailed implementations in [task-implementations.md](./task-implementations.md). Key points:

- **`release:pypi`**: Triggers on `pyproject.toml` + `scripts/publish-to-pypi.sh` or `[tool.maturin]`. Credentials via `.mise.toml [env]`.
- **`release:crates`**: Uses native `cargo publish --workspace` (Rust 1.90+). Never hardcode crate lists.
- **`release:postflight`**: Resets lockfile drift, fails on uncommitted changes or unpushed commits.

---

## Known Issue - `@semantic-release/git` Untracked File Explosion

**Bug**: `@semantic-release/git` v10.x runs `git ls-files -m -o` **without `--exclude-standard`**, listing ALL untracked files including gitignored ones. In repos with large `.venv/` or `node_modules/`, this produces ~100MB of stdout that crashes the plugin.

**Root cause**: `node_modules/@semantic-release/git/lib/git.js` line 12.

**Upstream issues**: [#345](https://github.com/semantic-release/git/issues/345), [#347](https://github.com/semantic-release/git/issues/347), [#107](https://github.com/semantic-release/git/issues/107)

**Fix**: Patch both local and global installations:

```bash
find /opt/homebrew/lib/node_modules $(npm root -g 2>/dev/null) node_modules \
  -path "*/@semantic-release/git/lib/git.js" 2>/dev/null | while read f; do
  if ! grep -q 'exclude-standard' "$f"; then
    sed -i '' "s/\['ls-files', '-m', '-o'\]/['ls-files', '-m', '-o', '--exclude-standard']/" "$f"
    echo "Patched: $f"
  fi
done
```

**Note**: Patch is lost on `npm update` or `brew upgrade`. Re-apply after upgrades.

---

## Partial Semantic-Release Recovery

When semantic-release **partially succeeds** (bumps version files but fails before creating tag):

1. **Detect**: `Cargo.toml`/`package.json` has new version but `git tag -l vX.Y.Z` returns empty
2. **Commit artifacts**: `git add Cargo.toml CHANGELOG.md && git commit -m "chore(release): vX.Y.Z"`
3. **Push**: `git push origin main`
4. **Create tag manually**: `git tag -a vX.Y.Z -m "vX.Y.Z\n\n<release notes>"`
5. **Push tag**: `git push origin vX.Y.Z`
6. **Create GitHub release**: `gh release create vX.Y.Z --title "vX.Y.Z" --notes "<notes>"`
7. **Continue with publish**: `mise run release:crates` and/or `mise run release:pypi`

**Critical**: Do NOT re-run `semantic-release --no-ci` after a partial failure — it will try to bump the version AGAIN.

---

## Post-Release Deploy Reminder

After publishing, deploy to production hosts if applicable. Forgetting to deploy means production runs stale code while monitoring reports version drift.

---

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
