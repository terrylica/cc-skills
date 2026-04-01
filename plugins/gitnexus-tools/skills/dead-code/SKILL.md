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

### Step 0: Pre-flight — Ensure CLI Is Callable

The `gitnexus` binary is installed via npm/mise. The mise shim may fail if node isn't active in the current project. Run this pre-flight before any gitnexus command:

```bash
# Test if gitnexus is actually callable (not just a broken shim)
gitnexus --version 2>/dev/null || mise use node@25.8.0
```

All commands below run from the repo root. If multiple repos are indexed in the workspace, add `--repo <repo-name>` to specify the target. Otherwise `--repo` is optional.

### Step 1: Auto-Reindex If Stale

```bash
gitnexus status
```

If stale (indexed commit ≠ HEAD), **automatically reindex before proceeding** — do not ask the user:

```bash
gitnexus analyze
```

Then re-check status to confirm index is current.

### Step 2: Run Cypher Queries

Run these 4 queries to detect different categories of dead code:

#### Orphan Functions

Functions with no incoming CALLS edges and not participating in any process:

```bash
gitnexus cypher "MATCH (f:Function) WHERE NOT EXISTS { MATCH ()-[:CALLS]->(f) } AND NOT EXISTS { MATCH ()-[:STEP_IN_PROCESS]->(f) } RETURN f.name, f.file, f.line ORDER BY f.file LIMIT 50"
```

#### Dangling Imports

Import edges with low confidence (< 0.5), indicating potentially broken references:

```bash
gitnexus cypher "MATCH (a)-[r:IMPORTS]->(b) WHERE r.confidence < 0.5 RETURN a.name, b.name, r.confidence, a.file ORDER BY r.confidence LIMIT 30"
```

#### Dead Code (Unreachable)

Functions unreachable from any entry point — no callers and no process membership:

```bash
gitnexus cypher "MATCH (f:Function) WHERE NOT EXISTS { MATCH ()-[:CALLS]->(f) } AND NOT EXISTS { MATCH ()-[:STEP_IN_PROCESS]->(f) } AND NOT f.name STARTS WITH '_' AND NOT f.name STARTS WITH 'test_' RETURN f.name, f.file, f.line ORDER BY f.file LIMIT 50"
```

#### Isolated Files

Files with no imports in or out:

```bash
gitnexus cypher "MATCH (f:File) WHERE NOT EXISTS { MATCH (f)-[:IMPORTS]->() } AND NOT EXISTS { MATCH ()-[:IMPORTS]->(f) } RETURN f.path ORDER BY f.path LIMIT 30"
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


## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
