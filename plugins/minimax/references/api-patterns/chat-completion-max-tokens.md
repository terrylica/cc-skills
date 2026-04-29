# Chat Completion — `max_tokens` Boundary Probing

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-max-tokens.md` (source-of-truth — read-only, source iter-6). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-8).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. Tests `max_tokens` at 4 values: tiny (8), default-ish (200), large (10000), absurd (100000). All against the same simple prompt: `"Count from 1 to 5, one number per line."`.

## Results matrix

| `max_tokens` | HTTP | finish_reason | reasoning | completion | visible                   | latency |
| ------------ | ---- | ------------- | --------- | ---------- | ------------------------- | ------- |
| 8            | 200  | **length**    | 8         | 8          | (empty)                   | 1.55s   |
| 200          | 200  | stop          | 89        | 98         | `"1\n2\n3\n4\n5"`         | 3.10s   |
| 10000        | 200  | stop          | 95        | 104        | `"1\n2\n3\n4\n5"`         | 3.30s   |
| 100000       | 200  | stop          | 139       | 148        | `"1  \n2  \n3  \n4  \n5"` | 3.95s   |

## Headline findings

### Finding 1: Server accepts arbitrarily large `max_tokens` silently

`max_tokens=100000` returned HTTP 200 with no warning, no error, no truncation message. **The cap is NOT enforced at the request boundary** — only actual generated tokens are billed.

This means:

- You can set `max_tokens` generously high without server pushback
- You can't use `max_tokens` to discover the model's actual context window — the server doesn't tell you
- Production cost protection requires CLIENT-side cost ceilings (e.g., reject responses above N tokens) — server won't enforce for you

### Finding 2: `finish_reason` distinguishes "stop" from "length"

| finish_reason | Meaning                                           |
| ------------- | ------------------------------------------------- |
| `"stop"`      | Natural completion — model finished within budget |
| `"length"`    | Hit `max_tokens` cap before completing            |

For `max_tokens=8` we got `"length"` because reasoning alone exceeded the budget. For all larger budgets we got `"stop"` because reasoning + visible output finished naturally.

**Production code MUST check `finish_reason`** — `"length"` indicates a possibly truncated/incomplete response. Retry with higher `max_tokens` or accept the truncation explicitly.

### Finding 3: Tiny `max_tokens` produces silent empty output (footgun)

`max_tokens=8` returned HTTP 200 with empty visible content. Application-level: it LOOKS successful (200 + valid JSON), but content is missing. Without checking `finish_reason`, you'd silently process empty tags / empty summaries.

**Defensive client pattern**:

```python
resp = call_minimax(...)
finish = resp["choices"][0]["finish_reason"]
content = resp["choices"][0]["message"]["content"]
visible = strip_think_tags(content)

if finish == "length" and not visible:
    # Reasoning consumed entire budget; retry with higher max_tokens
    raise RuntimeError("MiniMax produced empty output; max_tokens too low for reasoning + completion")
elif finish == "length":
    # Output truncated mid-stream; either accept or retry
    log.warning("MiniMax response truncated by max_tokens cap")
```

### Finding 4: Reasoning tokens scale with task complexity, NOT with `max_tokens`

For the same prompt:

- `max_tokens=200` → 89 reasoning tokens
- `max_tokens=10000` → 95 reasoning tokens
- `max_tokens=100000` → 139 reasoning tokens

Reasoning is roughly stable (~90-140 tokens for this counting task) regardless of how much budget is offered. The model doesn't "fill" the budget; it reasons until done, then emits.

The slight variance (89 vs 95 vs 139) is likely sampling-related (also see iter-5 finding: temp=0 isn't deterministic, so reasoning trace varies even at low temp).

**Practical implication**: setting `max_tokens` high doesn't waste money — you only pay for generated tokens. So when in doubt, **err high** (e.g., 4096-8192) and let the model decide when to stop.

### Finding 5: Latency scales mildly with `max_tokens` despite same actual output

| max_tokens | Latency |
| ---------- | ------- |
| 8          | 1.55s   |
| 200        | 3.10s   |
| 10000      | 3.30s   |
| 100000     | 3.95s   |

Larger `max_tokens` adds ~0.5-2s latency even when actual output is identical. Possibly server-side resource allocation overhead (allocating buffers/scheduling slots proportional to declared budget). For latency-sensitive paths, set `max_tokens` to "right-sized" rather than "very high".

## Idiomatic patterns by use case

### Defensive default (most production cases)

```json
{
  "max_tokens": 4096
}
```

Big enough for any single-turn use case (tagging, summary, Q&A). Reasoning fits comfortably. Latency overhead vs 1024 is small (~0.3s).

### Latency-sensitive production (Karakeep tagging at scale)

```json
{
  "max_tokens": 1024
}
```

Lower latency (~0.3s saved per call vs 4096). Sufficient for 5-tag output + reasoning headroom. Will fail if reasoning unexpectedly explodes (rare for tagging).

### Hard cost ceiling

For business-critical paths where runaway costs are unacceptable, set explicit `max_tokens` AND check `usage.completion_tokens` post-response to enforce client-side budget:

```python
MAX_BILLED_PER_CALL = 2000

resp = call_minimax(..., max_tokens=2048)
billed = resp["usage"]["completion_tokens"]
if billed > MAX_BILLED_PER_CALL:
    log.error(f"Cost-ceiling tripped: {billed} tokens billed")
    # take action: alert, suspend, etc.
```

### Discovering the actual hard cap (untested — for follow-up)

To find MiniMax's actual maximum output length, send a prompt that forces long output (e.g., "Write 5000 words of fiction") with `max_tokens: 200000` and observe `finish_reason` + `completion_tokens`. If `finish_reason: "length"` and `completion_tokens` is well below 200000, the actual cap is somewhere in between. Promote to T3.x if needed.

## Open questions for follow-up

- **Actual hard cap on output length** — unknown; server accepts huge `max_tokens` without protest, but model probably has a hidden ceiling. Probe with a prompt that forces lots of output.
- **Context window size** (input + output combined) — `prompt_tokens + max_tokens` may have a combined ceiling. Untested.
- **Behavior at `max_tokens=0`** — does it 400-error, or just produce empty? Untested. Add to T3.2 (error response shapes).

## Provenance

| Probe             | trace-id     | finish_reason | tokens (p+c) |
| ----------------- | ------------ | ------------- | ------------ |
| max_tokens=8      | (in fixture) | length        | 54+8         |
| max_tokens=200    | (in fixture) | stop          | 54+98        |
| max_tokens=10000  | (in fixture) | stop          | 54+104       |
| max_tokens=100000 | (in fixture) | stop          | 54+148       |

Fixtures:

- [`fixtures/chat-completion-maxtokens-8-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-maxtokens-8-2026-04-28.json)
- [`fixtures/chat-completion-maxtokens-200-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-maxtokens-200-2026-04-28.json)
- [`fixtures/chat-completion-maxtokens-10000-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-maxtokens-10000-2026-04-28.json)
- [`fixtures/chat-completion-maxtokens-100000-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-maxtokens-100000-2026-04-28.json)

Verifier: autonomous-loop iter-6. 4 API calls.
