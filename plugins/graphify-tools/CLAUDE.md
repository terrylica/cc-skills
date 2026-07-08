# graphify-tools Plugin

> Multimodal knowledge graphs via Graphify-Labs/graphify (code + docs + PDFs + images → one queryable graph).

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Siblings**: [quality-tools](../quality-tools/CLAUDE.md) | [devops-tools](../devops-tools/CLAUDE.md)

## Skills

- [setup](./skills/setup/SKILL.md) — install/verify engine via `uv tool install graphifyy`
- [build-graph](./skills/build-graph/SKILL.md) — core: folder → `graphify-out/` (graph.html, GRAPH_REPORT.md, graph.json)
- [query-and-explain](./skills/query-and-explain/SKILL.md) — `query` / `path` / `explain` a persistent graph
- [auto-sync](./skills/auto-sync/SKILL.md) — post-commit hook or `--watch` freshness

## Backend routing SSoT

[`references/backends.md`](./references/backends.md) is the SSoT for **which LLM does extraction** — the three wired backends (fleet Opus 4.8, gemini-2.5-flash, MiniMax-M3), their keys/base-URLs, the mandatory proxy-unset, and `GRAPHIFY_LLM_TEMPERATURE=omit` for Opus. All three skills point there instead of duplicating env blocks.

## Critical invariants (read before editing)

1. **PyPI package is `graphifyy` (double-y), CLI is `graphify`.** Temporary upstream naming while the `graphify` PyPI name is reclaimed. If upstream reclaims it, update setup/SKILL.md's install command and the gotcha callout together. `uv tool install graphify` installs the WRONG package.
2. **uv-first, never pip/pipx.** Operator standing directive. `uv tool` provisions its own Python 3.10+, so the host repo's pinned Python is untouched (pin-wins rule).
3. **Do NOT run `graphify install` by default.** It writes an upstream `~/.claude/skills/graphify/SKILL.md` that duplicates this plugin's `build-graph` invocation path. Skill files here wrap the CLI directly; two overlapping skills confuse triggering.
4. **Division of labor vs codegraph (MCP)**: codegraph = symbol-level, deterministic, sub-ms (callers/callees/impact). graphify = concept-level, LLM-extracted, multimodal, persistent across sessions. Skills must hand off accordingly — build-graph and query-and-explain both carry the handoff note; keep it when editing.
5. **Token-cost gate in build-graph**: LLM extraction of docs/images costs real tokens — the skill must keep its scope-check step (size probe + ask before big corpora). Don't "simplify" it away.
6. **`graphify-out/` is gitignored by default** (graph.json can be large, cache/ is machine-local). Committing the graph is an explicit operator opt-in.
7. **`--backend claude` is BLOCKED on this fleet** (verified 2026-07-07): `ANTHROPIC_BASE_URL` points at doorward's fidelity-guarded `/v1/messages` door, which 426-rejects any request missing the `X-Ccmax-Wrapper-Version` header — only ccmax-claude's own proxy injects it; third-party SDKs can't. Use the fleet **openai** door instead (backend A in backends.md) — same eon accounts, unguarded `/v1/chat/completions` path. Install extras `graphifyy[anthropic,gemini]` or semantic extraction fails with a missing-package error.
8. **Same-named files in different dirs collide** (upstream #1666 adjacent): cross-chunk node-ID collisions drop the second node with a warning. For corpora with repeated filenames (e.g. many `SKILL.md`), consider per-subfolder `graphify extract` + `graphify merge-graphs`.
9. **Backend env quirks (backends.md is SSoT)**: every backend needs `unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy` (bearer-pin proxy 502s external hosts). Fleet Opus needs `GRAPHIFY_LLM_TEMPERATURE=omit` (400 otherwise). MiniMax-M3 works but is slow (~5 min/6 files, thinking-on; graphify can't send its `reasoning_split` flag) — reserve for small dense corpora, not bulk.

## Smoke test provenance (2026-07-07)

Target: `plugins/statusline-tools/` (24 code + 15 docs). Result: 344 nodes, 484 edges, 26 communities; 100% EXTRACTED edges; cost $0.14 (gemini-2.5-flash). God node #1 = `statusline-tools Plugin`; report correctly surfaced the doorward-integration and telemetry-analytics communities. Two-step flow used: `extract` → `cluster-only`.

## Provenance

- 2026-07-07: plugin created. Operator asked whether Graphify-Labs/graphify (79.5k★) was ever installed — it wasn't; codegraph covered the code-graph niche before graphify existed/was known. Decided complementary, wrapped as 4 skills per AskUserQuestion round: new dedicated plugin, uv install, all four capability skills, smoke-tested on this repo.
- 2026-07-07 (follow-up): operator asked graphify to use "our LLM" like markmind/harpa. Surveyed `~/eon/ccmax-monitor` → sub2api OpenAI gateway (`eon.25u.com:8450/v1`). Provisioned a dedicated `graphify` sub2api user (id 102, group 5, $50, key id 20148) per the harpa/markmind doctrine; stored in 1Password `2eeg5h4n3st6kcmt3icjhfjiiy`. Verified graphify `--backend openai` → Opus 4.8 end-to-end (needs `GRAPHIFY_LLM_TEMPERATURE=omit`). Also tested MiniMax-M3 (`api.minimax.io`, 1Password `e54cb3ujopexslaq7loywpuycm`): works, richer extraction, but ~5 min/6 files. Backend routing SSoT → `references/backends.md`.
