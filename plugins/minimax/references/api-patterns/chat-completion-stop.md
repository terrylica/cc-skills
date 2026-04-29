# Chat Completion — `stop` Sequence Behavior

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-stop.md` (source-of-truth — read-only, source iter-7). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-8).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. Probes the OpenAI-compatible `stop` parameter with 4 strategic test cases. **Headline finding: the `stop` parameter is silently ignored.**

## Test setup

4 parallel probes, each with `max_tokens: 4096` and the stop strings designed to either appear in reasoning, in visible output, or both:

| Probe | `stop` array            | Prompt                                             | Hypothesis                                                          |
| ----- | ----------------------- | -------------------------------------------------- | ------------------------------------------------------------------- |
| A     | `["5"]`                 | "Count from 1 to 10, one number per line."         | If honored, output ends before "5" → visible "1\n2\n3\n4"           |
| B     | `["</think>"]`          | "What is 2+2? Reply briefly."                      | If honored on reasoning trace, terminates at end of `<think>` block |
| C     | `["END"]`               | "Repeat exactly: 'hello END world'"                | If honored, visible truncates after "hello "                        |
| D     | `["foo", "bar", "baz"]` | "Output these three on three lines: foo, bar, baz" | If honored, visible stops at first match (probably "foo")           |

## Results

| Probe | finish_reason | reasoning | completion | Visible output                  | Stop string in output?                                 |
| ----- | ------------- | --------- | ---------- | ------------------------------- | ------------------------------------------------------ |
| A     | `stop`        | 91        | 110        | `1\n2\n3\n4\n5\n6\n7\n8\n9\n10` | ✅ "5" present (multiple times in reasoning + visible) |
| B     | `stop`        | 54        | 55         | `4`                             | ✅ literal `</think>` tag present in raw content       |
| C     | `stop`        | 291       | 294        | `hello END world`               | ✅ "END" present verbatim                              |
| D     | `stop`        | 281       | 286        | `foo\nbar\nbaz`                 | ✅ all three present verbatim                          |

**Verdict: ALL 4 stop strings appeared unchanged in the output.** The `stop` parameter is silently accepted by the API (no 400 error) but has no effect on generation.

## Headline findings

### Finding 1: 🚨 `stop` parameter is silently ignored on M2.7-highspeed

The smoking gun is Probe C: stop=["END"] + a prompt that explicitly contains "END" in the requested verbatim output. If the stop sequence were honored, generation would terminate after "hello " and the visible output would be `"hello "`. Instead the model emitted the full `"hello END world"`. Same pattern in all 4 probes.

This is a **critical departure from OpenAI norm** where `stop` sequences are first-class generation-time controls.

### Finding 2: ⚠️ `finish_reason="stop"` is NOT diagnostic for stop-sequence detection

All 4 probes returned `finish_reason="stop"`. In OpenAI's API, `finish_reason="stop"` is the same value for both "natural completion" and "stop sequence matched" — they're indistinguishable. So you cannot use `finish_reason` alone to detect whether a stop sequence fired.

On MiniMax, since stop is ignored entirely, `finish_reason="stop"` always means natural completion (or `"length"` for cap hit, per iter-6).

### Finding 3: API accepts `stop` parameter without protest (silent acceptance)

No 400 error, no warning, no `unsupported_parameter` flag in the response. The OpenAI-compat layer accepts the request body shape and simply drops the `stop` field downstream. This is the worst kind of silent failure — clients that copy OpenAI examples will appear to work but produce subtly wrong results in production.

### Finding 4: Cannot use `stop` to cap reasoning cost

Probe B tested whether `stop=["</think>"]` would terminate generation at the end of the reasoning trace, which would be a powerful cost-control pattern (truncating right after `<think>...</think>` saves all visible-output tokens for cases where you only care about the reasoning trace). It did not work — the model emitted the full reasoning AND the visible answer. So this clever workaround is unavailable.

### Finding 5: Reasoning tokens still scale with task ambiguity

Reasoning costs varied widely across probes:

- Probe A (count 1-10): 91 reasoning tokens
- Probe B (2+2): 54 reasoning tokens
- Probe C (verbatim repeat with quote ambiguity): **291** reasoning tokens
- Probe D (list three words): **281** reasoning tokens

Probes C and D had ~5x more reasoning than A/B because the prompts were ambiguous (quote handling for C, output formatting for D). This is consistent with iter-5's finding that reasoning scales with task complexity, not output size.

## Implications

### For production clients

1. **Do not use `stop` parameter on MiniMax — it does nothing.** Any client code that relies on stop sequences for output truncation, delimiter detection, or custom termination is broken on MiniMax even though no error surfaces.
2. **Do post-processing client-side** — if you need to truncate output at a marker, regex-strip after receiving the response:

   ```python
   resp = call_minimax(...)
   visible = strip_think_tags(resp["choices"][0]["message"]["content"])
   visible_truncated = visible.split("END")[0]  # client-side stop equivalent
   ```

3. **Cannot cap reasoning via `stop=["</think>"]`** — the natural workaround for OpenAI o1-style models doesn't apply.

### For Karakeep/Linkwarden tagging

If you were tempted to use a stop sequence to terminate output after N tags (e.g., `stop=["\n\n"]` to cap at one paragraph), that doesn't work. Use `max_tokens` for hard length caps + client-side post-processing for delimiter-based truncation.

### For migration from OpenAI/other providers

Any code path that tests stop sequences via integration tests against OpenAI will pass on OpenAI but produce wrong outputs on MiniMax — without any error. Add explicit tests that assert stop strings are NOT in output to catch this.

## Idiomatic patterns

### Replace `stop` with client-side truncation

```python
# OpenAI-compatible code — DOESN'T WORK on MiniMax:
# resp = client.chat.completions.create(..., stop=["END"])
# truncated_visible = resp.choices[0].message.content

# MiniMax-safe equivalent:
resp = client.chat.completions.create(...)  # omit stop entirely
content = resp.choices[0].message.content
visible = re.sub(r"<think>[\s\S]*?</think>\s*", "", content, flags=re.DOTALL)
truncated = visible.split("END", 1)[0]  # client-side
```

### Cap output with `max_tokens` + check `finish_reason`

```python
resp = call_minimax(..., max_tokens=200)
finish = resp["choices"][0]["finish_reason"]
if finish == "length":
    log.warning("Output truncated by max_tokens cap")
```

This is the only reliable way to bound output length on MiniMax.

## Open questions for follow-up

- **Does `stop` work on other MiniMax models?** Tested only M2.7-highspeed. Plain `MiniMax-M2.7` (non-highspeed) and older M-series might differ. Add to T3.7 (model aliasing).
- **Are there MiniMax-specific termination parameters?** OpenAI has `stop`; Anthropic has `stop_sequences`. MiniMax may have a custom name we haven't discovered. Check official docs at <https://platform.minimax.io/docs/api-reference>.
- **Does streaming respect `stop`?** Tested only non-streaming. SSE streaming might apply stop sequences differently. Defer to T1.8 (streaming).

## Provenance

| Probe | trace-id (in fixture) | finish_reason | tokens (p+c) | latency |
| ----- | --------------------- | ------------- | ------------ | ------- |
| A     | (in fixture)          | stop          | 60+110       | 2.55s   |
| B     | (in fixture)          | stop          | 51+55        | 2.68s   |
| C     | (in fixture)          | stop          | 56+294       | 6.40s   |
| D     | (in fixture)          | stop          | 63+286       | 7.56s   |

Fixtures:

- [`fixtures/chat-completion-stop-A-count-stop-5-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-stop-A-count-stop-5-2026-04-28.json)
- [`fixtures/chat-completion-stop-B-stop-think-close-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-stop-B-stop-think-close-2026-04-28.json)
- [`fixtures/chat-completion-stop-C-stop-end-marker-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-stop-C-stop-end-marker-2026-04-28.json)
- [`fixtures/chat-completion-stop-D-multi-stop-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-stop-D-multi-stop-2026-04-28.json)

Verifier: autonomous-loop iter-7. 4 API calls.
