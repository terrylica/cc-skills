# Benchmarking: divan and Criterion

Two leading Rust benchmarking frameworks compared. divan offers a simpler attribute-based API; Criterion provides statistical analysis and HTML reports.

## divan

### Installation

Add to `Cargo.toml`:

```toml
[dev-dependencies]
divan = "<version>"  # See https://crates.io/crates/divan

[[bench]]
name = "my_benchmarks"
harness = false
```

### Basic Usage

```rust
// benches/my_benchmarks.rs
fn main() {
    divan::main();
}

#[divan::bench]
fn simple_bench() {
    // Code to benchmark (return value is black-boxed automatically)
    std::hint::black_box(fibonacci(20));
}

#[divan::bench]
fn bench_with_bencher(bencher: divan::Bencher) {
    // Setup outside the timing loop
    let data = prepare_data();

    bencher.bench(|| {
        process(&data)
    });
}
```

### Generic Benchmarks

divan's killer feature — benchmark across multiple types with one function:

```rust
#[divan::bench(types = [Vec<u8>, Vec<u16>, Vec<u32>, Vec<u64>])]
fn bench_sort<T: Ord + Default + Clone>(bencher: divan::Bencher) {
    let data: Vec<T> = generate_data();
    bencher
        .with_inputs(|| data.clone())
        .bench_values(|mut v| v.sort());
}
```

### Allocation Profiling

Built-in `AllocProfiler` — no external tools needed:

```rust
#[global_allocator]
static ALLOC: divan::AllocProfiler = divan::AllocProfiler::system();

fn main() {
    divan::main();
}

#[divan::bench]
fn bench_allocations() {
    // divan automatically reports allocation count and bytes
    let v: Vec<i32> = (0..1000).collect();
    std::hint::black_box(v);
}
```

Output includes: allocs/iter, bytes/iter, and allocation patterns.

### Parameterized Benchmarks

```rust
#[divan::bench(args = [10, 100, 1000, 10000])]
fn bench_fibonacci(n: u64) -> u64 {
    fibonacci(n)
}

// Multiple parameter axes
#[divan::bench(
    types = [Vec<u8>, Vec<u32>],
    args = [100, 1000, 10000],
)]
fn bench_sort<T: Ord + Default>(bencher: divan::Bencher, len: usize) {
    bencher
        .with_inputs(|| generate_vec::<T>(len))
        .bench_values(|mut v| v.sort());
}
```

### Running

```bash
cargo bench

# Filter specific benchmarks
cargo bench -- bench_sort

# With specific sample count
cargo bench -- --sample-count 100
```

## Criterion

### Installation

Add to `Cargo.toml`:

```toml
[dev-dependencies]
criterion = { version = "<version>", features = ["html_reports"] }  # See https://crates.io/crates/criterion

[[bench]]
name = "my_benchmarks"
harness = false
```

### Basic Usage

```rust
// benches/my_benchmarks.rs
use criterion::{criterion_group, criterion_main, Criterion, black_box};

fn bench_fibonacci(c: &mut Criterion) {
    c.bench_function("fibonacci_20", |b| {
        b.iter(|| fibonacci(black_box(20)));
    });
}

criterion_group!(benches, bench_fibonacci);
criterion_main!(benches);
```

### Parameterized Benchmarks

```rust
fn bench_sort_sizes(c: &mut Criterion) {
    let mut group = c.benchmark_group("sort");

    for size in [100, 1000, 10000] {
        group.bench_with_input(
            BenchmarkId::from_parameter(size),
            &size,
            |b, &size| {
                let data: Vec<i32> = (0..size).collect();
                b.iter(|| {
                    let mut v = data.clone();
                    v.sort();
                    v
                });
            },
        );
    }
    group.finish();
}
```

### Throughput Measurement

```rust
fn bench_throughput(c: &mut Criterion) {
    let mut group = c.benchmark_group("parse");
    let input = "large input string...";

    group.throughput(Throughput::Bytes(input.len() as u64));
    group.bench_function("parse", |b| {
        b.iter(|| parse(black_box(input)));
    });
    group.finish();
}
```

### Statistical Analysis

Criterion automatically provides:

- Confidence intervals
- Change detection (vs previous run)
- Outlier detection
- Linear regression for throughput

### HTML Reports

```bash
cargo bench
# Reports generated at target/criterion/report/index.html
```

### Running

```bash
cargo bench

# Filter specific benchmarks
cargo bench -- sort

# Save baseline
cargo bench -- --save-baseline before_change

# Compare against baseline
cargo bench -- --baseline before_change
```

## Comparison

| Feature                  | divan                        | Criterion                            |
| ------------------------ | ---------------------------- | ------------------------------------ |
| **API**                  | `#[divan::bench]` attribute  | `criterion_group!` macro             |
| **Setup complexity**     | Minimal                      | Moderate (macros, groups)            |
| **Generic benchmarks**   | Built-in `types = [...]`     | Manual with macros                   |
| **Allocation tracking**  | Built-in `AllocProfiler`     | External (dhat, etc.)                |
| **Statistical analysis** | Basic                        | Comprehensive (confidence intervals) |
| **Reports**              | Terminal (colored)           | HTML + Gnuplot                       |
| **Throughput**           | Basic                        | Built-in `Throughput` type           |
| **Baselines/comparison** | No                           | Yes (`--save-baseline`)              |
| **CI integration**       | CodSpeed (native)            | CodSpeed + criterion-compare         |
| **Maintenance**          | Maintained (check crates.io) | Active (criterion-rs organization)   |

## CodSpeed CI Integration

Both frameworks support CodSpeed for continuous benchmarking in CI:

```yaml
# GitHub Actions with CodSpeed
- uses: CodSpeedHQ/action@v3
  with:
    run: cargo bench # Works with both divan and criterion
    token: ${{ secrets.CODSPEED_TOKEN }}
```

## Recommendation

- **New projects**: Start with divan (simpler API, generic benchmarks, allocation profiling)
- **Existing Criterion users**: Stay with Criterion (active maintenance, HTML reports)
- **Need statistical rigor**: Criterion (confidence intervals, change detection)
- **Need allocation profiling**: divan (built-in, zero config)
- **Library crates**: Consider both — divan for dev, Criterion for published benchmarks
