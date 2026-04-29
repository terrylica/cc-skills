# Chat Completion — Multi-Turn Conversation State

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-multi-turn.md` (source-of-truth — read-only, source iter-4). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-8).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. Tests whether MiniMax stores conversation state server-side or relies entirely on the messages array per request.

## Test setup

| Variant | Messages                                                                             |
| ------- | ------------------------------------------------------------------------------------ |
| E1      | `[user: "Pick a random number 1-100..."]`                                            |
| E2      | `[user: <same>, assistant: "42" (FABRICATED), user: "What number did you give me?"]` |

The trick: between E1 and E2, **fabricate** the assistant turn with "42" (deliberately different from whatever E1's actual model output was). If the model has session-level memory, it will reference E1's real output. If state is request-only, it will trust the messages array and echo "42".

## Results

| Probe                         | Visible output            | Verdict                         |
| ----------------------------- | ------------------------- | ------------------------------- |
| E1                            | "47" (a real random pick) | Baseline                        |
| E2 (fabricated "42" injected) | **"42"**                  | ✅ State is fully request-based |

**Conclusion: MiniMax has NO server-side conversation memory.** The model trusts whatever's in the `messages` array — including fabricated history. Standard OpenAI-compatible stateless behavior.

## Implications

### For consumers (Karakeep, Linkwarden, future amonic services)

1. **You are responsible for conversation history.** Store every turn client-side; replay as `messages` array on each request.
2. **`x-session-id` and `x-mm-request-id` headers are tracing identifiers, not state tokens.** Don't try to use them for "session resumption" — there's no such thing.
3. **You can rewrite history.** If you want to "undo" a bad assistant turn, just drop it from the messages array — the model can't tell.
4. **You can inject false context.** Useful for testing, jailbreak resilience research, or providing few-shot examples that look like prior conversation.

### For cost modeling

Multi-turn requests pay for the FULL message array each time:

- Turn 1: prompt = N tokens
- Turn 2: prompt = N + assistant1 + user2 tokens (whole thing re-sent)
- Turn 3: prompt = N + assistant1 + user2 + assistant2 + user3 (whole thing re-sent)

Long conversations get expensive linearly. **For tagging/summarization use cases, prefer single-turn requests** — don't accumulate context unless you actually need it.

### Alternative: state-bearing modes (untested for MiniMax)

OpenAI has the Assistants API (server-side threads). Anthropic has prompt caching via `cache_control`. **MiniMax may have similar mechanisms** based on the `cache-read(Text API)` consumption type observed in the billing UI. Currently unprobed — see T4.1 / T4.2 in queue.

If MiniMax does support cache-based context reuse, that would change cost analysis significantly for multi-turn chat. Not yet known.

## Probe data: prompt_tokens scaling for user/assistant turns

This iter ALSO confirmed (against iter-3's anomaly) that **user and assistant role turns add tokens roughly proportional to content**:

| Setup                                                     | prompt_tokens  | Δ vs single-turn       |
| --------------------------------------------------------- | -------------- | ---------------------- |
| Single user turn ("Pick a random number...")              | 50 (iter-2)    | baseline               |
| Single user turn (different content, "capital of France") | 48 (iter-3 E2) | -2 (different content) |
| Multi-turn: user + fabricated assistant + new user        | 88 (iter-4 E2) | +38                    |

The +38 increase covers the fabricated `assistant: "42"` (~5 tokens with framing) + the new user message "What number did you give me? Repeat it back exactly, no other text." (~33 tokens with framing). Roughly proportional to visible content.

**Contrast with iter-3 system role**: ~25-token system message → only +2 prompt_tokens. The anomaly is system-role-specific. T3.10 reproducer plan should confirm this with a deliberately-LONG system prompt.

## Idiomatic patterns

### Continuing a conversation

```python
messages = [
    {"role": "system", "content": system_prompt},
    {"role": "user", "content": "first question"},
    {"role": "assistant", "content": "first answer"},   # captured from prior response
    {"role": "user", "content": "follow-up question"},
]
# send → get answer → append to messages → repeat
```

### Resetting the conversation

Just start with a fresh `messages` array. No "session close" call needed.

### Few-shot prompting via fake conversation

Since MiniMax can't tell real history from fabricated, you can prime the model with synthetic examples:

```python
messages = [
    {"role": "system", "content": "You generate concise tags."},
    {"role": "user", "content": "Page about Linux kernel scheduling"},
    {"role": "assistant", "content": "linux, kernel, scheduling, systems, performance"},
    {"role": "user", "content": "Page about Mediterranean cooking"},
    {"role": "assistant", "content": "cooking, mediterranean, food, recipes, lifestyle"},
    # ... real query:
    {"role": "user", "content": "<actual page content>"},
]
```

Effective for getting MiniMax into a consistent output format faster than long instructional system prompts (which we saw in iter-3 cause expensive reasoning overhead).

### Trimming long histories

For long-running chats, trim the oldest turns when context window pressure builds. Keep the system prompt + the last N turns. The "context window boundary" is documented in T3.3 (untested yet).

## Provenance

| Probe                                     | trace-id                           | Visible output | Latency |
| ----------------------------------------- | ---------------------------------- | -------------- | ------- |
| E1 (single turn)                          | `cefc4f2b745ca3f79a9e45b0c04c5286` | "47"           | 4.4s    |
| E2 (multi-turn with fabricated assistant) | (in fixture)                       | "42"           | 1.8s    |

Fixtures:

- [`fixtures/chat-completion-multi-turn-1-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-multi-turn-1-2026-04-28.json)
- [`fixtures/chat-completion-multi-turn-2-fabricated-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-multi-turn-2-fabricated-2026-04-28.json)

Verifier: autonomous-loop iter-4.
