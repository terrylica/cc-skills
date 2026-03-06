---
name: dead-code
description: "Find orphan functions, dangling imports, and dead code via GitNexus CLI (gitnexus). CLI ONLY - NO MCP server exists, never use readMcpResource with gitnexus:// URIs. TRIGGERS - dead code, orphan functions, unused imports, dangling references, unreachable code."
allowed-tools: Bash, Read, Grep, Glob
model: haiku
---

# GitNexus Dead Code Detector

> **CLI ONLY — no MCP server exists. Never use `readMcpResource` with `gitnexus://` URIs.**

Find orphan functions, dangling imports, isolated files, and unreachable code using the GitNexus knowledge graph.

## When to Use

- Periodic codebase cleanup
- Before a major release to reduce surface area
- After a refactor to find newly orphaned code
- "Are there any unused functions?"

**For language-specific dead code tools** (vulture, knip, clippy): use `quality-tools:dead-code-detector` instead. This skill uses the GitNexus graph for cross-file structural analysis.

## Workflow

### Step 0: Resolve CLI and Repo Name

Resolve the CLI command (bare `gitnexus` may fail if the project's mise node version differs from where it was installed):

```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
GN=$(command -v gitnexus >/dev/null 2>&1 && echo "gitnexus" || echo "npx gitnexus")
```

Use `$GN --repo "$REPO_NAME"` on all commands below.

### Step 1: Auto-Reindex If Stale

```bash
$GN status --repo "$REPO_NAME"
```

If stale (indexed commit ≠ HEAD), **automatically reindex before proceeding** — do not ask the user:

```bash
$GN analyze --repo "$REPO_NAME"
```

Then re-check status to confirm index is current.

### Step 2: Run Cypher Queries

Run these 4 queries to detect different categories of dead code:

#### Orphan Functions

Functions with no incoming CALLS edges and not participating in any process:

```bash
$GN cypher "MATCH (f:Function) WHERE NOT EXISTS { MATCH ()-[:CALLS]->(f) } AND NOT EXISTS { MATCH ()-[:STEP_IN_PROCESS]->(f) } RETURN f.name, f.file, f.line ORDER BY f.file LIMIT 50" --repo "$REPO_NAME"
```

#### Dangling Imports

Import edges with low confidence (< 0.5), indicating potentially broken references:

```bash
$GN cypher "MATCH (a)-[r:IMPORTS]->(b) WHERE r.confidence < 0.5 RETURN a.name, b.name, r.confidence, a.file ORDER BY r.confidence LIMIT 30" --repo "$REPO_NAME"
```

#### Dead Code (Unreachable)

Functions unreachable from any entry point — no callers and no process membership:

```bash
$GN cypher "MATCH (f:Function) WHERE NOT EXISTS { MATCH ()-[:CALLS]->(f) } AND NOT EXISTS { MATCH ()-[:STEP_IN_PROCESS]->(f) } AND NOT f.name STARTS WITH '_' AND NOT f.name STARTS WITH 'test_' RETURN f.name, f.file, f.line ORDER BY f.file LIMIT 50" --repo "$REPO_NAME"
```

#### Isolated Files

Files with no imports in or out:

```bash
$GN cypher "MATCH (f:File) WHERE NOT EXISTS { MATCH (f)-[:IMPORTS]->() } AND NOT EXISTS { MATCH ()-[:IMPORTS]->(f) } RETURN f.path ORDER BY f.path LIMIT 30" --repo "$REPO_NAME"
```

### Step 3: Filter Results

Exclude false positives:

- **Test files** (`**/test_*`, `**/tests/*`, `**/*_test.*`) — test functions are legitimately "uncalled"
- **`__init__` files** — may be legitimately empty or used for re-exports
- **Entry points** (`main`, `cli`, `__main__`) — called by the runtime, not by other code
- **Private helpers** prefixed with `_` — may be used via dynamic dispatch

### Step 4: Structured Report

Present categorized by module/directory:

```
## Dead Code Report

### Orphan Functions (N found)
| Function | File | Line |
|----------|------|------|
| ...      | ...  | ...  |

### Dangling Imports (N found)
| Source | Target | Confidence |
|--------|--------|------------|
| ...    | ...    | ...        |

### Isolated Files (N found)
- path/to/file.py
- ...

### Summary
- Total orphans: N
- Total dangling: N
- Total isolated: N
```

## Notes

- Results depend on index freshness — reindex if results seem wrong
- The graph captures static relationships only — dynamic dispatch, reflection, and plugin loading may cause false positives
- Use `quality-tools:dead-code-detector` for language-specific analysis (vulture, knip, clippy) which complements this structural view
