---
name: explore
description: "Explore how code works using GitNexus CLI (npx gitnexus@latest). CLI ONLY - NO MCP server exists, never use readMcpResource with gitnexus:// URIs. TRIGGERS - how does X work, explore symbol, understand function, trace execution, code walkthrough."
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

### Step 1: Determine Repo Name

The `--repo` flag is required for multi-repo setups. Use the basename of the git root:

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")
```

### Step 2: Verify Index

```bash
npx gitnexus@latest status --repo "$REPO"
```

If stale, suggest running `/gitnexus-tools:reindex` first.

### Step 3: Find Execution Flows

```bash
npx gitnexus@latest query "<concept>" --repo "$REPO" --limit 5
```

This returns ranked execution flows (process chains) related to the concept.

### Step 4: Get 360° Symbol View

For each relevant symbol found:

```bash
npx gitnexus@latest context "<symbol>" --repo "$REPO" --content
```

This shows:

- **Callers** — who calls this symbol
- **Callees** — what this symbol calls
- **Processes** — execution flows this symbol participates in
- **Source** — the actual code (with `--content`)

If multiple candidates are returned, disambiguate with:

```bash
npx gitnexus@latest context "<symbol>" --repo "$REPO" --uid "<full-uid>" --content
# or
npx gitnexus@latest context "<symbol>" --repo "$REPO" --file "<file-path>" --content
```

### Step 5: Read Source Files

Use the Read tool to examine source files at the line numbers identified by GitNexus.

### Step 6: Synthesize

Present a clear explanation covering:

- **What it is** — purpose and responsibility
- **Execution flows** — how data moves through the system
- **Dependencies** — what it depends on, what depends on it
- **Key files** — the most important files to understand

## Example

User: "How does the kintsugi gap repair work?"

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")
npx gitnexus@latest query "kintsugi gap repair" --repo "$REPO" --limit 5
npx gitnexus@latest context "KintsugiReconciler" --repo "$REPO" --content
npx gitnexus@latest context "discover_shards" --repo "$REPO" --content
```

Then read the relevant source files and synthesize the explanation.
