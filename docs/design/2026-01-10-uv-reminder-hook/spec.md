---
adr: 2026-01-10-uv-reminder-hook
source: session-continuation (2026-01-22)
implementation-status: completed
phase: phase-1
last-updated: 2026-01-22
---

# UV Reminder Hook

**ADR**: [UV Reminder Hook for Pip Usage](/docs/adr/2026-01-10-uv-reminder-hook.md)

## Problem Statement

Claude Code often forgets to use `uv` instead of `pip` for Python dependency management, despite user preferences documented in CLAUDE.md. This leads to:

- Slower dependency resolution (pip) vs 10-100x faster (uv)
- Missing lockfile management (uv.lock)
- Inconsistent reproducible builds

## Solution Overview

PostToolUse reminder hook integrated into `posttooluse-reminder.ts` (TypeScript/Bun):

| Pattern                           | Reminder                                      |
| --------------------------------- | --------------------------------------------- |
| `pip install <pkg>`               | Use `uv add <pkg>`                            |
| `pip uninstall <pkg>`             | Use `uv remove <pkg>`                         |
| `pip install -e .`                | Use `uv pip install -e .`                     |
| `pip install -r requirements.txt` | Use `uv sync`                                 |
| `source .venv/bin/activate`       | Use `uv run <command>` (no activation needed) |

## Implementation

### TypeScript Hook (Bun Runtime)

**File**: `plugins/itp-hooks/hooks/posttooluse-reminder.ts`

```typescript
function checkVenvActivation(command: string): string | null {
  const commandLower = command.toLowerCase();

  // Exception: documentation/echo context
  if (/^\s*(echo|printf)|grep.*venv/i.test(commandLower)) {
    return null;
  }

  // Detect: source .venv/bin/activate, . .venv/bin/activate, etc.
  const venvPattern = /(source|\.)\s+[^|;&]*\.?venv\/bin\/activate/i;
  if (!venvPattern.test(commandLower)) {
    return null;
  }

  return `[UV-REMINDER] venv activation detected - use 'uv run' instead...`;
}

function checkPipUsage(command: string): string | null {
  const commandLower = command.toLowerCase();

  // Exceptions: uv context, documentation, lock file generation
  if (/^\s*uv\s+(run|exec|pip)/i.test(commandLower)) return null;
  if (/^\s*#|^\s*echo.*pip|grep.*pip/i.test(commandLower)) return null;
  if (/pip-compile|pip\s+freeze/i.test(commandLower)) return null;

  // Detect pip usage
  const pipPattern =
    /(^|\s|"|'|&&\s*)(pip|pip3|python[0-9.]*\s+(-m\s+)?pip)\s+(install|uninstall)/i;
  if (!pipPattern.test(commandLower)) return null;

  // Generate suggested replacement
  let suggested = command
    .replace(/pip install/gi, "uv add")
    .replace(/pip3 install/gi, "uv add")
    .replace(/pip uninstall/gi, "uv remove");

  return `[UV-REMINDER] pip detected - use uv instead...`;
}
```

### Detection Priority

1. **graph-easy** (highest) - tracks state for PreToolUse exemption
2. **venv activation** - `source .venv/bin/activate` patterns
3. **pip usage** - `pip install/uninstall` patterns

### Exception Patterns

| Pattern              | Why Allowed                              |
| -------------------- | ---------------------------------------- |
| `uv pip install`     | Already in uv context                    |
| `pip freeze`         | Lock file generation (output, not input) |
| `pip-compile`        | Constraint compilation                   |
| `echo "pip install"` | Documentation/examples                   |
| `grep venv`          | Searching for references                 |
| `# pip install`      | Comments                                 |

### Test Suite

**File**: `plugins/itp-hooks/hooks/posttooluse-reminder.test.ts`

33 unit tests covering:

- Pip detection patterns (install, uninstall, python -m pip)
- Venv activation patterns (source, dot-source, SSH wrapped)
- Exception handling (echo, grep, uv context, comments)
- Priority ordering (graph-easy > venv > pip)
- Edge cases (empty command, malformed JSON)

```bash
bun test plugins/itp-hooks/hooks/posttooluse-reminder.test.ts
```

## Migration from Bash

| Aspect            | Bash Version            | TypeScript Version          |
| ----------------- | ----------------------- | --------------------------- |
| File              | posttooluse-reminder.sh | posttooluse-reminder.ts     |
| Runtime           | bash + jq               | Bun                         |
| Tests             | Manual                  | 33 automated tests          |
| Type safety       | None                    | Full TypeScript             |
| Hook registration | hooks.json              | hooks.json (updated to .ts) |

## Validation

```bash
# Run unit tests
bun test plugins/itp-hooks/hooks/posttooluse-reminder.test.ts

# Manual E2E test
echo '{"tool_name":"Bash","tool_input":{"command":"pip install requests"}}' | \
  bun plugins/itp-hooks/hooks/posttooluse-reminder.ts
```

## Success Criteria (Validated 2026-01-22)

| Criterion                                             | Status  | Evidence                                                                                                                            |
| ----------------------------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `pip install` triggers uv reminder                    | ✅ PASS | E2E: `echo '{"tool_name":"Bash","tool_input":{"command":"pip install requests"}}' \| bun posttooluse-reminder.ts` → `[UV-REMINDER]` |
| `pip uninstall` triggers uv reminder                  | ✅ PASS | E2E: `pip uninstall requests` → `PREFERRED: uv remove requests`                                                                     |
| `source .venv/bin/activate` triggers uv reminder      | ✅ PASS | E2E: `source .venv/bin/activate` → `[UV-REMINDER] venv activation detected`                                                         |
| `uv pip install` does NOT trigger (exception)         | ✅ PASS | E2E: No output (correct exception handling)                                                                                         |
| `echo "pip install"` does NOT trigger (documentation) | ✅ PASS | E2E: No output (documentation context exception)                                                                                    |
| `pip freeze` does NOT trigger (lock file generation)  | ✅ PASS | E2E: No output (lock file generation exception)                                                                                     |
| TypeScript implementation with Bun runtime            | ✅ PASS | `ls plugins/itp-hooks/hooks/posttooluse-reminder.ts` exists (9951 bytes)                                                            |
| 33 unit tests passing                                 | ✅ PASS | `bun test` → `33 pass, 0 fail, 57 expect() calls`                                                                                   |
| hooks.json updated to use .ts file                    | ✅ PASS | `jq '.hooks.PostToolUse[0].hooks[0].command'` → `bun ...posttooluse-reminder.ts`                                                    |
| Bash version deprecated and deleted                   | ✅ PASS | `ls posttooluse-reminder.sh` → "No such file" (source); marketplace synced                                                          |

### Additional Validations

| Check                         | Status  | Evidence                                                              |
| ----------------------------- | ------- | --------------------------------------------------------------------- |
| settings.json uses .ts        | ✅ PASS | `jq '.hooks.PostToolUse[0].hooks[0].command' ~/.claude/settings.json` |
| Marketplace hooks.json synced | ✅ PASS | Manually synced 2026-01-22 (was stale)                                |
| Marketplace .sh removed       | ✅ PASS | `rm ~/.claude/.../posttooluse-reminder.sh` executed                   |
| ADR references .ts            | ✅ PASS | Updated 3 occurrences of .sh → .ts                                    |
| CLAUDE.md files aligned       | ✅ PASS | All 3 files reference .ts, no counts                                  |
| Plugin validation passes      | ✅ PASS | `bun scripts/validate-plugins.mjs` → 0 errors                         |
