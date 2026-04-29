# Chat Completion — SSE Streaming (`stream: true`)

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-streaming.md` (source-of-truth — read-only, source iter-8). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-8).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. Two probes characterizing the SSE streaming behavior, chunk shape, finish detection, and whether streaming mode honors `stop` differently from non-streaming (it doesn't).

## Test setup

| Probe | Request shape                                                      | Purpose                                                                      |
| ----- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| S1    | `stream:true` + simple counting prompt                             | Characterize basic chunk shape, timing, finish marker                        |
| S2    | `stream:true` + `stop:["END"]` + "hello END world" verbatim prompt | Test if streaming honors stop (iter-7 confirmed it doesn't in non-streaming) |

`max_tokens: 4096`, default temperature/top_p. Captured raw SSE lines + parsed events to fixture files.

## Results

| Metric               | S1 (basic)                 | S2 (stop sequence)         |
| -------------------- | -------------------------- | -------------------------- |
| HTTP status          | 200                        | 200                        |
| Chunk count          | 4                          | 12                         |
| First chunk @        | 1.04s                      | 1.04s                      |
| Last chunk @         | 2.53s                      | 6.88s                      |
| Total latency        | 2.54s                      | 6.88s                      |
| `finish_reason`      | `stop` (on last chunk)     | `stop` (on last chunk)     |
| `usage` in any chunk | **null** (never populated) | **null** (never populated) |
| Visible (post-strip) | `1\n2\n3\n4\n5`            | `hello END world`          |
| `stop` honored?      | n/a                        | ❌ "END" emitted verbatim  |

## Headline findings

### Finding 1: Chunks are coarse-grained, not token-by-token

S1 produced ~50 tokens of accumulated content in **4 chunks**. Real OpenAI streaming would emit ~50 chunks for the same volume. S2 produced ~1500 chars in 12 chunks (~125 chars/chunk average).

**Implication**: streaming on MiniMax does NOT give smooth per-token rendering. It will look like "type-paste-type-paste" rather than a typewriter. For UX where smooth-typing matters, this is a meaningful UX gap vs OpenAI/Anthropic.

The first chunk for both probes contained `<think>\nThe user...` — meaning even the FIRST emission is mid-`<think>`-tag, ~10-15 tokens of content, not a single token.

### Finding 2: 🚨 `usage` is null in every chunk — token accounting unavailable in streaming

```json
"usage": null,
```

Every single chunk in both probes had `usage: null`, including the final chunk that carries `finish_reason="stop"`. There is no usage data in the stream at all.

**Implication**: cannot derive `prompt_tokens`, `completion_tokens`, or `reasoning_tokens` from a streaming response. Production code that needs cost tracking + streaming must either:

1. Use non-streaming (forfeits TTFB benefit)
2. Approximate from `len(accumulated_content)` × known token-per-char ratio (imprecise; doesn't account for reasoning tokens that are billed but rendered)
3. Rely on out-of-band billing reconciliation (MiniMax billing UI, async)

OpenAI's solution is `stream_options: {include_usage: true}` which emits a final usage-only chunk. **MiniMax may or may not support this** — untested, promote to T3.x follow-up.

### Finding 3: 🚨 `stop` parameter is STILL silently ignored in streaming mode

S2 sent `stream:true` + `stop:["END"]` + a prompt explicitly containing "END" in the requested verbatim output. The accumulated visible output was `hello END world` — the stop string emitted unchanged, just like non-streaming (iter-7).

**Implication**: iter-7's finding generalizes. Stop is dropped server-side regardless of stream mode. Workaround for both modes: client-side post-processing.

### Finding 4: Time-to-first-chunk ~1.04s — useful UX win but not "instant"

Both probes had first chunk at exactly ~1.04s. For UX-sensitive paths (e.g., a chat interface), this halves the perceived latency:

- Non-streaming: full response at 2.5s for simple prompts
- Streaming: first content visible at ~1s

But "1 second cold start" is still noticeable — much slower than OpenAI gpt-3.5-turbo's ~200ms TTFB. Likely because MiniMax M-series buffers reasoning before emitting any chunk. The reasoning phase still has to complete (or get well underway) before chunks start flowing.

### Finding 5: Chunks roll-up reasoning trace — clients must accumulate-then-strip

Each chunk's `delta.content` is a partial string, e.g.:

- chunk 0: `"<think>\nThe user"`
- chunk 1: `"...\n2\n3\n4\n5"` (closing reasoning + emitting visible)

So the `<think>` tags are split across chunks. Naive per-chunk processing breaks if you try to strip per-chunk. **Pattern**:

```python
buffer = ""
visible_emitted = False
for chunk in stream:
    delta = chunk.choices[0].delta.content or ""
    buffer += delta
    if not visible_emitted and "</think>" in buffer:
        # Reasoning closed — switch to streaming visible to user
        _, visible = buffer.split("</think>", 1)
        emit_to_user(visible.lstrip())
        visible_emitted = True
        buffer = visible
    elif visible_emitted:
        emit_to_user(delta)
```

This accumulates until the reasoning trace closes, then streams the visible portion to the user. Hides the `<think>` content entirely.

### Finding 6: Each chunk carries the full MiniMax envelope (bandwidth waste)

Every chunk includes `name: "MiniMax AI"`, `audio_content: ""`, `input_sensitive: false`, `output_sensitive: false`, `input_sensitive_type: 0`, `output_sensitive_type: 0` — even though these don't change. Real OpenAI streaming sends only the deltas that changed.

**Implication**: bandwidth/parsing overhead. For a 12-chunk stream (S2), the redundant fields probably account for ~30% of stream bytes. Negligible for low-volume use, real cost at scale.

### Finding 7: Standard OpenAI SSE protocol envelope

Each line is `data: {json}` followed by a blank line, terminated with `data: [DONE]`. No MiniMax-specific divergence at the protocol level. `object: "chat.completion.chunk"` matches OpenAI's chunk type. Standard SSE clients (e.g., `openai-python`'s streaming, Server-Sent-Events libraries in TS/Go) work without modification — only the chunk shape inside diverges.

## Open questions for follow-up

- **Does MiniMax support `stream_options: {include_usage: true}`?** Untested. If yes, that solves Finding 2 (usage in stream). If not, document as a hard limitation.
- **Reasoning chunk timing**: chunk count was 4 for S1 vs 12 for S2 over 1.5s vs 5.8s. Roughly ~2 chunks/sec independent of content length. Worth probing: is it a fixed timer (~500ms tick), or does it scale with token-rate? Affects perceived smoothness.
- **Mid-stream errors**: untested. What does the stream look like if the request 429s mid-flight, or if the server times out? Defer to T3.1/T3.2.
- **Streaming with `max_tokens` cap mid-reasoning**: untested but probably interesting — does the stream emit partial reasoning + finish_reason="length" before any visible content?

## Idiomatic patterns

### Basic streaming consumer (Python, with `<think>` hiding)

```python
import re

with client.chat.completions.create(
    model="MiniMax-M2.7-highspeed",
    messages=[...],
    max_tokens=4096,
    stream=True,
) as stream:
    buffer = ""
    visible_started = False
    for chunk in stream:
        delta = chunk.choices[0].delta.content or ""
        buffer += delta
        if not visible_started and "</think>" in buffer:
            _, visible_part = buffer.split("</think>", 1)
            print(visible_part.lstrip(), end="", flush=True)
            visible_started = True
            buffer = ""
        elif visible_started:
            print(delta, end="", flush=True)
        # finish_reason is on the LAST chunk
        if chunk.choices[0].finish_reason:
            break
```

### Why you might want non-streaming despite slower TTFB

- Need usage accounting (Finding 2)
- Reasoning trace itself is the product (e.g., debugging, observability)
- Output is short enough that the streaming win is small (S1: 2.5s total non-streaming vs 1s TTFB streaming — only ~1.5s saved)

### Why streaming is worth the friction

- Long output with high reasoning_tokens — streaming's TTFB ~1s vs non-streaming's potential 13-22s (iter-5 finding)
- Chat UX where partial output is better than spinner

## Provenance

| Probe | First chunk @ | Total | Chunks | finish_reason | trace-id (in fixture) |
| ----- | ------------- | ----- | ------ | ------------- | --------------------- |
| S1    | 1.04s         | 2.54s | 4      | stop          | (in fixture)          |
| S2    | 1.04s         | 6.88s | 12     | stop          | (in fixture)          |

Fixtures (each contains raw SSE lines + parsed events + accumulated content):

- [`fixtures/chat-completion-stream-S1-basic-stream-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-stream-S1-basic-stream-2026-04-28.json)
- [`fixtures/chat-completion-stream-S2-stream-stop-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-stream-S2-stream-stop-2026-04-28.json)

Verifier: autonomous-loop iter-8. 2 API calls.
