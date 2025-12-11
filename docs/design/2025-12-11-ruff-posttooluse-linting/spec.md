---
adr: 2025-12-11-ruff-posttooluse-linting
source: ~/.claude/plans/lazy-forging-engelbart.md
implementation-status: implemented
phase: phase-1
last-updated: 2025-12-11
---

# Ruff PostToolUse Linting - Implementation Spec

**ADR**: [Ruff PostToolUse Linting](/docs/adr/2025-12-11-ruff-posttooluse-linting.md)

## Problem Statement

AI coding agents often hallucinate during implementation - they don't follow error handling principles, use outdated syntax, or introduce common bugs. Instead of relying on Claude's memory of the `impl-standards` skill, implement **deterministic enforcement** using Ruff integrated into the existing PostToolUse hook.

**Scope Decision**: Comprehensive linting with **warnings only** (no auto-fix) - Claude sees issues and decides what to fix.

---

## Implementation Tasks

### Task 1: Integrate Ruff into PostToolUse Hook

**File**: `plugins/itp-hooks/hooks/posttooluse-reminder.sh`

**Integration Point** (existing code block for .py files):

```bash
elif [[ "$FILE_PATH" =~ ^(src/|lib/|scripts/|plugins/[^/]+/skills/[^/]+/scripts/) ]] || \
     [[ "$FILE_PATH" =~ \.(py|ts|js|mjs|rs|go)$ ]]; then
```

**New Logic** (comprehensive linting, warnings only):

```bash
# For Python files, run comprehensive Ruff checks
if [[ "$FILE_PATH" =~ \.py$ ]]; then
    # Comprehensive rule set: error handling + idiomatic Python
    RUFF_OUTPUT=$(ruff check "$FILE_PATH" \
        --select BLE,S110,E722,F,UP,SIM,B,I,RUF \
        --ignore D,ANN \
        --no-fix \
        --output-format=concise \
        2>/dev/null | head -20)

    if [[ -n "$RUFF_OUTPUT" ]]; then
        REMINDER="[RUFF] Issues detected in ${BASENAME}:
${RUFF_OUTPUT}
Run 'ruff check ${FILE_PATH} --fix' to auto-fix safe issues."
    fi
fi
```

### Task 2: Update impl-standards Skill

**File**: `plugins/itp/skills/impl-standards/SKILL.md`

**Keep the skill** but add reference to deterministic enforcement:

1. Add section explaining the PostToolUse hook enforcement
2. Document which violations are auto-detected vs require manual review
3. Link to Ruff rule documentation for context

### Task 3: Create Ruff Configuration (Optional)

**File**: `plugins/itp-hooks/hooks/ruff.toml`

```toml
# Comprehensive Python linting for Claude Code hooks
[lint]
select = [
    "BLE",   # Blind except
    "S110",  # try-except-pass
    "E722",  # Bare except
    "F",     # Pyflakes
    "UP",    # Pyupgrade
    "SIM",   # Simplify
    "B",     # Bugbear
    "I",     # Isort
    "RUF",   # Ruff-specific
]
ignore = [
    "D",     # Docstrings (too noisy)
    "ANN",   # Type annotations (use mypy)
]

[lint.per-file-ignores]
"**/test_*.py" = ["S110", "B011"]  # Allow in test setup/teardown
"**/*_test.py" = ["S110", "B011"]
"**/conftest.py" = ["F401"]        # Allow unused imports in fixtures
```

---

## Ruff Rule Categories Enabled

| Category       | Code   | What It Catches                                     |
| -------------- | ------ | --------------------------------------------------- |
| Error Handling | `BLE`  | Blind except (`except Exception:`)                  |
| Error Handling | `S110` | try-except-pass (silent failures)                   |
| Error Handling | `E722` | Bare `except:` without type                         |
| Pyflakes       | `F`    | Unused imports, undefined names, shadowed vars      |
| Pyupgrade      | `UP`   | Outdated syntax (`Union` → `\|`, old-style classes) |
| Simplify       | `SIM`  | Unnecessary else, overly complex expressions        |
| Bugbear        | `B`    | Mutable default args, `getattr` with constant       |
| Isort          | `I`    | Import ordering                                     |
| Ruff-specific  | `RUF`  | Ruff's own rules (unused noqa, etc.)                |

**Ignored**: `D` (docstrings - too noisy), `ANN` (type annotations - handled by mypy)

---

## Files to Modify

| File                                              | Action                                        |
| ------------------------------------------------- | --------------------------------------------- |
| `plugins/itp-hooks/hooks/posttooluse-reminder.sh` | Add comprehensive Ruff linting for .py files  |
| `plugins/itp/skills/impl-standards/SKILL.md`      | Add enforcement documentation                 |
| `plugins/itp-hooks/hooks/ruff.toml`               | Create (optional) Ruff config for consistency |

---

## Success Criteria

- [ ] PostToolUse hook runs Ruff on .py file edits
- [ ] All 9 rule categories trigger warnings (BLE, S110, E722, F, UP, SIM, B, I, RUF)
- [ ] Non-blocking (exit code 0 always, just outputs reminder)
- [ ] Performance acceptable (Ruff is fast, <100ms)
- [ ] Output limited to 20 lines (prevents wall of text)
- [ ] Reminder includes fix command for user convenience
- [ ] impl-standards skill updated with enforcement docs

---

## Test Cases

```bash
# Test file with known violations
cat > /tmp/test_ruff.py << 'EOF'
import os  # F401: unused import
from typing import Optional  # UP007: use X | None

def foo(items=[]):  # B006: mutable default argument
    try:
        pass
    except:  # E722: bare except
        pass  # S110: try-except-pass
EOF

# Should trigger multiple warnings
ruff check /tmp/test_ruff.py --select BLE,S110,E722,F,UP,SIM,B,I,RUF
```

---

## Decision: Keep impl-standards Skill

The skill provides valuable context that static analysis cannot:

- **Why** proper error handling matters
- **Patterns** to follow (not just anti-patterns to avoid)
- **ADR traceability** guidance

Enforcement via hooks handles the "what not to do"; the skill handles the "what to do instead".
