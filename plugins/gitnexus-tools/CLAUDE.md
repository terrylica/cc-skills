# gitnexus-tools Plugin

> GitNexus knowledge graph: explore symbols, blast radius analysis, dead code detection, staleness hooks.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md) | [quality-tools CLAUDE.md](../quality-tools/CLAUDE.md)

## Overview

This plugin wraps the [GitNexus](https://www.npmjs.com/package/gitnexus) CLI (`npx gitnexus@latest`) with skills for code exploration, impact analysis, and dead code detection — plus hooks for index staleness detection.

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

| Hook                             | Event       | Matcher     | Purpose                                             |
| -------------------------------- | ----------- | ----------- | --------------------------------------------------- |
| `posttooluse-staleness-detector` | PostToolUse | Write\|Edit | Warn when index is 5+ commits behind (once/session) |
| `stop-reindex-reminder`          | Stop        | —           | Remind to reindex at session end if stale           |

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

| Command                                            | Purpose               |
| -------------------------------------------------- | --------------------- |
| `npx gitnexus@latest query "<concept>" --limit 5`  | Find execution flows  |
| `npx gitnexus@latest context "<symbol>" --content` | 360° symbol view      |
| `npx gitnexus@latest impact "<symbol>" --depth 3`  | Blast radius          |
| `npx gitnexus@latest status`                       | Check index freshness |
| `npx gitnexus@latest analyze`                      | Re-index              |
| `npx gitnexus@latest cypher "<query>"`             | Raw Cypher query      |

Disambiguate symbols with `--uid` (from candidates list) or `--file` flags.

## References

- [hooks.json](./hooks/hooks.json) - Hook configuration
- [Explore Skill](./skills/explore/SKILL.md)
- [Impact Skill](./skills/impact/SKILL.md)
- [Dead Code Skill](./skills/dead-code/SKILL.md)
- [Reindex Skill](./skills/reindex/SKILL.md)
