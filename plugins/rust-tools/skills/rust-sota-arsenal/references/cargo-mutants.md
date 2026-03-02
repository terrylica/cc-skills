# cargo-mutants

Mutation testing for Rust: automatically modifies your source code and checks whether your tests catch the changes. Finds weak spots in your test suite.

## Installation

```bash
cargo install cargo-mutants
```

## How It Works

1. cargo-mutants generates **mutants** — small changes to your source code
2. For each mutant, it runs your test suite
3. If tests still pass with the mutation → **missed** (your tests are weak here)
4. If tests fail → **caught** (your tests are good here)

### Mutation Types

| Mutation             | Example                                     | What It Tests           |
| -------------------- | ------------------------------------------- | ----------------------- |
| Replace return value | `fn foo() -> bool` returns `true` → `false` | Return value assertions |
| Replace with default | `fn foo() -> Vec<T>` returns `vec![]`       | Non-empty result checks |
| Remove function body | `fn process() { ... }` → `fn process() {}`  | Side effect testing     |
| Negate condition     | `if x > 0` → `if x <= 0`                    | Branch coverage         |
| Replace binary op    | `a + b` → `a - b`                           | Arithmetic correctness  |

## Basic Usage

```bash
# Run mutation testing on entire crate
cargo mutants

# Dry run — show what mutations would be generated (no testing)
cargo mutants --list

# Count mutations
cargo mutants --list | wc -l
```

## Filtering

```bash
# Filter to specific files
cargo mutants --file src/parser.rs
cargo mutants --file "src/lib.rs" --file "src/core.rs"

# Filter by function name regex
cargo mutants --regex "parse_.*"
cargo mutants --regex "^(encode|decode)"

# Exclude specific functions
cargo mutants --exclude "test_.*"
cargo mutants --exclude "Debug|Display"

# Skip functions returning specific types
cargo mutants --skip-calls-to "log::*,tracing::*"
```

## Using cargo-nextest (Faster)

```bash
# Use nextest as the test runner (recommended — much faster)
cargo mutants -- --test-tool nextest

# With nextest profile
cargo mutants -- --test-tool nextest --profile ci
```

## Result Categories

| Category     | Meaning                           | Action                                   |
| ------------ | --------------------------------- | ---------------------------------------- |
| **caught**   | Tests detected the mutation       | Good — tests are effective               |
| **missed**   | Tests still passed with mutation  | Bad — add/improve tests                  |
| **timeout**  | Tests took too long with mutation | Usually OK (infinite loop from mutation) |
| **unviable** | Mutated code doesn't compile      | Neutral — type system caught it          |

### Reading Results

```bash
# Results directory
ls mutants.out/

# Key files
cat mutants.out/missed.txt     # Mutations your tests didn't catch
cat mutants.out/caught.txt     # Mutations your tests caught
cat mutants.out/timeout.txt    # Mutations that caused timeouts
cat mutants.out/unviable.txt   # Mutations that didn't compile

# Detailed log
cat mutants.out/outcomes.json  # Machine-readable results
```

## Configuration

### In `Cargo.toml`

```toml
[package.metadata.cargo-mutants]
# Skip functions that are hard to test
exclude_re = ["Debug", "Display", "Default"]

# Skip calls to logging/tracing (mutations here are noise)
skip_calls_to = ["log::.*", "tracing::.*", "println"]

# Timeout multiplier (default: 5x normal test time)
timeout_multiplier = 3.0
```

### In `.cargo/mutants.toml`

```toml
# Equivalent to package.metadata but in separate file
exclude_re = ["Debug", "Display"]
skip_calls_to = ["log::.*"]
timeout_multiplier = 3.0
```

## CI Integration

```yaml
# GitHub Actions
- name: Mutation testing
  run: |
    cargo install cargo-mutants cargo-nextest
    cargo mutants -- --test-tool nextest --timeout 300

- name: Check for missed mutants
  run: |
    if [ -s mutants.out/missed.txt ]; then
      echo "::warning::Missed mutants found"
      cat mutants.out/missed.txt
    fi
```

## Parallelism

```bash
# Run mutations in parallel (default: number of CPUs)
cargo mutants --jobs 4

# Incremental: only test mutations in changed files
cargo mutants --in-diff git diff main
```

## Interpreting Results

### High missed count in a file?

The tests for that module are likely:

1. **Missing edge cases** — add targeted tests
2. **Only testing happy path** — add error/boundary tests
3. **Testing implementation, not behavior** — refactor tests

### All caught?

Your test suite is strong for that code. Focus mutation testing on:

- Recently changed code
- Critical paths (payment, auth, data integrity)
- Complex logic with many branches

## Tips

- Start with `--file` on critical modules, not the whole crate
- `--regex` is great for focusing on specific subsystems
- Combine with `cargo-nextest` for 2-3x faster mutation runs
- `unviable` mutations are free wins — Rust's type system is your friend
- Run `--list` first to estimate how long the full run will take
- Typical: 5-20 seconds per mutation (depends on test suite speed)
