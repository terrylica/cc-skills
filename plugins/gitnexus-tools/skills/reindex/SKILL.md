---
name: reindex
description: "Re-index the GitNexus knowledge graph via CLI (npx gitnexus@latest). CLI ONLY - NO MCP server exists, never use readMcpResource with gitnexus:// URIs. TRIGGERS - reindex, refresh index, update knowledge graph, gitnexus analyze."
allowed-tools: Bash, Read
model: haiku
---

# GitNexus Reindex

> **CLI ONLY — no MCP server exists. Never use `readMcpResource` with `gitnexus://` URIs.**

Re-index the current repository's GitNexus knowledge graph and verify the updated stats.

## When to Use

- After significant refactors (5+ files changed)
- When staleness hook reports index is behind
- After merging a large PR
- "Refresh the knowledge graph"

## Workflow

### Step 1: Check Current Status

Run from the repo root (the CLI auto-detects the repo from cwd):

```bash
npx gitnexus@latest status
```

If already current (lastCommit matches HEAD), report "Index is up to date" and stop.

### Step 2: Run Indexer

```bash
npx gitnexus@latest analyze
```

Use `--force` if the index appears corrupted or if a normal analyze doesn't pick up changes:

```bash
npx gitnexus@latest analyze --force
```

This may take 30–120 seconds depending on codebase size.

### Step 3: Verify New Index

```bash
npx gitnexus@latest status
```

### Step 4: Report Stats

Present the updated stats:

```
## GitNexus Reindex Complete

| Metric      | Before | After |
| ----------- | ------ | ----- |
| Nodes       | ...    | ...   |
| Edges       | ...    | ...   |
| Communities | ...    | ...   |
| Flows       | ...    | ...   |
| Last Commit | ...    | ...   |

Index is now current with HEAD.
```

## Notes

- The `analyze` command runs locally — no network calls
- KuzuDB database is stored in `.gitnexus/` at the repo root
- Large codebases (10k+ files) may take 2+ minutes
- The `--force` flag rebuilds from scratch; without it, incremental analysis is used
