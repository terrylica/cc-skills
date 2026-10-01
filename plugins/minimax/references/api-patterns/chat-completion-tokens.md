# Chat Completion — Token Counting Reconciliation

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-tokens.md` (source-of-truth — read-only, source iter-10). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-9).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. Closes Tier 1 of the autonomous-loop campaign by definitively documenting the `usage` object math, the M-series reasoning-token accounting, and a previously-undiscovered server-side optimization for multi-turn chat.

## Test setup

3 parallel probes designed to characterize the full token accounting:

| Probe | Setup                                                                     | Question                                                      |
| ----- | ------------------------------------------------------------------------- | ------------------------------------------------------------- |
| T1    | Single-turn factual ("capital of Japan?")                                 | Verify `completion_tokens = reasoning_tokens + visible`       |
| T2    | Multi-turn replay with **FULL** `<think>...</think>` content in assistant | Measure `prompt_tokens` impact of replaying reasoning content |
| T3    | Multi-turn replay with `<think>` STRIPPED from assistant                  | Compare against T2 to detect server-side think-stripping      |

T2 vs T3: the assistant content differed by 414 chars (~150 tokens). If prompt_tokens scales with content, T2 should be ~150 tokens higher than T3.

## Results

| Metric                    | T1 (single-turn) | T2 (with `<think>`)  | T3 (stripped)    |
| ------------------------- | ---------------- | -------------------- | ---------------- |
| `prompt_tokens`           | 51               | **70**               | **70**           |
| `completion_tokens`       | 84               | 29                   | 19               |
| `reasoning_tokens`        | 83               | 28                   | 18               |
| `total_tokens`            | 135              | 99                   | 89               |
| `total_characters`        | **0**            | **0**                | **0**            |
| Visible                   | "Tokyo"          | "Paris"              | "Paris"          |
| Raw content chars         | 378              | 130                  | 82               |
| Assistant content (T2/T3) | n/a              | 419 chars (~150 tok) | 5 chars (~2 tok) |

## Headline findings

### Finding 1: 🎯 SERVER-SIDE `<think>` STRIPPING — multi-turn replay does NOT double-bill for reasoning content

**T2 and T3 have IDENTICAL `prompt_tokens` (70 each).**

T2's assistant turn was 419 chars (~150 tokens) of `<think>` content + "Tokyo". T3's was just "Tokyo" (5 chars). The expected delta if MiniMax tokenized assistant content naively would be ~150 tokens. The actual delta is **0**.

**Conclusion**: MiniMax strips `<think>...</think>` from assistant turns server-side before prompt tokenization for billing.

This is a major cost optimization that has significant production implications:

1. **Multi-turn conversations don't accumulate prompt cost from reasoning traces.** A 10-turn conversation with 1000-token reasoning per turn doesn't cost 10000+ extra prompt_tokens on turn 11.
2. **Clients don't need to strip `<think>` client-side before replay for cost reasons.** They DO still need to strip for display (UI concerns) and for retrieval/serialization (think-tags pollute logs and searches).
3. **The recommendation in iter-4 to "strip before replay for cleaner history"** is correct for hygiene but irrelevant for billing.

This generalizes the M-series pattern: reasoning is a cost paid in the iteration that produced it (as `reasoning_tokens` within `completion_tokens`), but it's not a recurring cost on replay. Linear cost growth in multi-turn, not quadratic.

### Finding 2: Math — `completion_tokens = reasoning_tokens + visible_emitted_tokens`

All 3 probes confirm: `completion_tokens - reasoning_tokens = 1` and visible output for each was 1 token ("Tokyo" or "Paris").

The standard accounting is:

```
completion_tokens = reasoning_tokens + visible_emitted_tokens
```

So `reasoning_tokens` is a SUBSET of `completion_tokens`, not separately billed. This matches OpenAI's o1 reasoning-model billing convention.

**Practical implication**: when budgeting cost, `completion_tokens` is the actual billed amount. `reasoning_tokens` is a metric of how much of that budget went to private reasoning vs visible output.

### Finding 3: Math — `total_tokens = prompt_tokens + completion_tokens`

All 3 probes confirm. Standard OpenAI accounting; no deviation.

```
total_tokens = prompt_tokens + completion_tokens
```

Where `completion_tokens` includes `reasoning_tokens` (Finding 2). So you DON'T add reasoning separately to total — it's already inside completion.

### Finding 4: `total_characters: 0` is always emitted but always zero

```json
{
  "total_tokens": 135,
  "total_characters": 0,
  "prompt_tokens": 51,
  "completion_tokens": 84,
  "completion_tokens_details": { "reasoning_tokens": 83 }
}
```

The `total_characters` field appears in every probe's `usage` object but its value is always `0`. Possible interpretations:

- **Reserved for audio API**: `total_characters` likely refers to TTS-generated character count, not chat-completion content. Will become non-zero when probing audio endpoints (T2.4).
- **Deprecated field**: Legacy from an older version.
- **Different unit semantics**: Possibly counts something specific that happens to be 0 for our probes.

Until verified via audio endpoint testing, treat as unused for chat-completion accounting.

### Finding 5: `completion_tokens_details.reasoning_tokens` is the only standardized sub-field

The `usage.completion_tokens_details` object only contains `reasoning_tokens`. OpenAI's `usage.completion_tokens_details` can include `accepted_prediction_tokens`, `rejected_prediction_tokens`, `audio_tokens`, etc. on certain models — none of these appear on M2.7-highspeed.

So the only "subtype" of completion tokens that MiniMax M-series exposes is the reasoning vs visible split.

## Cost-modeling implications

### Pattern: Multi-turn cost projection

Given the server-side `<think>` stripping (Finding 1):

```python
def project_multi_turn_cost(messages_so_far, expected_response_tokens):
    """Estimate cost for the NEXT turn in a chat."""
    # NOTE: <think> tags in prior assistant turns are STRIPPED server-side.
    # Compute prompt_tokens estimate based on visible content only.
    visible_messages = [
        {**m, "content": strip_think_tags(m["content"])} if m["role"] == "assistant"
        else m
        for m in messages_so_far
    ]
    estimated_prompt_tokens = sum(
        approx_token_count(m["content"]) + role_overhead(m["role"])
        for m in visible_messages
    )
    estimated_completion_tokens = expected_response_tokens
    return estimated_prompt_tokens + estimated_completion_tokens
```

**For Karakeep tagging**: each tagging request is single-turn so this doesn't apply. But for any future chat-style amonic service (Telegram bot, conversational interface), this pattern matters.

### Pattern: Verifying prompt_tokens client-side

If you want to assert that MiniMax's billing matches your understanding:

```python
import tiktoken  # approximate; not MiniMax-specific
enc = tiktoken.get_encoding("cl100k_base")  # approximation

def verify_prompt_accounting(messages, response):
    actual = response["usage"]["prompt_tokens"]
    # Naive estimate: count tokens of visible message content
    expected_naive = sum(
        len(enc.encode(strip_think_tags(m["content"]) if m["role"] == "assistant" else m["content"]))
        + 4  # role-framing overhead approximation
        for m in messages
    )
    discrepancy = actual - expected_naive
    if abs(discrepancy) > 20:
        log.warning(f"prompt_tokens discrepancy: actual={actual}, expected={expected_naive}, delta={discrepancy}")
```

The role-framing overhead (~4 tokens per turn) is approximate. iter-3's still-unresolved system-role anomaly may further complicate this — be cautious for system-message-heavy traffic.

## Outstanding anomalies

### Anomaly: iter-3 system-role accounting

iter-3 found a 25-token system message caused only +2 increase in prompt_tokens (50 vs 48 for identical user messages). This iter (T1.10) does NOT re-test that — these probes used user/assistant only, no system messages.

The iter-3 anomaly remains queued for T3.10 (deliberately-long system prompt scaling test). Hypothesis given iter-10's `<think>` finding: MiniMax might have a server-side preprocessing layer that handles BOTH `<think>` AND system messages specially. Maybe system prompts are partially absorbed into a baseline tokenization that gets templated rather than concatenated.

### Open question: does `total_characters` ever surface a value?

Untested. Probably populated by audio endpoint (TTS character counts). Defer to T2.4 (audio probe).

### Open question: do `cached_tokens` or `prompt_cache_hit_tokens` exist?

Iter-2's bootstrap call had no `prompt_cache_hit_tokens` field, and the billing UI showed `cache-read(Text API)` as a separate consumed type. Whether MiniMax populates a `prompt_tokens_details.cached_tokens` field on cache-hit responses is untested. Defer to T4.1/T4.2 (prompt caching).

## Idiomatic patterns

### Pattern 1: Cost extraction from a response

```python
usage = resp["usage"]
prompt_t = usage["prompt_tokens"]
completion_t = usage["completion_tokens"]
reasoning_t = (usage.get("completion_tokens_details") or {}).get("reasoning_tokens", 0)
visible_t = completion_t - reasoning_t
total_t = usage["total_tokens"]

assert total_t == prompt_t + completion_t  # math reconciliation
billable_total = total_t  # this is what shows up in billing
```

### Pattern 2: Reasoning efficiency tracking

```python
def reasoning_overhead_ratio(usage):
    """Returns reasoning_tokens / completion_tokens — high values mean
    the model spent most of its budget thinking, not speaking."""
    completion = usage["completion_tokens"]
    reasoning = (usage.get("completion_tokens_details") or {}).get("reasoning_tokens", 0)
    if completion == 0:
        return None
    return reasoning / completion
```

For Karakeep tagging, you'd want this ratio < 0.6 ideally (reasoning shouldn't dominate when the task is simple). If it climbs >0.9 consistently, the prompt is too ambiguous — refactor.

### Pattern 3: Multi-turn cost-per-turn delta

```python
def cost_delta(prev_usage, current_usage):
    """How many tokens did this turn add over the previous turn's total?"""
    prev_total = prev_usage["total_tokens"]
    curr_total = current_usage["total_tokens"]
    return curr_total - prev_total
```

This will reveal whether server-side optimizations (like `<think>` stripping) are kicking in. Sudden non-linear jumps may indicate a context-window threshold or rate-limit window crossing.

## Provenance

| Probe | trace-id (in fixture) | Visible | prompt_t + completion_t = total_t | reasoning_t | latency      |
| ----- | --------------------- | ------- | --------------------------------- | ----------- | ------------ |
| T1    | (in fixture)          | "Tokyo" | 51 + 84 = 135                     | 83          | (in fixture) |
| T2    | (in fixture)          | "Paris" | 70 + 29 = 99                      | 28          | (in fixture) |
| T3    | (in fixture)          | "Paris" | 70 + 19 = 89                      | 18          | (in fixture) |

Fixtures:

- `fixtures/chat-completion-tokens-T1-single-turn-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-tokens-T1-single-turn-2026-04-28.json`)
- `fixtures/chat-completion-tokens-T2-multiturn-with-think-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-tokens-T2-multiturn-with-think-2026-04-28.json`)
- `fixtures/chat-completion-tokens-T3-multiturn-stripped-think-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-tokens-T3-multiturn-stripped-think-2026-04-28.json`)

Verifier: autonomous-loop iter-10 (closes Tier 1). 3 API calls.
