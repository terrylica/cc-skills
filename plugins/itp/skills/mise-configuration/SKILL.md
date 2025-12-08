---
name: mise Configuration SSoT
description: This skill should be used when the user asks to "configure environment variables", "use mise env", "add mise configuration", "refactor hardcoded values", "centralize configuration", mentions "mise [env]", "mise.toml", or needs guidance on environment variable patterns with backward compatibility.
---

# mise Configuration as Single Source of Truth

Use mise `[env]` as centralized configuration with backward-compatible defaults.

## Core Principle

Define all configurable values in `.mise.toml` `[env]` section. Scripts read via environment variables with fallback defaults. Same code path works WITH or WITHOUT mise installed.

**Key insight**: mise auto-loads `[env]` values when shell has `mise activate` configured. Scripts using `os.environ.get("VAR", "default")` pattern work identically whether mise is present or not.

## When to Apply

- Creating new skills with configurable timeouts, paths, or thresholds
- Refactoring hardcoded values to environment variables
- Adding user-overridable settings to scripts
- Consolidating scattered configuration into single source

## Quick Reference

| Language   | Pattern                            | Notes                       |
| ---------- | ---------------------------------- | --------------------------- |
| Python     | `os.environ.get("VAR", "default")` | Returns string, cast if int |
| Bash       | `${VAR:-default}`                  | Standard POSIX expansion    |
| JavaScript | `process.env.VAR \|\| "default"`   | Falsy check, watch for "0"  |
| Go         | `os.Getenv("VAR")` with default    | Empty string if unset       |
| Rust       | `std::env::var("VAR").unwrap_or()` | Returns Result<String>      |

## Minimal .mise.toml

```toml
# .mise.toml - Single source of truth for configuration
# Values auto-load when mise activate is in shell

[env]
TIMEOUT = "300"
OUTPUT_DIR = "output"
DEBUG_MODE = "false"
```

## Existing Implementations

| Skill                    | Variables                                   | Purpose                  |
| ------------------------ | ------------------------------------------- | ------------------------ |
| code-hardcode-audit      | AUDIT_PARALLEL_WORKERS, AUDIT_JSCPD_TIMEOUT | Performance tuning       |
| pypi-doppler             | DOPPLER_PROJECT, DOPPLER_CONFIG             | Credential source        |
| implement-plan-preflight | ADR_DIR, DESIGN_DIR, DESIGN_SPEC_FILENAME   | Path conventions         |
| semantic-release         | ADR_DIR, DESIGN_DIR                         | Release note integration |

## Implementation Steps

1. **Identify hardcoded values** - timeouts, paths, thresholds, feature flags
2. **Create `.mise.toml`** - add `[env]` section with documented variables
3. **Update scripts** - use env vars with original values as defaults
4. **Add ADR reference** - comment: `# ADR: 2025-12-08-mise-env-centralized-config`
5. **Test without mise** - verify script works using defaults
6. **Test with mise** - verify activated shell uses `.mise.toml` values

## Variable Naming Convention

Use uppercase with underscores, prefixed by skill/tool context:

```
# Good - clear context
AUDIT_PARALLEL_WORKERS
DOPPLER_PROJECT
ADR_DIR

# Avoid - too generic
TIMEOUT
DIR
WORKERS
```

## Anti-Patterns to Avoid

| Anti-Pattern                  | Why                    | Instead                                              |
| ----------------------------- | ---------------------- | ---------------------------------------------------- |
| `mise exec -- script.py`      | Forces mise dependency | Use env vars with defaults                           |
| Tool version pinning via mise | Different concern      | Keep tool versions in separate `.mise.toml` sections |
| Secrets in `.mise.toml`       | Visible in repo        | Use Doppler for secrets                              |
| No defaults in scripts        | Breaks without mise    | Always provide fallback                              |

## Additional Resources

For complete code patterns and templates by language, see: **[`references/patterns.md`](./references/patterns.md)**

**ADR**: [mise Environment Variables as Centralized Configuration](/docs/adr/2025-12-08-mise-env-centralized-config.md)
