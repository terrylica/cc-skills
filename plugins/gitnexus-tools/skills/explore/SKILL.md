---
name: explore
description: "Explore how code works using GitNexus CLI (gitnexus). CLI ONLY - NO MCP server exists, never use readMcpResource with gitnexus:// URIs. TRIGGERS - how does X work, explore symbol, understand function, trace execution, code walkthrough."
allowed-tools: Bash, Read, Grep, Glob
model: haiku
---

# GitNexus Explore

> **CLI ONLY — no MCP server exists. Never use `readMcpResource` with `gitnexus://` URIs.**

Trace execution flows and understand how code works using the GitNexus knowledge graph.

## When to Use

- "How does X work?"
- "What's the execution flow for Y?"
- "Walk me through the Z subsystem"
- Exploring unfamiliar code areas before making changes

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

### Step 2: Find Execution Flows

```bash
gitnexus query "<concept>" --limit 5
```

This returns ranked execution flows (process chains) related to the concept.

### Step 3: Get 360° Symbol View

For each relevant symbol found:

```bash
gitnexus context "<symbol>" --content
```

This shows:

- **Callers** — who calls this symbol
- **Callees** — what this symbol calls
- **Processes** — execution flows this symbol participates in
- **Source** — the actual code (with `--content`)

If multiple candidates are returned, disambiguate with:

```bash
gitnexus context "<symbol>" --uid "<full-uid>" --content
# or
gitnexus context "<symbol>" --file "<file-path>" --content
```

### Step 4: Read Source Files

Use the Read tool to examine source files at the line numbers identified by GitNexus.

### Step 5: Synthesize

Present a clear explanation covering:

- **What it is** — purpose and responsibility
- **Execution flows** — how data moves through the system
- **Dependencies** — what it depends on, what depends on it
- **Key files** — the most important files to understand

## Example

User: "How does the kintsugi gap repair work?"

```bash
gitnexus query "kintsugi gap repair" --limit 5
gitnexus context "KintsugiReconciler" --content
gitnexus context "discover_shards" --content
```

Then read the relevant source files and synthesize the explanation.


## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
