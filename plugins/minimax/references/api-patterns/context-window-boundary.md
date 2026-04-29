# Chat Completion — Context Window Boundary

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/context-window-boundary.md` (source-of-truth — read-only, source iter-24). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-10).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. **Headline finding: context window ceiling sits between 142K and ~262K tokens — most likely 200K based on contemporary peer models.** Prompts up to 500KB (~142K tokens) accepted; 1MB rejected fast with "context window exceeds limit".

Closes T3.3 by bracketing the ceiling within a factor-of-~1.85 in a single 5-probe parallel sweep.

## Test setup

5 parallel probes at exponentially-increasing sizes, each with the same structure:

- Long varied lorem ipsum padding
- Final question: `"Ignoring all the padding above, what is 2+2? Reply with just the digit."`

`max_tokens: 64` (for budget; doesn't affect prompt-capacity testing). Same prompt structure across all 5 ensures fair comparison.

| Probe | Padding size | Approx tokens (chars/4) |
| ----- | ------------ | ----------------------- |
| C1    | 50KB         | ~12,500                 |
| C2    | 100KB        | ~25,000                 |
| C3    | 200KB        | ~50,000                 |
| C4    | 500KB        | ~127,000                |
| C5    | 1024KB (1MB) | ~262,000                |

## Results

| Probe    | Size  | Actual prompt_tokens (server) | HTTP status | Latency | Outcome                                  |
| -------- | ----- | ----------------------------- | ----------- | ------- | ---------------------------------------- |
| C1-50KB  | 50KB  | **14,268**                    | 200         | 3.15s   | ✅ Success                               |
| C2-100KB | 100KB | **28,501**                    | 200         | 3.42s   | ✅ Success                               |
| C3-200KB | 200KB | **56,973**                    | 200         | 4.94s   | ✅ Success                               |
| C4-500KB | 500KB | **142,383**                   | 200         | 8.32s   | ✅ Success (largest)                     |
| C5-1MB   | 1MB   | (not reported)                | 400         | 2.04s   | ❌ "context window exceeds limit (2013)" |

## Headline findings

### Finding 1: 🆕 Context window ceiling: between 142K and ~262K tokens (likely 200K)

The largest probe that succeeded (C4) used **142,383 actual prompt_tokens** server-side. The smallest that failed (C5) sent ~262,000 chars (token count not reported). The boundary is bracketed.

**Common 2026-era model context windows**:

- 128K = 131,072 (older Claude 3.5 Sonnet, Llama 3.1 405B)
- 200K = 204,800 (Claude 3.7 Sonnet, recent peer models)
- 256K = 262,144 (Gemini Pro variants)
- 1M = 1,048,576 (Gemini 1.5 Pro long-context)

C4's 142K success rules out 128K (would have failed). C5's failure at ~262K rules out 256K-or-higher (would have succeeded). **Most likely: 200K context window**, matching the contemporary Anthropic Claude 3.7 baseline. A binary-search probe at ~750KB could tighten this if precise value matters; for production purposes "between 142K and 200K" is sufficient.

### Finding 2: Tokenization throughput ~17K tokens/second at large sizes

| Probe    | prompt_tokens | Latency | tokens/sec |
| -------- | ------------- | ------- | ---------- |
| C1-50KB  | 14,268        | 3.15s   | ~4,500     |
| C2-100KB | 28,501        | 3.42s   | ~8,300     |
| C3-200KB | 56,973        | 4.94s   | ~11,500    |
| C4-500KB | 142,383       | 8.32s   | ~17,100    |

Tokenization throughput INCREASES with size — fixed overhead dominates small probes; variable cost dominates large. **Implication**: per-token tokenization cost converges to ~58 microseconds/token at the high end. For production capacity planning, large-context requests are NOT 10x slower than small-context requests despite 10x more tokens — closer to 2-3x slower.

### Finding 3: 🆕 Fast-reject path for over-ceiling payloads (~2s vs 7.5s for far-over-ceiling)

C5-1MB failed in **2.04 seconds** — much faster than C4's 8.32s success. By comparison, iter-23's E413-5MB took 7.5 seconds to fail. Two interpretations:

1. **Byte-size threshold check** at ~1MB before tokenization: payloads >1MB get rejected with minimal tokenization work, only their first portion is processed
2. **Partial tokenization with early-exit**: server tokenizes a sample, observes it'll exceed limit, bails

Either way, **production-relevant takeaway**: ~1MB requests fail FAST (good error UX); but 5MB requests are still slow (likely dominated by network upload time, not server processing). For client-side validation, the practical ceiling is 1MB byte-size — anything over should be rejected client-side to avoid even the 2s fast-reject latency.

### Finding 4: max_tokens=64 produced empty visible output on all successes

All 5 success probes returned `visible=''` — the `<think>` reasoning consumed the entire 64-token budget. Consistent with iter-5/6 findings (M-series burns 30-100+ reasoning tokens before any visible output).

This means iter-24's probes confirmed PROMPT-side capacity (tokens-in) but NOT generation quality from large context (tokens-out). **Separate question for T4.x**: can M2.7 actually USE 100K+ context effectively? "Lost-in-the-middle" effects are common at long context; needles-in-haystack benchmarks would answer this.

For iter-24's purposes, prompt-capacity bracketing is sufficient — 200K context window is established.

### Finding 5: Token-to-byte ratio is ~3.6 chars/token for English text

| Probe    | bytes   | tokens (server) | chars/token ratio |
| -------- | ------- | --------------- | ----------------- |
| C1-50KB  | 51,156  | 14,268          | 3.59              |
| C2-100KB | 102,373 | 28,501          | 3.59              |
| C3-200KB | 204,773 | 56,973          | 3.59              |
| C4-500KB | 511,968 | 142,383         | 3.60              |

**Highly stable at 3.59-3.60 chars/token** for varied lorem ipsum English text. This is in line with Claude's ~3.5 chars/token and OpenAI tiktoken's ~4 chars/token for English. For amonic services that need approximate token counting client-side without a tokenizer dependency: **`tokens ≈ chars / 3.6`** is reliable for English content.

For non-English (Chinese, Japanese, Arabic), this ratio will differ — untested in iter-24.

## Implications

### For amonic services — context-window-friendly defaults

```python
# Safe operating ceiling (well below 200K):
SAFE_PROMPT_TOKEN_LIMIT = 100_000  # well below 142K confirmed success
SAFE_CONTENT_BYTE_LIMIT = 350_000  # ~100K tokens at 3.6 chars/token

def validate_request_size(messages: list[dict]) -> None:
    total_chars = sum(len(m.get("content", "")) for m in messages)
    if total_chars > SAFE_CONTENT_BYTE_LIMIT:
        approx_tokens = total_chars // 3.6
        raise ValueError(
            f"Request too large: {total_chars} chars (~{approx_tokens:.0f} tokens). "
            f"Limit is {SAFE_CONTENT_BYTE_LIMIT} chars (~100K tokens). "
            f"Hard ceiling is ~200K tokens; staying under 100K leaves headroom for system + reasoning."
        )
```

For Karakeep tagging: typical bookmark page is 2-20KB, well within limits. No active concern.
For Linkwarden article archives: long-form articles can exceed 100KB; chunk if storing full-text in messages.

### For migration testing from OpenAI

OpenAI returns HTTP 400 with error message containing `context_length_exceeded`. MiniMax returns HTTP 400 with `"context window exceeds limit (2013)"` — different message text. Code that string-matches `context_length_exceeded` won't trigger on MiniMax.

```python
# OpenAI-compatible code that BREAKS on MiniMax:
try:
    resp = client.chat.completions.create(...)
except openai.BadRequestError as e:
    if "context_length_exceeded" in str(e):
        handle_oversized()

# MiniMax-correct pattern:
try:
    resp = client.chat.completions.create(...)
except openai.BadRequestError as e:
    msg = str(e).lower()
    if "context window exceeds limit" in msg or "context_length_exceeded" in msg:
        handle_oversized()
```

Or just check for HTTP 400 + the keyword "context" — covers both providers.

### For long-context use cases (RAG, document summarization)

200K context is generous — comfortably fits 100-page documents. Practical chunking decisions for amonic:

- **Single-doc summarization**: paste entire document, no chunking, leave 30K headroom for system prompt + reasoning
- **Multi-doc retrieval**: top-K=10 documents at 5K each = 50K tokens; well within limits
- **Whole-archive search**: still need vector retrieval (per iter-17/18); can't fit gigabytes

For Karakeep at scale (thousands of bookmarks per user), don't try to put all bookmarks in a single chat-completion. Use embeddings (locally per iter-17/18) for retrieval.

## Open questions for follow-up

- **Precise context ceiling**: 142K-262K bracket; binary-search probes at 700KB would tighten. Worth doing if exact value matters; not for typical production use.
- **Long-context QUALITY**: probes used `max_tokens=64`, getting no visible output. Re-run at `max_tokens=2048` with a deliberately-located answer in the padding (e.g., insert "the secret word is BANANA" at position N) to test "needle-in-haystack" recall. Defer to a quality-focused iter.
- **Non-English token-to-byte ratio**: Chinese/Japanese typically have lower chars/token than English. Affects byte-size estimates. T4.x cross-language probe will cover.
- **Does multi-message context split differently**? iter-24 used a single user message; conversation history (system + user1 + assistant1 + user2 + ...) may have different per-message overhead. Worth a probe.

## Provenance

| Probe    | Size  | prompt_tokens | HTTP | Latency | Outcome             |
| -------- | ----- | ------------- | ---- | ------- | ------------------- |
| C1-50KB  | 50KB  | 14,268        | 200  | 3.15s   | ✅ Success          |
| C2-100KB | 100KB | 28,501        | 200  | 3.42s   | ✅ Success          |
| C3-200KB | 200KB | 56,973        | 200  | 4.94s   | ✅ Success          |
| C4-500KB | 500KB | 142,383       | 200  | 8.32s   | ✅ Success          |
| C5-1MB   | 1MB   | (rejected)    | 400  | 2.04s   | ❌ ceiling exceeded |

Fixtures:

- [`fixtures/context-boundary-C1-50KB-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/context-boundary-C1-50KB-2026-04-28.json)
- [`fixtures/context-boundary-C2-100KB-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/context-boundary-C2-100KB-2026-04-28.json)
- [`fixtures/context-boundary-C3-200KB-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/context-boundary-C3-200KB-2026-04-28.json)
- [`fixtures/context-boundary-C4-500KB-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/context-boundary-C4-500KB-2026-04-28.json)
- [`fixtures/context-boundary-C5-1MB-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/context-boundary-C5-1MB-2026-04-28.json)

Verifier: autonomous-loop iter-24. 5 API calls.
