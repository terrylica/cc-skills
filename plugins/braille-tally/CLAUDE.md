# braille-tally Plugin

> The Braille Tally: rank items on a few axes at once as one shape of Braille cells (level n = n dots), default axes Importance · Urgency · Simplicity.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md)

## Files

| File                                                                             | Role                                                                                          |
| -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| [`skills/braille-tally/SKILL.md`](./skills/braille-tally/SKILL.md)               | **SSoT of the convention**: axes, legend, ranking, placement, the measurements                |
| [`lib/tally.ts`](./lib/tally.ts)                                                 | The only implementation; no dependencies, so other plugins and projects can copy or import it |
| [`scripts/braille-tally.ts`](./scripts/braille-tally.ts)                         | CLI over the library; `spec` prints its command set as JSON                                   |
| [`hooks/askuserquestion-tally-guard.ts`](./hooks/askuserquestion-tally-guard.ts) | PreToolUse deny for untallied or out-of-rank AskUserQuestion options              |
| [`hooks/issue-title-tally-guard.ts`](./hooks/issue-title-tally-guard.ts)         | PreToolUse deny for a GitHub issue title that does not start with a tally                     |
| [`tests/tally.test.ts`](./tests/tally.test.ts), [`tests/issue-title.test.ts`](./tests/issue-title.test.ts) | `bun test` from this directory                                                  |

## Hooks

| Hook                             | Event      | Matcher         | Purpose                                                                                                                                                                                |
| -------------------------------- | ---------- | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `askuserquestion-tally-guard.ts` | PreToolUse | AskUserQuestion | Deny until every option label starts with a tally and the options are in rank order (no legend in the question); escape token `BRAILLE-TALLY-EXEMPT` (never in the deny message) |

| `issue-title-tally-guard.ts`     | PreToolUse | `Bash\|Write\|Edit\|mcp__.*github.*__.*(create_issue\|update_issue\|issue_write)` | Deny until every literal issue title (`gh issue create/edit`, `gh api` REST or GraphQL, a shell script being written, GitHub MCP tools) starts with a tally and one space, the glyph alone; same escape token, never in the deny message |

`hooks/hooks.json` is the only registration.

## Invariants

- **`CELLS` is fixed: `⡀⣀⣠⣤⣴⣶⣾⣿`.** Level n has exactly n dots, each level keeps every dot of the one below, and the bottom row fills first. A test checks this from the code points; changing a cell breaks every tally already written.
- **Default axis order is Importance · Urgency · Simplicity**, with ties inside a Pareto front broken by urgency, then importance, then simplicity.
- **The guard denies and never repairs.** It fails open on any unexpected input, and its deny message must never spell the escape token.
- **Nothing personal:** examples and docs carry no names, clients or projects.
