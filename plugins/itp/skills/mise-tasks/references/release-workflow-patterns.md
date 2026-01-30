**Skill**: [mise-tasks](../SKILL.md) | **Related**: [semantic-release](../../semantic-release/SKILL.md) | [pypi-doppler](../../pypi-doppler/SKILL.md)

# Release Workflow Patterns for mise Tasks

Patterns and anti-patterns for orchestrating multi-phase release workflows with mise `[tasks]`. Based on real-world failures in Rust+Python (maturin) projects.

---

## The Core Problem: Unlinked Pipeline Stages

Release workflows have natural phases that must execute in order. When phases are defined as independent mise tasks without `depends`, nothing prevents running them out of order:

```toml
# ❌ BROKEN: publish has no dependency on build
[tasks."release:build-all"]
depends = ["release:version"]
run = "maturin build --release"

[tasks."release:pypi"]
# No depends! Can run before build-all completes
run = "./scripts/publish-to-pypi.sh"
```

**Failure mode**: Running `mise run release:pypi` before `mise run release:build-all` fails with "no wheels found". The publish script has a runtime check, but the task system doesn't enforce ordering — the failure happens late instead of being prevented by the DAG.

---

## Pattern 1: Full DAG with `depends`

**Use when**: You want a single command (`mise run release:full`) that does everything.

```toml
# Phase 1: Preflight
[tasks."release:preflight"]
description = "Validate prerequisites"
run = """
git update-index --refresh -q || true
[ -z "$(git status --porcelain)" ] || { echo "FAIL: dirty"; exit 1; }
[ "$(git branch --show-current)" = "main" ] || { echo "FAIL: not main"; exit 1; }
"""

# Phase 2: Sync
[tasks."release:sync"]
description = "Synchronize with remote"
depends = ["release:preflight"]
run = """
git pull --rebase origin main
git push origin main
"""

# Phase 3a: Version bump
[tasks."release:version"]
description = "Bump version via semantic-release"
depends = ["release:sync"]
run = "./scripts/semantic-release.sh"

# Phase 3b: Build (after version bump sets new version)
[tasks."release:build-all"]
description = "Build all platform artifacts"
depends = ["release:version"]
run = """
mise run release:macos-arm64
mise run release:linux
mise run release:sdist
# Consolidate artifacts to dist/
VERSION=$(grep '^version' Cargo.toml | head -1 | sed 's/.*= "\\(.*\\)"/\\1/')
cp -n target/wheels/*-${VERSION}-*.whl dist/ 2>/dev/null || true
cp -n target/wheels/*-${VERSION}.tar.gz dist/ 2>/dev/null || true
"""

# Phase 4: Smoke test (runs after build)
[tasks.smoke]
description = "Verify built artifacts"
depends = ["smoke:import", "smoke:process"]

# Phase 5: Postflight verification
[tasks."release:postflight"]
description = "Verify release state"
depends = ["smoke", "release:build-all"]
run = """
echo "Found $(find dist/ -name '*.whl' | wc -l | tr -d ' ') wheel(s)"
"""

# Phase 6: Publish (depends on build — CRITICAL)
[tasks."release:pypi"]
description = "Publish to PyPI"
depends = ["release:build-all"]
run = "./scripts/publish-to-pypi.sh"

# Orchestrator: single command for everything
[tasks."release:full"]
description = "Full release: version → build → smoke → publish"
depends = ["release:postflight", "release:pypi"]
run = "echo 'Release complete and published!'"
```

**Dependency DAG**:

```
preflight → sync → version → build-all → postflight ─┐
                                  ↓                    ↓
                            release:pypi ────→ release:full
```

**Key properties**:

- `mise run release:full` runs everything in correct order
- `mise run release:pypi` alone still works — it triggers build-all first
- `mise run release:build-all` alone still works — it triggers version first
- Every standalone invocation is safe because `depends` enforces prerequisites

---

## Pattern 2: Selective Re-Run with Shared Guards

**Use when**: You need to re-run individual phases (e.g., rebuild after fixing a compile error) without re-running the entire chain.

```toml
# Guard: check that version was bumped (artifact exists)
[tasks._guard-version-bumped]
hide = true
run = """
TAG=$(git describe --tags --exact-match HEAD 2>/dev/null || true)
[ -n "$TAG" ] || { echo "FAIL: HEAD is not tagged. Run release:version first."; exit 1; }
"""

# Guard: check that wheels exist
[tasks._guard-wheels-exist]
hide = true
run = """
VERSION=$(grep '^version' Cargo.toml | head -1 | sed 's/.*= "\\(.*\\)"/\\1/')
COUNT=$(find dist/ -name "*-${VERSION}-*.whl" 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -gt 0 ] || { echo "FAIL: No wheels for v${VERSION}. Run release:build-all first."; exit 1; }
"""

# Publish with guard (not depends on build)
[tasks."release:pypi"]
description = "Publish to PyPI (requires pre-built wheels)"
depends = ["_guard-wheels-exist"]
run = "./scripts/publish-to-pypi.sh"
```

**When to use this instead of Pattern 1**: When cross-platform builds are slow (e.g., remote Docker builds) and you want to re-run publish without rebuilding on every invocation.

---

## Anti-Patterns

### 1. Publish Without Build Dependency

```toml
# ❌ No depends — can run in any order
[tasks."release:build-all"]
run = "maturin build"

[tasks."release:pypi"]
run = "./scripts/publish-to-pypi.sh"
```

**Fix**: Add `depends = ["release:build-all"]` to `release:pypi`.

### 2. Missing sdist in Build Chain

```toml
# ❌ Only builds wheels, forgets source distribution
[tasks."release:build-all"]
run = """
mise run release:macos-arm64
mise run release:linux
"""
```

**Fix**: Add `mise run release:sdist` and copy all artifacts to `dist/`.

PyPI requires either a wheel per platform or an sdist for source-only installs. Missing sdist means users on unsupported platforms can't `pip install`.

### 3. Artifact Scatter

```toml
# ❌ Wheels land in different directories
[tasks."release:macos-arm64"]
run = "maturin build"  # → target/wheels/

[tasks."release:linux"]
run = "ssh remote 'maturin build' && scp remote:wheels/*.whl dist/"  # → dist/

[tasks."release:pypi"]
run = "uv publish"  # Looks in dist/ only
```

**Fix**: `release:build-all` should consolidate all artifacts into `dist/` after building. The publish step should only need to look in one place.

### 4. Orchestrator as Pass-Through

```toml
# ❌ release:full just prints a message, doesn't enforce anything
[tasks."release:full"]
depends = ["release:postflight"]
run = "echo 'Done! Now run: mise run release:pypi'"
```

**Fix**: Include `release:pypi` in the `depends` array so `release:full` is truly complete:

```toml
[tasks."release:full"]
depends = ["release:postflight", "release:pypi"]
run = "echo 'Released and published!'"
```

---

## Checklist: Release Task Audit

When reviewing a release workflow in `.mise.toml`:

- [ ] Every phase task has `depends` on its prerequisites
- [ ] `release:pypi` (or equivalent publish) depends on build
- [ ] `release:build-all` includes sdist, not just wheels
- [ ] All build artifacts are consolidated to a single directory (`dist/`)
- [ ] `release:full` includes all phases including publish in its dependency chain
- [ ] Standalone invocation of any task is safe (prerequisites enforced by DAG)
- [ ] Version bump happens before build (so artifacts have correct version)

---

## Real-World Example: rangebar-py

The rangebar-py project (Rust+Python via maturin) hit the "publish without build" anti-pattern in production:

1. `mise run release:pypi` was called before wheels were built
2. The publish script detected "no wheels found" and failed
3. Wheels were built manually, then publish was re-run successfully
4. Both success and failure notifications arrived, causing confusion

**Root cause**: `release:pypi` had no `depends` — it was designed as a "manual step after `release:full`" but nothing enforced that ordering.

**Fix**: Added `depends = ["release:build-all"]` to `release:pypi` and included `release:pypi` in `release:full`'s dependency chain.

**Lesson**: If two tasks must always run in a specific order, use `depends`. "Manual step after X" is not enforcement — it's documentation that gets ignored under time pressure.
