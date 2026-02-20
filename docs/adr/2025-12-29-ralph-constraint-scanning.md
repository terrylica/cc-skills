---
status: accepted
date: 2025-12-29
---

# Ralph Constraint Scanning

## Status

Accepted

## Context and Problem Statement

Ralph autonomous loop mode is overly constrained by the alpha-forge environment, lacking freedom to:

- Refactor code structure (hardcoded paths block changes)
- Adhere to encourage/prohibit lists effectively (no systematic detection)
- Explore frontier methods (rigid structure assumptions prevent experimentation)

Additionally, the term "preflight" was overloaded:

| Usage                   | Component               | Purpose                             |
| ----------------------- | ----------------------- | ----------------------------------- |
| Preflight verifier      | `preflight-verifier.sh` | Verify hooks installed before start |
| Preflight scanner (OLD) | `preflight-scanner.py`  | Detect environment constraints      |

This created confusion in documentation and code.

## Decision Drivers

- Dynamic worktree detection (not hardcoded `~/eon/alpha-forge`)
- Clear terminology separation from existing "preflight" verifier
- 4-tier severity system for actionable prioritization
- AskUserQuestion integration for user screening
- Backwards compatibility with existing v2.0.0 configs

## Considered Options

1. **Add constraints to existing config** - Embed detection in `ralph:start` bash script
2. **Standalone Python scanner** - Dedicated tool with clear naming
3. **Hook-based detection** - Add PreToolUse hook for real-time constraint detection

## Decision Outcome

Chosen option: **Option 2 - Standalone Python scanner** renamed to `constraint-scanner.py` because:

- Clear separation of concerns (scanning vs execution)
- Python enables complex regex and JSON output
- Can run independently for debugging
- Avoids naming collision with `preflight-verifier.sh`

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  CONSTRAINT SCANNING WORKFLOW                                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  /ralph:start                                                    │    │
│  │  ──────────────────────────────────────────────────────────────  │    │
│  │  Step 1.5: Preset Confirmation                                   │    │
│  │  Step 1.6: Session Guidance (if Alpha Forge)                     │    │
│  └───────────────────────────────┬─────────────────────────────────┘    │
│                                  │                                       │
│                                  ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  constraint-scanner.py                                           │    │
│  │  ──────────────────────────────────────────────────────────────  │    │
│  │  • Dynamic worktree detection (git rev-parse --git-common-dir)   │    │
│  │  • 4-tier severity: CRITICAL > HIGH > MEDIUM > LOW               │    │
│  │  • Scans: hardcoded paths, rigid structure, global config        │    │
│  │  • Output: ~/.claude/ralph-constraint-scan-results.json          │    │
│  └───────────────────────────────┬─────────────────────────────────┘    │
│                                  │                                       │
│                                  ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  AskUserQuestion (3-panel flow)                                  │    │
│  │  ──────────────────────────────────────────────────────────────  │    │
│  │  Panel 1: PROHIBIT (multiSelect) - from CRITICAL/HIGH items     │    │
│  │  Panel 2: ENCOURAGE (multiSelect) - from built-in busywork      │    │
│  │  Panel 3: CONTINUE? (single) - deep-dive or done                │    │
│  └───────────────────────────────┬─────────────────────────────────┘    │
│                                  │                                       │
│                                  ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  ralph-config.json v3.0.0                                        │    │
│  │  ──────────────────────────────────────────────────────────────  │    │
│  │  guidance:                                                       │    │
│  │    forbidden: ["Hardcoded path in settings.json:15", ...]        │    │
│  │    encouraged: ["Refactoring freedom", ...]                      │    │
│  │    timestamp: "2025-12-29T10:00:00Z"                             │    │
│  │  constraint_scan: { ... scan results ... }                       │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
[ /ralph:start\n────────────\nStep 1.5: Preset Confirmation\nStep 1.6: Session Guidance ] --> [ constraint-scanner.py\n────────────────────────\n• Dynamic worktree detection\n• 4-tier severity\n• Scans all config files\n• JSON output ]

[ constraint-scanner.py\n────────────────────────\n• Dynamic worktree detection\n• 4-tier severity\n• Scans all config files\n• JSON output ] --> [ AskUserQuestion\n────────────────\nPanel 1: PROHIBIT\nPanel 2: ENCOURAGE\nPanel 3: CONTINUE? ]

[ AskUserQuestion\n────────────────\nPanel 1: PROHIBIT\nPanel 2: ENCOURAGE\nPanel 3: CONTINUE? ] --> [ ralph-config.json v3.0.0\n────────────────────────\nguidance:\n  forbidden: [...]\n  encouraged: [...]\nconstraint_scan: {...} ]
```

</details>

### 4-Tier Severity System

| Severity | Ralph Action             | Example                          |
| -------- | ------------------------ | -------------------------------- |
| CRITICAL | Block loop start         | Current user home path hardcoded |
| HIGH     | Escalate to user via AUQ | `/Users/someone/` in config      |
| MEDIUM   | Show in deep-dive        | `outputs/runs/` dependency       |
| LOW      | Log only                 | Non-Ralph hook detected          |

### Dynamic Worktree Detection

All scripts use `git rev-parse --git-common-dir` instead of hardcoded paths:

```bash
GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null || echo "")

if [[ "$GIT_COMMON_DIR" == .git ]]; then
    # Main worktree
    MAIN_ROOT="$(pwd)"
else
    # Linked worktree - git-common-dir points to main's .git
    MAIN_ROOT="$(dirname "$GIT_COMMON_DIR")"
fi
```

### Config Schema v3.0.0 (Pydantic)

Migration from dataclasses to Pydantic v2 with new fields:

```python
class GuidanceConfig(BaseModel):
    forbidden: list[str] = Field(default_factory=list)
    encouraged: list[str] = Field(default_factory=list)
    timestamp: str = ""

class ConstraintScanConfig(BaseModel):
    scan_timestamp: str = ""
    project_dir: str = ""
    worktree_type: str = ""  # "main" | "linked"
    constraints: list[dict] = Field(default_factory=list)
    builtin_busywork: list[dict] = Field(default_factory=list)

class RalphConfig(BaseModel):
    version: str = "3.0.0"
    guidance: GuidanceConfig = Field(default_factory=GuidanceConfig)
    constraint_scan: ConstraintScanConfig | None = None
    skip_constraint_scan: bool = False
    production_mode: bool = False
    # ... existing fields ...
```

### New CLI Flag

`--skip-constraint-scan` for power users who want to bypass the scanner:

```bash
/ralph:start --skip-constraint-scan --production
```

## Consequences

### Positive

- Clear terminology: "constraint scanner" vs "preflight verifier"
- Dynamic detection works in any worktree configuration
- 4-tier severity enables actionable prioritization
- Pydantic v2 provides validation and better error messages
- filelock prevents race conditions in concurrent sessions
- Backwards compatible: v2.0.0 configs still parse correctly

### Negative

- Additional dependency: `pydantic>=2.10.0`, `filelock>=3.20.0`
- Scanner adds ~2-3 seconds to `/ralph:start` latency
- Deep-dive AUQ flow can extend startup time for verbose users

## Related

- [ADR 2025-12-20: Ralph Eternal Loop](/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md)
- [ADR 2025-12-14: Alpha Forge Worktree Management](/docs/adr/2025-12-14-alpha-forge-worktree-management.md)
- [README.md](/plugins/ru/README.md) - RU autonomous loop mode documentation
