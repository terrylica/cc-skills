# zai — Plugin SSoT (maintainers)

Z.ai **GLM Coding Plan (Pro)** exposed to Claude Code as a **complementary** consultant + toolbelt.
This never touches Claude Code's own model routing (Opus/Sonnet/**Haiku stay as-is**) — GLM is an
on-demand tool, mirroring the `catgpt`/`ask-chatgpt` pattern. Every fact here was **empirically
verified 2026-07-21** via 202 live API calls; the drift-checkable matrix is [`references/CAPABILITIES.md`](./references/CAPABILITIES.md).

**Hub**: [plugins/CLAUDE.md](../CLAUDE.md) | **User-facing**: [README.md](./README.md)

## What this plugin ships

| Layer                  | Path                               | Role                                                                                                                                                                                        |
| ---------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CLI (the engine)       | `scripts/zai.ts`                   | one Bun CLI: `chat` (fast/deep, ~1M via `--file`), `vision`, `websearch`, `read`, `models`, `quota`, `doctor`. Symlink → `~/.local/bin/zai`.                                                |
| Capability matrix      | `references/CAPABILITIES.md`       | the empirical SSoT: endpoints, 8 models, reasoning knobs, param matrix, MCP tools, what's gated                                                                                             |
| ask-glm skill          | `skills/ask-glm/SKILL.md`          | Claude **autonomously** consults GLM-5.2 (second opinion / big-context) — `allowed-tools: Bash`                                                                                             |
| zai-web-research skill | `skills/zai-web-research/SKILL.md` | Claude uses `zai websearch`/`zai read` (bundled MCP) for grounded research                                                                                                                  |
| glm subagent           | `agents/glm.md`                    | delegated, isolated GLM consult that returns a crisp verdict (Haiku orchestrator shells out)                                                                                                |
| glm skill (`/zai:glm`) | `skills/glm/SKILL.md`              | manual consult; `disable-model-invocation: true` so it fires only on the user's `/zai:glm` (was `commands/glm.md`, migrated to a skill 2026-07-22 so no plugin ships a raw `commands/` dir) |

## Critical invariants (don't break these)

1. **COMPLEMENTARY, never a replacement.** Do NOT wire GLM into `ANTHROPIC_DEFAULT_HAIKU_MODEL` or the
   base URL. Haiku keeps the web-analysis role (it resists prompt-injection in fetched content; GLM does
   not — see the injection finding in `references/CAPABILITIES.md`). GLM is a _tool you call_.
2. **Endpoint = coding, key = SCS.** Chat/vision/models use `https://api.z.ai/api/coding/paas/v4`
   (bills the subscription; the general `/api/paas/v4` returns "insufficient balance"). Key resolves
   `GLM_API_KEY | ZAI_API_KEY` env → `vault get glm api_key` (**never 1Password**). Proxy is stripped
   in-process (a local MITM proxy breaks direct z.ai calls).
3. **Two reasoning modes are the product.** fast = `thinking:{type:"disabled"}` (reasoning_tokens=0);
   deep = `thinking:{type:"enabled"}` + `reasoning_effort: low|medium|high|max`. Baseline (no key) =
   reasoning ON. Reasoning shares the `max_tokens` budget — give deep calls headroom.
4. **Output ceiling 131072** (200000 → error 1210). Input ~1.03M (measured). `glm-5.2[1m]` is NOT a
   valid API id — a client-side flag; plain `glm-5.2` already accepts ~1M.
5. **Vision needs a vision model** (`glm-4.6v`/`glm-4.5v`) on the coding endpoint; `glm-5.2` rejects
   images. `zai vision` defaults to `glm-4.6v`.
6. **MCP tools are SSE JSON-RPC.** `Accept` MUST include BOTH `application/json` AND `text/event-stream`.
   `web_search_prime` verified working; `web_reader`/`zread` were live but returned transient errors
   during the probe — retry-tolerant. `scripts/` is stripped from the runtime plugin cache, so run the
   CLI from the source checkout / the `~/.local/bin/zai` symlink, never the cache.

## Shared vs. NOT-shared quota

Bills the **same coding-plan quota as `~/459ecs/curve-dental`** (per-token TOKENS_LIMIT + a 1000/mo
MCP-call TIME_LIMIT for search-prime/web-reader/zread). `zai quota` shows it. Be considerate: a heavy
`--deep`/1M sweep bumps the 5-hour window (a full capability probe used ~9%). Gate bulk runs.

## Not available on this plan (verified)

Embeddings (err 1211), image generation (cogview → 1211), video generation (cogvideox → 1113
insufficient balance). Audio endpoints exist but need undocumented model ids (untested).

## Verify everything

```bash
zai doctor                      # key + coding-endpoint liveness
zai chat --fast "ping"          # fast mode
zai chat --deep --effort max "17*23-100? think then answer"   # deep mode
zai websearch "GLM-5.2"         # bundled web_search_prime MCP
zai models && zai quota
```

## Recent changes

- **2026-07-21** — Plugin created from a 12-area empirical probe (202 calls, 0 errors). CLI + ask-glm
  skill + glm subagent + /glm + capability matrix. Complementary-only by design.
- **2026-07-21** — Latest-model audit: every area confirmed on the newest id (chat/reasoning `glm-5.2`,
  vision `glm-4.6v`; nothing newer exists). Pins moved to one home (`CHAT_MODEL`/`VISION_MODEL` in
  `scripts/zai.ts`, read by chat/vision/doctor) + `zai models` drift-check. Details:
  [`references/CAPABILITIES.md`](./references/CAPABILITIES.md) § "Latest-model verification".
- **2026-07-22** — Migrated the manual consult from a raw `commands/glm.md` to a
  `skills/glm/SKILL.md` skill (`/zai:glm`, `disable-model-invocation: true`). zai was the only
  plugin shipping a plugin-root `commands/` dir, which tripped the release verifier's "legacy
  commands/" check on every release; skills are the marketplace's canonical command surface. The
  bare `/glm` alias is gone — invoke as `/zai:glm`. `ask-glm` (autonomous) is unchanged.
