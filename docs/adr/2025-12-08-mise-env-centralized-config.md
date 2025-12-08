---
status: accepted
date: 2025-12-08
decision-maker: Terry Li
consulted: [Claude Opus 4.5]
research-method: single-agent
clarification-iterations: 3
perspectives: [Configuration, Backward-Compatibility, Developer-Experience]
---

# mise Environment Variables as Centralized Configuration

**Design Spec**: [Implementation Spec](/docs/design/2025-12-08-mise-env-centralized-config/spec.md)

## Context and Problem Statement

The ITP workflow invokes several skills (`code-hardcode-audit`, `semantic-release`, `pypi-doppler`, `implement-plan-preflight`) that contain hardcoded configuration values scattered across Python and Bash scripts. These values include:

- Timeouts (300s for jscpd, 120s for gitleaks)
- Parallel worker counts (4)
- Doppler project/config names
- Directory paths for ADRs and design specs

Users have no way to customize these values without modifying source code. Meanwhile, `/itp:setup` has robust mise integration for tool detection, but the skills themselves don't leverage mise's `[env]` feature for configuration.

### Before State

Scripts have hardcoded values that users cannot override without code changes.

```
 🔒 Before: Hardcoded Configuration

        ╭──────────────────╮
        │      Script      │
        ╰──────────────────╯
          │
          │
          ∨
        ╔══════════════════╗
        ║ Hardcoded Values ║
        ║   timeout=300    ║
        ║    workers=4     ║
        ╚══════════════════╝
          │
          │ locked
          ∨
        ┌──────────────────┐
        │    Execution     │
        └──────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🔒 Before: Hardcoded Configuration"; flow: south; }
[ Script ] { shape: rounded; }
[ Hardcoded Values\ntimeout=300\nworkers=4 ] { border: double; }
[ Script ] -> [ Hardcoded Values\ntimeout=300\nworkers=4 ] -- locked --> [ Execution ]
```

</details>

### After State

mise `[env]` provides centralized configuration with graceful fallback for users without mise.

```
🔓 After: mise [env] Centralized Config

         ╔═════════════════════╗
         ║     .mise.toml      ║
         ╚═════════════════════╝
           │
           │ pre-loads
           ∨
         ┌─────────────────────┐
         │  Shell Environment  │
         └─────────────────────┘
           │
           │
           ∨
         ╭─────────────────────╮
         │       Script        │
         ╰─────────────────────╯
           │
           │ defaults if no env
           ∨
         ┌─────────────────────┐
         │      Execution      │
         └─────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🔓 After: mise [env] Centralized Config"; flow: south; }
[ .mise.toml ] { border: double; }
[ Shell Environment ]
[ Script ] { shape: rounded; }
[ Execution ]
[ .mise.toml ] -- pre-loads --> [ Shell Environment ]
[ Shell Environment ] -> [ Script ]
[ Script ] -- defaults if no env --> [ Execution ]
```

</details>

## Research Summary

Investigation of ITP skills revealed hardcoded values in 4 skills:

1. **code-hardcode-audit**: `timeout=300`, `timeout=120`, `max_workers=4`
2. **pypi-doppler**: `DOPPLER_PROJECT="claude-config"`, `DOPPLER_CONFIG="prd"`
3. **implement-plan-preflight**: `ADR_DIR`, `DESIGN_DIR`, required field lists
4. **semantic-release**: `docs/adr`, `docs/design` paths

The `/itp:setup` command already has mise detection (`HAS_MISE` variable) but skills don't use mise's `[env]` feature.

## Decision Log

| Date       | Decision                                              | Rationale                                   |
| ---------- | ----------------------------------------------------- | ------------------------------------------- |
| 2025-12-08 | Use mise `[env]` only, not `mise exec`                | Avoid forcing tool version control          |
| 2025-12-08 | Require backward compatibility via `os.environ.get()` | Not all users have mise installed           |
| 2025-12-08 | Include optional `[tasks]` sections                   | Convenience for users who want task aliases |
| 2025-12-08 | Target all 4 ITP-invoked skills                       | Comprehensive configuration centralization  |

## Synthesis

The combination of mise `[env]` for configuration with `os.environ.get()` fallbacks creates a flexible system where:

- **With mise**: Environment variables are automatically set when entering the skill directory
- **Without mise**: Scripts use hardcoded defaults (same as current behavior)
- **Manual override**: Users can set env vars directly regardless of mise

This approach respects user choice while providing improved developer experience for mise users.

## Decision Drivers

- **Centralized configuration**: Single source of truth in `.mise.toml`
- **Backward compatibility**: Scripts MUST work without mise installed
- **No tool lock-in**: Don't force mise-controlled tool versions
- **Transparency**: Defaults match current hardcoded values exactly
- **Overridability**: Users can customize via env vars or mise config

## Considered Options

1. **mise [env] only** - Environment variables as configuration, no tool version control
2. **mise exec wrappers** - Force all tool invocations through mise
3. **Dedicated config files** - JSON/YAML config files per skill
4. **No change** - Keep hardcoded values

## Decision Outcome

**Chosen option**: "mise [env] only" because it provides centralized configuration while maintaining backward compatibility. Scripts use `os.environ.get("VAR", "default")` in Python and `${VAR:-default}` in Bash, working identically with or without mise.

### Consequences

**Good**:

- Users with mise get automatic configuration loading
- Users without mise experience no change (defaults work)
- Configuration is visible and documented in `.mise.toml`
- No additional dependencies or complexity

**Neutral**:

- Requires reading `.mise.toml` to understand available options

**Bad**:

- Two places to check for configuration (env vars and code defaults)

## Architecture

```
                        🏗️ Configuration Architecture

╔════════════╗     ╭───────────────╮  sets vars   ┌───────────┐     ┌────────┐
║ .mise.toml ║ ──> │ mise activate │ ───────────> │ Shell Env │ ──> │ Script │
╚════════════╝     ╰───────────────╯              └───────────┘     └────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Configuration Architecture"; flow: east; }
[ .mise.toml ] { border: double; }
[ mise activate ] { shape: rounded; }
[ Shell Env ]
[ Script ]
[ .mise.toml ] -> [ mise activate ] -- sets vars --> [ Shell Env ] -> [ Script ]
```

</details>

### Skills to Modify

| Skill                      | Files                                  | Env Vars                                     |
| -------------------------- | -------------------------------------- | -------------------------------------------- |
| `code-hardcode-audit`      | `.mise.toml`, `audit_hardcodes.py`     | `AUDIT_PARALLEL_WORKERS`, `*_TIMEOUT`        |
| `pypi-doppler`             | `.mise.toml`, `publish-to-pypi.sh`     | `DOPPLER_PROJECT`, `DOPPLER_CONFIG`          |
| `implement-plan-preflight` | `.mise.toml`, `preflight_validator.py` | `ADR_DIR`, `DESIGN_DIR`, `*_REQUIRED_FIELDS` |
| `semantic-release`         | `.mise.toml`, `generate-adr-notes.mjs` | `ADR_DIR`, `DESIGN_DIR`                      |

### Configuration Pattern

```python
# Python pattern
timeout = int(os.environ.get("AUDIT_JSCPD_TIMEOUT", "300"))
```

```bash
# Bash pattern
DOPPLER_PROJECT="${DOPPLER_PROJECT:-claude-config}"
```

## Validation

- [ ] Scripts work WITH mise activated (env vars pre-loaded)
- [ ] Scripts work WITHOUT mise (defaults applied)
- [ ] Default values match current hardcoded values exactly
- [ ] `.mise.toml` files document all configurable options

## More Information

- **Related**: `/itp:setup` already detects mise for tool installation
- **Source Plan**: `~/.claude/plans/whimsical-juggling-cookie.md`
