# Task Implementation Reference

> Detailed implementations for `release:pypi`, `release:crates`, and `release:postflight` tasks.
> Referenced from SKILL.md — move here to keep SKILL.md under 500 lines.

## `release:pypi` (Optional - Only if Python Package)

**Triggers**: `pyproject.toml` exists AND (`scripts/publish-to-pypi.sh` exists OR `[tool.maturin]` present)

**Implementation**:

```bash
#!/usr/bin/env bash
#MISE description="Phase 2b: Publish to PyPI via uv publish (pure Python) or twine (maturin wheels)"
set -euo pipefail

if [[ -x "scripts/publish-to-pypi.sh" ]]; then
    # Use custom script (handles maturin, 1Password tokens, service accounts, etc.)
    ./scripts/publish-to-pypi.sh
elif grep -q '\[tool\.maturin\]' pyproject.toml; then
    # Maturin project: wheels built by release:build-all
    echo "Publishing maturin wheels to PyPI..."
    echo "ERROR: release:pypi requires scripts/publish-to-pypi.sh"
    exit 1
else
    # Pure Python: use uv publish with UV_PUBLISH_TOKEN
    echo "Publishing pure Python package to PyPI..."
    UV_PUBLISH_TOKEN="${UV_PUBLISH_TOKEN:-}" uv publish || {
        echo "⚠ uv publish failed - set UV_PUBLISH_TOKEN in .mise.toml [env]"
        return 1
    }
fi
```

**Credentials (via `.mise.toml [env]`)**:

```toml
[env]
# PyPI token (supports both uv and twine)
UV_PUBLISH_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/pypi-token') | trim }}"

# For 1Password service account (alternative):
# OP_SERVICE_ACCOUNT_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/op-service-account-token') | trim }}"
```

**Post-Publish Verification** (add to `release:verify`):

```bash
PACKAGE_NAME=$(grep '^name = ' pyproject.toml | sed 's/name = "\(.*\)"/\1/' | head -1)
CURRENT_VERSION=$(grep '^version = ' pyproject.toml | sed 's/version = "\(.*\)"/\1/' | head -1)

echo "Checking PyPI for ${PACKAGE_NAME} v${CURRENT_VERSION}..."
if curl -s "https://pypi.org/pypi/${PACKAGE_NAME}/${CURRENT_VERSION}/json" | grep -q "version"; then
    echo "✓ Published to PyPI"
else
    echo "⚠ Still propagating to PyPI (check in 30 seconds)"
fi
```

## `release:crates` (Optional - Only if Rust Workspace)

**Triggers**: `Cargo.toml` exists AND `[workspace.package]` present AND `rust-version >= 1.90`

**Use native `cargo publish --workspace`** (stabilized in Rust 1.90, Sept 2025). This single command:

- Auto-discovers all publishable crates (skips `publish = false`)
- Topologically sorts by dependency order
- Pre-validates the entire workspace builds correctly before publishing any crate
- Handles crates.io index propagation between dependent publishes

**Never** hardcode crate lists, iterate `crates/*/` in filesystem order, or write bespoke topological sort scripts. All of these are superseded by native Cargo support.

**Implementation**:

```bash
#!/usr/bin/env bash
#MISE description="Phase 2c: Publish Rust crates to crates.io (native workspace publish)"
set -euo pipefail

if [[ -z "${CARGO_REGISTRY_TOKEN:-}" ]]; then
    echo "ERROR: CARGO_REGISTRY_TOKEN not set in .mise.toml [env]"
    exit 1
fi

cargo publish --workspace

echo "✓ Crates.io publishing complete"
```

**Preflight Gate** (add to `release:preflight`):

```bash
cargo publish --workspace --dry-run
```

**Credentials (via `.mise.toml [env]`)**:

```toml
[env]
CARGO_REGISTRY_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/crates-io-token') | trim }}"
```

**Post-Publish Verification** (add to `release:verify`):

```bash
CRATES=$(cargo metadata --no-deps --format-version 1 | \
  jq -r '.packages[] | select(.source == null) | select(.publish == null) | select(.name | endswith("-py") | not) | .name')
for crate in $CRATES; do
    echo "Checking crates.io for ${crate} v${CRATE_VERSION}..."
    if curl -s "https://crates.io/api/v1/crates/${crate}/${CRATE_VERSION}" | grep -q "version"; then
        echo "✓ ${crate} published"
    else
        echo "⚠ ${crate} still propagating (check in 30 seconds)"
    fi
done
```

## `release:postflight` (Mandatory — All Repos)

**Purpose**: Validates that the release process left the repository in a clean state.

**Implementation**:

```bash
#!/usr/bin/env bash
#MISE description="Phase 5: Post-release git state validation"
set -euo pipefail

ERRORS=0

# 1. Reset lockfile drift (artifact from cargo build, uv run, npm install, etc.)
LOCKFILE_DRIFT=$(git diff --name-only | grep -E '^(uv\.lock|package-lock\.json|Cargo\.lock|bun\.lockb|yarn\.lock|pnpm-lock\.yaml)$' || true)
if [[ -n "$LOCKFILE_DRIFT" ]]; then
    echo "Lockfile drift detected — resetting (build artifact)"
    echo "$LOCKFILE_DRIFT" | xargs git checkout --
fi

# 2. Check for uncommitted changes (after lockfile reset)
DIRTY=$(git status --porcelain)
if [[ -n "$DIRTY" ]]; then
    echo "FAIL: Uncommitted changes detected:"
    echo "$DIRTY" | head -20
    ERRORS=$((ERRORS + 1))
fi

# 3. Check for unpushed commits
UNPUSHED=$(git log --oneline @{u}..HEAD 2>/dev/null || echo "")
if [[ -n "$UNPUSHED" ]]; then
    echo "FAIL: Unpushed commits:"
    echo "$UNPUSHED"
    ERRORS=$((ERRORS + 1))
fi

if [[ $ERRORS -gt 0 ]]; then
    echo "Postflight FAILED ($ERRORS issue(s))"
    exit 1
fi
echo "✓ Postflight PASSED — clean landing"
```

**Key design decisions**:

- **Lockfile reset is automatic**: Build artifacts, not intentional changes
- **Uncommitted changes are fatal**: Release process left side-effects
- **Unpushed commits are fatal**: Tags reference remote commits
- **Runs after verify**: Verify checks artifacts exist, postflight checks local state

**Repo-specific extensions**: Add custom checks after the 3 core checks:

- Native app repos: Verify `.app` bundle is signed
- Workspace repos: Verify all sub-crate versions match
- Monorepos: Verify all changed packages were published
