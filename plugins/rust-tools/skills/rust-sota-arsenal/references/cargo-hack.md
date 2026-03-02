# cargo-hack

Feature flag combination testing for Rust crates. Essential for library authors to verify that all feature combinations compile and pass tests.

## Installation

```bash
cargo install cargo-hack
```

## Why cargo-hack

Rust crates often expose feature flags, but testing only the default combination misses:

- Features that conflict with each other
- Features that depend on missing optional deps
- Code that compiles only with specific flag combinations
- `#[cfg(feature = "...")]` blocks that are never tested

## Core Commands

### Test Every Feature Individually

```bash
# Check each feature alone (no default features + one at a time)
cargo hack check --each-feature

# Same but also run tests
cargo hack test --each-feature
```

This runs `cargo check` once per feature, plus once with no features and once with all features.

### Feature Powerset Testing

```bash
# Test ALL feature combinations (2^n runs — use with care)
cargo hack check --feature-powerset

# Limit depth to avoid combinatorial explosion
cargo hack check --feature-powerset --depth 2

# Exclude dev-deps (faster, check-only)
cargo hack check --feature-powerset --no-dev-deps
```

**Warning**: With N features, `--feature-powerset` runs 2^N times. Use `--depth` to cap:

- `--depth 1` = each feature alone (~N runs)
- `--depth 2` = each pair (~N^2/2 runs)
- `--depth 3` = each triple (~N^3/6 runs)

### Skip Specific Features

```bash
# Skip features that are known-incompatible
cargo hack check --each-feature --skip feature-a,feature-b

# Skip features that need external deps (e.g., system libs)
cargo hack check --each-feature --skip ffi,gpu
```

### Workspace Support

```bash
# Check all crates in workspace
cargo hack check --each-feature --workspace

# Specific package
cargo hack check --each-feature -p my-crate
```

## CI Integration

### GitHub Actions

```yaml
- name: Feature flag testing
  run: |
    cargo install cargo-hack
    cargo hack check --feature-powerset --depth 2 --no-dev-deps
```

### Recommended CI Matrix

```yaml
jobs:
  feature-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - name: Install cargo-hack
        run: cargo install cargo-hack
      - name: Check feature powerset
        run: cargo hack check --feature-powerset --depth 2 --no-dev-deps
      - name: Test each feature
        run: cargo hack test --each-feature
```

## Common Patterns

### Library Crate Validation

```bash
# Full validation before publish
cargo hack check --feature-powerset --no-dev-deps
cargo hack test --each-feature
cargo hack doc --each-feature --no-deps
```

### MSRV (Minimum Supported Rust Version) Check

```bash
# Check MSRV with all feature combinations
cargo +1.70.0 hack check --feature-powerset --depth 2
```

### Conditional Compilation Audit

```bash
# Find features that break compilation when alone
cargo hack check --each-feature 2>&1 | grep "error"
```

## Flags Reference

| Flag                 | Purpose                            |
| -------------------- | ---------------------------------- |
| `--each-feature`     | Test each feature individually     |
| `--feature-powerset` | Test all feature combinations      |
| `--depth N`          | Limit powerset depth               |
| `--no-dev-deps`      | Skip dev-dependencies              |
| `--skip FEATURES`    | Comma-separated features to skip   |
| `--workspace`        | Check all workspace crates         |
| `--include-features` | Only test these features           |
| `--group-features`   | Treat listed features as one group |
| `--version-range`    | Test across Rust versions (MSRV)   |

## Tips

- Start with `--depth 2` — it catches most real issues without combinatorial explosion
- Use `--no-dev-deps` for `check` (faster) and full deps for `test`
- Combine with `cargo-semver-checks` for pre-publish validation
- Run `cargo hack` in CI on every PR for library crates
