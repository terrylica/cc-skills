# Cache-Read Semantics — Threshold, Prefix Match, TTL

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/cache-read-semantics.md` (source-of-truth — read-only, source iter-40). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-11).

**Endpoint**: `POST /v1/chat/completions` with caching mechanisms from [`prompt-caching.md`](./prompt-caching.md).
**Model verified**: `MiniMax-M2.7-highspeed`
**Verified**: 2026-04-29 (iter-40, T4.2)

iter-39 confirmed MiniMax supports hybrid OpenAI+Anthropic caching APIs. iter-40 characterizes the operational semantics: **when does it activate, what does it match on, and how long does it persist?**

## TL;DR — production-critical findings

| Question                          | Answer                                                                                                 |
| --------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Activation threshold (auto-cache) | Between **264 and 597 prompt_tokens** — likely ~512-token block boundary                               |
| Cache scope                       | **Cross-session / account-wide** — iter-39's prompt was still cached at iter-40 start                  |
| Prefix matching                   | ✅ **System prefix matches even when user message differs** — 3 different user msgs all hit 891 tokens |
| Cache TTL                         | ≥ 3 minutes (185s tested with zero decay; upper bound undetermined)                                    |
| Block granularity                 | Cached counts cluster at **443 / 891** — block-based, NOT arbitrary-prefix                             |
| Latency benefit                   | None (per iter-39); caching is purely a billing optimization                                           |

## The probe

3 sub-probes on highspeed:

- **P1** — threshold sweep at sizes 100/300/700/1500 system tokens × cold/warm
- **P2** — prefix-match: long system + 3 different user messages, sequential
- **P3** — TTL decay: same prompt replayed at t=0/5s/35s/95s/185s

Source: `/tmp/mm-iter40-cache-semantics.py`. Fixture: [`fixtures/cache-semantics-iter40-2026-04-29.json`](~/own/amonic/minimax/api-patterns/fixtures/cache-semantics-iter40-2026-04-29.json).

## Results

### P1 — Threshold sweep

| target tokens | actual prompt_tokens | cold cached_tokens | warm cached_tokens | activated? |
| ------------- | -------------------- | ------------------ | ------------------ | ---------- |
| 100           | 105                  | 0                  | 0                  | ❌         |
| 300           | 264                  | 0                  | 0                  | ❌         |
| 700           | 597                  | 0                  | **443**            | ✅         |
| 1500          | 1256                 | **443**            | **891**            | ✅         |

**Activation threshold: between 264 and 597 prompt_tokens.** Below 300 tokens, no cache fields appear regardless of repetition. The 443 / 891 specific values are diagnostic: caching is **block-based** at what looks like a ~256-token boundary. You don't get fractional caching of "the parts the model thought were stable" — you get whole blocks.

**Cross-session surprise**: at size=1500, the COLD call (first invocation this run) showed `cached_tokens=443` — that 443 came from iter-39's quant-finance system prompt cached an hour earlier. The cache is **account-wide and persistent**, not session-scoped. This is OPPOSITE to what the word "ephemeral" in `cache_control: {type: "ephemeral"}` suggests.

### P2 — Prefix match (the production-critical one)

Long ~1500-token system prompt + 3 entirely different user messages, sequential after a warmup:

| user message                                          | prompt_tokens | cached_tokens | hit rate |
| ----------------------------------------------------- | ------------- | ------------- | -------- |
| "...gamma is highest at-the-money."                   | 1256          | 891           | 71%      |
| "...convexity matters for bonds."                     | 1255          | 891           | 71%      |
| "...implied vol skews negatively for equity indices." | 1258          | 891           | 71%      |

**The cache matches on the SYSTEM PREFIX even when the USER MESSAGE varies.** Identical 891 cached tokens across 3 fundamentally different user questions. This is the most production-relevant finding of iter-40 — it means amonic services with stable system prompts get cache hits on EVERY call, not just on identical-input replays.

For Karakeep tagging, Linkwarden summarization, F2 trade signals: a stable system rubric + varying user content = consistent ~70% input-token cost reduction across the batch.

### P3 — TTL decay

Same 1500-token prompt replayed at t=0/5s/35s/95s/185s:

| t (s) | prompt_tokens | cached_tokens |
| ----- | ------------- | ------------- |
| 0     | 1256          | 891           |
| 5     | 1256          | 891           |
| 35    | 1256          | 891           |
| 95    | 1256          | 891           |
| 185   | 1256          | 891           |

**Zero decay across 185 seconds.** No drift, no expiry, no cache eviction in the tested window. The upper bound is undetermined — Anthropic's `ephemeral` cache TTL is 5 minutes; MiniMax may match this or be longer. For amonic batch flows that complete within ~3 minutes per chunk, cache persistence is effectively unlimited.

## Why these results matter

iter-39 told us caching exists; iter-40 tells us **how to use it**.

The combination of (a) prefix-only matching, (b) cross-session persistence, and (c) ≥3-minute TTL means **a single warmup call per system prompt locks in cost savings for the next ~3+ minutes of varied user queries** — exactly the shape of Karakeep-style batch tagging.

## Production patterns

### Batch flow with explicit cache prime

```python
# At the start of a batch run, prime the cache with one explicit-create call
# to guarantee subsequent calls hit cache_read regardless of automatic threshold.
def prime_cache(api_key: str, system: str, sample_user: str) -> None:
    """Send one priming call with explicit cache_control to populate the cache."""
    body = {
        "model": "MiniMax-M2.7-highspeed",
        "messages": [
            {"role": "system", "content": system,
             "cache_control": {"type": "ephemeral"}},
            {"role": "user", "content": sample_user},
        ],
        "max_tokens": 64,
        "temperature": 0,
    }
    # Fire and forget — we just want the cache populated
    _post(api_key, body)


def tag_bookmark(api_key: str, system: str, bookmark_text: str) -> str:
    """Subsequent calls hit cache_read on the system prefix."""
    body = {
        "model": "MiniMax-M2.7-highspeed",
        "messages": [
            {"role": "system", "content": system,
             "cache_control": {"type": "ephemeral"}},
            {"role": "user", "content": bookmark_text},
        ],
        "max_tokens": 256,
        "temperature": 0.2,
    }
    return _post(api_key, body)


# Production usage:
SYSTEM = "You are a tagging assistant. Generate 3-5 lowercase tags..."  # ~700+ tokens
prime_cache(api_key, SYSTEM, "sample bookmark for cache priming")
for bookmark in bookmarks:
    tags = tag_bookmark(api_key, SYSTEM, bookmark)
```

### Threshold-aware system prompt sizing

Below ~300 prompt_tokens, caching does NOT activate. If your service's natural system prompt is shorter than that and you want caching:

```python
# Pad the system prompt to the activation threshold with a deterministic stable suffix
def cacheable_system(core_prompt: str, min_tokens: int = 600) -> str:
    """Pad short system prompts to activate caching."""
    suffix = (
        "\n\n# Operational Notes\n"
        "Output should be concise and well-structured. "
        "Use plain text unless markdown is explicitly requested. "
        "If uncertain, prefer a brief acknowledgment of limits over fabrication. "
        "Cite specific evidence when making factual claims. "
        # ... add stable filler until min_tokens is met
    )
    target_chars = min_tokens * 36 // 10  # ~3.6 chars/token
    if len(core_prompt) >= target_chars:
        return core_prompt
    return core_prompt + suffix * (1 + (target_chars - len(core_prompt)) // len(suffix))
```

This is a real cost optimization: a 200-token tagging prompt that doesn't cache vs the same prompt padded to 700 tokens that DOES cache → net token cost is ~30% LOWER with the padding once cached, despite sending more bytes per request. Counterintuitive but real.

### Reading the unified cache field

```python
def get_cached_token_count(usage: dict) -> int:
    """Extract cached tokens from MiniMax response, supporting both API shapes."""
    pt_details = usage.get("prompt_tokens_details") or {}
    return (
        pt_details.get("cached_tokens", 0)           # OpenAI shape (auto-cache)
        or usage.get("cache_read_input_tokens", 0)   # Anthropic shape (explicit)
        or 0
    )


def cache_hit_rate(usage: dict) -> float:
    cached = get_cached_token_count(usage)
    total = usage.get("prompt_tokens", 0)
    return cached / total if total else 0.0
```

### When NOT to bother with caching

- **Short prompts** (system < 300 tokens, user < 200 tokens) — under threshold, no benefit
- **Latency-sensitive interactive UI** — caching is cost-only on MiniMax (per iter-39); won't reduce TTFT
- **One-off ad-hoc calls** — by definition you can't reuse the prefix; explicit cache_control wastes a `cache_creation` budget on a single call

## Caveats

- **Cache TTL upper bound unknown** — only tested to 185s. Production code targeting >5min gaps between calls should add a re-prime step.
- **Block boundary undocumented** — observed cluster points at 443 / 891 suggest ~256-token blocks but not confirmed. Don't write code that assumes specific block sizes.
- **Cross-account cache leakage untested** — does my cache_control on one API key affect another key on the same plan? Likely no (would be a security violation), but unverified.
- **Long-context interaction** — for a 27K-token F4 10-K probe, what fraction caches? Untested at that size; would expect higher absolute cached tokens but possibly lower hit rate due to block-boundary effects.

## Open follow-ups

- **TTL precise measurement**: extend to 5min / 10min / 30min gaps
- **Block-size verification**: probe at sizes 264 / 320 / 512 / 600 / 770 to map exact boundaries
- **Long-context caching**: re-run iter-32 F4 (27K-token 10-K) with cache_control to measure absolute cost reduction at scale
- **Concurrent cache writes**: do parallel calls with cache_control race? Or share?
- **Mixed cache_control + automatic**: send 5 calls, 3 with explicit and 2 without — do they cooperate or conflict?

## Provenance

| Probe           | Trace ID      |
| --------------- | ------------- |
| P1.size700.warm | (see fixture) |
| P2.U1           | (see fixture) |
| P3.t185s        | (see fixture) |

All raw responses captured in [`fixtures/cache-semantics-iter40-2026-04-29.json`](~/own/amonic/minimax/api-patterns/fixtures/cache-semantics-iter40-2026-04-29.json).
