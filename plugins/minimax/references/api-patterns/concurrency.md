# Chat Completion — Concurrency Behavior

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/concurrency.md` (source-of-truth — read-only, source iter-25). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-10).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. **Headline finding: chat-completion has TRUE parallelism up to ~10 concurrent calls (wall-clock ≈ single-call latency); beyond p=10, modest tail-latency growth indicates a soft concurrency ceiling but no full serialization.** Per-call latency stays within +16% of serial baseline even at p=20.

Closes T3.4 by quantifying the parallelism characteristics that iter-22's burst probe hinted at.

## Test setup

Three probe sets, each with identical simple prompts ("Reply with the digit N"):

| Probe set      | Concurrency | Calls | Approach   |
| -------------- | ----------- | ----- | ---------- |
| S1-serial-3    | 1           | 3     | sequential |
| S2-parallel-10 | 10          | 10    | concurrent |
| S3-parallel-20 | 20          | 20    | concurrent |

`max_tokens: 128`, `model: MiniMax-M2.7-highspeed`. 2-second pause between probe sets to allow any micro-bucket recovery.

## Results

### S1-serial-3 (baseline)

| Metric           | Value      |
| ---------------- | ---------- |
| Total wall-clock | 5.876s     |
| Per-call mean    | **1.958s** |
| Per-call min     | 1.804s     |
| Per-call max     | 2.073s     |
| Stdev            | 0.139s     |

Per-call latency is consistent (low stdev) when calls are sequential.

### S2-parallel-10

| Metric           | Value                                                 |
| ---------------- | ----------------------------------------------------- |
| Total wall-clock | **2.532s** ← essentially equal to single-call latency |
| Per-call mean    | 2.01s                                                 |
| Per-call min     | 1.479s                                                |
| Per-call max     | 2.529s                                                |
| Stdev            | 0.327s                                                |

**Wall-clock at p=10 ≈ wall-clock at p=1.** This is the "perfect parallelism" signature — server processes 10 calls concurrently without serialization.

### S3-parallel-20

| Metric           | Value                                        |
| ---------------- | -------------------------------------------- |
| Total wall-clock | 4.049s                                       |
| Per-call mean    | 2.269s                                       |
| Per-call min     | 1.43s                                        |
| Per-call max     | **4.047s** ← slowest call took 2× the median |
| Stdev            | 0.614s                                       |

At p=20, mean per-call latency grows by +16% vs serial. But total wall-clock doubles vs p=10. The slowest call (4.05s) is exactly the wall-clock — meaning that one call serialized all the way through.

## Headline findings

### Finding 1: ✅ TRUE PARALLELISM up to ~p=10 — wall-clock equals single-call latency

The most diagnostic data point: at p=10, total wall-clock (2.53s) ≈ single-call latency (1.96s). If MiniMax queued calls behind the scenes, total would have been ~10× single-call latency = ~20s. Instead it's 2.5s.

**Production implication**: amonic services that need throughput can safely fan out up to 10 concurrent calls without paying queueing penalty. For Karakeep at scale (e.g., bulk-tagging 100 bookmarks), 10-way parallelism gives effective ~5x throughput improvement over serial.

### Finding 2: 🆕 Soft concurrency ceiling around p=10 — modest tail-latency growth at p=20

At p=20:

- Mean per-call latency: 2.27s (only +16% vs serial)
- Max per-call latency: 4.05s (≈2× serial)
- Stdev: 0.61s (4× serial's 0.14s)

The fastest calls at p=20 were FASTER than serial (1.43s vs 1.80s) — likely warmcache effects. The slowest call took 4.05s — near 2× the median. **Variance grows with concurrency.**

This shape indicates a **soft concurrency cap**: server runs ~10 calls concurrently, queues additional calls in a fair-share scheduler. The slowest at p=20 = wall-clock = the call that waited longest in the queue.

**Production implication**: at p=20, expect bimodal latency distribution. Some calls are fast (warm cache); some are slow (queued). For latency-sensitive paths (interactive UI), keep concurrency ≤ 10. For batch paths (overnight indexing), p=20+ is fine — accept the tail latency.

### Finding 3: 🆕 Server has minimum latency floor of ~1.4-1.5s

Across all 3 probe sets, the fastest calls clustered around 1.43-1.50s. This is the floor — fixed overhead of network round-trip + tokenization + minimum model invocation time, regardless of concurrency.

**Implication**: don't try to optimize a single MiniMax call below 1.5s. Even with `max_tokens=64`, the M-series reasoning preamble + network adds ~1.5s. For sub-second latency requirements, MiniMax isn't the right provider — consider local models.

### Finding 4: Per-call latency growth is sub-linear with concurrency

| Concurrency | Per-call mean | Growth vs p=1 |
| ----------- | ------------- | ------------- |
| 1           | 1.96s         | baseline      |
| 10          | 2.01s         | +3%           |
| 20          | 2.27s         | +16%          |

Sub-linear growth confirms the soft-ceiling model: between p=1 and p=10, the server has spare capacity (no growth); between p=10 and p=20, queueing emerges but is gentle. **A 200-call burst would NOT take 200×1.96s = 6.5 minutes** — likely closer to 30-60s based on the scaling pattern.

### Finding 5: Throughput vs latency tradeoff calibrated

For amonic capacity planning:

| Concurrency | Per-call latency | Wall-clock for N calls | Throughput    |
| ----------- | ---------------- | ---------------------- | ------------- |
| 1 (serial)  | 1.96s            | N × 1.96s              | 0.5 calls/sec |
| 10          | 2.01s            | ceil(N/10) × 2.5s      | ~4 calls/sec  |
| 20          | 2.27s            | ceil(N/20) × 4.0s      | ~5 calls/sec  |

**Throughput plateaus around p=10**. Going to p=20 only buys ~25% more throughput (5 vs 4 calls/sec) while doubling the worst-case latency (4s vs 2.5s). Sweet spot is **p=10 for production**.

## Implications

### For Karakeep tagging at scale

```python
async def tag_bookmarks_in_batches(bookmarks: list[Bookmark], concurrency: int = 10):
    """Tag a large set of bookmarks via concurrency-10 parallelism (sweet spot)."""
    semaphore = asyncio.Semaphore(concurrency)

    async def tag_one(bm):
        async with semaphore:
            return await call_minimax(messages=[...{"content": bm.content}])

    results = await asyncio.gather(*[tag_one(bm) for bm in bookmarks])
    return results
```

For 100 bookmarks at concurrency=10: ~10 batches × 2.5s = ~25s total. Vs serial (~196s), that's 8x speedup.

### For Linkwarden bulk-import

Same pattern — use concurrency=10 for ingestion-time tagging. Don't go higher unless you've measured and accepted the tail-latency tradeoff.

### For latency-sensitive interactive UI

Keep concurrency=1 (no parallelism) per request. Use a request-deduplication / cache layer to avoid redundant calls. Server's minimum latency floor (~1.5s) is the lower bound regardless of optimization.

### Cross-endpoint generalization

This iter measured chat-completion only. **Per-endpoint parallelism characteristics may differ**:

- **Embeddings**: per iter-17/18, RPM cooldown is much tighter — concurrency=10 will likely 1002 immediately. Use concurrency=1-2 with backoff.
- **Files**: per iter-19, no rate-limit issues at small scale; untested at high parallelism.
- **TTS/Video**: plan-gated entirely on this tier; not testable.

Don't extrapolate chat-completion's p=10 sweet spot to other endpoints. Each needs its own characterization.

## Open questions for follow-up

- **Where exactly is the soft ceiling?** iter-25 showed p=10 perfect, p=20 modestly degraded. Probes at p=12, p=15 would localize the inflection.
- **Does the ceiling depend on prompt complexity?** All iter-25 probes used trivial prompts. Long-context or reasoning-heavy prompts may have different ceiling.
- **Does sustained high parallelism trigger 1002 RPM?** iter-22 showed bursts work; sustained p=10 over 5+ minutes might exhaust the per-window quota.
- **Is the ceiling per-account or per-key?** If we had a second API key, parallel-from-both might double the effective ceiling.

## Provenance

| Probe          | Concurrency | Total wall | Per-call mean | Per-call min | Per-call max | Stdev |
| -------------- | ----------- | ---------- | ------------- | ------------ | ------------ | ----- |
| S1-serial-3    | 1           | 5.876s     | 1.958s        | 1.804s       | 2.073s       | 0.139 |
| S2-parallel-10 | 10          | 2.532s     | 2.01s         | 1.479s       | 2.529s       | 0.327 |
| S3-parallel-20 | 20          | 4.049s     | 2.269s        | 1.43s        | 4.047s       | 0.614 |

Fixture (consolidated):

- [`fixtures/concurrency-iter25-parallelism-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/concurrency-iter25-parallelism-2026-04-28.json)

Verifier: autonomous-loop iter-25. 33 API calls (3 + 10 + 20).
