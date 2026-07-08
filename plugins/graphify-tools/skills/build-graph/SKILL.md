---
name: build-graph
description: "Build a multimodal knowledge graph from any folder (code, markdown, PDFs, images) using graphify. Produces graph.html, GRAPH_REPORT.md, graph.json, Obsidian vault, optional agent wiki. TRIGGERS - graphify, build knowledge graph, graph this folder, map this codebase, concept graph, god nodes, surprising connections."
allowed-tools: Read, Bash, Glob, Grep, AskUserQuestion
---

# Build Knowledge Graph

Run the graphify engine on a target folder and surface what it found.

> **Prerequisite**: `graphify` CLI on PATH. If missing, invoke `graphify-tools:setup` first.
>
> **Complement, not replacement**: for symbol-level code questions (callers/callees/impact) use the **codegraph** MCP tools — they are sub-ms and deterministic. Reach for graphify when the corpus is **mixed** (code + docs + papers + images) or the question is **conceptual** ("what connects X to Y across these files?").

## Steps

### 1. Scope the target

Default to the current repo, but ASK before running on anything huge — LLM extraction of docs/images costs tokens and time. Scoping heuristics:

```bash
# Size check first
scc --no-complexity <target> 2>/dev/null | tail -3
find <target> -name '*.pdf' -o -name '*.png' -o -name '*.jpg' | wc -l
```

- < ~100 files: run directly
- Larger: propose a subfolder (e.g. `docs/`, one plugin dir) or `--update` incremental mode
- **1000s of files with many same-named files** (e.g. a marketplace of `SKILL.md`s): cross-chunk node-ID collisions silently drop the second same-named node. Extract per-subfolder then `graphify merge-graphs`, rather than one whole-repo shot.

### 2. Build

Pick a backend and set its env — **full copy-paste blocks for all three live in [`../../references/backends.md`](../../references/backends.md)** (the routing SSoT). Quick guide:

| Backend              | When                                                   | One-liner                                                                    |
| -------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------- |
| **gemini-2.5-flash** | large / bulk runs (safe default, no ban-risk)          | `graphify extract <target> --backend gemini --model gemini-2.5-flash`        |
| **fleet Opus 4.8**   | interactive / smaller graphs, best quality ("our LLM") | `--backend openai --model claude-opus-4-8` + `GRAPHIFY_LLM_TEMPERATURE=omit` |
| **MiniMax-M3**       | a few dense files, latency OK                          | `--backend openai --model MiniMax-M3`                                        |

> **Always `unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy` first** — the ccmax-claude bearer-pin proxy 502s external hosts. The `claude` backend is BLOCKED (doorward 426); use the fleet **openai** door instead. See backends.md for keys, base URLs, and the mandatory `GRAPHIFY_LLM_TEMPERATURE=omit` for Opus.

Two-step headless flow (any backend): `graphify extract <target> …` then `graphify cluster-only <target> …` (regenerates GRAPH_REPORT.md + names communities). The plain `graphify <target>` one-shot also works once a backend's env is set. Cost prints after every run — relay it.

Useful flags (combinable):

| Flag                  | Effect                                                                  |
| --------------------- | ----------------------------------------------------------------------- |
| `--mode deep`         | More aggressive INFERRED edge extraction (slower, more edges)           |
| `--update`            | Re-extract only changed files (SHA256 cache), merge into existing graph |
| `--wiki`              | Also emit agent-crawlable wiki (`index.md` + article per community)     |
| `--svg` / `--graphml` | Static exports (Gephi, yEd)                                             |

Output lands in `<target>/graphify-out/`:

```
graphify-out/
├── graph.html       interactive graph (click, search, filter by community)
├── obsidian/        openable as an Obsidian vault
├── wiki/            (with --wiki) agent-navigable markdown wiki
├── GRAPH_REPORT.md  god nodes, surprising connections, suggested questions
├── graph.json       persistent graph — query later without re-reading files
└── cache/           SHA256 file cache for incremental --update runs
```

### 3. Report

Read `graphify-out/GRAPH_REPORT.md` and summarize for the operator:

1. **God nodes** — highest-degree concepts everything routes through
2. **Surprising connections** — with the plain-English "why" (code↔doc edges rank highest)
3. **Suggested questions** — what the graph is uniquely positioned to answer
4. **Token benchmark** — the printed reduction factor vs reading raw files

Remind the operator every edge is tagged `EXTRACTED` / `INFERRED` / `AMBIGUOUS` — trust extracted, verify inferred.

### 4. Ingest external sources (optional)

```bash
graphify add https://arxiv.org/abs/<id>     # paper → saved + merged into graph
graphify add https://x.com/<user>/status/…  # tweet
```

## Housekeeping

Add `graphify-out/` to `.gitignore` unless the operator explicitly wants the graph committed (graph.json can be large; cache/ is machine-local).
