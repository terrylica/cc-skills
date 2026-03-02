# cargo-semver-checks

Lint your Rust crate's API for semver violations before publishing. Catches accidental breaking changes with hundreds of built-in lints (growing with each release).

## Installation

```bash
cargo install cargo-semver-checks
```

## Why cargo-semver-checks

Publishing a crate with accidental breaking changes (without a major version bump) causes downstream build failures. cargo-semver-checks catches these **before** `cargo publish`:

- Function signature changes
- Removed public items
- Changed trait requirements
- Type alias changes
- Struct field visibility changes
- And many more categories (run `cargo semver-checks --list-lints` for the full list)

## Basic Usage

```bash
# Check against last published version on crates.io
cargo semver-checks check-release

# Check against specific baseline version
cargo semver-checks check-release --baseline-version <baseline>

# Check against a git revision
cargo semver-checks check-release --baseline-rev <tag-or-sha>

# Workspace mode
cargo semver-checks check-release --workspace

# Specific package in workspace
cargo semver-checks check-release -p my-crate
```

## Common Violations

| Violation                          | What Happened           | Semver Impact   |
| ---------------------------------- | ----------------------- | --------------- |
| `function_missing`                 | Public function removed | Major           |
| `function_parameter_count_changed` | Param added/removed     | Major           |
| `struct_missing`                   | Public struct removed   | Major           |
| `struct_pub_field_missing`         | Public field removed    | Major           |
| `enum_variant_missing`             | Enum variant removed    | Major           |
| `trait_method_missing`             | Required method removed | Major           |
| `method_parameter_count_changed`   | Method params changed   | Major           |
| `type_changed_kind`                | e.g., struct → enum     | Major           |
| `function_must_use_added`          | `#[must_use]` added     | Minor (allowed) |
| `inherent_method_must_use_added`   | `#[must_use]` on method | Minor (allowed) |

## Configuration

### In `Cargo.toml`

```toml
[package.metadata.cargo-semver-checks]
# Lint-level overrides
[package.metadata.cargo-semver-checks.lints]
function_missing = "allow"  # Override specific lint
```

### CLI Overrides

```bash
# Allow specific violations
cargo semver-checks check-release --allow function_missing

# Deny specific additions (stricter)
cargo semver-checks check-release --deny function_must_use_added
```

## Pre-Publish Workflow

```bash
# Full pre-publish check
cargo semver-checks check-release && \
cargo test && \
cargo doc --no-deps && \
echo "Ready to publish!"
```

## CI Integration

```yaml
# GitHub Actions
- name: Semver check
  run: |
    cargo install cargo-semver-checks
    cargo semver-checks check-release

# Or use the official action
- uses: obi1kenobi/cargo-semver-checks-action@v2
```

## Cargo Integration Status

cargo-semver-checks has an approved RFC for integration into Cargo itself. Until that lands, use it as a standalone tool. The lints and behavior will carry over.

## Custom Lints

cargo-semver-checks supports custom lint definitions using a Trustfall query language:

```bash
# List all available lints
cargo semver-checks --list-lints

# Show details for a specific lint
cargo semver-checks --explain function_missing
```

## Tips

- **Run before every publish**: Add to your pre-publish checklist
- **Baseline version**: defaults to latest on crates.io; use `--baseline-version` for specific comparisons
- **False positives**: Rare but possible — use lint-level overrides
- **Workspace crates**: Use `--workspace` to check all public crates
- **Speed**: Much faster than a full compile — uses rustdoc JSON output
- **Lint coverage**: Comprehensive and growing with each release — run `--list-lints` to check
- **Combines with**: `cargo-hack` (test all features) and `cargo-deny` (full audit)
