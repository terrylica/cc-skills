# cargo-pgo

Profile-Guided Optimization (PGO) and BOLT post-link optimization for Rust binaries. Automates the multi-phase PGO workflow that typically gives 10-20% speedup on CPU-bound code.

## Installation

```bash
cargo install cargo-pgo

# For BOLT support (Linux only)
cargo install cargo-pgo --features bolt
```

## What is PGO?

PGO is a compiler optimization technique:

1. **Instrument**: Compile with profiling instrumentation
2. **Profile**: Run the instrumented binary with representative workload
3. **Optimize**: Recompile using the collected profile data

The compiler uses profile data to make better decisions about:

- Function inlining
- Branch prediction hints
- Code layout (hot/cold splitting)
- Loop unrolling decisions

## Three-Phase Workflow

### Phase 1: Instrument

```bash
# Build instrumented binary
cargo pgo build

# Binary is at target/release/<name> (with instrumentation)
```

### Phase 2: Collect Profiles

```bash
# Run with REPRESENTATIVE workload
# The workload MUST reflect real usage — this is the critical step
./target/release/my-binary < typical_input.txt
./target/release/my-binary --benchmark real-data.json

# Multiple runs accumulate profile data (they merge)
./target/release/my-binary < input1.txt
./target/release/my-binary < input2.txt

# Profile data is written to target/pgo-profiles/
```

**Critical**: The profiling workload must represent real usage. If you profile with synthetic data, optimizations target the wrong code paths.

### Phase 3: Optimize

```bash
# Build with collected profiles
cargo pgo optimize

# The optimized binary is at target/release/<name>
```

## BOLT Post-Link Optimization (Linux Only)

BOLT reorganizes the binary after linking for better instruction cache utilization:

```bash
# Phase 1: Build with BOLT instrumentation
cargo pgo bolt build

# Phase 2: Run with workload
./target/release/my-binary < typical_input.txt

# Phase 3: Optimize with BOLT
cargo pgo bolt optimize
```

### Combined PGO + BOLT

```bash
# PGO first, then BOLT on top
cargo pgo build
./target/release/my-binary < workload.txt
cargo pgo optimize

# Now BOLT on the PGO-optimized binary
cargo pgo bolt build
./target/release/my-binary < workload.txt
cargo pgo bolt optimize
```

## When PGO Helps

| Scenario               | Expected Gain | Why                         |
| ---------------------- | ------------- | --------------------------- |
| CPU-bound parsers      | 10-20%        | Branch prediction, inlining |
| Compilers/interpreters | 15-25%        | Hot loop optimization       |
| Crypto/hashing         | 5-10%         | Code layout optimization    |
| I/O-bound code         | Minimal       | Bottleneck isn't CPU        |
| Short-lived CLIs       | Minimal       | Startup-dominated           |

## Combining with cargo-wizard

```bash
# Step 1: Use cargo-wizard for profile settings
cargo wizard  # Choose "fast-runtime"

# Step 2: Then layer PGO on top
cargo pgo build
# ... run workload ...
cargo pgo optimize
```

cargo-wizard sets Cargo profile options (LTO, codegen-units), while cargo-pgo adds profile-guided optimizations. They complement each other.

## CI Integration

```yaml
# PGO in CI (for release builds)
- name: PGO Build
  run: |
    cargo install cargo-pgo
    cargo pgo build
    ./target/release/my-binary --bench  # Representative workload
    cargo pgo optimize

- name: Upload optimized binary
  uses: actions/upload-artifact@v4
  with:
    name: my-binary-pgo
    path: target/release/my-binary
```

## Flags Reference

| Command                   | Purpose                                 |
| ------------------------- | --------------------------------------- |
| `cargo pgo build`         | Build instrumented binary               |
| `cargo pgo optimize`      | Build with collected profiles           |
| `cargo pgo test`          | Run tests with instrumented binary      |
| `cargo pgo bench`         | Run benchmarks with instrumented binary |
| `cargo pgo bolt build`    | Build BOLT-instrumented binary          |
| `cargo pgo bolt optimize` | Apply BOLT optimization                 |
| `cargo pgo info`          | Show PGO profile info                   |

## Tips

- **Profile quality matters more than quantity**: One representative run > 100 synthetic runs
- **Profile data location**: `target/pgo-profiles/` (auto-managed by cargo-pgo)
- **LTO + PGO**: Enable LTO in your Cargo profile for maximum benefit
- **Benchmarking PGO**: Compare before/after with `hyperfine` or divan
- **BOLT**: Linux-only, requires LLVM BOLT (`llvm-bolt` binary)
- **Incremental**: PGO profiles are invalidated by code changes — re-profile after changes
- **Author**: Kobzol (major Rust contributor, works on rustc performance)
