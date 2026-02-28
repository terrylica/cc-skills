---
name: explore
description: Explore how code works using GitNexus knowledge graph. TRIGGERS - how does X work, explore symbol, understand function, trace execution, code walkthrough.
allowed-tools: Bash, Read, Grep, Glob
model: haiku
---

# GitNexus Explore

Trace execution flows and understand how code works using the GitNexus knowledge graph.

## When to Use

- "How does X work?"
- "What's the execution flow for Y?"
- "Walk me through the Z subsystem"
- Exploring unfamiliar code areas before making changes

## Workflow

### Step 1: Verify Index

```bash
npx gitnexus@latest status
```

If stale, suggest running `/gitnexus-tools:reindex` first.

### Step 2: Find Execution Flows

```bash
npx gitnexus@latest query "<concept>" --limit 5
```

This returns ranked execution flows (process chains) related to the concept.

### Step 3: Get 360° Symbol View

For each relevant symbol found:

```bash
npx gitnexus@latest context "<symbol>" --content
```

This shows:

- **Callers** — who calls this symbol
- **Callees** — what this symbol calls
- **Processes** — execution flows this symbol participates in
- **Source** — the actual code (with `--content`)

If multiple candidates are returned, disambiguate with:

```bash
npx gitnexus@latest context "<symbol>" --uid "<full-uid>" --content
# or
npx gitnexus@latest context "<symbol>" --file "<file-path>" --content
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
npx gitnexus@latest query "kintsugi gap repair" --limit 5
npx gitnexus@latest context "KintsugiReconciler" --content
npx gitnexus@latest context "discover_shards" --content
```

Then read the relevant source files and synthesize the explanation.
