# Chat Completion — Tokens/Second Emission Rate

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-tps.md` (source-of-truth — read-only, source iter-26). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-10).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. **Headline finding: actual TPS asymptotic ceiling is ~50 tokens/sec — significantly below the Plan's "~100 TPS sustained, up to 3x faster" claim.** TPS scales with output size (saturation curve): short outputs measure ~23 TPS due to per-call overhead dominance; long outputs (1000+ tokens) approach the ~50 TPS ceiling.

Closes T3.5 by quantifying the Plan-vs-reality gap so amonic services can size capacity correctly.

## Test setup

4 parallel chat-completion probes at varied target output sizes (chat-completion handles p=10 per iter-22; p=4 is well under the soft ceiling at p=10 per iter-25):

| Probe      | Target visible | max_tokens | Prompt purpose                            |
| ---------- | -------------- | ---------- | ----------------------------------------- |
| P1-50tok   | 50             | 1024       | List 10 fruits (short factual)            |
| P2-200tok  | 200            | 2048       | Paragraph about coffee history            |
| P3-500tok  | 500            | 4096       | Five short paragraphs about seasons       |
| P4-1000tok | 1000           | 8192       | 1000-word essay on clean water importance |

System prompt intentionally tight ("concise writing assistant ... no preamble, no markdown") to minimize reasoning preamble per iter-21 finding. `temperature: 0.3` for mild variety. Non-streaming so the `usage` object is populated (iter-8 showed streaming returns `usage: null` in every chunk).

## Results

| Probe      | Latency | completion_tokens | reasoning_tokens | visible_tokens | **TPS_total** | TPS_visible | reasoning_ratio |
| ---------- | ------- | ----------------- | ---------------- | -------------- | ------------- | ----------- | --------------- |
| P1-50tok   | 2.58s   | 60                | 30               | 30             | **23.3**      | 11.6        | 0.500           |
| P2-200tok  | 7.20s   | 291               | 42               | 249            | **40.4**      | 34.6        | 0.144           |
| P3-500tok  | 14.81s  | 717               | 291              | 426            | **48.4**      | 28.8        | 0.406           |
| P4-1000tok | 27.17s  | 1324              | 93               | 1231           | **48.7**      | 45.3        | 0.070           |

**TPS_total** = `completion_tokens / latency` (the fundamental server emission rate — this is what MiniMax could legitimately claim).
**TPS_visible** = `visible_tokens / latency` (what the user actually receives after `<think>` strip).
**reasoning_ratio** = `reasoning_tokens / completion_tokens` (highly variable, sampling-jitter-affected).

## Headline findings

### Finding 1: 🚨 Plan's "~100 TPS sustained" claim is NOT MET at any output size

Mean TPS_total across all 4 probes: **40.2 tokens/sec** — 40% of the Plan's headline number.

The largest probe (P4 at 1324 completion tokens emitted, 27s latency) measured 48.7 TPS — still less than half the claim. Even adjusting for reasoning overhead by using TPS_visible, the highest measurement was 45.3 (P4) — also under the claim.

**The Plan claim is either:**

1. Aspirational marketing (the underlying model can sustain 100 TPS in some configurations, but not on Plus-High-Speed for typical prompts)
2. Reference to a DIFFERENT model (perhaps a non-reasoning model where there's no `<think>` overhead)
3. A peak burst rate, not sustained throughput
4. Comparison vs base M2.7 (not -highspeed) — the "up to 3x faster" suggests THIS is plausible; would mean base M2.7 is ~17 TPS, which is then 3x'd to ~50 TPS for highspeed

**Production implication**: capacity planning that assumes 100 TPS will undersize compute by 2-2.5×. Use **40 TPS as the target throughput baseline for chat-completion on M2.7-highspeed** — leaves headroom for short-prompt slowdown and reasoning-heavy spikes.

### Finding 2: 🆕 TPS scales with output size — saturation curve

TPS climbs as output gets larger:

```
P1 (60 comp_tok)   → 23.3 TPS
P2 (291 comp_tok)  → 40.4 TPS
P3 (717 comp_tok)  → 48.4 TPS
P4 (1324 comp_tok) → 48.7 TPS  ← asymptote
```

This is a **saturation curve** — fixed per-call overhead dominates at small outputs, asymptotes at ~50 TPS for outputs over ~500 tokens. The shape:

- **Floor**: per-call overhead (network + tokenization + reasoning preamble) is ~1.4-1.5s per iter-25's minimum-latency-floor finding. For a 60-token output, latency is 2.58s; ~1.5s of that is overhead, leaving 1.08s for emission of 60 tokens = 56 TPS during the emission phase. The 23 TPS observed is the "blended" rate including overhead.
- **Asymptote**: at large outputs, fixed overhead becomes negligible relative to emission time. P4's 27s latency divided across 1324 tokens = ~20ms/token = 50 TPS.

**Production implication**: TPS is the wrong metric for short-output workloads (tagging, classification, single-word answers). Use **per-call latency** instead. For Karakeep tagging (output ~5-15 tokens), expect 1.5-2.5s end-to-end regardless of "TPS" — the per-call overhead is the constraint.

For long-form generation (article summaries, essays), 50 TPS is the realistic sustained rate.

### Finding 3: 🆕 Reasoning ratio is highly variable, NOT predictable from prompt

| Probe      | reasoning_tokens | completion_tokens | reasoning_ratio |
| ---------- | ---------------- | ----------------- | --------------- |
| P1-50tok   | 30               | 60                | **0.500**       |
| P2-200tok  | 42               | 291               | **0.144**       |
| P3-500tok  | 291              | 717               | **0.406**       |
| P4-1000tok | 93               | 1324              | **0.070**       |

The ratio swings between 7% (P4) and 50% (P1). It does NOT correlate cleanly with prompt complexity:

- P1 (simple list) had 50% reasoning ratio — model deliberated about format
- P3 (5 paragraphs) had 41% reasoning — longer plan than emission time would suggest
- P4 (1000-word essay) had only 7% — once the plan was set, emission dominated

**Sampling jitter** appears to affect reasoning depth more than prompt content. Per iter-5's temp=0 nondeterminism finding, even identical prompts produce different reasoning lengths.

**Production implication**: cost-modeling spreadsheets that assume "X% reasoning overhead" will be wrong by ±35 percentage points. For accurate cost projection: (1) measure your actual workload with N=20 samples per prompt template, (2) use the 90th percentile reasoning_tokens as the budget assumption, (3) for latency budgets, use the maximum observed rather than mean.

### Finding 4: 🆕 TPS_visible vs TPS_total diverges sharply at high reasoning ratios

| Probe      | TPS_total | TPS_visible | divergence |
| ---------- | --------- | ----------- | ---------- |
| P1-50tok   | 23.3      | 11.6        | 50%        |
| P2-200tok  | 40.4      | 34.6        | 14%        |
| P3-500tok  | 48.4      | 28.8        | 41%        |
| P4-1000tok | 48.7      | 45.3        | 7%         |

For interactive UI where user-perceived speed = visible token rate, P3's 28.8 TPS_visible vs 48.4 TPS_total means the user "sees" the response generated at 60% of the server emission rate — the rest is invisible reasoning.

**Production implication**: streaming UX is even more important than naive TPS suggests. With non-streaming, users wait the FULL latency including reasoning before seeing anything. With streaming (per iter-8 patterns), users still see nothing during the `<think>` phase, but emission of visible tokens after `</think>` happens at the higher TPS_total rate.

### Finding 5: TPS plateaus at ~50 because of reasoning-model architecture

The asymptotic ceiling at ~50 TPS for a reasoning model like M2.7 is consistent with industry benchmarks. Compare:

- **GPT-4o** (non-reasoning): ~80-120 TPS sustained
- **OpenAI o1/o3** (reasoning): ~30-50 TPS sustained (reasoning models trade speed for thoughtfulness)
- **Claude 3.5 Sonnet**: ~85-100 TPS
- **MiniMax M2.7-highspeed** (this measurement): ~50 TPS asymptotic

M2.7 is in the reasoning-model camp; ~50 TPS is reasonable. The "~100 TPS" Plan claim conflicts with this architectural reality — likely either a typo, a reference to a different model, or a marketing exaggeration.

**Production implication**: don't pick MiniMax for use cases that need 100+ TPS. For high-throughput needs (e.g., summarizing news feeds in real time), use a non-reasoning model (Llama 3.1 70B locally, GPT-4o, or Claude Haiku).

## Implications

### For Karakeep AI tagging at scale

Karakeep generates 5-15 tokens of tags per bookmark. From P1 measurement:

- Per-call latency: 2.58s (vast majority overhead)
- TPS is irrelevant — overhead dominates

For 100 bookmarks at concurrency=10 (per iter-25's sweet spot):

```
Wall-clock = ceil(100/10) × 2.58s = 26s
Throughput = 100 / 26s = 3.8 calls/sec (matches iter-25's ~4 calls/sec at p=10)
```

To go faster: **use a non-reasoning model**. M2.7's overhead is fundamental. If sub-1s tagging is required, switch to Llama-3-instruct on bigblack or OpenAI gpt-4o-mini.

### For Linkwarden article summarization

Long articles produce long summaries (~500-1000 visible tokens). From P3/P4 measurements:

- 500-token output: 14.8s latency at 48 TPS
- 1000-token output: 27.2s latency at 49 TPS

Per article, expect **15-30 seconds end-to-end**. For real-time UI (user clicks "Summarize"), this is too slow — show a progress indicator and let it run async. For background indexing (overnight cron), it's acceptable: 1000 articles at concurrency=10 = ~100 batches × 27s = ~45min, totally feasible overnight.

### For latency-budget calculations

```python
def estimate_minimax_latency(target_visible_tokens: int) -> float:
    """Estimate MiniMax-M2.7-highspeed latency for given visible output size.

    Based on iter-26 measurements; mean estimate, not P95.
    For P95 cost-modeling, multiply by 1.5x.
    """
    # Per-call overhead (per iter-25's minimum-latency-floor finding)
    OVERHEAD_SEC = 1.5
    # Asymptotic TPS for blended completion (reasoning + visible)
    TPS_ASYMPTOTE = 50
    # Reasoning ratio (mean across iter-26's 4 probes)
    REASONING_RATIO = 0.28  # 28% — actual workloads should measure their own

    visible_tokens = target_visible_tokens
    estimated_completion = visible_tokens / (1 - REASONING_RATIO)
    emission_seconds = estimated_completion / TPS_ASYMPTOTE
    return OVERHEAD_SEC + emission_seconds
```

Sanity check against iter-26 data:

| Target | Predicted | Measured | Error |
| ------ | --------- | -------- | ----- |
| 50     | 2.9s      | 2.58s    | -11%  |
| 200    | 7.1s      | 7.20s    | +1%   |
| 500    | 15.4s     | 14.81s   | -4%   |
| 1000   | 29.3s     | 27.17s   | -7%   |

Within ±15% of measured — useful for capacity planning. Adjust REASONING_RATIO upward to 0.4 for the P95 case.

### For migration testing from OpenAI

OpenAI gpt-4o sustains ~80-100 TPS; MiniMax M2.7-highspeed is ~50 TPS. **Same prompt that completes in N seconds on OpenAI will take 1.6-2× as long on MiniMax**. Migration code that assumes OpenAI-comparable speeds will hit timeouts under load. Bump request timeouts by 2× when porting.

## Open questions for follow-up

- **Does plain `MiniMax-M2.7` hit lower TPS?** If "up to 3x faster" refers to highspeed vs base, base M2.7 should sustain ~15-17 TPS. Worth a single comparison probe (T3.7 also covers model aliasing).
- **Is the 50 TPS ceiling stable across sustained load?** iter-26 measured single bursts. A 5-minute sustained generation might thermal-throttle (warm caches drain, server-side resource pressure). Test with a 60s probe at constant emission.
- **Does `temperature` affect TPS?** Higher temperature might mean more sampling work per token — untested. iter-5's haiku probes at temp=0/0.5/1.0 weren't designed for TPS measurement.
- **Streaming TPS vs non-streaming**: iter-8 measured ~125 chars per chunk and ~2 chunks/sec — that's ~250 chars/sec ≈ 70 TPS in streaming mode. Conflicts with iter-26's 50 TPS non-streaming measurement! Worth re-probing to disambiguate (chars/4 vs actual tokens, or streaming has different rate).
- **Chinese/non-English TPS**: MiniMax is a Chinese provider; TPS for Mandarin output may differ. Defer to T4.3 cross-language probe.

## Provenance

| Probe      | http_status | latency | completion_tokens | reasoning_tokens | visible_tokens | TPS_total | TPS_visible | finish_reason |
| ---------- | ----------- | ------- | ----------------- | ---------------- | -------------- | --------- | ----------- | ------------- |
| P1-50tok   | 200         | 2.576s  | 60                | 30               | 30             | 23.3      | 11.6        | stop          |
| P2-200tok  | 200         | 7.200s  | 291               | 42               | 249            | 40.4      | 34.6        | stop          |
| P3-500tok  | 200         | 14.812s | 717               | 291              | 426            | 48.4      | 28.8        | stop          |
| P4-1000tok | 200         | 27.171s | 1324              | 93               | 1231           | 48.7      | 45.3        | stop          |

Wall-clock for 4 parallel probes: 27.17s (max latency dominates).

Fixture:

- [`fixtures/tps-iter26-emission-rate-2026-04-29.json`](~/own/amonic/minimax/api-patterns/fixtures/tps-iter26-emission-rate-2026-04-29.json)

Verifier: autonomous-loop iter-26. 4 API calls.
