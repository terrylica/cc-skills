---
name: dead-code-detector
description: Detect unused/unreachable code in polyglot codebases (Python, TypeScript, Rust). TRIGGERS - dead code, unused functions, unused imports, unreachable code.
allowed-tools: Read, Grep, Bash, Edit, Write
---

# Dead Code Detector

Find and remove unused code across Python, TypeScript, and Rust codebases.

## Tools by Language

| Language   | Tool                                                      | Detects                                       |
| ---------- | --------------------------------------------------------- | --------------------------------------------- |
| Python     | [vulture](https://github.com/jendrikseipp/vulture) v2.14+ | Unused imports, functions, classes, variables |
| TypeScript | [knip](https://knip.dev/) v5.0+                           | Unused exports, dependencies, files           |
| Rust       | `cargo clippy` + `rustc` lints                            | Unused functions, imports, dead_code warnings |

**Why these tools?**

- **vulture**: AST-based, confidence scoring (60-100%), whitelist support
- **knip**: Successor to ts-prune (maintenance mode), monorepo-aware, auto-fix
- **cargo clippy**: Built-in to Rust toolchain, zero additional deps

---

## When to Use This Skill

Use this skill when:

- Cleaning up a codebase before release
- Refactoring to reduce maintenance burden
- Investigating bundle size / compile time issues
- Onboarding to understand what code is actually used

**NOT for**: Code duplication (use `quality-tools:code-clone-assistant`)

---

## Quick Start Workflow

### Python (vulture)

```bash
# Step 1: Install
uv pip install vulture

# Step 2: Scan with 80% confidence threshold
vulture src/ --min-confidence 80

# Step 3: Generate whitelist for false positives
vulture src/ --make-whitelist > vulture_whitelist.py

# Step 4: Re-scan with whitelist
vulture src/ vulture_whitelist.py --min-confidence 80
```

### TypeScript (knip)

```bash
# Step 1: Install (project-local recommended)
bun add -d knip

# Step 2: Initialize config
bunx knip --init

# Step 3: Scan for dead code
bunx knip

# Step 4: Auto-fix (removes unused exports)
bunx knip --fix
```

### Rust (cargo clippy)

```bash
# Step 1: Scan for dead code warnings
cargo clippy -- -W dead_code -W unused_imports -W unused_variables

# Step 2: For stricter enforcement
cargo clippy -- -D dead_code  # Deny (error) instead of warn

# Step 3: Auto-fix what's possible
cargo clippy --fix --allow-dirty
```

---

## Confidence and False Positives

### Python (vulture)

| Confidence | Meaning                                     | Action                          |
| ---------- | ------------------------------------------- | ------------------------------- |
| 100%       | Guaranteed unused in analyzed files         | Safe to remove                  |
| 80-99%     | Very likely unused                          | Review before removing          |
| 60-79%     | Possibly unused (dynamic calls, frameworks) | Add to whitelist if intentional |

**Common false positives**:

- Django/Flask view functions (called by framework)
- pytest fixtures (implicitly used)
- `__all__` exports
- Celery tasks

### TypeScript (knip)

Knip uses TypeScript's type system for accuracy. Configure in `knip.json`:

```json
{
  "entry": ["src/index.ts"],
  "project": ["src/**/*.ts"],
  "ignore": ["**/*.test.ts"],
  "ignoreDependencies": ["@types/*"]
}
```

### Rust

Suppress false positives with attributes:

```rust
#[allow(dead_code)]  // Single item
fn intentionally_unused() {}

// Or module-wide
#![allow(dead_code)]
```

---

## Integration with CI

### Python (pyproject.toml)

```toml
[tool.vulture]
min_confidence = 80
paths = ["src"]
exclude = ["*_test.py", "conftest.py"]
```

### TypeScript (package.json)

```json
{
  "scripts": {
    "dead-code": "knip",
    "dead-code:fix": "knip --fix"
  }
}
```

### Rust (Cargo.toml)

```toml
[lints.rust]
dead_code = "warn"
unused_imports = "warn"
```

---

## Reference Documentation

For detailed information, see:

- [Python Workflow](./references/python-workflow.md) - vulture advanced usage
- [TypeScript Workflow](./references/typescript-workflow.md) - knip configuration
- [Rust Workflow](./references/rust-workflow.md) - clippy lint categories

---

## Troubleshooting

| Issue                         | Cause                     | Solution                                                           |
| ----------------------------- | ------------------------- | ------------------------------------------------------------------ |
| vulture reports Django views  | Framework magic           | Add to whitelist: `vulture --make-whitelist`                       |
| knip misses dynamic imports   | Not in entry points       | Add to `entry` array in knip.json                                  |
| Rust warns about test helpers | Tests compiled separately | Use `#[cfg(test)]` module with `#[allow(...)]`                     |
| Too many false positives      | Threshold too low         | Increase `--min-confidence` (vulture) or configure ignore patterns |
| Missing type exports (TS)     | Type-only exports         | knip handles these automatically since v5                          |

---

## Sources

- [vulture GitHub](https://github.com/jendrikseipp/vulture)
- [knip documentation](https://knip.dev/)
- [Effective TypeScript: Use knip](https://effectivetypescript.com/2023/07/29/knip/)
- [Rust dead_code lint](https://doc.rust-lang.org/rust-by-example/attribute/unused.html)
- [DCE-LLM research paper](https://aclanthology.org/2025.naacl-long.501.pdf) (emerging LLM-based approach)
