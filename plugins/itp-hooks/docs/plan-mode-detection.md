# Plan Mode Detection

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Implementation: `isPlanMode()` in [`hooks/lib/plan-mode-detector.ts`](../hooks/lib/plan-mode-detector.ts), re-exported by `hooks/pretooluse-helpers.ts`.

Hooks can detect when Claude is in plan mode and skip validation. This prevents blocking during planning phase when Claude writes to plan files or explores the codebase.

### Usage

```typescript
import { isPlanMode, allow } from "./pretooluse-helpers.ts";

const planContext = isPlanMode(input, {
  checkPermission: true,
  checkPath: true,
});
if (planContext.inPlanMode) {
  logger.debug("Skipping in plan mode", { reason: planContext.reason });
  return allow();
}
```

### Detection Signals

| Signal                             | Priority  | Description                                          |
| ---------------------------------- | --------- | ---------------------------------------------------- |
| `permission_mode: "plan"`          | Primary   | Claude Code sets this when `EnterPlanMode` is active |
| File path `/plans/*.md`            | Secondary | Catches writes to plan directories                   |
| Active files in `~/.claude/plans/` | Tertiary  | Expensive filesystem check (disabled by default)     |

### Hooks with Plan Mode Support

- `pretooluse-version-guard.ts` - Skips version checks in plan mode
- `pretooluse-mise-hygiene-guard.ts` - Skips hygiene checks in plan mode
- `pretooluse-file-size-guard.ts` - Skips line-count checks in plan mode
- `pretooluse-typescript-version-guard.ts` - Skips TypeScript version checks in plan mode
- `pretooluse-shell-script-safety-guard.ts` - Skips shell-script checks in plan mode
- `pretooluse-typescript-legacy-install-command-guard.ts` - Skips legacy-install command checks in plan mode

All six run inside an orchestrator (the first five as Write\|Edit subhooks, the last as a Bash guard), so the skip applies per subhook.

**ADR**: [/docs/adr/2026-02-05-plan-mode-detection-hooks.md](/docs/adr/2026-02-05-plan-mode-detection-hooks.md)
