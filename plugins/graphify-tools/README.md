# graphify-tools

Claude Code skills wrapping [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) — turn any folder of code, docs, PDFs, and images into a queryable, persistent **knowledge graph**. Get god nodes, surprising cross-corpus connections, an interactive `graph.html`, an Obsidian vault, and an agent-navigable wiki — with ~71× token reduction on large mixed corpora vs re-reading raw files.

## Skills

| Skill                               | Purpose                                                                                        |
| ----------------------------------- | ---------------------------------------------------------------------------------------------- |
| `/graphify-tools:setup`             | Install/verify the engine (`uv tool install "graphifyy[anthropic,gemini]"`) and pick a backend |
| `/graphify-tools:build-graph`       | Build the graph: `graph.html`, `GRAPH_REPORT.md`, `graph.json`, Obsidian vault, optional wiki  |
| `/graphify-tools:query-and-explain` | `query` / `path` / `explain` an existing graph without re-reading sources                      |
| `/graphify-tools:auto-sync`         | Keep the graph current: post-commit hook or `--watch` mode                                     |

## Install

```bash
claude plugin install graphify-tools@cc-skills
/graphify-tools:setup
```

## Invoking it on ANY repository or folder

Two ways — a natural-language skill invocation, or the raw CLI.

### 1. Via the skill (recommended in a Claude session)

Just ask, naming the folder. Claude routes to `build-graph`:

```
graphify ~/eon/some-project          # build a graph of that repo
map this codebase                     # graphs the current repo
graph ~/raw --wiki                    # build + agent wiki
```

Then, later, ask the persistent graph questions (routes to `query-and-explain`, **no LLM/cost**):

```
what connects the auth layer to the database in ~/eon/some-project?
path from DigestAuth to Response
explain the SwinTransformer node
```

### 2. Via the raw CLI (any shell, any repo)

The engine is a normal binary once installed. The invariant preamble on **this machine** (ccmax fleet):

```bash
cd <any-repo>
unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy     # bearer-pin proxy 502s external hosts

# choose ONE backend (see "Which LLM" below), then:
graphify extract .        --backend <b> --model <m>     # AST + semantic extraction
graphify cluster-only .   --backend <b> --model <m>     # names communities, writes GRAPH_REPORT.md
# → output in ./graphify-out/  (graph.html, GRAPH_REPORT.md, graph.json, obsidian/, cache/)

graphify query "<question>"      # ask the built graph (no LLM)
graphify path "A" "B"            # shortest/strongest concept path
graphify explain "NodeName"      # deep-dive one node
graphify update .                # incremental re-extract of changed files (AST, no LLM cost)
graphify add https://arxiv.org/abs/1706.03762   # fetch + merge an external paper/tweet
```

**Big repos with many same-named files** (a marketplace of `SKILL.md`s): extract per-subfolder then `graphify merge-graphs`, so cross-chunk name collisions don't drop nodes.

## Which LLM does the extraction? (fleet-routed)

graphify's `--backend` picks the model for the semantic step. Three are wired for this operator — **full copy-paste env blocks + keys live in [`references/backends.md`](./references/backends.md)** (the routing SSoT):

| Backend              | Command shape                                                                | When                                    | Ban-risk                               |
| -------------------- | ---------------------------------------------------------------------------- | --------------------------------------- | -------------------------------------- |
| **gemini-2.5-flash** | `--backend gemini --model gemini-2.5-flash`                                  | large / bulk runs — the safe default    | none                                   |
| **fleet Opus 4.8**   | `--backend openai --model claude-opus-4-8` + `GRAPHIFY_LLM_TEMPERATURE=omit` | interactive / smaller graphs, "our LLM" | ⚠ HEART-103 bypass on eon Max accounts |
| **MiniMax-M3**       | `--backend openai --model MiniMax-M3`                                        | a few dense files, latency OK (slow)    | none                                   |

Fleet Opus routes through a **dedicated `graphify` sub2api key** (1Password `2eeg5h4n3st6kcmt3icjhfjiiy`), provisioned the same way as the MarkMind/HARPA browser integrations — its own wallet + one-line kill-switch. The `claude` backend is **blocked** (doorward's fidelity guard 426s direct SDK calls); the fleet **openai** door reaches the same accounts unguarded.

## Why this exists alongside codegraph

codegraph (the MCP server already in this workspace) answers **symbol-level** code questions deterministically (callers, callees, impact) in sub-ms. graphify answers **concept-level** questions across a **mixed corpus** — code + papers + markdown + screenshots — with LLM-extracted edges tagged `EXTRACTED` / `INFERRED` / `AMBIGUOUS`. Use both: codegraph for "what calls X", graphify for "what connects X to Y across these files".

## Keeping a graph fresh

```bash
graphify hook install     # post-commit hook: rebuild after each commit (recommended)
graphify . --watch        # live rebuild on file save (foreground; for active multi-agent sessions)
```

See `/graphify-tools:auto-sync` for the trade-offs.

## Requirements

- `uv` (engine installs as an isolated uv tool; Python 3.10+ provisioned automatically)
- Extraction backend key (gemini in-env, or a fleet/MiniMax key from 1Password — see backends.md)
- `op` (1Password CLI) to resolve the fleet/MiniMax keys
