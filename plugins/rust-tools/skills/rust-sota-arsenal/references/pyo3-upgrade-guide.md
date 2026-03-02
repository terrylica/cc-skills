# PyO3 Upgrade Guide: 0.22+

Migration guide for PyO3 Rust↔Python bindings. PyO3 has evolved significantly — the API surface changed substantially starting from 0.22. Always check the [PyO3 changelog](https://pyo3.rs/main/changelog.html) for the latest version.

> **Web-verify first**: Before planning a PyO3 migration, check the actual latest versions:
>
> - `WebFetch: https://crates.io/api/v1/crates/pyo3` — get latest PyO3 version
> - `WebFetch: https://crates.io/api/v1/crates/pyo3-arrow` — if using Arrow bindings
> - Check that downstream crates (pyo3-arrow, pyo3-polars, etc.) support the target PyO3 version before upgrading

## Version Overview

| Version | Key Change                                           |
| ------- | ---------------------------------------------------- |
| 0.22    | `Bound<'py, T>` API introduced (replaces GIL refs)   |
| 0.23    | GIL ref removal complete, `IntoPyObject` trait       |
| 0.24    | `vectorcall` support, performance improvements       |
| 0.25+   | Free-threaded Python (3.13t) support, `UniqueGilRef` |

## The Big Change: Bound API (0.22)

### Before (GIL References — Deprecated)

```rust
// OLD: Using &PyAny, &PyDict, etc. (GIL references)
use pyo3::prelude::*;
use pyo3::types::PyDict;

#[pyfunction]
fn old_style(py: Python<'_>, dict: &PyDict) -> PyResult<()> {
    let value = dict.get_item("key")?;
    Ok(())
}
```

### After (Bound API — Current)

```rust
// NEW: Using Bound<'py, PyAny>, Bound<'py, PyDict>, etc.
use pyo3::prelude::*;
use pyo3::types::PyDict;

#[pyfunction]
fn new_style(dict: &Bound<'_, PyDict>) -> PyResult<()> {
    let value = dict.get_item("key")?;
    Ok(())
}
```

### Why the Change

- GIL references (`&PyAny`) tied the reference to the GIL lifetime implicitly
- `Bound<'py, T>` makes the GIL lifetime explicit
- Required for free-threaded Python (3.13t) support
- Better memory safety guarantees

## Migration Patterns

### Pattern 1: Function Arguments

```rust
// Before:
fn process(obj: &PyAny) -> PyResult<()> { ... }

// After:
fn process(obj: &Bound<'_, PyAny>) -> PyResult<()> { ... }
```

### Pattern 2: Return Types

```rust
// Before:
fn create_dict(py: Python<'_>) -> PyResult<&PyDict> {
    let dict = PyDict::new(py);
    Ok(dict)
}

// After:
fn create_dict(py: Python<'_>) -> PyResult<Bound<'_, PyDict>> {
    let dict = PyDict::new(py);
    Ok(dict)
}
```

### Pattern 3: Extracting Values

```rust
// Before:
let value: i64 = obj.extract()?;

// After (same syntax, works on Bound):
let value: i64 = obj.extract()?;
```

### Pattern 4: Creating Python Objects

```rust
// Before:
let list = PyList::new(py, &[1, 2, 3]);

// After:
let list = PyList::new(py, [1, 2, 3])?;  // Note: now returns Result
```

## IntoPyObject Trait (0.23)

Replaces `IntoPy<PyObject>` and `ToPyObject`:

```rust
// Before:
impl IntoPy<PyObject> for MyType {
    fn into_py(self, py: Python<'_>) -> PyObject {
        self.value.into_py(py)
    }
}

// After:
impl<'py> IntoPyObject<'py> for MyType {
    type Target = PyAny;
    type Output = Bound<'py, Self::Target>;
    type Error = PyErr;

    fn into_pyobject(self, py: Python<'py>) -> Result<Self::Output, Self::Error> {
        self.value.into_pyobject(py)
    }
}
```

For simple cases, derive macros handle this automatically:

```rust
#[pyclass]
#[derive(Clone)]
struct MyType {
    value: i64,
}
// IntoPyObject is auto-derived for #[pyclass] types
```

## Vectorcall Support (0.24)

Faster Python function calls using the vectorcall protocol:

```rust
// Automatic for #[pyfunction] and #[pymethods]
// No code changes needed — PyO3 uses vectorcall internally when available
```

Performance improvement: ~10-30% faster for frequently-called functions.

## Free-Threaded Python (0.25+)

Python 3.13t (free-threaded, no GIL) support:

```rust
// Check if running free-threaded at runtime
if pyo3::cfg!(Py_GIL_DISABLED) {
    // Running on free-threaded Python
}
```

Key considerations for free-threaded:

- `Bound<'py, T>` is required (GIL refs won't work)
- Shared mutable state needs explicit synchronization
- `#[pyclass]` types should be `Send + Sync` when possible

## Migration Checklist

1. **Update Cargo.toml**: Change PyO3 version
2. **Replace GIL references**: `&PyAny` → `&Bound<'_, PyAny>`, etc.
3. **Update return types**: `&PyDict` → `Bound<'_, PyDict>`
4. **Handle new Result types**: `PyList::new()` now returns `Result`
5. **Update IntoPy**: Replace `IntoPy<PyObject>` with `IntoPyObject`
6. **Test with maturin**: `maturin develop` to verify compilation
7. **Test Python side**: Run Python tests to verify behavior

## Build Tools

```bash
# Development build (fast iteration)
maturin develop --release

# Build wheel for distribution
maturin build --release

# Build and install
pip install .
```

## Tips

- **Incremental migration**: PyO3 0.22-0.23 supports both old and new APIs — migrate gradually
- **Deprecation warnings**: Enable them to find old API usage: `RUSTFLAGS="-W deprecated"`
- **maturin**: Preferred build tool for PyO3 projects
- **Python version**: Test against Python 3.9+ (PyO3 minimum)
- **Changelog**: Always check the [PyO3 changelog](https://pyo3.rs/main/changelog.html) for version-specific notes
- **Free-threaded**: Not yet production-ready — test thoroughly if targeting 3.13t
