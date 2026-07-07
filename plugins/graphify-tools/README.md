# graphify-tools

Claude Code skills wrapping [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) — turn any folder of code, docs, PDFs, and images into a queryable, persistent knowledge graph.

## Skills

| Skill                               | Purpose                                                                                       |
| ----------------------------------- | --------------------------------------------------------------------------------------------- |
| `/graphify-tools:setup`             | Install/verify the engine (`uv tool install graphifyy`)                                       |
| `/graphify-tools:build-graph`       | Build the graph: `graph.html`, `GRAPH_REPORT.md`, `graph.json`, Obsidian vault, optional wiki |
| `/graphify-tools:query-and-explain` | `query` / `path` / `explain` an existing graph without re-reading sources                     |
| `/graphify-tools:auto-sync`         | Keep the graph current: post-commit hook or `--watch` mode                                    |

## Install

```bash
claude plugin install graphify-tools@cc-skills
/graphify-tools:setup
```

## Why this exists alongside codegraph

codegraph (the MCP server already in this workspace) answers **symbol-level** code questions deterministically (callers, callees, impact). graphify answers **concept-level** questions across a **mixed corpus** — code + papers + markdown + screenshots — with LLM-extracted edges tagged `EXTRACTED`/`INFERRED`/`AMBIGUOUS` and ~71× token reduction on large corpora. Use both: codegraph for "what calls X", graphify for "what connects X to Y".

## Requirements

- `uv` (engine installs as an isolated uv tool; Python 3.10+ provisioned automatically)
- Claude Code (extraction of docs/images uses Claude)
