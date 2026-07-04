# Read-Only Command Detection

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## Read-Only Command Detection

Hooks can skip validation for read-only commands (grep, find, ls, etc.) to reduce noise. This follows the [Claude Code hooks best practice](https://code.claude.com/docs/en/hooks) of skipping non-destructive operations.

### Usage

```typescript
import { isReadOnly, allow } from "./pretooluse-helpers.ts";

if (tool_name === "Bash") {
  const command = tool_input.command || "";
  if (isReadOnly(command)) {
    return allow(); // Skip validation for read-only commands
  }
}
```

### Detected Read-Only Commands

| Category      | Commands                                          |
| ------------- | ------------------------------------------------- |
| Search        | `rg`, `grep`, `ag`, `ack`, `find`, `fd`, `locate` |
| File viewing  | `cat`, `less`, `head`, `tail`, `bat`              |
| Directory     | `ls`, `tree`, `exa`, `eza`                        |
| Git read-only | `git status`, `git log`, `git diff`, `git show`   |
| Package info  | `npm list`, `pip list`, `cargo tree`              |

### Hooks with Read-Only Detection

- `pretooluse-process-storm-guard.mjs` - Skips process storm checks for read-only commands
- `pretooluse-cwd-deletion-guard.ts` - Skips CWD deletion checks for read-only commands

