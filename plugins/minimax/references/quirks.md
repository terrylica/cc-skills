# MiniMax M-series Quirks Reference

Sub-spoke of [`../CLAUDE.md`](~/own/amonic/minimax/CLAUDE.md). **Read this BEFORE wiring MiniMax into any production service.** This is a navigable index of behavioral quirks that diverge from the OpenAI-compat baseline — knowing them saves debugging cycles later.

> **Aggregated copy** of `~/own/amonic/minimax/quirks/CLAUDE.md` (source-of-truth — read-only). Cross-references retargeted to plugin-relative paths. Aggregated 2026-04-29 (iter-6 of cc-skills minimax aggregation campaign).

Each entry is a 2-4 sentence summary; deep dives live in [`../api-patterns/`](./api-patterns/) (linked per item). Verified hands-on by the autonomous-loop campaign documented in [`../LOOP_CONTRACT.md`](~/own/amonic/minimax/LOOP_CONTRACT.md). Last consolidation: 2026-04-29 after Tier 1 closure.

---

## 🔴 Critical findings (production wiring MUST know)

These five findings change how you write production code. If you only read one section, read this one.

### 1. `<think>...</think>` reasoning trace appears IN the response content

M-series is a reasoning model. Every chat-completion response has the model's private reasoning wrapped in literal `<think>` tags **inside the `content` string**, followed by the visible answer. Production clients MUST regex-strip `<think>[\s\S]*?</think>\s*` before showing output to users — otherwise users see deliberation followed by the answer (embarrassing UX).

**Cross-ref**: [chat-completion-minimal.md](./api-patterns/chat-completion-minimal.md), [chat-completion-streaming.md](./api-patterns/chat-completion-streaming.md) (where think-tags split across chunks)

### 2. Reasoning tokens DOMINATE the completion budget

A 3-line haiku consumed 906-1047 reasoning tokens (95-99% of budget) for 15-22 visible tokens. A simple counting prompt used ~90-140 reasoning tokens. **Setting `max_tokens=512` for any non-trivial task will produce empty visible output** — model burns the entire budget reasoning before emitting. Updated minimum floors: 1024 for tagging, 2048 for sentence answers, 4096 for creative writing.

**Cross-ref**: [chat-completion-temperature.md](./api-patterns/chat-completion-temperature.md), [chat-completion-max-tokens.md](./api-patterns/chat-completion-max-tokens.md)

### 3. Three OpenAI parameters are SILENTLY DROPPED

Verified across iter-7/iter-8/iter-9: `stop`, `usage` in streaming, and `response_format` (both `json_object` AND `json_schema` strict) are accepted with HTTP 200 but have NO effect on generation. This generalizes to: assume any non-trivial OpenAI parameter is silently dropped on MiniMax until proven otherwise by behavior-test. Real OpenAI 400-errors for invalid params; MiniMax just shrugs.

**Cross-ref**: [chat-completion-stop.md](./api-patterns/chat-completion-stop.md), [chat-completion-streaming.md](./api-patterns/chat-completion-streaming.md), [chat-completion-json.md](./api-patterns/chat-completion-json.md)

### 4. `temperature=0.0` is NOT deterministic

Two identical requests at temp=0.0 produced completely different haikus (different sha256 hashes). Deviates from OpenAI norm where temp=0 is effectively deterministic. Likely cause: reasoning trace samples regardless of `temperature`, plus backend MoE/batch nondeterminism, plus no client-controllable seed parameter. Do NOT rely on temp=0 for repeatable output (testing, dedup, content-hash caching).

**Cross-ref**: [chat-completion-temperature.md](./api-patterns/chat-completion-temperature.md)

### 5. Server-side `<think>` stripping in multi-turn replay (cost optimization)

When you replay a prior assistant turn that contains `<think>...</think>` content, MiniMax strips it server-side BEFORE prompt tokenization for billing. iter-10 confirmed: 419-char assistant content vs 5-char produced IDENTICAL `prompt_tokens` (70 each). **Multi-turn chat does NOT double-bill for accumulated reasoning** — linear cost growth, not quadratic. Clients don't need to strip `<think>` before replay for cost reasons (only for display/UI hygiene).

**Cross-ref**: [chat-completion-tokens.md](./api-patterns/chat-completion-tokens.md), [chat-completion-multi-turn.md](./api-patterns/chat-completion-multi-turn.md)

---

## Silent-drop / silent-omit catalog

The OpenAI-compat layer accepts these without error but doesn't honor them. **Test before depending on any non-listed parameter.**

| Parameter / Field                      | Status                                          | Verified iter | Workaround                                     |
| -------------------------------------- | ----------------------------------------------- | ------------- | ---------------------------------------------- |
| `stop`                                 | Accepted (200), no effect on generation         | iter-7        | Client-side `content.split(marker, 1)[0]`      |
| `usage` in streaming chunks            | Always `null` — no token accounting             | iter-8        | Use non-streaming, or approximate from content |
| `response_format=json_object`          | Accepted (200), no JSON enforcement             | iter-9        | Explicit prompt + `json.loads` + retry         |
| `response_format=json_schema` (strict) | Same as above                                   | iter-9        | Same — prompt-engineered JSON                  |
| Server enforcement of `max_tokens`     | Server allows arbitrarily large values silently | iter-6        | Client-side post-response cost ceiling check   |

**Untested but suspect** (worth behavior-testing before depending on them):

- `logit_bias`, `frequency_penalty`, `presence_penalty`
- `seed`, `top_logprobs`, `n>1`
- `tools` + `tool_choice` (defer to T2.1)
- `stream_options: {include_usage: true}` (might solve the streaming usage gap)
- `parallel_tool_calls`

---

## M-series reasoning quirks

### Reasoning math reconciliation

```
total_tokens = prompt_tokens + completion_tokens     # standard OpenAI
completion_tokens = reasoning_tokens + visible_emitted_tokens   # M-series convention
```

`reasoning_tokens` is a SUBSET of `completion_tokens`, not separately billed. So `cost = prompt × input_rate + completion × output_rate` (standard formula). The `reasoning/completion` ratio is purely diagnostic — high values (>0.9) mean the prompt is too ambiguous; refactor.

**Cross-ref**: [chat-completion-tokens.md](./api-patterns/chat-completion-tokens.md)

### `usage.completion_tokens_details` only contains `reasoning_tokens`

OpenAI's full schema includes `accepted_prediction_tokens`, `rejected_prediction_tokens`, `audio_tokens`, etc. on certain models. None of those appear on M-series. Defensive client pattern: `(usage.get("completion_tokens_details") or {}).get("reasoning_tokens", 0)`.

### Reasoning tokens scale with TASK complexity, not budget

iter-6 confirmed: same prompt at `max_tokens` ∈ {200, 10000, 100000} → reasoning was 89/95/139 (essentially constant ~90-140 with sampling jitter). The model doesn't fill the budget; it reasons until done. Don't try to "starve" the model by lowering `max_tokens` — that just truncates mid-thought and produces empty output.

### Persona prompts ~double reasoning tokens

iter-3: pirate-persona system prompt → 67 reasoning vs 38 reasoning without. The model spends extra reasoning on HOW to phrase under the persona constraint, not just WHAT to say. For tagging/summarization where reasoning overhead is wasteful, **prefer SHORT, INSTRUCTIONAL system prompts** ("Output 3-5 lowercase tags, comma-separated, no explanation") over persona prompts ("You are a tagging assistant...").

### Few-shot via fabricated assistant turns is cheaper than personas

Per iter-4 (stateless confirmed) + iter-3 (persona costs reasoning): instead of `system: "You are a tagging assistant..."`, use `system: "Generate 3-5 tags."` plus 2 fake `[user → assistant]` example pairs showing desired output format. Server-side `<think>` stripping (Critical Finding #5) means these fake assistant turns don't accumulate cost on replay.

### Creative prompts cost 5-7x latency vs factual lookup

Factual lookup ("capital of France?") completes in 1.8-3s; creative prompts (haiku, joke) take 13-22s. Production timeouts MUST be at least 30s for creative use cases. The "~100 TPS sustained" marketing claim refers to OUTPUT streaming, not reasoning generation speed — don't use it as a latency budget.

---

## Token accounting anomalies

### ⚠️ UNRESOLVED: `prompt_tokens` system-role anomaly (T3.10)

iter-3 observed that a ~25-token system message caused only +2 increase in `prompt_tokens` (50 vs 48). iter-4 narrowed scope: user/assistant turns DO scale proportionally, so the anomaly is **system-role-specific**. iter-10's `<think>` stripping discovery suggests MiniMax has server-side preprocessing for assistant role; possibly system role gets similar special handling (baseline replacement rather than concatenation?).

**Pending probe (T3.10)**: send a deliberately-long system prompt (500 tokens) and observe whether prompt_tokens scales proportionally. If non-proportional → MiniMax has discount/replacement billing for system role. **Until verified, count system tokens client-side via tiktoken and reconcile against `usage.prompt_tokens`** for cost-modeling.

**Cross-ref**: [chat-completion-system-prompt.md](./api-patterns/chat-completion-system-prompt.md)

### `usage.total_characters: 0` always present but always zero

Every chat-completion response includes `total_characters: 0` regardless of content size. Likely reserved for the audio/TTS API (where character count is the standard billing unit, not tokens). Defer confirmation to T2.4 audio probe. **Ignore for chat-completion accounting.**

---

## Output formatting defaults

### Default formatting is Markdown + emoji

`**Paris**` (Markdown bold) and 🏴‍☠️ (decorative emoji) appear unprompted. Chat-product DNA — built for conversational UX, not API-pipe-to-script. Services consuming MiniMax output for **plain-text contexts** (terminal, logs, CSV) MUST add explicit `"Output plain text only. No Markdown formatting. No emoji."` instruction in system prompt.

### Server-side validation is permissive

OpenAI 400-errors on invalid `response_format` shapes, missing required fields, etc. MiniMax accepts more loosely — many params silently drop. Server-side validation is for protocol shape only, not behavioral semantics. Test parameters before depending on them.

---

## Streaming quirks

### Coarse-grained chunks (not per-token)

`stream: true` emits chunks every ~300-500ms with ~125 chars per chunk. NOT per-token like real OpenAI. UX won't feel like ChatGPT typewriter; will look "type-paste-type-paste". Time-to-first-chunk is ~1.04s — halves perceived latency vs ~2.5s non-streaming for short prompts. Win is TTFB, not animation smoothness.

### `<think>` tags split across chunks

The first chunk of a stream typically contains `delta.content="<think>\nThe user"` — partial tag mid-chunk. Naive per-chunk think-tag stripping fails. **Pattern**: accumulate into a buffer, watch for `</think>` to appear, then split-and-emit-visible-portion. After that point, stream subsequent chunks directly to user.

```python
buffer = ""
visible_started = False
for chunk in stream:
    delta = chunk.choices[0].delta.content or ""
    buffer += delta
    if not visible_started and "</think>" in buffer:
        _, visible_part = buffer.split("</think>", 1)
        emit_to_user(visible_part.lstrip())
        visible_started = True
    elif visible_started:
        emit_to_user(delta)
```

### Each chunk repeats full MiniMax envelope

Every chunk includes `name: "MiniMax AI"`, `audio_content: ""`, sensitivity flags, etc. — even when their values don't change. Real OpenAI streaming sends only changed deltas. At scale this is bandwidth waste (~30% of bytes for a 12-chunk stream); negligible for low-volume.

**Cross-ref**: [chat-completion-streaming.md](./api-patterns/chat-completion-streaming.md)

---

## Headers, envelope, and protocol

### Six distinct id-style identifiers

MiniMax sends: `trace-id`, `x-session-id`, `x-mm-request-id`, `minimax-request-id`, `alb_receive_time`, `alb_request_id`. The body's `id` field equals `trace-id`. **Production clients should log `x-mm-request-id` for billing correlation** (it has the unique `<num>_<random>` shape that maps to billing exports).

### Endpoint-specific header sets

`x-session-id` and `x-mm-request-id` appeared on chat-completion but NOT on `/v1/models`. Don't write portable code that REQUIRES these headers — only chat-completion guarantees them.

### `base_resp` envelope leaks through

Chat-completion responses wrap a `base_resp: {status_code, status_msg}` envelope from MiniMax's internal RPC layer. Production clients should check `base_resp.status_code === 0` as a redundancy with HTTP status — if MiniMax ever ships a partial-success (HTTP 200 + base_resp.status_code != 0), this is the canary.

### Billing UI says `chatcompletion-v2(Text API)` even though URL is `/v1/chat/completions`

The "v2" refers to MiniMax's internal API version, not the URL path. Don't be confused if a future model lists `chatcompletion-v3(Text API)` in billing — internal protocol bump that may or may not require URL changes.

### Standard OpenAI SSE protocol envelope

Streaming uses `data: {json}` lines + `data: [DONE]` terminator. `object: "chat.completion.chunk"`. No protocol-level divergence — standard SSE clients work. Only the chunk shape inside diverges.

### Non-standard response fields

| Field                                            | Always present? | Notes                                 |
| ------------------------------------------------ | --------------- | ------------------------------------- |
| `message.name`                                   | Yes             | Usually `"MiniMax AI"` — not settable |
| `message.audio_content`                          | Yes             | Empty string in chat-completion       |
| `usage.total_characters`                         | Yes             | Always 0 (likely audio-API reserved)  |
| `input_sensitive` / `output_sensitive`           | Yes             | Both `false` on benign content        |
| `input_sensitive_type` / `output_sensitive_type` | Yes             | Both `0` on benign content            |

---

## Model catalog & upgrades

### Non-monotonic numbering

MiniMax released `M2 → M2.1 → M2.5 → M2.7`, skipping M2.2/2.3/2.4/2.6. Don't predict the next model name. **Use `/v1/models` listing as the source of truth** for valid model ids.

### `-highspeed` variants ship paired with their plain counterpart

From M2.1 onwards, both ship on the same `created` timestamp. Highspeed isn't a separate release cycle — it's a deployment mode bundled with each model release. M2 had no highspeed twin (introduced from M2.1).

### `response.model` is the authoritative model identity

The `model` request parameter is what you ASKED for; `response.model` is what ACTUALLY served you. Providers can silently route to a different tier on capacity issues. **For verification ("what model am I really using?"), inspect `response.model`, never trust the request field.**

**Cross-ref**: [models-endpoint.md](./api-patterns/models-endpoint.md)

### Cadence ~5-8 weeks between minor releases

Worth setting up a `mise run minimax:check-upgrade` task (T4.4) to poll `/v1/models` daily and fire alerts when a new highspeed variant lands. Defer to T4.4.

---

## Operational practices

### Shell heredoc + JSON body don't mix safely

First chat-completion attempt failed with `JSONDecodeError: Invalid control character at column 117` because nested quotes in `curl -d '...'` got mangled by bash. **Always write request bodies to `/tmp/<name>.json` and pass `--data @/tmp/<name>.json`.** Eliminates entire class of escape-hell bugs. Code in `api-patterns/` should always use file-based bodies for non-trivial JSON.

### Stateless conversation model

MiniMax has zero server-side conversation memory (iter-4 confirmed by injecting fabricated assistant turn). Implications: clients store/replay history; `x-session-id` is a tracing identifier NOT a state token; rewriting/trimming history is allowed; few-shot via fake assistant turns works (and is cheap, per Critical Finding #5).

### Plan budget: 300 prompts / 5 hour window (Plus – High-Speed)

Per the user's plan tier. Pacing matters at scale. The autonomous-loop campaign uses ~3 calls/iter average — well within budget for incremental probing. Production: plan for sub-second backoff on 429.

### `max_tokens` is OPTIONAL

MiniMax has a generous default budget. Contradicts OpenAI's older default of 16. For ad-hoc/dev calls you can omit `max_tokens` entirely. For production, still set it explicitly (cost predictability).

---

## Recommended client-side defaults

Combining the findings into a sensible default config for amonic services consuming MiniMax:

```python
PRODUCTION_DEFAULTS = {
    "model": "MiniMax-M2.7-highspeed",
    # response.model is authoritative — verify on first request
    "max_tokens": 4096,
    # 1024 minimum for tagging, 2048 for sentence, 4096 default safe ceiling
    # Higher values DON'T cost more (only generated tokens billed)
    # but add ~0.3s latency overhead at scale
    "temperature": 0.3,
    # Don't use 0.0 (NOT deterministic); 0.3 gives predictable-ish output
    # with enough variance for ambiguous inputs
    # DO NOT SET (silently dropped):
    # "stop": [...]
    # "response_format": {...}
    # "stream_options": {...}  # untested
    # "logit_bias": ...        # untested, suspect
    # "seed": ...              # untested, suspect
}

REQUIRED_PROMPT_HYGIENE = [
    "Output plain text only. No Markdown formatting. No emoji.",  # for plain-text consumers
    # OR for JSON consumers:
    "Output ONLY a JSON object matching: <shape>. No markdown, no code fences, no explanation.",
]

DEFENSIVE_RESPONSE_HANDLING = """
1. Check resp.choices[0].finish_reason:
   - "stop": natural completion (could also be invisible stop-trigger; can't tell)
   - "length": cap hit — if visible is empty, retry with higher max_tokens
2. Strip <think>...</think> from message.content via regex
3. If JSON expected: try json.loads(); on JSONDecodeError, retry with stricter prompt
4. Log x-mm-request-id for billing correlation
"""
```

---

## Pointers

- Campaign log: [`../LOOP_CONTRACT.md`](~/own/amonic/minimax/LOOP_CONTRACT.md) — full revision history, queue, Non-Obvious Learnings
- Endpoint patterns: [`../api-patterns/`](./api-patterns/) — one file per `/v1/<endpoint>`
- Hub: [`../CLAUDE.md`](~/own/amonic/minimax/CLAUDE.md) — verified facts table, consumption patterns, security notes
- Official docs (re-check at upgrades): <https://platform.minimax.io/docs/api-reference/text-openai-api>
- Billing UI: <https://platform.minimax.io/user-center/payment/billing-history>

## Tier 1 closure summary (2026-04-29)

Iters 1-10 closed all of T1.x (10 chat-completion + models patterns). 40+ Non-Obvious Learnings consolidated above. Outstanding from Tier 1: prompt_tokens system-role anomaly (T3.10 deferred). Next phase: Tier 2 endpoint discovery (function calling, vision, audio, video, embeddings, files, web-search MCP).
