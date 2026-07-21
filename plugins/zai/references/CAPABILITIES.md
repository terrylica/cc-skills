# Z.ai GLM Coding Plan (Pro) — empirically verified capability matrix

**Probed 2026-07-21** via 202 live API calls (12 parallel probe agents, 0 errors). Only VERIFIED
findings below; unverified items are marked. This is the drift contract — re-probe before trusting a
stale row.

## Endpoints

| Endpoint                           | URL                                                                | Auth                                          | Notes                            |
| ---------------------------------- | ------------------------------------------------------------------ | --------------------------------------------- | -------------------------------- |
| OpenAI-compat (chat/vision/models) | `https://api.z.ai/api/coding/paas/v4`                              | `Authorization: Bearer`                       | bills the coding plan            |
| Anthropic-compat                   | `https://api.z.ai/api/anthropic/v1/messages`                       | `x-api-key` + `anthropic-version: 2023-06-01` | same plan/key; full Messages API |
| MCP tools                          | `https://api.z.ai/api/mcp/{web_search_prime,web_reader,zread}/mcp` | `Bearer`                                      | JSON-RPC 2.0 over SSE            |
| Quota                              | `https://api.z.ai/api/monitor/usage/quota/limit`                   | `Bearer`                                      | per-token + MCP allowance        |
| General PAYG (NOT this plan)       | `https://api.z.ai/api/paas/v4`                                     | —                                             | returns "insufficient balance"   |

## Models (8 chat + 2 vision)

| Model id                | Resolves to | Use                                                  |
| ----------------------- | ----------- | ---------------------------------------------------- |
| `glm-5.2`               | glm-5.2     | flagship; ~1M ctx; default                           |
| `glm-5-turbo`           | glm-5-turbo | faster/cheaper tier                                  |
| `glm-5` / `glm-5.1`     | → glm-5.2   | server-side alias                                    |
| `glm-4.7`               | glm-4.7     | prior gen (heavy reasoner)                           |
| `glm-4.5-air`           | → glm-4.7   | alias                                                |
| `glm-4.6` / `glm-4.5`   | self        | legacy                                               |
| `glm-4.6v` / `glm-4.5v` | self        | **vision** (not always in /models; `glm-4v` invalid) |

### Latest-model verification (2026-07-21)

Each area is pinned to the **newest available** id (probed exhaustively): **chat/reasoning = `glm-5.2`**
(no `glm-5.3`/`5.5`/`6`/`-pro`/`-max`/`-flash` — all "Unknown Model"); **vision = `glm-4.6v`** (no
`glm-4.7v`/`5v`/`5.2v`; only `4.5v`/`4.6v` exist). The pins live in one home in `scripts/zai.ts`
(`CHAT_MODEL`, `VISION_MODEL`); `zai models` drift-checks the live catalog and flags a newer id to port.

## Chat parameter matrix (glm-5.2, OpenAI endpoint)

| Param                      | Status           | Param                           | Status                                     |
| -------------------------- | ---------------- | ------------------------------- | ------------------------------------------ |
| temperature                | ✅ honored       | response_format json_object     | ✅                                         |
| top_p / top_k              | ✅ honored       | response_format json_schema     | ✅ enforced                                |
| stop                       | ✅ (first match) | tools + tool_choice (forced fn) | ✅                                         |
| seed                       | ✅ accepted      | parallel tool_calls             | ✅                                         |
| presence/frequency_penalty | ✅               | stream (SSE)                    | ✅ delta.reasoning_content + delta.content |
| n > 1                      | ❌ silently 1    | logprobs / top_logprobs         | ❌ not returned                            |

- **max_tokens ceiling = 131072** (200000 → HTTP 400 err 1210 "range [1,131072]").
- **Input context ≈ 1.03M** (measured: accepts 1,032,882 tokens, rejects ~1.27M err 1261).
- `tool_calls[].function.arguments` is a **JSON string**, not an object.

## Reasoning / thinking — the two-mode product

| Mode     | Body                                                                     | Effect                                                         |
| -------- | ------------------------------------------------------------------------ | -------------------------------------------------------------- |
| **fast** | `thinking:{type:"disabled"}`                                             | reasoning_tokens=0, full budget on the answer                  |
| **deep** | `thinking:{type:"enabled"}` + `reasoning_effort: low\|medium\|high\|max` | reasoning_content + reasoning_tokens (max ≈ deepest)           |
| baseline | (no thinking key)                                                        | reasoning ON by default (≈ medium) — opt-OUT model, not opt-in |
| hybrid   | `reasoning_effort:"high"` alone                                          | reasoning + content both populated                             |

`budget_tokens:N` also accepted under `thinking`. Reasoning shares the `max_tokens` pool — a small cap
with reasoning ON can exhaust the budget before any content (finish_reason="length").
`usage.completion_tokens_details.reasoning_tokens` reports the spend.

## Vision

- Coding endpoint, **vision model required**: `{model:"glm-4.6v", messages:[{role:"user", content:[{type:"text",text:"..."},{type:"image_url",image_url:{url:"data:image/png;base64,..."}}]}]}`. Key must be lowercase `url`. `glm-5.2` rejects image content.
- Anthropic endpoint: `{type:"image", source:{type:"url"|"base64", ...}}`.
- `glm-4.6v` reasoning ON by default; `thinking:{type:"disabled"}` suppresses it.

## Anthropic-compat endpoint (full Messages API)

system ✅ · tools (Anthropic format) ✅ · streaming ✅ · extended thinking `{type:"enabled",budget_tokens:N}` → `thinking` blocks + `signature` field ✅ · vision ✅ · json_object ✅. `glm-5.2[1m]` invalid; `anthropic-beta: context-1m` silently accepted (no-op — 1M already native).

## Bundled MCP tools (JSON-RPC 2.0 over SSE)

`Accept` header MUST include BOTH `application/json` AND `text/event-stream`. Handshake: `initialize`
→ `notifications/initialized` → `tools/call`. Result in `result.content[].text`.

| Server             | Tool(s)                                   | Status                                         | Key params                                                                                                                                |
| ------------------ | ----------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `web_search_prime` | `web_search_prime`                        | ✅ working                                     | search_query, search_recency_filter (oneDay/oneWeek/oneMonth/oneYear), content_size (medium/high), location (cn/us), search_domain_filter |
| `web_reader`       | `webReader`                               | ⚠️ live, transient "fetch failed" during probe | url, return_format (markdown/text), timeout, no_cache                                                                                     |
| `zread`            | search_doc, read_file, get_repo_structure | ⚠️ live, returned -500 during probe            | repo_name (owner/repo), query/file_path/dir_path                                                                                          |

Quota: 1000 MCP calls/month (TIME_LIMIT), shared across the three; `zai quota` shows usage.

## NOT available on this plan (verified)

| Capability                                                   | Result                                                         |
| ------------------------------------------------------------ | -------------------------------------------------------------- |
| Embeddings                                                   | ❌ err 1211 "Unknown Model" (no embedding models)              |
| Image generation (cogview-*)                                 | ❌ err 1211                                                    |
| Video generation (cogvideox-3)                               | ❌ err 1113 "insufficient balance" (plan-gated)                |
| Audio (speech/transcription)                                 | endpoints exist but need undocumented model ids — **untested** |
| `/v4/{files,batches,agents,assistants,completions,tokenize}` | ❌ 404 / 500                                                   |

## Undocumented-but-usable (flag)

1. Baseline reasoning is ON by default (opt-out, unlike OpenAI).
2. `reasoning_effort` alone (no `thinking` key) = hybrid reasoning+content.
3. Server-side model aliasing (glm-5/glm-5.1→glm-5.2, glm-4.5-air→glm-4.7).
4. Anthropic-compat endpoint + MCP tools bundled with the coding plan (no separate auth/gating).
5. `thinking.signature` field in extended-thinking responses (audit/trace, purpose unknown).
6. Quota endpoint `/api/monitor/usage/quota/limit` not in public docs.

## Security note (decision-relevant)

The MCP web tools fetch **untrusted** content — treat results as data, watch for prompt injection.
This is exactly why the web-analysis role stays on **Haiku** (injection-resistant) while GLM is used as
a _called tool_; earlier testing showed Haiku refuses injection-shaped content that GLM complies with.
