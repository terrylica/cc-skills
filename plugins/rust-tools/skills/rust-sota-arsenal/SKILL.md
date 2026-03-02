---
name: rust-sota-arsenal
description: "SOTA Rust tooling - refactoring (ast-grep, cargo-semver-checks), profiling (samply, cargo-pgo, cargo-wizard), benchmarking (divan, Criterion), testing (cargo-nextest, cargo-mutants, cargo-hack), SIMD (macerator). TRIGGERS - rust refactoring, cargo bench, profiling rust, simd optimization, rust performance, ast-grep, divan, mutation testing, samply, cargo-nextest, cargo-wizard."
allowed-tools: Read, Grep, Bash, Edit, Write
---

# Rust SOTA Arsenal

State-of-the-art Rust tooling knowledge for refactoring, profiling, benchmarking, testing, and SIMD optimization — tools that LLMs often lack deep training data on.

## When to Use

- Refactoring Rust code (AST-aware search/replace, API compatibility)
- Performance work (profiling, PGO, Cargo profile tuning)
- Benchmarking (choosing divan vs Criterion, setting up benchmarks)
- Testing (faster test runner, mutation testing, feature flag testing)
- SIMD optimization (portable SIMD on stable Rust)
- Migrating PyO3 bindings (0.22+)

## Quick Reference

| Tool                  | Install                               | One-liner                              | Category     |
| --------------------- | ------------------------------------- | -------------------------------------- | ------------ |
| `ast-grep`            | `cargo install ast-grep`              | AST-aware search/rewrite for Rust      | Refactoring  |
| `cargo-semver-checks` | `cargo install cargo-semver-checks`   | API compat linting (hundreds of lints) | Refactoring  |
| `samply`              | `cargo install samply`                | Profile → Firefox Profiler UI          | Performance  |
| `cargo-pgo`           | `cargo install cargo-pgo`             | PGO + BOLT optimization                | Performance  |
| `cargo-wizard`        | `cargo install cargo-wizard`          | Auto-configure Cargo profiles          | Performance  |
| `divan`               | `divan = "<version>"` in dev-deps     | `#[divan::bench]` attribute API        | Benchmarking |
| `criterion`           | `criterion = "<version>"` in dev-deps | Statistics-driven, Gnuplot reports     | Benchmarking |
| `cargo-nextest`       | `cargo install cargo-nextest`         | 3x faster, process-per-test            | Testing      |
| `cargo-mutants`       | `cargo install cargo-mutants`         | Mutation testing (missed/caught)       | Testing      |
| `cargo-hack`          | `cargo install cargo-hack`            | Feature powerset testing               | Testing      |
| `macerator`           | `macerator = "<version>"` in deps     | Type-generic SIMD + multiversioning    | SIMD         |
| `cargo-audit`         | `cargo install cargo-audit`           | RUSTSEC vulnerability scan             | Dependencies |
| `cargo-deny`          | `cargo install cargo-deny`            | License + advisory + ban               | Dependencies |
| `cargo-vet`           | `cargo install cargo-vet`             | Mozilla supply chain audit             | Dependencies |
| `cargo-outdated`      | `cargo install cargo-outdated`        | Dependency freshness                   | Dependencies |

## Refactoring Workflow

### ast-grep: AST-Aware Search and Rewrite

**When to use**: Refactoring patterns across a codebase — safer than regex because it understands Rust syntax.

```bash
# Search for .unwrap() calls
ast-grep --pattern '$X.unwrap()' --lang rust

# Replace unwrap with expect
ast-grep --pattern '$X.unwrap()' --rewrite '$X.expect("TODO: handle error")' --lang rust

# Find unsafe blocks
ast-grep --pattern 'unsafe { $$$BODY }' --lang rust

# Convert match to if-let (single-arm + wildcard)
ast-grep --pattern 'match $X { $P => $E, _ => () }' --rewrite 'if let $P = $X { $E }' --lang rust
```

For complex multi-rule transforms, use YAML rule files. See [ast-grep reference](./references/ast-grep-rust.md).

### cargo-semver-checks: API Compatibility

**When to use**: Before publishing a crate version — catches accidental breaking changes.

```bash
# Check current changes against last published version
cargo semver-checks check-release

# Check against specific baseline
cargo semver-checks check-release --baseline-version 1.2.0

# Workspace mode
cargo semver-checks check-release --workspace
```

Hundreds of built-in lints covering function removal, type changes, trait impl changes, and more (lint count grows with each release). See [cargo-semver-checks reference](./references/cargo-semver-checks.md).

## Performance Workflow

### Step 1: Profile with samply

```bash
# Build with debug info (release speed + symbols)
cargo build --release

# Profile (macOS — uses dtrace, needs SIP consideration)
samply record ./target/release/my-binary

# Opens Firefox Profiler UI in browser automatically
# Look for: hot functions, call trees, flame graphs
```

See [samply reference](./references/samply-profiling.md) for macOS dtrace setup and flame graph interpretation.

### Step 2: Auto-configure profiles with cargo-wizard

```bash
# Interactive — choose optimization goal
cargo wizard

# Templates:
# 1. "fast-compile" — minimize build time (incremental, low opt)
# 2. "fast-runtime" — maximize performance (LTO, codegen-units=1)
# 3. "min-size"     — minimize binary size (opt-level="z", LTO, strip)
```

cargo-wizard writes directly to `Cargo.toml` `[profile.*]` sections. Endorsed by the Cargo team. See [cargo-wizard reference](./references/cargo-wizard.md).

### Step 3: PGO + BOLT with cargo-pgo

Three-phase workflow for maximum performance:

```bash
# Phase 1: Instrument
cargo pgo build

# Phase 2: Collect profiles (run representative workload)
./target/release/my-binary < typical_input.txt

# Phase 3: Optimize with collected profiles
cargo pgo optimize

# Optional Phase 4: BOLT (post-link optimization, Linux only)
cargo pgo bolt optimize
```

PGO typically gives 10-20% speedup on CPU-bound code. See [cargo-pgo reference](./references/cargo-pgo.md).

## Benchmarking Workflow

### divan vs Criterion — When to Use Which

| Aspect               | divan                                     | Criterion                                           |
| -------------------- | ----------------------------------------- | --------------------------------------------------- |
| API style            | `#[divan::bench]` attribute               | `criterion_group!` + `criterion_main!` macros       |
| Setup                | Add dep + `#[divan::bench]`               | Add dep + `benches/` dir + `Cargo.toml` `[[bench]]` |
| Generic benchmarks   | Built-in `#[divan::bench(types = [...])]` | Manual with macros                                  |
| Allocation profiling | Built-in `AllocProfiler`                  | Needs external tools                                |
| Reports              | Terminal (colored)                        | HTML + Gnuplot graphs                               |
| CI integration       | CodSpeed (native)                         | CodSpeed + criterion-compare                        |
| Maintenance          | Maintained (check crates.io for cadence)  | Active (criterion-rs organization)                  |

**Recommendation**: divan for new projects (simpler API); Criterion for existing projects or when HTML reports needed. See [divan-and-criterion reference](./references/divan-and-criterion.md).

### divan Quick Start

```rust
fn main() {
    divan::main();
}

#[divan::bench]
fn my_benchmark(bencher: divan::Bencher) {
    bencher.bench(|| {
        // code to benchmark
    });
}
```

### Criterion Quick Start

```rust
use criterion::{criterion_group, criterion_main, Criterion};

fn my_benchmark(c: &mut Criterion) {
    c.bench_function("name", |b| {
        b.iter(|| {
            // code to benchmark
        });
    });
}

criterion_group!(benches, my_benchmark);
criterion_main!(benches);
```

## Testing Workflow

### cargo-nextest: Faster Test Runner

```bash
# Run all tests (3x faster than cargo test)
cargo nextest run

# Run with specific profile
cargo nextest run --profile ci

# Retry flaky tests
cargo nextest run --retries 2

# JUnit XML output (for CI)
cargo nextest run --profile ci --message-format libtest-json
```

Config file: `.config/nextest.toml`. See [cargo-nextest reference](./references/cargo-nextest.md).

### cargo-mutants: Mutation Testing

```bash
# Run mutation testing on entire crate
cargo mutants

# Filter to specific files/functions
cargo mutants --file src/parser.rs
cargo mutants --regex "parse_.*"

# Use nextest as test runner (faster)
cargo mutants -- --test-tool nextest

# Check results
cat mutants.out/missed.txt     # Tests that didn't catch mutations
cat mutants.out/caught.txt     # Tests that caught mutations
```

Result categories: **caught** (good), **missed** (weak test), **timeout**, **unviable** (won't compile). See [cargo-mutants reference](./references/cargo-mutants.md).

### cargo-hack: Feature Flag Testing

```bash
# Test every feature individually
cargo hack test --each-feature

# Test all feature combinations (powerset)
cargo hack test --feature-powerset

# Exclude dev-dependencies (check only)
cargo hack check --feature-powerset --no-dev-deps

# CI: verify no feature combination breaks compilation
cargo hack check --feature-powerset --depth 2
```

Essential for library crates with multiple features. See [cargo-hack reference](./references/cargo-hack.md).

## SIMD Decision Matrix

| Crate         | Stable Rust      | Type-Generic        | Multiversioning | Maintained                                          |
| ------------- | ---------------- | ------------------- | --------------- | --------------------------------------------------- |
| **macerator** | Yes              | Yes                 | Yes (stable)    | Active                                              |
| `wide`        | Yes              | No (concrete types) | No              | Active                                              |
| `pulp`        | Yes              | Yes                 | Yes             | Superseded by macerator                             |
| `std::simd`   | **Nightly only** | Yes                 | No              | Nightly-only (tracking issue: rust-lang/rust#86656) |

**Recommendation**: macerator for new SIMD work on stable Rust. It's a fork of `pulp` with type-generic operations and runtime multiversioning (SSE4.2 → AVX2 → AVX-512 dispatch). See [macerator reference](./references/macerator-simd.md).

**Watch list**: `fearless_simd` (limited arch support — only NEON/WASM/SSE4.2), `std::simd` (nightly-only — check tracking issue for stabilization status).

## PyO3 Upgrade Path

For Rust↔Python bindings, PyO3 has evolved significantly since 0.22. Always check the [PyO3 changelog](https://pyo3.rs/main/changelog.html) for the latest version:

| Version | Key Change                                           |
| ------- | ---------------------------------------------------- |
| 0.22    | `Bound<'_, T>` API introduced (replaces GIL refs)    |
| 0.23    | GIL ref removal complete, `IntoPyObject` trait       |
| 0.24    | `vectorcall` support, performance improvements       |
| 0.25+   | Free-threaded Python (3.13t) support, `UniqueGilRef` |

See [PyO3 upgrade guide](./references/pyo3-upgrade-guide.md) for migration patterns.

## Reference Documents

- [ast-grep-rust.md](./references/ast-grep-rust.md) — AST-aware refactoring patterns
- [cargo-hack.md](./references/cargo-hack.md) — Feature flag testing
- [cargo-mutants.md](./references/cargo-mutants.md) — Mutation testing
- [cargo-nextest.md](./references/cargo-nextest.md) — Next-gen test runner
- [cargo-pgo.md](./references/cargo-pgo.md) — Profile-Guided Optimization
- [cargo-semver-checks.md](./references/cargo-semver-checks.md) — API compatibility
- [cargo-wizard.md](./references/cargo-wizard.md) — Profile auto-configuration
- [divan-and-criterion.md](./references/divan-and-criterion.md) — Benchmarking comparison
- [macerator-simd.md](./references/macerator-simd.md) — Type-generic SIMD
- [pyo3-upgrade-guide.md](./references/pyo3-upgrade-guide.md) — PyO3 migration
- [samply-profiling.md](./references/samply-profiling.md) — Interactive profiling

## Troubleshooting

| Problem                         | Solution                                                          |
| ------------------------------- | ----------------------------------------------------------------- |
| `ast-grep` no matches           | Check `--lang rust` flag; patterns must match AST nodes, not text |
| `samply` permission denied      | macOS: `sudo samply record` or disable SIP for dtrace             |
| `cargo-pgo` no speedup          | Workload during profiling must be representative of real usage    |
| `cargo-mutants` too slow        | Filter with `--file` or `--regex`; use `-- --test-tool nextest`   |
| `divan` vs `criterion` conflict | They can coexist — use separate bench targets in `Cargo.toml`     |
| `macerator` compile errors      | Check minimum Rust version; requires SIMD target features         |
| `cargo-nextest` missing tests   | Doc-tests not supported; use `cargo test --doc` separately        |
| `cargo-hack` OOM on powerset    | Use `--depth 2` to limit combinations                             |
