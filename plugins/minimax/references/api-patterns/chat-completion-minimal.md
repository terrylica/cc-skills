# POST /v1/chat/completions — Minimum-Viable Request

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-minimal.md` (source-of-truth — read-only, source iter-2). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-8).

Verified 2026-04-29 against `https://api.minimax.io/v1/chat/completions` with `MiniMax-M2.7-highspeed`.

## Required fields (verified)

| Field      | Type             | Notes                                                                                                                            |
| ---------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `model`    | string           | Must be a valid id from `/v1/models` (see [`models-endpoint.md`](./models-endpoint.md)). Verified with `MiniMax-M2.7-highspeed`. |
| `messages` | array of objects | Standard OpenAI shape: `[{"role": "user", "content": "..."}]`. Must be non-empty.                                                |

That's it. **No `max_tokens` required**, no `temperature`, no `top_p`.

## Optional fields with implicit defaults (verified)

| Field         | Default behavior                                                                                 | Test                                                                           |
| ------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `max_tokens`  | adequate budget — sufficient for reasoning + visible output without truncation on simple prompts | Omitted in E2 → 107 completion tokens + `finish_reason: "stop"` (not "length") |
| `temperature` | non-zero (sampling occurs)                                                                       | Inferred from response — separate temperature sweep deferred to T1.5           |
| `top_p`       | active                                                                                           | Same — deferred to T1.5                                                        |
| `stream`      | `false` (single JSON response, not SSE)                                                          | Default behavior in all iter-2 tests                                           |

## Bare-minimum example (use this everywhere)

```bash
API_KEY=$(op read "op://<vault>/<item>/password" --account <account>)

cat > /tmp/mm-req.json << 'JSON'
{
  "model": "MiniMax-M2.7-highspeed",
  "messages": [{"role": "user", "content": "What is 7 times 8? Answer with just the number."}],
  "max_tokens": 1024
}
JSON

curl -sS -X POST https://api.minimax.io/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  --data @/tmp/mm-req.json
```

**File-based body is mandatory** in any non-trivial example: shell escaping for nested JSON quotes is error-prone. See [`../LOOP_CONTRACT.md`](~/own/amonic/minimax/LOOP_CONTRACT.md) Non-Obvious Learnings for the heredoc-traps reasoning. Even small examples should use this pattern for muscle memory.

## Response anatomy (verified)

```json
{
  "id": "06407ea121ddc267a22ca62c3e0a6997",
  "choices": [
    {
      "finish_reason": "stop",
      "index": 0,
      "message": {
        "content": "<think>\nThe user asks: \"What is 7 times 8?\" ... \n</think>\n\n56",
        "role": "assistant",
        "name": "MiniMax AI",
        "audio_content": ""
      }
    }
  ],
  "created": 1777421217,
  "model": "MiniMax-M2.7-highspeed",
  "object": "chat.completion",
  "usage": {
    "total_tokens": 116,
    "total_characters": 0,
    "prompt_tokens": 55,
    "completion_tokens": 61,
    "completion_tokens_details": {
      "reasoning_tokens": 60
    }
  },
  "input_sensitive": false,
  "output_sensitive": false,
  "input_sensitive_type": 0,
  "output_sensitive_type": 0,
  "output_sensitive_int": 0,
  "base_resp": {
    "status_code": 0,
    "status_msg": ""
  }
}
```

Full fixtures:

- [`fixtures/chat-completion-minimal-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-minimal-2026-04-28.json) — with explicit `max_tokens: 1024`
- [`fixtures/chat-completion-no-max-tokens-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-no-max-tokens-2026-04-28.json) — `max_tokens` omitted

## Critical content-parsing pattern: stripping `<think>...</think>`

**The `content` string contains the reasoning trace AS LITERAL TAGS** — clients that just print the content show users the model's private chain-of-thought followed by the actual answer. Example from the 7×8 probe:

```
<think>
The user asks: "What is 7 times 8?" So answer should be "56". However, check if any policy issues...
</think>

56
```

Production clients MUST strip the `<think>...</think>` block before showing to users. Suggested patterns:

```python
import re
visible = re.sub(r"<think>.*?</think>\s*", "", content, flags=re.DOTALL)
```

```javascript
const visible = content.replace(/<think>[\s\S]*?<\/think>\s*/, "");
```

```bash
# rough shell version — assumes single <think> block
echo "$content" | sed -E 's|<think>.*</think>||' | tr -s '\n'
```

Failure mode if NOT stripped: end-users see the model debating policy / re-stating the prompt, then the answer. Embarrassing for production UX.

## Token-accounting rule (verified)

- `usage.completion_tokens` is the **total** generated tokens
- `usage.completion_tokens_details.reasoning_tokens` is **included in** completion_tokens (not added)
- Visible-output tokens = `completion_tokens - reasoning_tokens`

Example from the 7×8 probe: `completion_tokens=61`, `reasoning_tokens=60` → only 1 visible token ("56"). Reasoning consumed 98% of the completion budget for an arithmetic question.

**Practical implication for `max_tokens` sizing**:

| Use case                             | Suggested `max_tokens` floor |
| ------------------------------------ | ---------------------------- |
| Tagging (5-15 visible tokens output) | 256-512                      |
| Sentence-length answers              | 512-1024                     |
| Paragraph summaries                  | 1024-2048                    |
| Multi-paragraph responses            | 2048-4096+                   |

Always budget at least 200-500 tokens of headroom for `<think>` reasoning, even if you only need 10 visible tokens. Setting `max_tokens=30` (as in iter-0) caused full truncation with zero visible output.

## MiniMax-specific response fields (vs OpenAI)

These fields are NOT in OpenAI's standard chat.completion response:

| Field                                              | Type   | Observed values                        | Inferred meaning                                                       |
| -------------------------------------------------- | ------ | -------------------------------------- | ---------------------------------------------------------------------- |
| `choices[].message.name`                           | string | `"MiniMax AI"`                         | Model self-identifier; constant across requests                        |
| `choices[].message.audio_content`                  | string | `""` (empty)                           | Reserved for audio output; non-empty when model returns voice          |
| `usage.total_characters`                           | int    | `0`                                    | Probably populated for char-billed services (TTS); always 0 for text   |
| `usage.completion_tokens_details.reasoning_tokens` | int    | varies                                 | M-series only — not in OpenAI's M0/4o-mini/etc.                        |
| `input_sensitive`                                  | bool   | `false`                                | Content moderation flag on input                                       |
| `output_sensitive`                                 | bool   | `false`                                | Content moderation flag on output                                      |
| `input_sensitive_type`                             | int    | `0`                                    | Moderation severity enum (full set TBD — T3.8)                         |
| `output_sensitive_type`                            | int    | `0`                                    | Same as above for output                                               |
| `output_sensitive_int`                             | int    | `0`                                    | Distinct from `output_sensitive_type` — purpose unclear                |
| `base_resp`                                        | object | `{"status_code": 0, "status_msg": ""}` | MiniMax's internal RPC envelope; non-zero status_code likely on errors |

Standard OpenAI response is a strict subset; portable cross-provider clients should ignore unknown fields rather than fail.

## MiniMax-specific response headers (vs OpenAI)

```
trace-id: 06407ea121ddc267a22ca62c3e0a6997
x-session-id: 81cd052099a10698672c8e3bc7c1459c          ← NEW (not in /v1/models)
x-mm-request-id: 2024530792255857454_17774212171z9k8v   ← NEW (not in /v1/models)
minimax-request-id: 13b28894ff08a8a99d16caf17d41d783
alb_receive_time: 1777421217.378
alb_request_id: fa0365fef89968d03a66eeb6fe494f0882875e89
```

**MiniMax sends 4 distinct id-style headers** plus 2 AWS ALB ones:

| Header               | Source  | Notes                                                                 |
| -------------------- | ------- | --------------------------------------------------------------------- |
| `trace-id`           | MiniMax | Identical to `response.body.id`                                       |
| `x-session-id`       | MiniMax | Connection/session — appeared on chat-completion, not on `/v1/models` |
| `x-mm-request-id`    | MiniMax | Different format (`<long-num>_<random>`); use for billing correlation |
| `minimax-request-id` | MiniMax | Hex; same shape as `trace-id`                                         |
| `alb_receive_time`   | AWS ALB | Edge ingress timestamp                                                |
| `alb_request_id`     | AWS ALB | Load balancer's id                                                    |

Production logging recommendation: capture `x-mm-request-id` in any production logging — it's the value you'd quote in support tickets or correlate with billing exports.

## Performance baseline

| Metric                                | Value            | Notes                                                         |
| ------------------------------------- | ---------------- | ------------------------------------------------------------- |
| Latency, simple prompt with reasoning | 2.7-3.4s         | M-series spends time reasoning even for trivial prompts       |
| Response size, simple prompt          | 800-1100 bytes   | Dominated by `content` field (which contains `<think>` block) |
| Tokens/sec measurement                | deferred to T3.5 | This iteration didn't time output streaming                   |

## Provenance

| Verification call    | Value (E1: with max_tokens)            | Value (E2: no max_tokens) |
| -------------------- | -------------------------------------- | ------------------------- |
| Date                 | 2026-04-29 00:06:57 UTC                | 2026-04-29 00:07:09 UTC   |
| HTTP status          | 200                                    | 200                       |
| Latency              | 2.746s                                 | 3.379s                    |
| Response size        | 831B                                   | 1095B                     |
| `trace-id`           | `06407ea121ddc267a22ca62c3e0a6997`     | (in fixture)              |
| `minimax-request-id` | `13b28894ff08a8a99d16caf17d41d783`     | (in fixture)              |
| `x-mm-request-id`    | `2024530792255857454_17774212171z9k8v` | (in fixture)              |
| Verifier             | autonomous-loop iter-2                 | iter-2                    |
