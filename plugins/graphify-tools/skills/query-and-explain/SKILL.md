---
name: query-and-explain
description: "Query an already-built graphify knowledge graph: natural-language questions, path-finding between two concepts, or explain a single node — without re-reading the source files. TRIGGERS - graphify query, ask the graph, what connects, path between concepts, explain node, query knowledge graph."
allowed-tools: Read, Bash, Glob, Grep
---

# Query & Explain the Graph

> **Self-Evolving Skill**: This skill improves through use. If a query verb drifts or graph-interpretation guidance proves wrong — fix this file immediately, don't defer. Only update for real, reproducible issues.

Interrogate a persistent `graphify-out/graph.json` built earlier by `graphify-tools:build-graph`. This is the token-efficiency payoff: answers come from the graph (~71× fewer tokens on large corpora), not from re-reading raw files.

> **Prerequisite**: a `graphify-out/` directory must exist for the target corpus. If missing, invoke `graphify-tools:build-graph` first. If the corpus changed since the last build, suggest `graphify <target> --update` before trusting answers.

## Verbs

Run from the directory containing `graphify-out/` (or pass the target folder):

```bash
# Natural-language question across the whole graph
graphify query "what connects attention to the optimizer?"

# Shortest/strongest path between two named nodes
graphify path "DigestAuth" "Response"

# Deep-dive one node: its edges, communities, provenance
graphify explain "SwinTransformer"
```

## Interpreting results

- Edge tags matter: `EXTRACTED` = found in source; `INFERRED` = LLM-suggested; `AMBIGUOUS` = flagged uncertain. Quote the tag when relaying a claim to the operator.
- If `query` returns nothing useful, check node naming with the graph's own inventory first — `GRAPH_REPORT.md` lists god nodes and communities; `graph.html` has interactive search.
- For **symbol-level** follow-ups (who calls this function, what breaks if I change it) hand off to the codegraph MCP tools instead — that's their home turf.
- `query`/`path`/`explain` read `graph.json` locally — **no LLM call, no backend needed**. (Only `extract`/`cluster-only`/`label` hit an LLM; see [`../../references/backends.md`](../../references/backends.md).)

## Staleness check

```bash
# Newest source file vs newest cache entry — if sources are newer, recommend --update
find <target> -newer <target>/graphify-out/graph.json -type f | grep -v graphify-out | head
```

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency (esp. `references/backends.md`) that no longer matches reality.
4. **Log it.** — Add a dated note to the plugin CLAUDE.md provenance with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
