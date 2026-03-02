# macerator: Type-Generic SIMD

Type-generic SIMD operations with runtime multiversioning on stable Rust. A fork of `pulp` that adds type-generic operations and improved architecture support.

## Installation

Add to `Cargo.toml`:

```toml
[dependencies]
macerator = "<version>"  # See https://crates.io/crates/macerator
```

## Why macerator

The Rust SIMD landscape:

| Crate         | Stable      | Type-Generic  | Multiversioning | Status                                              |
| ------------- | ----------- | ------------- | --------------- | --------------------------------------------------- |
| **macerator** | Yes         | Yes           | Yes             | Active                                              |
| `wide`        | Yes         | No (concrete) | No              | Active                                              |
| `pulp`        | Yes         | Yes           | Yes             | Superseded                                          |
| `std::simd`   | **Nightly** | Yes           | No              | Nightly-only (tracking issue: rust-lang/rust#86656) |
| `packed_simd` | **Nightly** | Yes           | No              | Deprecated                                          |

**macerator** is the only option that provides all three: stable Rust, type-generic operations, and runtime multiversioning.

## Core Concepts

### Type-Generic Operations

Write SIMD code once, works across `f32`, `f64`, `i32`, `u64`, etc.:

```rust
use macerator::{SimdFor, Simd};

fn dot_product<T: SimdFor>(a: &[T], b: &[T]) -> T
where
    T: std::ops::Mul<Output = T> + std::ops::Add<Output = T> + Default + Copy,
{
    // This function works for f32, f64, i32, etc.
    // macerator handles the SIMD width automatically
    let simd = Simd::new();
    simd.vectorize(|| {
        a.iter()
            .zip(b.iter())
            .map(|(&x, &y)| x * y)
            .fold(T::default(), |acc, v| acc + v)
    })
}
```

### Runtime Multiversioning

macerator compiles multiple versions of your SIMD code and selects the best at runtime based on CPU features:

```rust
use macerator::Simd;

fn process(data: &mut [f32]) {
    let simd = Simd::new(); // Detects CPU features at runtime

    // Dispatches to best available:
    // - AVX-512 on supported CPUs
    // - AVX2 on most modern x86_64
    // - SSE4.2 on older x86_64
    // - NEON on ARM
    simd.vectorize(|| {
        for x in data.iter_mut() {
            *x = x.sqrt();
        }
    });
}
```

The dispatch happens once (at `Simd::new()`) — not per-operation.

### Architecture Support

| Architecture | Instruction Sets      |
| ------------ | --------------------- |
| x86_64       | SSE4.2, AVX2, AVX-512 |
| aarch64      | NEON                  |
| wasm32       | SIMD128               |

## Migration from pulp

macerator is a fork of pulp. Migration is mostly renaming:

```rust
// Before (pulp):
use pulp::Simd;
let simd = Simd::new();

// After (macerator):
use macerator::Simd;
let simd = Simd::new();
```

Key differences from pulp:

- Type-generic operations (pulp required concrete types)
- Better ARM/NEON support
- Continued maintenance (pulp is no longer updated)

## Patterns

### Vectorized Map

```rust
use macerator::Simd;

fn scale(data: &mut [f32], factor: f32) {
    let simd = Simd::new();
    simd.vectorize(|| {
        for x in data.iter_mut() {
            *x *= factor;
        }
    });
}
```

### Vectorized Reduction

```rust
use macerator::Simd;

fn sum(data: &[f32]) -> f32 {
    let simd = Simd::new();
    simd.vectorize(|| {
        data.iter().copied().sum()
    })
}
```

### Conditional SIMD

```rust
use macerator::Simd;

fn clamp(data: &mut [f32], min: f32, max: f32) {
    let simd = Simd::new();
    simd.vectorize(|| {
        for x in data.iter_mut() {
            *x = x.max(min).min(max);
        }
    });
}
```

## Comparison with wide

`wide` provides concrete SIMD types (`f32x4`, `f32x8`), while macerator provides type-generic operations:

```rust
// wide: concrete types, manual width selection
use wide::f32x8;
let a = f32x8::from([1.0; 8]);
let b = f32x8::from([2.0; 8]);
let c = a + b;

// macerator: type-generic, automatic width
use macerator::Simd;
let simd = Simd::new();
simd.vectorize(|| {
    // Works on any numeric type, auto-selects width
});
```

**Use wide when**: You need explicit control over SIMD width and types.
**Use macerator when**: You want portable, type-generic SIMD with automatic dispatch.

## Comparison with std::simd

`std::simd` (nightly-only) provides similar type-generic operations:

```rust
// std::simd (nightly only):
#![feature(portable_simd)]
use std::simd::f32x4;

// macerator (stable):
use macerator::Simd;
```

**Use std::simd when**: You're on nightly and want stdlib support.
**Use macerator when**: You need stable Rust (which is most projects).

## Watch List

- **`fearless_simd`**: Limited arch support (only NEON/WASM/SSE4.2) — check crates.io for updates
- **`std::simd` stabilization**: Track rust-lang/rust#86656 for stabilization progress
- **`simdeez`**: Low adoption — check crates.io download counts before adopting

## Tips

- **Start with `Simd::new()`**: Let macerator detect the best ISA
- **Profile first**: Use samply to confirm SIMD is your bottleneck before optimizing
- **Alignment**: macerator handles alignment internally — no manual alignment needed
- **Fallback**: macerator always provides a scalar fallback if no SIMD is available
- **Testing**: SIMD code should produce identical results to scalar — test both paths
- **Benchmarking**: Use divan or Criterion to measure actual speedup
