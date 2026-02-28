**Skill**: [Implement Plan Engineering Standards](../SKILL.md)

# SSoT / Dependency Injection Patterns

Core principle: **Centralize defaults in one config object, inject via None-default parameters, resolve at call time**

---

## Beyond Constants

[Constants management](./constants-management.md) covers named constants and configuration objects. This document extends that to the **full resolution chain** — eliminating scattered defaults that drift across files.

**The problem**: `ouroboros_mode="year"` hardcoded in 10+ function signatures across 6 files. Changing the system-wide default requires editing every file.

**The solution**: One env var change propagates everywhere.

---

## The 5-Step Resolution Chain

```
ENV VAR → CONFIG SINGLETON → RESOLVER HELPER → NONE-DEFAULT → ENTRY-POINT VALIDATION
```

| Step                      | What                                | Why                                         |
| ------------------------- | ----------------------------------- | ------------------------------------------- |
| 1. Env var                | `OUROBOROS_MODE=year`               | External configuration, no code changes     |
| 2. Config singleton       | `Settings.ouroboros_mode`           | One validated object, fail-fast startup     |
| 3. Resolver helper        | `resolve_mode(mode)`                | `None` → config lookup, value → passthrough |
| 4. None-default params    | `def foo(mode: str \| None = None)` | Functions don't hardcode defaults           |
| 5. Entry-point validation | Validate at public API boundaries   | Catch bad inputs early, not deep in logic   |

---

## Language-Specific Examples

### Python (Settings frozen dataclass)

```python
# ✅ Config singleton
from dataclasses import dataclass
import os

@dataclass(frozen=True)
class Settings:
    ouroboros_mode: str = os.getenv("OUROBOROS_MODE", "year")  # SSoT-OK: config entrypoint
    batch_size: int = int(os.getenv("BATCH_SIZE", "64"))

    @classmethod
    def get(cls) -> "Settings":
        if not hasattr(cls, "_instance"):
            cls._instance = cls()
        return cls._instance

# ✅ Resolver helper
def resolve_mode(mode: str | None = None) -> str:
    return mode if mode is not None else Settings.get().ouroboros_mode

# ✅ None-default parameter
def process_data(mode: str | None = None):
    effective_mode = resolve_mode(mode)
    # ...
```

### TypeScript (config object)

```typescript
// ✅ Config singleton
const config = {
  ouroboros_mode: process.env.OUROBOROS_MODE ?? "year", // SSoT-OK: config entrypoint
  batchSize: parseInt(process.env.BATCH_SIZE ?? "64", 10),
} as const;

// ✅ Resolver + None-default
function processData(mode?: string) {
  const effectiveMode = mode ?? config.ouroboros_mode;
  // ...
}
```

### Rust (Config + Default trait)

```rust
// ✅ Config struct with Default
#[derive(Debug)]
struct Config {
    ouroboros_mode: String,
    batch_size: usize,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            ouroboros_mode: std::env::var("OUROBOROS_MODE") // SSoT-OK: config entrypoint
                .unwrap_or_else(|_| "year".to_string()),
            batch_size: std::env::var("BATCH_SIZE")
                .ok().and_then(|s| s.parse().ok()).unwrap_or(64),
        }
    }
}

// ✅ Option parameter + config resolution
fn process_data(mode: Option<&str>, config: &Config) {
    let effective_mode = mode.unwrap_or(&config.ouroboros_mode);
    // ...
}
```

### Go (functional options)

```go
// ✅ Config struct
type Config struct {
    OuroborosMode string
    BatchSize     int
}

func NewConfig() Config {
    mode := os.Getenv("OUROBOROS_MODE") // SSoT-OK: config entrypoint
    if mode == "" {
        mode = "year"
    }
    return Config{OuroborosMode: mode, BatchSize: 64}
}

// ✅ Functional option pattern
type Option func(*processor)

func WithMode(mode string) Option {
    return func(p *processor) { p.mode = mode }
}
```

---

## Anti-Patterns Detected by ast-grep

| Anti-Pattern                  | ast-grep Rule                     | Fix                                            |
| ----------------------------- | --------------------------------- | ---------------------------------------------- |
| `def foo(mode: str = "year")` | `hardcoded-string-default-python` | `def foo(mode: str \| None = None)` + resolver |
| `def foo(size: int = 64)`     | `hardcoded-int-default-python`    | `def foo(size: int \| None = None)` + resolver |
| `os.environ.get("VAR")`       | `direct-env-access-python`        | `Settings.get().var`                           |
| `process.env.VAR`             | `direct-process-env-typescript`   | `config.var`                                   |
| `env::var("VAR")`             | `direct-env-var-rust`             | `Config::default().var`                        |
| `os.Getenv("VAR")`            | `direct-os-getenv-go`             | `config.Var`                                   |

Rules location: `plugins/itp-hooks/hooks/ast-grep-ssot/rules/`

---

## Real-World Case Study: rangebar-py Ouroboros Migration

**Before**: `ouroboros_mode="year"` hardcoded in 10 function signatures across 6 files.

**After**: One `Settings` singleton + one `resolve_ouroboros_mode()` helper + `None`-default parameters everywhere.

**Result**: Changing the system-wide default from `"year"` to `"month"` = one env var: `OUROBOROS_MODE=month`.

| Metric                           | Before | After            |
| -------------------------------- | ------ | ---------------- |
| Files to edit for default change | 6      | 0 (env var only) |
| Functions with hardcoded default | 10     | 0                |
| Config entrypoints               | 0      | 1 (Settings)     |

---

## Escape Hatch

Add `# SSoT-OK` (Python/Rust) or `// SSoT-OK` (TypeScript/Go) comment to suppress ast-grep findings.

Use for legitimate config entrypoints (the one place that reads env vars), mathematical constants, or protocol-defined values.

---

## Hierarchical Lookup Pattern

For systems with multiple override levels:

```
Per-item override → Registry lookup → Class default → Global fallback (with warning)
```

```python
def resolve_threshold(symbol: str | None = None) -> float:
    """Hierarchical lookup with warning on fallback."""
    if symbol and symbol in SYMBOL_THRESHOLDS:
        return SYMBOL_THRESHOLDS[symbol]          # Per-item override
    if symbol and symbol in THRESHOLD_REGISTRY:
        return THRESHOLD_REGISTRY[symbol]          # Registry lookup
    if hasattr(Settings.get(), "default_threshold"):
        return Settings.get().default_threshold    # Class default
    import warnings
    warnings.warn("Using hardcoded fallback threshold")
    return 0.5                                     # Fallback (with warning)
```
