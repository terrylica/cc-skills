# File Size Bloat Guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`pretooluse-file-size-guard.ts`](../hooks/pretooluse-file-size-guard.ts), subhook `file-size-guard` of the [PreToolUse Write/Edit orchestrator](./pretooluse-write-edit-orchestrator.md) (timeout 4500 ms).

The hook prevents single-file bloat by checking line count before Write/Edit operations. It is tiered: above the block threshold it denies with splitting guidance; between warn and block it allows, and the soft reminder comes from `checkFileSizeReminder()` in [`posttooluse-reminder.ts`](../hooks/posttooluse-reminder.ts).

### Detection

| Tool  | Method                                                                  |
| ----- | ----------------------------------------------------------------------- |
| Write | Counts lines in proposed `content`                                      |
| Edit  | Reads existing file, applies `old_string` → `new_string`, counts result |

### Default Thresholds

| Extension                                         | Warn | Block |
| ------------------------------------------------- | ---- | ----- |
| `.rs`, `.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.go` | 1000 | 2000  |
| `.md`                                             | 1600 | 3000  |
| `.toml`                                           | 400  | 1000  |
| `.json`                                           | 2000 | 6000  |
| Other                                             | 1000 | 2000  |

The limits are generous on purpose: the in-process hook orchestrators combine many subhook classifiers in one file and are legitimately large.

The guard itself only enforces the **Block** column. The soft reminder in `posttooluse-reminder.ts` uses a fixed 1000–2000 band, not this table, and only for code and config extensions (`.rs .py .ts .tsx .js .jsx .go .java .c .cpp .h .hpp .rb .swift .kt .sh .bash .toml .yml .yaml .json`) — never `.md`. So a per-extension Warn value, including one set in the config file, currently has no effect.

### Exclusions

- Wildcard patterns, always exempt: `*.lock`, `*.generated.*`, `*.min.js`, `*.min.css`.
- Exact file names (`package-lock.json`, `Cargo.lock`, `uv.lock`, and any name added in config) are exempt only once the file's first git commit is more than a week old; an untracked or new file is still checked.

### Escape Hatch

Add a `# FILE-SIZE-OK` comment anywhere in the resulting file content to suppress the block (case-sensitive substring; the token itself can be changed with `escapeComment` in the config file).

### Configuration

Create `.claude/file-size-guard.json` under the session's working directory (project-level) or `~/.claude/file-size-guard.json` (global). The first one found wins; its `defaults` and `extensions` are merged over the built-ins and its `excludes` appended:

```json
{
  "defaults": { "warn": 600, "block": 1200 },
  "extensions": { ".rs": { "warn": 400, "block": 800 } },
  "excludes": ["my-generated-file.ts"]
}
```

### Plan Mode

Automatically skipped when Claude is in planning phase.
