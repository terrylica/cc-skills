---
name: impact
description: "Blast radius analysis via GitNexus CLI (gitnexus). CLI ONLY - NO MCP server exists, never use readMcpResource with gitnexus:// URIs. TRIGGERS - what breaks if I change, blast radius, impact analysis, safe to modify."
allowed-tools: Bash, Read, Grep, Glob
model: haiku
---

# GitNexus Impact Analysis

> **CLI ONLY — no MCP server exists. Never use `readMcpResource` with `gitnexus://` URIs.**

Analyze the blast radius of changing a symbol — who calls it, what processes it participates in, and what tests cover it.

## When to Use

- Before modifying a function with many callers
- "What breaks if I change X?"
- "Is it safe to modify Y?"
- "What's the blast radius of changing Z?"

## Workflow

### Step 1: Verify Index

Run from the repo root (the CLI auto-detects the repo from cwd):

```bash
gitnexus status
```

If stale, suggest running `/gitnexus-tools:reindex` first.

### Step 2: Upstream Blast Radius

```bash
gitnexus impact "<symbol>" --depth 3
```

This shows everything that depends on the symbol (callers, transitive callers up to depth 3).

If multiple candidates are returned, disambiguate:

```bash
gitnexus impact "<symbol>" --uid "<full-uid>" --depth 3
# or
gitnexus impact "<symbol>" --file "<file-path>" --depth 3
```

### Step 3: Downstream Dependencies (Optional)

```bash
gitnexus impact "<symbol>" --direction downstream --depth 3
```

Shows what the symbol depends on — useful for understanding if dependencies might change.

### Step 4: Test Coverage

```bash
gitnexus impact "<symbol>" --include-tests
```

Shows which test files exercise this symbol.

### Step 5: Risk Assessment

Based on the number of direct dependents:

| Dependents | Risk Level   | Recommendation                                      |
| ---------- | ------------ | --------------------------------------------------- |
| < 5        | **LOW**      | Safe to modify with basic testing                   |
| 5–20       | **MEDIUM**   | Review all callers, run related tests               |
| 20–50      | **HIGH**     | Consider backward-compatible API, extensive testing |
| 50+        | **CRITICAL** | Needs deprecation strategy, phased migration        |

### Step 6: Structured Report

Present:

- **Risk level** with dependent count
- **Top affected processes** — execution flows that include this symbol
- **Direct callers** — functions/methods that call this directly
- **Test coverage** — tests that exercise this symbol (or gaps)
- **Recommendation** — safe to modify, needs tests, needs migration plan

## Example

User: "What breaks if I change RangeBarProcessor?"

```bash
gitnexus impact "RangeBarProcessor" --depth 3
gitnexus impact "RangeBarProcessor" --include-tests
```

Output: "CRITICAL risk — 73 dependents across 12 processes. 8 test files cover it. Recommend backward-compatible changes only."
