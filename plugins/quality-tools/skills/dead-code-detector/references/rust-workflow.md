# Rust Dead Code Detection with cargo clippy

Advanced usage patterns for dead code detection in Rust projects.

## Built-in Lints

Rust's compiler includes dead code detection by default:

```bash
# Standard build (warns on dead code)
cargo build

# Clippy with all warnings
cargo clippy

# Strict mode (errors instead of warnings)
cargo clippy -- -D dead_code -D unused_imports
```

## Lint Categories

| Lint                 | Detects                                    | Default |
| -------------------- | ------------------------------------------ | ------- |
| `dead_code`          | Unused functions, structs, enums, variants | Warn    |
| `unused_imports`     | Imports not used in scope                  | Warn    |
| `unused_variables`   | Variables assigned but never read          | Warn    |
| `unused_mut`         | Mutable bindings that don't need mut       | Warn    |
| `unused_assignments` | Assignments that are never read            | Warn    |
| `unreachable_code`   | Code after return/panic/loop               | Warn    |

## Command Reference

```bash
# Check for dead code only
cargo clippy -- -W dead_code

# Multiple lint categories
cargo clippy -- -W dead_code -W unused_imports -W unused_variables

# Deny (fail build) on dead code
cargo clippy -- -D dead_code

# Auto-fix what's possible
cargo clippy --fix --allow-dirty

# Check all targets (tests, examples, benches)
cargo clippy --all-targets -- -W dead_code

# JSON output for CI
cargo clippy --message-format=json -- -W dead_code
```

## Configuration (Cargo.toml)

```toml
[lints.rust]
dead_code = "warn"
unused_imports = "warn"
unused_variables = "warn"
unused_mut = "warn"

[lints.clippy]
# Additional clippy lints for unused code
needless_pass_by_value = "warn"
unused_self = "warn"
```

## Configuration (clippy.toml)

```toml
# Project-level clippy configuration
warn-on-all-wildcard-imports = true
```

## Suppressing False Positives

### Single Item

```rust
#[allow(dead_code)]
fn intentionally_unused_for_ffi() {
    // Called from C code, Rust doesn't know
}
```

### Module-wide

```rust
#![allow(dead_code)]
// All items in this module can be unused
```

### Conditional Compilation

```rust
#[cfg(test)]
mod tests {
    // Test helpers often appear "unused" to the compiler
    #[allow(dead_code)]
    fn test_helper() {}
}
```

### Feature-gated Code

```rust
#[cfg(feature = "unstable")]
#[allow(dead_code)]
pub fn experimental_api() {
    // Only compiled with --features unstable
}
```

## Common False Positive Patterns

| Pattern               | Why It's Flagged          | Solution                     |
| --------------------- | ------------------------- | ---------------------------- |
| FFI functions         | Called from C/Python      | `#[allow(dead_code)]`        |
| Trait implementations | Methods required by trait | Usually not flagged          |
| Derive macro outputs  | Generated but not called  | Usually not flagged          |
| Test fixtures         | Only used in test cfg     | `#[cfg(test)]` module        |
| Public API not used   | Library exports           | `pub` items are not flagged  |
| Workspace crate       | Used by other crates      | Ensure proper `extern crate` |

## Workspace Configuration

For monorepos, configure at workspace level:

```toml
# Workspace Cargo.toml
[workspace.lints.rust]
dead_code = "warn"
unused_imports = "warn"

# Per-crate Cargo.toml
[lints]
workspace = true
```

## CI Integration

```yaml
# Example CI step
- name: Check for dead code
  run: |
    cargo clippy --all-targets -- \
      -D dead_code \
      -D unused_imports \
      -D unused_variables
```

## Comparison with Other Tools

| Tool            | Scope               | Integrated | Auto-fix |
| --------------- | ------------------- | ---------- | -------- |
| `rustc` lints   | Dead code, unused   | Built-in   | No       |
| `cargo clippy`  | Style + dead code   | Built-in   | Some     |
| `cargo-udeps`   | Unused dependencies | Addon      | No       |
| `cargo-machete` | Unused dependencies | Addon      | Yes      |

### Unused Dependencies

For detecting unused crate dependencies (not code):

```bash
# Install
cargo install cargo-udeps

# Run (requires nightly)
cargo +nightly udeps

# Alternative: cargo-machete (stable, faster)
cargo install cargo-machete
cargo machete
```

## Anti-patterns

### Don't Use `#[deny(warnings)]`

```rust
// BAD: Breaks on new compiler warnings
#![deny(warnings)]

// GOOD: Be explicit about what you deny
#![deny(dead_code)]
#![deny(unused_imports)]
```

This is documented in [Rust Design Patterns](https://rust-unofficial.github.io/patterns/anti_patterns/deny-warnings.html) as an anti-pattern because new compiler versions may add warnings, breaking your build.

## Sources

- [Rust dead_code lint](https://doc.rust-lang.org/rust-by-example/attribute/unused.html)
- [rustc warn-by-default lints](https://doc.rust-lang.org/rustc/lints/listing/warn-by-default.html)
- [cargo-clippy GitHub](https://github.com/rust-lang/rust-clippy)
- [#[deny(warnings)] anti-pattern](https://rust-unofficial.github.io/patterns/anti_patterns/deny-warnings.html)
