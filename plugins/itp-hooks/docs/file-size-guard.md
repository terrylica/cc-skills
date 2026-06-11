# File Size Bloat Guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## File Size Bloat Guard

The `pretooluse-file-size-guard.ts` hook prevents single-file bloat by checking line count before Write/Edit operations. Uses tiered approach: warn via PostToolUse (soft notification), block via `deny` (hard block with guidance) at the block threshold.

### Detection

| Tool  | Method                                                                  |
| ----- | ----------------------------------------------------------------------- |
| Write | Counts lines in proposed `content`                                      |
| Edit  | Reads existing file, applies `old_string` → `new_string`, counts result |

### Default Thresholds

| Extension                  | Warn | Block |
| -------------------------- | ---- | ----- |
| `.rs`, `.py`, `.ts`, `.go` | 1000 | 2000  |
| `.md`                      | 1600 | 3000  |
| `.toml`                    | 400  | 1000  |
| `.json`                    | 2000 | 6000  |
| Other                      | 1000 | 2000  |

**History**: Doubled 2026-05-26 (was 500/1000 default) to reduce reminder noise and false-positive blocks on the iter-84 → iter-98 in-process hook orchestrators that intentionally combine many subhook classifiers into one bun process. The PostToolUse soft reminder in `posttooluse-reminder.ts` also moved to WARN=1000 / BLOCK=2000.

### Exclusions

Lock files (`*.lock`, `package-lock.json`, `Cargo.lock`, `uv.lock`), generated files (`*.generated.*`, `*.min.js`, `*.min.css`).

### Escape Hatch

Add `# FILE-SIZE-OK` comment anywhere in the file to suppress the warning.

### Configuration

Create `.claude/file-size-guard.json` (project-level) or `~/.claude/file-size-guard.json` (global):

```json
{
  "defaults": { "warn": 600, "block": 1200 },
  "extensions": { ".rs": { "warn": 400, "block": 800 } },
  "excludes": ["my-generated-file.ts"]
}
```

### Plan Mode

Automatically skipped when Claude is in planning phase.

