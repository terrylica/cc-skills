---
name: reindex
description: "Re-index the GitNexus knowledge graph via CLI (gitnexus). CLI ONLY - NO MCP server exists, never use readMcpResource with gitnexus:// URIs. TRIGGERS - reindex, refresh index, update knowledge graph, $GN analyze."
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

### Step 0: Resolve CLI and Repo Name

Resolve the CLI command (bare `gitnexus` may fail if the project's mise node version differs from where it was installed):

```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
GN=$(command -v gitnexus >/dev/null 2>&1 && echo "gitnexus" || echo "npx gitnexus")
```

Use `$GN --repo "$REPO_NAME"` on all commands below.

### Step 1: Check Current Status

```bash
$GN status --repo "$REPO_NAME"
```

If already current (lastCommit matches HEAD), report "Index is up to date" and stop.

### Step 2: Run Indexer

```bash
$GN analyze --repo "$REPO_NAME"
```

Use `--force` if the index appears corrupted or if a normal analyze doesn't pick up changes:

```bash
$GN analyze --force --repo "$REPO_NAME"
```

This may take 30–120 seconds depending on codebase size.

### Step 3: Verify New Index

```bash
$GN status --repo "$REPO_NAME"
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
