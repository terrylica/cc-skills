# gitnexus-tools Plugin

> GitNexus knowledge graph: explore symbols, blast radius analysis, dead code detection, staleness hooks.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md) | [quality-tools CLAUDE.md](../quality-tools/CLAUDE.md)

## Overview

This plugin wraps the [GitNexus](https://www.npmjs.com/package/gitnexus) CLI (`gitnexus`) with skills for code exploration, impact analysis, and dead code detection — plus hooks for index staleness detection.

GitNexus indexes codebases into a KuzuDB knowledge graph (nodes: functions, classes, files; edges: calls, imports, extends). Skills provide structured workflows on top of the CLI; hooks provide passive staleness monitoring.

**Why CLI-only (no MCP)**: MCP tool schemas (~3,500 tokens for 7 tools) occupy context window on every turn. Skills + hooks give the same capabilities with zero idle context cost.

## Skills

| Skill       | Slash Command               | Purpose                                            |
| ----------- | --------------------------- | -------------------------------------------------- |
| `explore`   | `/gitnexus-tools:explore`   | Trace execution flows, understand how code works   |
| `impact`    | `/gitnexus-tools:impact`    | Blast radius analysis before modifying code        |
| `dead-code` | `/gitnexus-tools:dead-code` | Find orphan functions, dangling imports, dead code |
| `reindex`   | `/gitnexus-tools:reindex`   | Re-index repository and verify graph stats         |

## Hooks

| Hook                             | Event       | Matcher                | Purpose                                             |
| -------------------------------- | ----------- | ---------------------- | --------------------------------------------------- |
| `posttooluse-cli-reminder`       | PostToolUse | Glob\|Grep\|Bash\|Task | CLI reminder on first exploration in indexed repo   |
| `posttooluse-staleness-detector` | PostToolUse | Write\|Edit            | Warn when index is 5+ commits behind (once/session) |
| `stop-reindex-reminder`          | Stop        | —                      | Remind to reindex at session end if stale           |

### CLI Reminder

On the first exploration tool use in a repo with `.gitnexus/meta.json`, reminds Claude to use the GitNexus CLI (`gitnexus`) instead of MCP or manual grep. Gates once per session per repo via `/tmp/.claude-gitnexus-cli-reminder/`. MCP operations (`readMcpResource`) do not go through the hook pipeline, so this proactive reminder fires early to guide Claude before it tries MCP.

### Staleness Detection

Both hooks share the same logic:

1. Check if edited file is in a code file (by extension)
2. Find git root → check `.gitnexus/meta.json` exists (skip non-indexed repos)
3. Compare `meta.json.lastCommit` with `git rev-parse HEAD`
4. Only warn if **5+ commits** behind (reduces noise)
5. **Fail-open everywhere** — every catch exits 0

The PostToolUse hook gates once per session per repo (via `/tmp/.claude-gitnexus-staleness/`).

## Behavioral Triggers (for indexed repos)

Add these to project CLAUDE.md files to guide when skills are invoked:

- **Before modifying a function with many callers**: Run `/gitnexus-tools:impact <symbol>`
- **When exploring unfamiliar code areas**: Run `/gitnexus-tools:explore <concept>`
- **After significant refactors (5+ files changed)**: Run `/gitnexus-tools:reindex`
- **Periodic cleanup**: Run `/gitnexus-tools:dead-code` to find orphans

## Quick CLI Reference

> **CLI ONLY — no MCP server exists. Never use `readMcpResource` with `gitnexus://` URIs.**
>
> Run all commands from the repo root. The CLI auto-detects the repo from cwd.

**Always resolve CLI and repo name first** (bare `gitnexus` may fail if the project's mise node version differs from where it was installed):

```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
GN=$(command -v gitnexus >/dev/null 2>&1 && echo "gitnexus" || echo "npx gitnexus")
```

| Command                                                | Purpose               |
| ------------------------------------------------------ | --------------------- |
| `$GN list`                                             | List indexed repos    |
| `$GN query "<concept>" --limit 5 --repo "$REPO_NAME"`  | Find execution flows  |
| `$GN context "<symbol>" --content --repo "$REPO_NAME"` | 360° symbol view      |
| `$GN impact "<symbol>" --depth 3 --repo "$REPO_NAME"`  | Blast radius          |
| `$GN status --repo "$REPO_NAME"`                       | Check index freshness |
| `$GN analyze --repo "$REPO_NAME"`                      | Re-index              |
| `$GN cypher "<query>" --repo "$REPO_NAME"`             | Raw Cypher query      |

Disambiguate symbols with `--uid` (from candidates list) or `--file` flags.

## References

- [hooks.json](./hooks/hooks.json) - Hook configuration
- [Explore Skill](./skills/explore/SKILL.md)
- [Impact Skill](./skills/impact/SKILL.md)
- [Dead Code Skill](./skills/dead-code/SKILL.md)
- [Reindex Skill](./skills/reindex/SKILL.md)
