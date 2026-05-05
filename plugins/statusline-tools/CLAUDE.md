# statusline-tools Plugin

> Custom status line with git status indicators.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Siblings**: [itp-hooks](../itp-hooks/CLAUDE.md) | [asciinema-tools](../asciinema-tools/CLAUDE.md) | [link-tools](../link-tools/CLAUDE.md)

## Skills

- [tether](./skills/tether/SKILL.md) — renamed from `hooks` to avoid `/hooks` clash
- [ignore](./skills/ignore/SKILL.md)
- [session-info](./skills/session-info/SKILL.md)
- [setup](./skills/setup/SKILL.md)

## Commands

| Command                    | Purpose                      |
| -------------------------- | ---------------------------- |
| `/statusline-tools:setup`  | Configure statusline         |
| `/statusline-tools:ignore` | Manage ignore patterns       |
| `/statusline-tools:tether` | Manage link validation hooks |

## Hooks

| Hook                  | Trigger                              | Purpose                                   |
| --------------------- | ------------------------------------ | ----------------------------------------- |
| `cron-tracker.ts`     | PostToolUse (CronCreate/Delete/List) | Tracks active cron jobs in session state  |
| `stop-cron-gc.ts`     | Stop                                 | Prunes stale cron entries on session exit |
| `lychee-stop-hook.sh` | Stop (installed via manage-hooks.sh) | Link validation on session exit           |

## Status Line Indicators

| Indicator       | Meaning                                            |
| --------------- | -------------------------------------------------- |
| M/D/S/U         | Modified, Deleted, Staged, Untracked files         |
| ↑/↓             | Commits ahead/behind remote                        |
| ≡               | Stash count                                        |
| ⚠               | Merge conflicts                                    |
| Σ &lt;n&gt; LOC | Total lines of code (via `scc`, all tracked files) |
| cx &lt;n&gt;    | Cyclomatic complexity (yellow when ≥ 1k)           |
| MD/TS/Py …      | Top 3 languages by code share (% of total LOC)     |
| ~$&lt;n&gt;     | COCOMO basic-organic cost estimate (informational) |

## Code Statistics Line

Layout: `Σ <LOC> · <files> files · cx <complexity> · <top3 langs %> · ~$<cost> COCOMO`

Implementation: `scc --format=json2` piped through `jq` for compact formatting.
Runs on every render — no cache (selected for freshness 2026-04-26). Bounded by
1s timeout so pathologically large repos drop the line silently rather than
hang the statusline. Skipped when `scc` is not installed or cwd is not a git
work tree.

Cost on cc-skills repo: ~70ms cold (scc with complexity) + ~20ms jq = ~100ms
incremental over the pre-existing 1.1s baseline.

Dependency: `brew install scc` (Go binary, single-shot — no daemon).

## Optional: ccmax-monitor Integration

The status line includes an optional integration with [ccmax-monitor](https://github.com/terrylica/ccmax-monitor), a **private internal fleet system** for managing multi-account Claude Code Max subscriptions. This integration is **not required** and gracefully degrades — public users without ccmax-monitor see no change.

### What it shows

When ccmax-monitor is running locally, the datetime line gains:

```
2026-05-05 14:32 UTC | 03:32 PDT | usalchemist@gmail.com 42% 1d 22h [soft]
                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                    account  5h-used  7d-reset  pin-badge
```

| Element               | Source                                        | Meaning                                   |
| --------------------- | --------------------------------------------- | ----------------------------------------- |
| Account email         | `GET localhost:18095/api/status` (cached 60s) | Which fleet account is active on this Mac |
| `42%`                 | Same API response                             | 5-hour quota utilization                  |
| `1d 22h`              | Same API response                             | Time until 7-day quota reset              |
| `[soft]` / `[strict]` | `~/.config/ccmax/pin.toml`                    | Pin mode override (HEART-23)              |

### Pin badge

`custom-statusline.sh` reads `~/.config/ccmax/pin.toml` via Python `tomllib` (3.11+). If the file does not exist or is unreadable, `ccmax_pin_mode` is empty and no badge is shown.

| Badge             | Meaning                                                    |
| ----------------- | ---------------------------------------------------------- |
| _(none)_          | Following fleet rotation (default)                         |
| `[soft]` (yellow) | Pinned to a specific account; auto-fallback when unhealthy |
| `[strict]` (red)  | Pinned regardless of health                                |

### Graceful degradation

If ccmax-monitor is not running (`localhost:18095` unreachable), `curl` times out in 1–2 seconds and the entire ccmax section is silently omitted. The status line continues to work normally. The 60-second cache (`/tmp/ccmax-statusline-cache.json`) means one tunnel drop doesn't immediately blank the display.

### Scope

This integration is internal to the `terrylica` fleet. Public cc-skills users will never have `localhost:18095` listening, so the block is effectively a no-op — the `curl` silently fails and nothing appears.
