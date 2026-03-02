# cargo-nextest

Next-generation Rust test runner. Runs each test in its own process (vs cargo test's shared-process model), giving 3x faster execution, better output, flaky test detection, and JUnit XML reports.

## Installation

```bash
cargo install cargo-nextest
```

## Why cargo-nextest

| Feature         | `cargo test`   | `cargo nextest`                 |
| --------------- | -------------- | ------------------------------- |
| Execution model | Shared process | Process-per-test                |
| Speed           | Baseline       | ~3x faster (parallel)           |
| Flaky detection | No             | Built-in retries                |
| Output          | Interleaved    | Clean, per-test                 |
| JUnit XML       | No             | Built-in                        |
| Test filtering  | Basic          | Regex + filter expressions      |
| Timeouts        | No             | Per-test and per-suite          |
| Doc tests       | Yes            | **No** (use `cargo test --doc`) |

## Basic Usage

```bash
# Run all tests
cargo nextest run

# Run specific test
cargo nextest run test_name

# Run tests matching regex
cargo nextest run -E 'test(parse_)'

# Run tests in specific package (workspace)
cargo nextest run -p my-crate

# List tests without running
cargo nextest list
```

## Configuration

Config file: `.config/nextest.toml` (at project root)

```toml
[store]
# Directory for nextest artifacts
dir = "target/nextest"

[profile.default]
# Retry failed tests (catches flaky tests)
retries = 0

# Fail fast — stop on first failure
fail-fast = true

# Test timeout
slow-timeout = { period = "60s", terminate-after = 2 }

# Number of test threads
test-threads = "num-cpus"

[profile.ci]
# CI profile — more retries, JUnit output
retries = 2
fail-fast = false
slow-timeout = { period = "120s", terminate-after = 3 }

[profile.ci.junit]
path = "target/nextest/ci/junit.xml"
```

## Filter Expressions

nextest supports powerful filter expressions:

```bash
# Tests matching name
cargo nextest run -E 'test(my_test)'

# Tests in specific package
cargo nextest run -E 'package(my-crate)'

# Tests in specific binary
cargo nextest run -E 'binary(my-crate::bin/my-binary)'

# Combine with boolean operators
cargo nextest run -E 'test(parse_) & package(my-crate)'
cargo nextest run -E 'test(parse_) | test(lex_)'
cargo nextest run -E 'not test(slow_)'

# Tests that depend on specific binary
cargo nextest run -E 'deps(my-crate)'
```

## Profiles

```bash
# Use CI profile
cargo nextest run --profile ci

# Override retries
cargo nextest run --retries 3

# Override thread count
cargo nextest run --test-threads 2
```

## Flaky Test Detection

```bash
# Retry failed tests up to 3 times
cargo nextest run --retries 3

# In config:
[profile.default]
retries = { backoff = "exponential", count = 3, delay = "1s", max-delay = "10s" }
```

When a test fails then passes on retry, nextest marks it as **flaky** in the output.

## JUnit XML Output

```bash
# Generate JUnit XML (for CI systems)
cargo nextest run --profile ci

# Custom output path
cargo nextest run --profile ci --message-format libtest-json
```

Configure in `.config/nextest.toml`:

```toml
[profile.ci.junit]
path = "target/nextest/ci/junit.xml"
report-name = "my-project-tests"
```

## Partitioning (CI Sharding)

```bash
# Shard tests across CI machines
cargo nextest run --partition count:1/3  # Machine 1 of 3
cargo nextest run --partition count:2/3  # Machine 2 of 3
cargo nextest run --partition count:3/3  # Machine 3 of 3
```

## Archive for CI

```bash
# Create test archive (on build machine)
cargo nextest archive --archive-file tests.tar.zst

# Run from archive (on test machine — no Rust toolchain needed)
cargo nextest run --archive-file tests.tar.zst
```

## Debugging

```bash
# Run single test with output visible
cargo nextest run test_name --no-capture

# Run single test with debugger
cargo nextest run test_name -- --nocapture

# Show slow tests
cargo nextest run --status-level slow
```

## Integration with cargo-mutants

```bash
# Use nextest as the test runner for mutation testing
cargo mutants -- --test-tool nextest
```

## Tips

- **Doc tests**: nextest doesn't support them — run `cargo test --doc` separately
- **Test isolation**: Process-per-test means tests can't interfere with each other
- **Speed**: The process-per-test model enables better parallelism
- **Config location**: `.config/nextest.toml` (not `.cargo/`)
- **Workspace**: Works transparently with Cargo workspaces
- **Pre-built binaries**: Available via `cargo-binstall cargo-nextest` (faster install)

## Migration from cargo test

1. Install: `cargo install cargo-nextest`
2. Create `.config/nextest.toml` with profiles
3. Replace `cargo test` → `cargo nextest run` in scripts/CI
4. Keep `cargo test --doc` for doc-tests
5. Add `--retries 2` in CI for flaky detection
