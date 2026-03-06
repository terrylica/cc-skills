# cargo-hack Extended Reference

Deep reference for feature flag powerset testing. Supplements the [core cargo-hack reference](./cargo-hack.md) with advanced patterns.

## Feature Powerset Explained

Given a crate with features `a`, `b`, `c`, the powerset is every possible combination:

```
(none), a, b, c, a+b, a+c, b+c, a+b+c
```

That is 2^N combinations (8 for 3 features). For a crate with 10 features, that is 1024 runs. The `--depth` flag limits this to manageable subsets.

### Depth Limiter

`--depth N` limits the maximum number of features enabled simultaneously:

| Depth | Combinations Tested             | Runs (10 features) | Catches                 |
| ----- | ------------------------------- | ------------------ | ----------------------- |
| 1     | Each feature alone + none + all | ~12                | Single-feature breakage |
| 2     | All pairs + depth 1             | ~57                | Pairwise conflicts      |
| 3     | All triples + depth 2           | ~187               | Three-way interactions  |
| (all) | Full powerset                   | 1024               | Everything              |

**Recommendation**: `--depth 2` is the sweet spot for most projects. It catches the majority of real-world feature conflicts (pairwise interactions) without combinatorial explosion.

```bash
# Depth 2 — practical default
cargo hack check --feature-powerset --depth 2 --no-dev-deps

# Depth 3 — thorough (use for releases)
cargo hack check --feature-powerset --depth 3 --no-dev-deps
```

## --each-feature vs --feature-powerset

| Mode                 | What it tests                        | When to use                      |
| -------------------- | ------------------------------------ | -------------------------------- |
| `--each-feature`     | No features, each feature alone, all | Quick CI check, per-PR           |
| `--feature-powerset` | Every combination (bounded by depth) | Pre-release, thorough validation |

`--each-feature` is equivalent to `--feature-powerset --depth 1` plus an all-features run.

```bash
# Quick check (CI, every PR)
cargo hack check --each-feature --no-dev-deps

# Thorough check (pre-release)
cargo hack check --feature-powerset --depth 2 --no-dev-deps
```

## Grouping Features

`--group-features` treats multiple features as a single unit, reducing the combinatorial space:

```bash
# "serde" and "serde_json" always go together — treat as one
cargo hack check --feature-powerset --depth 2 \
  --group-features serde,serde_json

# Multiple groups (separated by --group-features flags)
cargo hack check --feature-powerset --depth 2 \
  --group-features serde,serde_json \
  --group-features async-std,async-trait
```

Use grouping when:

- Features are always used together (e.g., `serde` + `serde_json`)
- Features are mutually exclusive backends (group each backend's features)
- You want to reduce CI time by collapsing correlated features

### Include/Exclude Specific Features

```bash
# Only test these features in the powerset
cargo hack check --feature-powerset --include-features a,b,c

# Skip features that need external system deps
cargo hack check --feature-powerset --skip ffi,gpu,system-openssl

# Combine: test only relevant features, skip problematic ones
cargo hack check --feature-powerset --depth 2 \
  --include-features core,alloc,std \
  --skip nightly
```

## CI Sharding

For large projects, shard the powerset across multiple CI jobs:

### GitHub Actions Matrix Sharding

```yaml
jobs:
  feature-check:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        # Shard by depth level
        check-type:
          - name: "No features"
            args: "--no-default-features"
          - name: "Each feature"
            args: "--each-feature --no-dev-deps"
          - name: "Powerset depth 2"
            args: "--feature-powerset --depth 2 --no-dev-deps"
      fail-fast: false
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - name: Install cargo-hack
        run: cargo install cargo-hack
      - name: "${{ matrix.check-type.name }}"
        run: cargo hack check ${{ matrix.check-type.args }}
```

### Workspace Sharding

For large workspaces, shard by package:

```yaml
jobs:
  feature-check:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        package: [crate-a, crate-b, crate-c]
      fail-fast: false
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - name: Install cargo-hack
        run: cargo install cargo-hack
      - name: Check ${{ matrix.package }}
        run: cargo hack check --feature-powerset --depth 2 --no-dev-deps -p ${{ matrix.package }}
```

### Time-Based Sharding Strategy

```yaml
# Fast tier (every PR) — ~2 min
fast-check:
  runs-on: ubuntu-latest
  steps:
    - run: cargo hack check --each-feature --no-dev-deps

# Thorough tier (nightly/weekly) — ~15 min
thorough-check:
  if: github.event_name == 'schedule'
  runs-on: ubuntu-latest
  steps:
    - run: cargo hack check --feature-powerset --depth 3 --no-dev-deps
    - run: cargo hack test --each-feature
```

## Advanced Patterns

### MSRV Verification Across Features

```bash
# Verify MSRV holds for all feature combinations
cargo +1.70.0 hack check --feature-powerset --depth 2 --no-dev-deps
```

### Documentation Build Verification

```bash
# Ensure docs build for every feature combination
cargo hack doc --each-feature --no-deps
```

### Combined with cargo-semver-checks

```bash
# Pre-publish: verify features don't break semver
cargo hack check --feature-powerset --depth 2 --no-dev-deps
cargo semver-checks check-release
```

### Feature Flag Debugging

When a specific combination fails, narrow it down:

```bash
# Test a specific feature combination
cargo hack check --features a,c --no-default-features

# Test with default features plus one
cargo hack check --features default,experimental
```

## Flags Quick Reference

| Flag                    | Purpose                                                   |
| ----------------------- | --------------------------------------------------------- |
| `--each-feature`        | Test each feature individually (+ none + all)             |
| `--feature-powerset`    | Test all feature combinations                             |
| `--depth N`             | Max features enabled simultaneously in powerset           |
| `--no-dev-deps`         | Skip dev-dependencies (faster `check`)                    |
| `--skip FEATURES`       | Comma-separated features to exclude                       |
| `--include-features`    | Only test these features in powerset                      |
| `--group-features`      | Treat listed features as a single unit                    |
| `--workspace`           | Check all workspace crates                                |
| `-p PACKAGE`            | Check specific package                                    |
| `--no-default-features` | Start powerset from zero features                         |
| `--version-range`       | Test across Rust compiler versions (MSRV)                 |
| `--clean-per-run`       | Clean target dir between runs (slower but avoids caching) |

## Tips

- `--depth 2` catches ~95% of real feature interaction bugs
- Always use `--no-dev-deps` with `check` (dev-deps are irrelevant for compilation checks)
- Use `--group-features` to collapse features that are always used together
- Shard large workspaces by package in CI to keep job times under 10 minutes
- Run `--each-feature` on every PR, save `--feature-powerset` for nightly/pre-release
- Combine with `cargo hack test --each-feature` to catch runtime feature issues (not just compilation)
