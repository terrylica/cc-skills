# cargo-wizard

Auto-configure Cargo profiles for optimal compile time, runtime performance, or binary size. Endorsed by the Cargo team. Most LLMs don't know this tool exists.

## Installation

```bash
cargo install cargo-wizard
```

## Why cargo-wizard

Cargo has many profile settings (`opt-level`, `lto`, `codegen-units`, `strip`, `panic`, `debug`) that interact in non-obvious ways. cargo-wizard provides opinionated templates that configure all of them correctly for a specific goal.

## Usage

```bash
# Interactive mode — choose optimization goal
cargo wizard
```

This presents three templates:

### Template 1: Fast Compile Time

Minimizes build time for development iteration:

```toml
# What cargo-wizard sets in Cargo.toml:
[profile.dev]
opt-level = 0
debug = "line-tables-only"
incremental = true
codegen-units = 256
```

### Template 2: Fast Runtime Performance

Maximizes execution speed for release builds:

```toml
[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
panic = "abort"
strip = "debuginfo"
```

### Template 3: Minimum Binary Size

Minimizes the output binary size:

```toml
[profile.release]
opt-level = "z"
lto = "fat"
codegen-units = 1
panic = "abort"
strip = true
```

## How It Works

1. Asks which optimization goal you want
2. Asks which profile to modify (`dev`, `release`, or custom)
3. Writes the appropriate settings to `Cargo.toml`
4. Shows what changed

## Profile Settings Explained

| Setting         | Fast Compile       | Fast Runtime | Min Size |
| --------------- | ------------------ | ------------ | -------- |
| `opt-level`     | 0                  | 3            | "z"      |
| `lto`           | "off"              | "fat"        | "fat"    |
| `codegen-units` | 256                | 1            | 1        |
| `panic`         | "unwind"           | "abort"      | "abort"  |
| `strip`         | false              | "debuginfo"  | true     |
| `debug`         | "line-tables-only" | false        | false    |
| `incremental`   | true               | false        | false    |

### Key Trade-offs

- **`lto = "fat"`**: Enables Link-Time Optimization across all crates — slower compile, faster/smaller binary
- **`codegen-units = 1`**: Single compilation unit — slower compile, better optimization
- **`panic = "abort"`**: No unwinding — smaller binary, but no catch_unwind
- **`strip = true`**: Removes all symbols — smallest binary, but no debugging

## Combining with Other Tools

### With cargo-pgo

```bash
# Step 1: Set up profile with cargo-wizard
cargo wizard  # Choose "fast-runtime"

# Step 2: Layer PGO on top for additional 10-20%
cargo pgo build
./target/release/my-binary < workload.txt
cargo pgo optimize
```

### With samply

```bash
# For profiling, you want release speed + debug info
# Manually adjust after cargo-wizard:
[profile.release]
opt-level = 3
debug = true  # Keep debug info for profiler
strip = false  # Don't strip symbols
```

## Custom Profiles

cargo-wizard can also configure custom profiles:

```bash
# Create a "profiling" profile
cargo wizard  # Select custom profile name
```

```toml
# Result:
[profile.profiling]
inherits = "release"
debug = true
strip = false
```

## Tips

- **Run once per project**: Settings persist in `Cargo.toml`
- **Combine templates**: Use "fast-compile" for dev, "fast-runtime" for release
- **Review changes**: cargo-wizard shows the diff — review before accepting
- **Author**: Kobzol (same author as cargo-pgo, major Rust/rustc contributor)
- **Cargo team endorsed**: Featured in Cargo team discussions
- **Idempotent**: Running again with same choices produces same output
