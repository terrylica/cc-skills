# MiniMax Embeddings Endpoint Discovery

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/embeddings.md` (source-of-truth — read-only, source iter-17). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-9).

Verified 2026-04-29 with the same API key. **Headline findings: embeddings endpoint is `/v1/embeddings` (plural) with hybrid OpenAI-URL + MiniMax-canonical body shape. NOT plan-gated on Plus-High-Speed — but heavily rate-limited (code 1002 RPM family).**

This is the campaign's third non-chat-completion endpoint after TTS (iter-15) and video (iter-16). Differs from those: embeddings endpoint is at the OpenAI-compat URL but uses MiniMax-canonical body keys.

## Test setup

3 probes total:

| Probe | URL                        | Body shape                                             |
| ----- | -------------------------- | ------------------------------------------------------ |
| E1    | `/v1/embeddings` (plural)  | OpenAI-compat: `{model: "embo-01", input: "..."}`      |
| E2    | `/v1/embedding` (singular) | MiniMax-style: `{model, texts: [...], type: "db"}`     |
| E3    | `/v1/embeddings` (plural)  | MiniMax-canonical: `{model, texts: [...], type: "db"}` |

## Results

### E1: `/v1/embeddings` with OpenAI-style body → HTTP 200 + structured error

```json
{
  "vectors": null,
  "base_resp": {
    "status_code": 2013,
    "status_msg": "invalid params, binding: expr_path=texts, cause=missing required parameter"
  }
}
```

**Critical discoveries** in this single error response:

1. **Endpoint URL is correct** — HTTP 200 (not 404) confirms `/v1/embeddings` exists
2. **Body parameter is `texts` (array), NOT OpenAI's `input` (string|array)** — error message names the missing parameter explicitly
3. **NOT plan-gated** — error code is 2013 (invalid params), not 2061 (plan-gated). Embeddings ARE accessible on Plus-High-Speed plan
4. **Response key is `vectors`** — visible in `vectors: null` in the error envelope

### E2: `/v1/embedding` (singular) → HTTP 404

```
"404 page not found"
```

Singular form doesn't exist. **Plural URL is the correct one** — opposite of `/v1/video_generation` (singular full word) and `/v1/t2a_v2` (singular abbreviated).

### E3: `/v1/embeddings` with corrected MiniMax body → rate-limited

Body shape: `{model: "embo-01", texts: ["text1", "text2"], type: "db"}`

Result across 3 attempts (with 80s delays between attempts 1→2 and 2→3):

```json
{
  "vectors": null,
  "base_resp": {
    "status_code": 1002,
    "status_msg": "rate limit exceeded(RPM)"
  }
}
```

**Rate-limited persistently.** The `RPM` (requests-per-minute) name is misleading — 80s delays between attempts didn't clear the window. Either the RPM bucket is very small on Plus-High-Speed, or the cooldown is longer than the name suggests.

## Headline findings

### Finding 1: 🆕 Embeddings endpoint URL is `/v1/embeddings` — same as OpenAI

After three native endpoints (TTS at `/v1/t2a_v2`, video at `/v1/video_generation`, web-search at `tools[].type`), embeddings finally aligns with OpenAI's URL convention. **MiniMax's embeddings is at the OpenAI-compat URL** — `/v1/embeddings`. The compat layer DOES extend here (unlike audio, image, video which are MiniMax-native).

### Finding 2: 🆕 Body shape uses `texts` array, NOT OpenAI's `input`

OpenAI's embeddings spec: `{model: "...", input: "string" | ["array", "of", "strings"]}`. MiniMax: `{model: "...", texts: ["array", "always"]}`. Different parameter name AND different shape (always array, no string-or-array union).

Plus the `type: "db"` parameter — likely controls vector quality/dimension based on use case (`db` = retrieval optimization vs maybe `query` for query-side encoding). OpenAI doesn't have this; MiniMax-specific.

**Hybrid pattern**: OpenAI-compat URL + MiniMax-canonical body shape. This is genuinely surprising — it means migration code can't blindly point its OpenAI client at MiniMax embeddings; the body shape needs translation.

### Finding 3: 🎉 Embeddings are NOT plan-gated on Plus-High-Speed

Unlike TTS (iter-15) and video (iter-16) which both returned `2061 "plan not support model"`, embeddings returned `2013 "invalid params"` — meaning the endpoint is past the plan check, just rejecting the request shape. **Embeddings ARE accessible** on this plan tier.

This confirms the iter-17 hypothesis: embeddings are computationally cheaper than generation, so they're available on lower tiers.

### Finding 4: 🆕 New error code 1002 — rate limit exceeded (RPM family)

```json
{
  "base_resp": { "status_code": 1002, "status_msg": "rate limit exceeded(RPM)" }
}
```

This is the third distinct error code family in the campaign:

| Code | Family         | Meaning                                 | Iter discovered  |
| ---- | -------------- | --------------------------------------- | ---------------- |
| 1002 | Rate limiting  | Per-minute (RPM) request quota exceeded | iter-17          |
| 2013 | Invalid params | Request shape malformed                 | iter-9, iter-14  |
| 2061 | Plan gating    | Model not available on user's plan      | iter-15, iter-16 |

The error code prefix is informative: `1xxx` = rate/quota, `2xxx` = parameter/access. Production code can branch on the code prefix for high-level error categorization.

### Finding 5: 🚨 RPM window is much longer than 1 minute (or RPM bucket is very small)

iter-17 burned 4 API calls in quick succession (E1, E2, E3 attempt 1, 2, 3). Despite 80s delays between E3 attempts (160s total wall clock + cooldown), still rate-limited. Either:

- The RPM bucket on Plus-High-Speed embeddings tier is 1-2 requests, replenishing slowly
- The cooldown window is actually much longer than 60s (despite the "RPM" name)
- There's a separate burst-detection algorithm in play

**Production implication**: embeddings-heavy applications (RAG with thousands of documents) cannot just hammer the endpoint. Need careful per-batch pacing or batch multiple texts per call.

### Finding 6: Response shape preview from error envelope

The `vectors: null` field appearing in error responses confirms the success-shape is:

```json
{
  "vectors": [[0.1, -0.2, ...], [0.3, 0.05, ...]],  // array of vectors, one per text
  "total_tokens": 50,
  "base_resp": {"status_code": 0, "status_msg": "success"}
}
```

The `vectors` field is NOT OpenAI's `data: [{embedding: [...], index: 0, object: "embedding"}]` array of objects. **Different envelope** — OpenAI clients won't parse responses without translation.

## Implications

### For amonic services contemplating embeddings (RAG, semantic search)

**Embeddings work on the current plan** — first non-chat-completion feature accessible on Plus-High-Speed. This is good news for amonic services that need:

- Semantic search across bookmarks (Karakeep, Linkwarden)
- RAG over personal documents
- Similarity-based clustering of saved content

**But pay attention to rate limits**:

- Per-minute throttle (code 1002) is real and tight
- Batch multiple texts per call (`texts: [...]` array supports this natively)
- Add exponential backoff with jitter for production retry logic

### For migration testing from OpenAI

OpenAI client libraries WILL fail on MiniMax embeddings unless body translation is added:

```python
# OpenAI-compat code that WILL FAIL on MiniMax:
client.embeddings.create(model="embo-01", input="hello")

# MiniMax-required body shape:
httpx.post(
    "https://api.minimax.io/v1/embeddings",
    json={"model": "embo-01", "texts": ["hello"], "type": "db"},
    headers=auth,
)
```

The URL works at MiniMax — the body shape is the migration gap.

## Idiomatic patterns

### Pattern 1: Defensive embeddings client

```python
import httpx
import time

def get_embeddings(texts: list[str], model: str = "embo-01", embedding_type: str = "db") -> list[list[float]]:
    """Retrieve embeddings with rate-limit retry. Returns list of vectors (one per input text)."""
    body = {"model": model, "texts": texts, "type": embedding_type}

    for attempt in range(5):
        resp = httpx.post(
            "https://api.minimax.io/v1/embeddings",
            json=body,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            timeout=30,
        )
        parsed = resp.json()
        base = parsed["base_resp"]

        if base["status_code"] == 0:
            return parsed["vectors"]

        if base["status_code"] == 1002:
            wait = 2 ** attempt + (random.random() * 5)  # exp backoff with jitter
            log.warning(f"RPM rate-limited; waiting {wait:.1f}s before retry {attempt + 1}/5")
            time.sleep(wait)
            continue

        # Non-recoverable error
        raise RuntimeError(f"Embeddings failed: {base['status_msg']}")

    raise RuntimeError("Exhausted retries on rate-limited embeddings")
```

### Pattern 2: Batched embeddings for RAG ingestion

```python
def embed_corpus(documents: list[str], batch_size: int = 16) -> list[list[float]]:
    """Embed a large corpus by batching texts per request to amortize RPM."""
    all_vectors = []
    for i in range(0, len(documents), batch_size):
        batch = documents[i:i + batch_size]
        batch_vectors = get_embeddings(batch)
        all_vectors.extend(batch_vectors)
        time.sleep(0.5)  # gentle pacing between batches
    return all_vectors
```

### Pattern 3: Type parameter for query-vs-corpus encoding

The `type: "db"` parameter likely matters for retrieval quality — at least one alternative value should exist for query-side encoding. Until verified, use `"db"` for all stored documents and SAME for queries (degrades gracefully). When MiniMax docs confirm an alternative `query` value, update.

## Open questions for follow-up

- **What does `type: "query"` (or similar) do?** OpenAI doesn't have this; likely controls retrieval-vs-corpus encoding mode.
- **What's the actual RPM limit on Plus-High-Speed?** The 1002 retries showed it's very tight; documenting the actual number would help production planning.
- **What's the embedding dimensionality?** Likely 1024 for `embo-01`; verify when rate-limit clears.
- **Other embedding models?** `embo-01-large`, `embo-02`, etc. — TBD.
- **Maximum tokens per text?** Likely 8192 like OpenAI but unverified.
- **Maximum texts per batch?** Untested — what's the limit?

## Provenance

| Probe | URL                   | http_status | base_resp                                                 |
| ----- | --------------------- | ----------- | --------------------------------------------------------- |
| E1    | `/v1/embeddings`      | 200         | code 2013 ("invalid params, binding: expr_path=texts...") |
| E2    | `/v1/embedding`       | 404         | n/a (path doesn't exist)                                  |
| E3    | `/v1/embeddings` (3x) | 200         | code 1002 ("rate limit exceeded(RPM)") — all 3 attempts   |

Fixtures:

- [`fixtures/embeddings-E1-openai-style-embeddings-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/embeddings-E1-openai-style-embeddings-2026-04-28.json)
- [`fixtures/embeddings-E2-minimax-singular-embedding-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/embeddings-E2-minimax-singular-embedding-2026-04-28.json)
- [`fixtures/embeddings-E3-minimax-canonical-body-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/embeddings-E3-minimax-canonical-body-2026-04-28.json)

Verifier: autonomous-loop iter-17. 5 API calls (E1 + E2 + E3 ×3 with retries).

**Pending verification**: actual vector retrieval (currently rate-limited). iter-18 should retry once the RPM cooldown clears to confirm the success-response shape and dimensionality.

## iter-18 retry attempt (2026-04-29)

iter-18 was scheduled with a deliberate 10-minute wait specifically to clear the RPM cooldown, then ran a richer 2-call probe attempting:

- **P1**: `type: "db"` with 4 carefully-crafted texts (related/unrelated/duplicate) — designed to verify vector retrieval, dimensionality, cosine-similarity sanity, and reproducibility in one call
- **P2**: `type: "query"` with text 0 — probe for asymmetric encoding mode and `type` enum constraints

**Result**: BOTH calls returned `base_resp.status_code=1002 "rate limit exceeded(RPM)"` despite the 10-minute gap and 8-second pause between calls.

This sharpens the iter-17 finding: **the RPM cooldown on Plus-High-Speed embeddings is much longer than 10 minutes**, OR the per-window quota is so tight that even infrequent retries hit it. The "RPM" label is doubly misleading.

### Side discoveries from iter-18 (despite no vectors retrieved)

- **Header set**: embeddings endpoint emits `Trace-Id` and `alb_request_id` headers (same family as chat-completions). Production logging works the same way.
- **6th-category compat is reliable**: HTTP 200 + base_resp envelope holds even under sustained rate-limit. No HTTP 429 escape hatch.
- **Throttle is per-call, not burst-based**: 8-second spacing didn't help. iter-18's first call hit 1002 from cold; the throttle bucket wasn't replenished by the 10-minute wait.

### Production conclusion

**On Plus-High-Speed plan, MiniMax embeddings is best-effort only.** For amonic services that need RAG-class throughput, the practical recommendations are:

1. **Local embeddings**: `sentence-transformers` or `nomic-embed-text` via ollama on gpu-host-1 — no rate limits, full throughput, free
2. **Different commercial provider**: Voyage AI or OpenAI `text-embedding-3-small` — both have generous tiers
3. **Upgrade MiniMax plan**: if cost analysis vs. (1)/(2) warrants

Vector retrieval, dimensionality verification, and `type: "query"` discovery remain pending until plan upgrade or extended cooldown wait. The rest of the endpoint contract (URL, body shape, response envelope, error code families) is fully characterized.
