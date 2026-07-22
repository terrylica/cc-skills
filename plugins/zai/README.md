# zai

**Z.ai GLM Coding Plan (Pro) as a complementary consultant + toolbelt for Claude Code.** GLM-5.2 is a
large off-fleet model you can consult on demand — it does **not** replace Haiku/Sonnet/Opus. One `zai`
CLI plus a skill, subagent, and slash command. Every capability was empirically verified (2026-07-21).

## Install

```bash
# CLI on PATH (source checkout; scripts are stripped from the plugin cache)
ln -sf ~/eon/cc-skills/plugins/zai/scripts/zai.ts ~/.local/bin/zai
zai doctor          # verifies the SCS key + coding endpoint
```

Key resolves from `GLM_API_KEY` / `ZAI_API_KEY`, else Self-Custody Secrets `vault get glm api_key`.

## CLI

```bash
zai chat "quick q"                          # fast (thinking disabled)
zai chat --deep "hard reasoning q"          # extended reasoning (effort=high)
zai chat --deep --effort max --max 4000 "…" # deepest
zai chat --file big.log "summarize risks"   # ~1M-token context (also: --file -  for stdin)
zai vision --image shot.png "what's shown?" # image analysis (glm-4.6v)
zai websearch --recency oneWeek "query"     # bundled web_search_prime MCP
zai read https://example.com                # bundled web_reader MCP
zai models | zai quota | zai doctor
```

## In Claude Code

- **`ask-glm` skill** — Claude autonomously consults GLM for a second opinion / big-context read.
- **`glm` subagent** — delegate an isolated GLM consult that returns a crisp verdict.
- **`/zai:glm`** — manual consult (the `glm` skill; was `/glm`).

## Highlights (verified)

- **Two modes**: fast (`thinking:disabled`) and deep (`thinking:enabled` + `reasoning_effort low→max`).
- **~1M input context** (measured 1.03M); **131072** output cap.
- **8 chat models** (glm-4.5 … glm-5.2, `glm-5-turbo`) + **vision** (`glm-4.6v`/`glm-4.5v`).
- **Bundled MCP tools**: web search / web reader / (zread).
- **Not on this plan**: embeddings, image-gen, video-gen.

Maintainer SSoT: [CLAUDE.md](./CLAUDE.md). Full matrix: [references/CAPABILITIES.md](./references/CAPABILITIES.md).
