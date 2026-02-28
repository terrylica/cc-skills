---
name: dead-code
description: Find orphan functions, dangling imports, and dead code via GitNexus knowledge graph. TRIGGERS - dead code, orphan functions, unused imports, dangling references, unreachable code.
allowed-tools: Bash, Read, Grep, Glob
model: haiku
---

# GitNexus Dead Code Detector

Find orphan functions, dangling imports, isolated files, and unreachable code using the GitNexus knowledge graph.

## When to Use

- Periodic codebase cleanup
- Before a major release to reduce surface area
- After a refactor to find newly orphaned code
- "Are there any unused functions?"

**For language-specific dead code tools** (vulture, knip, clippy): use `quality-tools:dead-code-detector` instead. This skill uses the GitNexus graph for cross-file structural analysis.

## Workflow

### Step 1: Verify Index

```bash
npx gitnexus@latest status
```

If stale, suggest running `/gitnexus-tools:reindex` first.

### Step 2: Run Cypher Queries

Run these 4 queries to detect different categories of dead code:

#### Orphan Functions

Functions with no incoming CALLS edges and not participating in any process:

```bash
npx gitnexus@latest cypher "MATCH (f:Function) WHERE NOT EXISTS { MATCH ()-[:CALLS]->(f) } AND NOT EXISTS { MATCH ()-[:STEP_IN_PROCESS]->(f) } RETURN f.name, f.file, f.line ORDER BY f.file LIMIT 50"
```

#### Dangling Imports

Import edges with low confidence (< 0.5), indicating potentially broken references:

```bash
npx gitnexus@latest cypher "MATCH (a)-[r:IMPORTS]->(b) WHERE r.confidence < 0.5 RETURN a.name, b.name, r.confidence, a.file ORDER BY r.confidence LIMIT 30"
```

#### Dead Code (Unreachable)

Functions unreachable from any entry point — no callers and no process membership:

```bash
npx gitnexus@latest cypher "MATCH (f:Function) WHERE NOT EXISTS { MATCH ()-[:CALLS]->(f) } AND NOT EXISTS { MATCH ()-[:STEP_IN_PROCESS]->(f) } AND NOT f.name STARTS WITH '_' AND NOT f.name STARTS WITH 'test_' RETURN f.name, f.file, f.line ORDER BY f.file LIMIT 50"
```

#### Isolated Files

Files with no imports in or out:

```bash
npx gitnexus@latest cypher "MATCH (f:File) WHERE NOT EXISTS { MATCH (f)-[:IMPORTS]->() } AND NOT EXISTS { MATCH ()-[:IMPORTS]->(f) } RETURN f.path ORDER BY f.path LIMIT 30"
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
