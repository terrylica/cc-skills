# mise [env] Code Patterns

Complete code patterns for implementing mise `[env]` configuration with backward-compatible defaults.

## Python Pattern

```python
#!/usr/bin/env python3
"""Example script with mise [env] configuration."""

import os

# ADR: 2025-12-08-mise-env-centralized-config
# Configuration from environment with defaults
TIMEOUT = int(os.environ.get("SCRIPT_TIMEOUT", "300"))
OUTPUT_DIR = os.environ.get("OUTPUT_DIR", "output")
PARALLEL_WORKERS = int(os.environ.get("PARALLEL_WORKERS", "4"))
DEBUG_MODE = os.environ.get("DEBUG_MODE", "false").lower() == "true"

def main():
    print(f"Running with timeout={TIMEOUT}, workers={PARALLEL_WORKERS}")
    # ... script logic

if __name__ == "__main__":
    main()
```

**Key points:**

- Import `os` at top
- Define constants immediately after imports
- Cast to int/bool as needed (env vars are always strings)
- Use descriptive variable names matching .mise.toml

## Bash Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

# ADR: 2025-12-08-mise-env-centralized-config
# Configuration from environment with defaults
SCRIPT_TIMEOUT="${SCRIPT_TIMEOUT:-300}"
OUTPUT_DIR="${OUTPUT_DIR:-output}"
PARALLEL_WORKERS="${PARALLEL_WORKERS:-4}"
DEBUG_MODE="${DEBUG_MODE:-false}"

main() {
    echo "Running with timeout=$SCRIPT_TIMEOUT, workers=$PARALLEL_WORKERS"
    # ... script logic
}

main "$@"
```

**Key points:**

- Use `${VAR:-default}` POSIX syntax
- Define after shebang and set options
- No export needed - variables are local to script
- For boolean checks: `[[ "$DEBUG_MODE" == "true" ]]`

## JavaScript/Node.js Pattern

```javascript
#!/usr/bin/env node
/**
 * Example script with mise [env] configuration.
 */

// ADR: 2025-12-08-mise-env-centralized-config
// Configuration from environment with defaults
const TIMEOUT = parseInt(process.env.SCRIPT_TIMEOUT || "300", 10);
const OUTPUT_DIR = process.env.OUTPUT_DIR || "output";
const PARALLEL_WORKERS = parseInt(process.env.PARALLEL_WORKERS || "4", 10);
const DEBUG_MODE = process.env.DEBUG_MODE === "true";

async function main() {
  console.log(`Running with timeout=${TIMEOUT}, workers=${PARALLEL_WORKERS}`);
  // ... script logic
}

main().catch(console.error);
```

**Key points:**

- Use `process.env.VAR || "default"` pattern
- parseInt with radix 10 for numbers
- Boolean: strict equality check `=== "true"`
- Watch for falsy "0" - use `?? "default"` if "0" is valid

## Go Pattern

```go
package main

import (
    "fmt"
    "os"
    "strconv"
)

// ADR: 2025-12-08-mise-env-centralized-config
func getEnv(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
    if value := os.Getenv(key); value != "" {
        if i, err := strconv.Atoi(value); err == nil {
            return i
        }
    }
    return defaultValue
}

var (
    Timeout         = getEnvInt("SCRIPT_TIMEOUT", 300)
    OutputDir       = getEnv("OUTPUT_DIR", "output")
    ParallelWorkers = getEnvInt("PARALLEL_WORKERS", 4)
)

func main() {
    fmt.Printf("Running with timeout=%d, workers=%d\n", Timeout, ParallelWorkers)
}
```

## Rust Pattern

```rust
use std::env;

// ADR: 2025-12-08-mise-env-centralized-config
fn get_env_or(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

fn get_env_int(key: &str, default: i32) -> i32 {
    env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn main() {
    let timeout = get_env_int("SCRIPT_TIMEOUT", 300);
    let output_dir = get_env_or("OUTPUT_DIR", "output");
    let workers = get_env_int("PARALLEL_WORKERS", 4);

    println!("Running with timeout={}, workers={}", timeout, workers);
}
```

## Complete .mise.toml Template

```toml
# .mise.toml - Centralized configuration for this skill/project
# Values auto-load when shell has `mise activate` configured
# Scripts MUST work without mise (use defaults)

# ==============================================================================
# ENVIRONMENT CONFIGURATION
# ==============================================================================
[env]
# Timeouts (seconds)
SCRIPT_TIMEOUT = "300"
JSCPD_TIMEOUT = "120"

# Paths (relative to project root)
OUTPUT_DIR = "output"
ADR_DIR = "docs/adr"
DESIGN_DIR = "docs/design"

# Performance tuning
PARALLEL_WORKERS = "4"

# Feature flags
DEBUG_MODE = "false"
VERBOSE = "false"

# External service configuration (non-secrets only)
DOPPLER_PROJECT = "my-project"
DOPPLER_CONFIG = "prd"

# ==============================================================================
# OPTIONAL: Tool versions (separate concern from env config)
# ==============================================================================
# [tools]
# python = "3.11"
# node = "20"

# ==============================================================================
# OPTIONAL: Task definitions
# ==============================================================================
# [tasks]
# test = "pytest"
# lint = "ruff check ."
```

## Real-World Examples

### code-hardcode-audit/.mise.toml

```toml
[env]
AUDIT_PARALLEL_WORKERS = "4"
AUDIT_JSCPD_TIMEOUT = "300"
AUDIT_GITLEAKS_TIMEOUT = "120"
AUDIT_OUTPUT_FORMAT = "both"
PYTHONUNBUFFERED = "1"
```

### pypi-doppler/.mise.toml

```toml
[env]
DOPPLER_PROJECT = "claude-config"
DOPPLER_CONFIG = "prd"
DOPPLER_PYPI_SECRET = "PYPI_TOKEN"
PYPI_VERIFY_DELAY = "3"
```

### implement-plan-preflight/.mise.toml

```toml
[env]
ADR_DIR = "docs/adr"
DESIGN_DIR = "docs/design"
DESIGN_SPEC_FILENAME = "spec.md"
PREFLIGHT_STRICT_MODE = "true"
```

## Testing Pattern

```bash
# Test 1: Without mise (uses defaults)
unset SCRIPT_TIMEOUT OUTPUT_DIR
./script.py  # Should work with defaults

# Test 2: With mise activated
cd /path/to/skill
mise trust .mise.toml  # First time only
# Values auto-load from .mise.toml
./script.py  # Uses mise values

# Test 3: Override specific value
SCRIPT_TIMEOUT=60 ./script.py  # Explicit override wins
```

## Migration Checklist

When refactoring existing scripts to use mise `[env]`:

- [ ] Identify all hardcoded values (grep for magic numbers, paths)
- [ ] Create `.mise.toml` with `[env]` section
- [ ] Update script: add `os.environ.get()` with original as default
- [ ] Add ADR reference comment at config section
- [ ] Test: unset env vars, verify defaults work
- [ ] Test: set env vars manually, verify override works
- [ ] Test: in mise-activated shell, verify .mise.toml values load
- [ ] Document variables in skill's SKILL.md
