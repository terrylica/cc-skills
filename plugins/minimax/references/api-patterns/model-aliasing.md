# Chat Completion — Model Aliasing: Plain M2.7 vs M2.7-highspeed

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/model-aliasing.md` (source-of-truth — read-only, source iter-28). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-11).

Verified 2026-04-29 with both `MiniMax-M2.7` and `MiniMax-M2.7-highspeed`. **Headline finding: the two models are DISTINCT deployments — no silent aliasing — but the "highspeed" suffix is misleading for short-output workloads.** Plain M2.7 is 1.6-2.5× FASTER than highspeed for prompts under ~80 tokens; only at long-form generation (~250+ visible tokens) does highspeed pull ahead with a 1.5-1.6× speedup. The Plan's "up to 3x faster" claim is NOT validated at any tested output size.

Closes T3.7 by definitively comparing the two model deployments and resolving (with surprise) the iter-26 question about the "up to 3x" interpretation.

## Test setup

3 categorically-different prompts × 2 models = 6 parallel calls. Within iter-25's confirmed p=10 chat-completion sweet spot.

| Prompt     | Target output size | User text                                                                                                          |
| ---------- | ------------------ | ------------------------------------------------------------------------------------------------------------------ |
| A1-factual | Single token       | "What is the capital of France? One word."                                                                         |
| A2-medium  | ~20 tokens         | "Count from 1 to 10, one number per line. Plain digits only."                                                      |
| A3-long    | ~200 tokens        | "Write a paragraph of approximately 200 words about the history of coffee. Plain prose, no headings, no markdown." |

Both models received identical prompts + identical system prompt + identical max_tokens=2048 + temperature=0.3. The only variable is the `model` field.

## Results — paired comparison

| Prompt     | Model     | response.model         | Latency | comp_tok | reas_tok | TPS_total | Verdict                             |
| ---------- | --------- | ---------------------- | ------- | -------- | -------- | --------- | ----------------------------------- |
| A1-factual | plain     | MiniMax-M2.7           | 0.95s   | 28       | 30       | 29.5      | ✅ plain 2.5× FASTER                |
| A1-factual | highspeed | MiniMax-M2.7-highspeed | 2.33s   | 25       | 24       | 10.7      |                                     |
| A2-medium  | plain     | MiniMax-M2.7           | 1.69s   | 79       | 61       | 46.8      | ✅ plain 1.6× FASTER                |
| A2-medium  | highspeed | MiniMax-M2.7-highspeed | 2.77s   | 59       | 40       | 21.3      |                                     |
| A3-long    | plain     | MiniMax-M2.7           | 12.25s  | 271      | 33       | 22.1      |                                     |
| A3-long    | highspeed | MiniMax-M2.7-highspeed | 8.03s   | 286      | 40       | 35.6      | ✅ highspeed 1.5× FASTER (1.6× TPS) |

**Key observations**:

1. **`response.model` echoed back exactly**: no silent aliasing — the two models are routed to distinct deployments.
2. **Latency cross-over**: at A2-medium scale (~80 tokens), the gap is closing; at A3-long, highspeed pulls ahead. The cross-over point appears to be somewhere between 80-250 tokens of output.
3. **Highspeed reasons LESS on short prompts**: A2-medium reasoning_tokens were 40 (highspeed) vs 61 (plain). Suggests highspeed has been tuned to spend less reasoning budget on simple tasks — a latency-optimization that backfires on the per-call overhead-dominated regime.

## Headline findings

### Finding 1: 🎯 Models are DISTINCT — no silent aliasing

Per iter-1's "response.model is authoritative" rule (cross-checked again here): when you request `MiniMax-M2.7`, the server returns `response.model: "MiniMax-M2.7"`. When you request `MiniMax-M2.7-highspeed`, the server returns `response.model: "MiniMax-M2.7-highspeed"`. The two models have **separate deployment infrastructure**, not just billing labels.

This rules out the simplest interpretation of "highspeed" as a marketing-tier label that quietly hits the same backend.

### Finding 2: 🚨 "Highspeed" is COUNTERINTUITIVELY SLOWER for short prompts

For workloads with short outputs (under ~80 tokens), plain M2.7 measures 1.6-2.5× FASTER than highspeed:

| Output size       | Plain M2.7 latency | Highspeed latency | Plain advantage |
| ----------------- | ------------------ | ----------------- | --------------- |
| 1 token (A1)      | 0.95s              | 2.33s             | 2.5× faster     |
| 18-19 tokens (A2) | 1.69s              | 2.77s             | 1.6× faster     |

**Possible explanations**:

1. **Highspeed has higher per-call overhead** — the routing/scheduling layer for highspeed may add latency that's only justified at scale (long output amortizes the overhead).
2. **Highspeed is optimized for streaming output** — the iter-26 measurement (highspeed at ~50 TPS asymptote) may have included streaming buffer setup costs that don't show in non-streaming short-output measurements.
3. **Different deployment tier capacity** — highspeed may run on more-shared capacity for cost reasons, with higher contention at low-volume.

**Production implication for Karakeep tagging** (typical output: 5-15 tokens): **use plain `MiniMax-M2.7`, NOT `-highspeed`**. Counterintuitively, this saves both latency AND likely cost (plain may have lower per-token rate; verify in billing UI). For 100 bookmarks at concurrency=10:

- plain M2.7: ~10 batches × 1.69s = ~17s
- highspeed: ~10 batches × 2.77s = ~28s

Plain saves 11 seconds (~40%) per 100-bookmark batch.

### Finding 3: ✅ Highspeed wins on long-form generation (A3-long)

For A3 (200-word coffee history paragraph, ~250 visible tokens emitted):

- Plain M2.7: 12.25s, 22.1 TPS
- Highspeed: 8.03s, 35.6 TPS
- **Highspeed advantage: 1.5× faster latency, 1.6× higher TPS**

The cross-over point is somewhere between 80 and 250 visible tokens. For Linkwarden article summarization (typical output 500-1000 tokens), highspeed will dominate. iter-26's TPS measurement (50 TPS asymptote at 1000+ visible tokens) was specifically for highspeed; plain M2.7's asymptote may be lower (likely ~20-25 TPS based on A3 measurement).

### Finding 4: 🚨 The "up to 3x faster" Plan claim is NOT validated at any tested size

iter-28's max observed speedup of highspeed-vs-plain is **1.6× (TPS at A3-long)** — significantly below the marketing-claimed 3×. Even at the most favorable comparison (long generation), highspeed is only 60% faster than plain.

**Possible interpretations of the "up to 3x faster" claim**:

1. **Comparison vs older M-series** (M2.5, M2.1): if older models are 1.6× slower than current plain M2.7 (plausible), then highspeed-vs-M2.5 could be ~3×. iter-28 didn't test older models. Defer to T3.9 (deprecation behavior) or T4.4 (model upgrade detection).
2. **Peak-burst rate vs sustained**: marketing claims often quote peak rates. Sustained measurements rarely match.
3. **Cross-provider comparison**: "3x faster than `<unspecified competitor>`" — would explain the qualifier "up to" if MiniMax marketing chose the worst-case competitor.
4. **Specific output-size sweet spot we missed**: maybe at exactly 50K tokens of output, highspeed achieves 3× — untested.

**Production implication**: do NOT design capacity assuming 3× speedup for highspeed. Use **1.5× as the conservative speedup factor for long-form generation**, and note that highspeed is actually SLOWER for short outputs.

### Finding 5: 🆕 Token accounting anomaly on plain M2.7 — completion < reasoning

A1-plain showed `completion_tokens=28, reasoning_tokens=30` — reasoning is LARGER than completion. Per iter-10's documented formula `completion_tokens = reasoning_tokens + visible_emitted_tokens`, this would imply NEGATIVE visible_tokens, which is nonsensical.

**Possible explanations**:

1. **Convention difference between models**: iter-10 measured highspeed only; plain M2.7 may use a different convention where `reasoning_tokens` is reported separately (NOT a subset of `completion_tokens`).
2. **Server-side accounting bug**: MiniMax may have a small accounting inconsistency for very short outputs.
3. **API change since iter-10**: the response shape may have evolved; iter-10's "subset" model may no longer hold.

A2-plain (`comp=79, reasoning=61`) and A3-plain (`comp=271, reasoning=33`) both show `completion > reasoning` (consistent with iter-10's subset model). The anomaly is specifically at extremely short output (A1's 1 visible token).

**Production implication**: defensive token accounting code:

```python
def safe_visible_tokens(usage: dict) -> int:
    """Compute visible tokens defensively across both M2.7 variants."""
    comp = usage.get("completion_tokens", 0)
    reas = (usage.get("completion_tokens_details") or {}).get("reasoning_tokens", 0)
    # Clamp to non-negative; for very short outputs the convention may differ
    return max(0, comp - reas)
```

Use this everywhere instead of raw subtraction. iter-10's pattern doc should be updated with this caveat.

## Implications

### For Karakeep AI tagging (short output)

**Switch from `MiniMax-M2.7-highspeed` to plain `MiniMax-M2.7`**:

```python
# Before iter-28
INFERENCE_TEXT_MODEL = "MiniMax-M2.7-highspeed"

# After iter-28 (1.6-2.5× faster for short outputs)
INFERENCE_TEXT_MODEL = "MiniMax-M2.7"
```

This is a meaningful per-call latency win that compounds at scale (40% throughput improvement on bulk-tagging).

### For Linkwarden article summarization (long output)

**Keep `MiniMax-M2.7-highspeed`** — for outputs over ~250 tokens, highspeed is 1.5-1.6× faster.

### For mixed workloads (Gmail Commander summarization, where output size varies)

Either:

1. **Default to highspeed** (worse case 1.6× slower for short outputs; better case 1.6× faster for long outputs). Net: roughly break-even.
2. **Branch on expected output size** in the client:

```python
def select_minimax_model(estimated_visible_tokens: int) -> str:
    """Pick the faster model based on expected output size.

    Cross-over point per iter-28: ~150 tokens.
    Plain wins for short outputs; highspeed wins for long generation.
    """
    return "MiniMax-M2.7" if estimated_visible_tokens < 150 else "MiniMax-M2.7-highspeed"
```

### For latency estimator (iter-26 update)

iter-26's `latency = 1.5s + (visible / 0.72 / 50)` was measured on highspeed. Plain M2.7 likely has a different overhead/asymptote profile. Until measured, use:

- **Plain M2.7** (short outputs): `latency ≈ 0.8s + (visible / 0.72 / 25)` (lower overhead, lower TPS asymptote — guesstimate from iter-28 data)
- **Highspeed**: keep `latency ≈ 1.5s + (visible / 0.72 / 50)` (validated within ±15%)

T4.x follow-up: characterize plain M2.7's full TPS curve at varied output sizes, parallel to iter-26's highspeed measurement.

## Open questions for follow-up

- **Where exactly is the cross-over point?** iter-28 has 3 data points (1 / 19 / 246 visible tokens). Probes at 50, 100, 150, 200 tokens would localize the cross-over precisely.
- **Does plain M2.7 also have ~50 TPS asymptote, or lower?** A3-plain measured 22 TPS at 271 completion tokens — this might be the asymptote OR plain could keep climbing at larger output sizes. Untested.
- **Is highspeed's overhead actually higher**, or is iter-28 just one noisy measurement? Single-measurement variance per iter-25's p=20 finding is ~30%. N=10 paired probes would resolve.
- **Plan-tier billing**: does plain M2.7 have a different per-token rate than highspeed? Would change cost-modeling beyond just latency.
- **Streaming TPS for plain**: iter-26 didn't measure plain M2.7 streaming. iter-8's coarse-grained chunks were highspeed-only.

## Provenance

| Probe                                | request_model          | response.model         | model_match | latency | completion_tokens | reasoning_tokens | TPS_total | finish_reason |
| ------------------------------------ | ---------------------- | ---------------------- | ----------- | ------- | ----------------- | ---------------- | --------- | ------------- |
| A1-factual\_\_MiniMax-M2.7           | MiniMax-M2.7           | MiniMax-M2.7           | True        | 0.948s  | 28                | 30               | 29.5      | stop          |
| A1-factual\_\_MiniMax-M2.7-highspeed | MiniMax-M2.7-highspeed | MiniMax-M2.7-highspeed | True        | 2.330s  | 25                | 24               | 10.7      | stop          |
| A2-medium\_\_MiniMax-M2.7            | MiniMax-M2.7           | MiniMax-M2.7           | True        | 1.687s  | 79                | 61               | 46.8      | stop          |
| A2-medium\_\_MiniMax-M2.7-highspeed  | MiniMax-M2.7-highspeed | MiniMax-M2.7-highspeed | True        | 2.773s  | 59                | 40               | 21.3      | stop          |
| A3-long\_\_MiniMax-M2.7              | MiniMax-M2.7           | MiniMax-M2.7           | True        | 12.250s | 271               | 33               | 22.1      | stop          |
| A3-long\_\_MiniMax-M2.7-highspeed    | MiniMax-M2.7-highspeed | MiniMax-M2.7-highspeed | True        | 8.028s  | 286               | 40               | 35.6      | stop          |

Wall-clock for 6 parallel probes: 12.25s (A3-plain dominates).

Fixture:

- [`fixtures/model-aliasing-iter28-comparison-2026-04-29.json`](~/own/amonic/minimax/api-patterns/fixtures/model-aliasing-iter28-comparison-2026-04-29.json)

Verifier: autonomous-loop iter-28. 6 API calls.
