---
status: implemented
date: 2026-01-10
decision-maker: Terry Li
consulted: [lifecycle-reference.md, posttooluse-hook-visibility ADR]
research-method: multi-perspective-subagent-analysis
---

# ADR: UV Reminder Hook for Pip Usage

## Context and Problem Statement

Claude Code often forgets to use `uv` instead of `pip` for Python dependency management, despite user preferences documented in CLAUDE.md. This leads to:

- Slower dependency resolution (pip) vs 10-100x faster (uv)
- Missing lockfile management (uv.lock)
- Inconsistent reproducible builds

**User requirement**: Non-blocking reminder that nudges Claude toward `uv` after pip usage, without stopping command execution.

## Decision Drivers

- Must not block Claude's workflow ("without stopping")
- Should leverage existing hook infrastructure
- Zero-touch deployment (no manual `/itp:hooks install` after release)
- Follow lifecycle-reference.md patterns

## Considered Options

### Option A: Integrate into Existing Hook (Selected)

Modify `plugins/itp-hooks/hooks/posttooluse-reminder.sh` to add UV detection.

**Pros**:
- Zero-touch deployment after release
- No hooks.json modification needed
- Fits naturally with existing reminder patterns

**Cons**:
- Slightly longer script

### Option B: Create New Hook File

Create `plugins/itp-hooks/hooks/posttooluse-uv-reminder.sh`.

**Pros**:
- Clean separation of concerns

**Cons**:
- Requires hooks.json modification
- Requires manual `/itp:hooks install` after plugin update
- More moving parts

## Decision Outcome

**Chosen option**: Option A - Integrate into existing `posttooluse-reminder.sh`.

### Hook Type: PostToolUse (Not PreToolUse)

| Hook Type | Behavior | User Request |
|-----------|----------|--------------|
| PreToolUse | Blocks command BEFORE execution | "without stopping" |
| **PostToolUse** | Reminds AFTER command runs | Soft guidance |

**Key insight**: PostToolUse with `decision: "block"` doesn't actually block (tool already ran) - it just makes Claude SEE the message. This is the correct pattern for non-blocking reminders.

### Detection Patterns

**Pip patterns to detect**:
- `pip install <pkg>`
- `pip3 install <pkg>`
- `python -m pip install <pkg>`
- `pip uninstall <pkg>`

**Exception cases (no reminder)**:
- `uv pip install` - already in uv context
- `pip freeze` - lock file generation
- `pip-compile` - constraint compilation
- `echo "pip install"` - documentation/examples
- `# pip install` - comments

### Replacement Mapping

| Pip Command | UV Equivalent |
|------------|---------------|
| `pip install <pkg>` | `uv add <pkg>` |
| `pip uninstall <pkg>` | `uv remove <pkg>` |
| `pip install -e .` | `uv pip install -e .` |
| `pip install -r requirements.txt` | `uv sync` or `uv pip install -r requirements.txt` |

**Note**: Exception cases are only for lock file GENERATION (`pip freeze`, `pip-compile`), not installation from requirements files.

## Implementation

Added to `plugins/itp-hooks/hooks/posttooluse-reminder.sh` after the graph-easy check:

```bash
#--- Check for pip usage -> suggest uv ---
# ADR: 2026-01-10-uv-reminder-hook
if [[ -z "$REMINDER" ]]; then
    # Exception checks: uv context, documentation, lock file ops
    # Detection: pip/pip3/python -m pip + install/uninstall
    # Suggestion: Generate uv equivalent command
fi
```

## Consequences

### Positive

- Claude receives non-blocking reminders about uv
- Zero manual intervention after release
- Fits existing hook patterns

### Negative

- Reminder only appears AFTER pip command runs (by design)
- Claude must remember to use uv next time

## References

- [PostToolUse Hook Visibility ADR](/docs/adr/2025-12-17-posttooluse-hook-visibility.md)
- [lifecycle-reference.md](/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md)
- [CLAUDE.md toolchain section](/.claude/CLAUDE.md) - Python: uv
