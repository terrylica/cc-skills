---
adr: 2025-12-08-mise-env-centralized-config
source: ~/.claude/plans/whimsical-juggling-cookie.md
implementation-status: completed
phase: phase-2
last-updated: 2025-12-08
---

# mise Environment Variables as Centralized Configuration

**ADR**: [mise Environment Variables as Centralized Configuration](/docs/adr/2025-12-08-mise-env-centralized-config.md)

## User Requirements

- **Purpose**: Use mise `[env]` as centralized single source of truth for configuration
- **NOT**: Forcing mise-controlled tools (no `mise exec`, no tool version pinning)
- **Fallback**: Scripts MUST work without mise (use `os.environ.get()` with defaults)
- **Tasks**: Optional convenience aliases (not required)

## Design Principle

**mise [env] as Single Source of Truth**

- `.mise.toml` defines all configurable values
- Scripts read via `os.environ.get("VAR", "default")`
- Same code path works WITH or WITHOUT mise
- mise just pre-populates env vars when activated

---

## Implementation Overview

| Skill                        | Env Vars to Extract                | Tasks (Optional)     |
| ---------------------------- | ---------------------------------- | -------------------- |
| **code-hardcode-audit**      | Timeouts, workers                  | `mise run audit`     |
| **semantic-release**         | ADR paths                          | `mise run release`   |
| **pypi-doppler**             | Doppler project/config             | `mise run publish`   |
| **implement-plan-preflight** | Directory paths, validation fields | `mise run preflight` |

---

## 1. code-hardcode-audit

### Files to Modify

| File                                                                | Action |
| ------------------------------------------------------------------- | ------ |
| `plugins/itp/skills/code-hardcode-audit/.mise.toml`                 | Create |
| `plugins/itp/skills/code-hardcode-audit/scripts/audit_hardcodes.py` | Edit   |

### .mise.toml (New)

```toml
[env]
# Parallelism and timeouts (currently hardcoded in audit_hardcodes.py)
AUDIT_PARALLEL_WORKERS = "4"
AUDIT_JSCPD_TIMEOUT = "300"
AUDIT_GITLEAKS_TIMEOUT = "120"

# Output configuration
AUDIT_OUTPUT_FORMAT = "both"
PYTHONUNBUFFERED = "1"

# Optional: convenience tasks
[tasks.audit]
description = "Run full hardcode audit"
run = "uv run scripts/audit_hardcodes.py -- ${@:-.}"

[tasks."audit:secrets"]
description = "Run secret detection only"
run = "uv run scripts/run_gitleaks.py -- ${@:-.}"
```

### audit_hardcodes.py Changes

**Replace hardcoded values with env lookups (with defaults):**

```python
import os

# Replace hardcoded max_workers=4 (line ~316)
max_workers = int(os.environ.get("AUDIT_PARALLEL_WORKERS", "4"))

# Replace hardcoded timeout=300 in run_jscpd (line ~218)
jscpd_timeout = int(os.environ.get("AUDIT_JSCPD_TIMEOUT", "300"))

# Replace hardcoded timeout=120 in run_gitleaks (line ~264)
gitleaks_timeout = int(os.environ.get("AUDIT_GITLEAKS_TIMEOUT", "120"))
```

**Note**: Scripts still work without mise - defaults match current hardcoded values.

---

## 2. semantic-release

### Files to Modify

| File                                             | Action |
| ------------------------------------------------ | ------ |
| `plugins/itp/skills/semantic-release/.mise.toml` | Create |

### .mise.toml (New)

```toml
[env]
# ADR integration paths (used by generate-doc-notes.mjs)
ADR_DIR = "docs/adr"
DESIGN_DIR = "docs/design"

# Optional: convenience tasks
[tasks."release:dry"]
description = "Dry-run semantic-release"
run = "/usr/bin/env bash -c 'GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci --dry-run'"

[tasks.release]
description = "Execute semantic-release"
run = "/usr/bin/env bash -c 'GITHUB_TOKEN=$(gh auth token) npx semantic-release --no-ci'"
```

### generate-doc-notes.mjs Changes (if applicable)

```javascript
// Replace hardcoded paths (line 16-17)
const ADR_DIR = process.env.ADR_DIR || "docs/adr";
const DESIGN_DIR = process.env.DESIGN_DIR || "docs/design";
```

---

## 3. pypi-doppler

### Files to Modify

| File                                                         | Action |
| ------------------------------------------------------------ | ------ |
| `plugins/itp/skills/pypi-doppler/.mise.toml`                 | Create |
| `plugins/itp/skills/pypi-doppler/scripts/publish-to-pypi.sh` | Edit   |

### .mise.toml (New)

```toml
[env]
# Doppler configuration (currently hardcoded in publish-to-pypi.sh)
DOPPLER_PROJECT = "claude-config"
DOPPLER_CONFIG = "prd"
DOPPLER_PYPI_SECRET = "PYPI_TOKEN"

# Build configuration
PYPI_VERIFY_DELAY = "3"

# Optional: convenience tasks
[tasks.publish]
description = "Build and publish to PyPI"
run = "bash scripts/publish-to-pypi.sh"
```

### publish-to-pypi.sh Changes

**Replace hardcoded Doppler config with env lookups:**

```bash
# Replace hardcoded values (around line 293-294)
DOPPLER_PROJECT="${DOPPLER_PROJECT:-claude-config}"
DOPPLER_CONFIG="${DOPPLER_CONFIG:-prd}"
DOPPLER_PYPI_SECRET="${DOPPLER_PYPI_SECRET:-PYPI_TOKEN}"
PYPI_VERIFY_DELAY="${PYPI_VERIFY_DELAY:-3}"

# Use variables in doppler command
doppler secrets get "$DOPPLER_PYPI_SECRET" --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" --plain
```

**Note**: Keep existing tool discovery logic (don't remove it).

---

## 4. implement-plan-preflight

### Files to Modify

| File                                                                         | Action |
| ---------------------------------------------------------------------------- | ------ |
| `plugins/itp/skills/implement-plan-preflight/.mise.toml`                     | Create |
| `plugins/itp/skills/implement-plan-preflight/scripts/preflight_validator.py` | Edit   |

### .mise.toml (New)

```toml
[env]
# Directory structure (currently hardcoded in preflight_validator.py)
ADR_DIR = "docs/adr"
DESIGN_DIR = "docs/design"
DESIGN_SPEC_FILENAME = "spec.md"

# Validation config (currently hardcoded)
ADR_REQUIRED_FIELDS = "status,date,decision-maker,consulted,research-method,clarification-iterations,perspectives"
SPEC_REQUIRED_FIELDS = "adr,source,implementation-status,phase,last-updated"
REQUIRED_DIAGRAM_COUNT = "2"

# Optional: convenience task
[tasks."preflight:validate"]
description = "Validate ADR and design spec"
run = "uv run scripts/preflight_validator.py $@"
```

### preflight_validator.py Changes

```python
import os

# Replace hardcoded directories (line 16-17)
ADR_DIR = os.environ.get("ADR_DIR", "docs/adr")
DESIGN_DIR = os.environ.get("DESIGN_DIR", "docs/design")

# Replace hardcoded required fields (line 34-42)
ADR_REQUIRED_FIELDS = os.environ.get(
    "ADR_REQUIRED_FIELDS",
    "status,date,decision-maker,consulted,research-method,clarification-iterations,perspectives"
).split(",")
```

---

## Implementation Checklist

### Phase 1: code-hardcode-audit

- [x] Create `.mise.toml` with `[env]` section
- [x] Update `audit_hardcodes.py`: replace hardcoded timeouts/workers with `os.environ.get()`
- [x] Verify: script works WITH mise (env pre-loaded)
- [x] Verify: script works WITHOUT mise (uses defaults)

### Phase 2: pypi-doppler

- [x] Create `.mise.toml` with `[env]` section
- [x] Update `publish-to-pypi.sh`: replace hardcoded Doppler config with `${VAR:-default}`
- [x] Keep existing tool discovery logic (don't remove)

### Phase 3: implement-plan-preflight

- [x] Create `.mise.toml` with `[env]` section
- [x] Update `preflight_validator.py`: replace hardcoded paths/fields with `os.environ.get()`

### Phase 4: semantic-release

- [x] Create `.mise.toml` with `[env]` section
- [x] Update `generate-doc-notes.mjs` if it has hardcoded paths

---

## Files Summary

| File                                                                         | Action | Purpose                       |
| ---------------------------------------------------------------------------- | ------ | ----------------------------- |
| `plugins/itp/skills/code-hardcode-audit/.mise.toml`                          | Create | Env vars for timeouts/workers |
| `plugins/itp/skills/code-hardcode-audit/scripts/audit_hardcodes.py`          | Edit   | Read env with defaults        |
| `plugins/itp/skills/pypi-doppler/.mise.toml`                                 | Create | Env vars for Doppler config   |
| `plugins/itp/skills/pypi-doppler/scripts/publish-to-pypi.sh`                 | Edit   | Read env with defaults        |
| `plugins/itp/skills/implement-plan-preflight/.mise.toml`                     | Create | Env vars for paths/validation |
| `plugins/itp/skills/implement-plan-preflight/scripts/preflight_validator.py` | Edit   | Read env with defaults        |
| `plugins/itp/skills/semantic-release/.mise.toml`                             | Create | Env vars for ADR paths        |

---

## Benefits

1. **Centralized config**: `.mise.toml` is single source of truth
2. **Backward compatible**: Scripts work with or without mise
3. **Transparent**: Defaults match current hardcoded values
4. **Overridable**: Users can customize via env vars or mise config
5. **No tool lock-in**: Tools invoked directly, not through mise
