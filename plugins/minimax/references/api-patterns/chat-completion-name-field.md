# Chat Completion — `message.name` Field Oddity

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-name-field.md` (source-of-truth — read-only, source iter-20). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-9).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. **Headline finding: response `message.name` is a fixed brand string `"MiniMax AI"`, regardless of request input. The `name` field on request messages is silently accepted but does NOT customize identity, propagate into response, or affect model behavior.** This closes the campaign's investigation of the `name` field oddity first observed in iter-2.

This is the **6th silent-dropped parameter** in the campaign (after `stop`, streaming `usage`, `response_format`, `tool_choice`, `image_url`).

## Test setup

3 parallel probes covering the main customization vectors OpenAI supports:

| Probe | Request shape                                                 | Hypothesis                                           |
| ----- | ------------------------------------------------------------- | ---------------------------------------------------- |
| N1    | `{role: "user", name: "Alice", content: "Reply with: OK"}`    | Does request `name` affect identity or round-trip?   |
| N2    | Multi-turn with assistant turn `name: "CustomBot"`            | Does fabricated assistant name affect self-identity? |
| N3    | `{role: "user", name: "user_123", content: "Reply with: OK"}` | Does numeric-id style work and surface anywhere?     |

`max_tokens: 1024`, default temperature.

## Results

| Probe | http_status | Response `message.name` | Visible content | Tokens (p+c) |
| ----- | ----------- | ----------------------- | --------------- | ------------ |
| N1    | 200         | `"MiniMax AI"`          | `"OK"`          | 45+60        |
| N2    | 200         | `"MiniMax AI"`          | `"MiniMax"`     | 62+17        |
| N3    | 200         | `"MiniMax AI"`          | `"OK"`          | 45+38        |

All three probes returned `message.name = "MiniMax AI"` — **identical fixed brand string**. The request `name` field disappeared into the void.

## Headline findings

### Finding 1: 🚨 Response `message.name` is a FIXED brand string

`"MiniMax AI"` appears in every response regardless of:

- Request `name` field on user messages (N1, N3)
- Request `name` field on assistant messages in multi-turn (N2)
- Different content patterns

**This is brand metadata, not user data.** Clients should NOT try to interpret it as a customizable identity field. It's the API equivalent of `User-Agent: MiniMax-API/...` — informational, not actionable.

### Finding 2: N2 confirms model self-identity is brand-locked, not message-driven

The most diagnostic probe was N2: a multi-turn where the FAKE prior assistant turn was labeled `name: "CustomBot"` AND said `"Hi"`. When asked "What's your name? Reply in one word", the model answered **"MiniMax"** — NOT "CustomBot".

This means:

- Fabricated `name` on assistant turns does not influence the model's self-identity
- Model's persona is locked at `MiniMax AI` regardless of role-play scaffolding via `name`
- For persona/character apps, you MUST use system prompts (per iter-3 — those work) and even then, persona reasoning is expensive (iter-3 found persona doubles reasoning tokens)

### Finding 3: Request `name` is silently accepted (no 400 error)

Per the campaign's silent-drop pattern, OpenAI parameters that MiniMax doesn't honor still pass validation. Sending `name: "Alice"` on a user message returns HTTP 200 — no `2013 "invalid params"` error. The field is simply discarded.

### Finding 4: Joins the silent-drop catalog as the 6th confirmed-dropped parameter

| Parameter                  | Iter discovered | Behavior                                     |
| -------------------------- | --------------- | -------------------------------------------- |
| `stop`                     | iter-7          | Silently ignored                             |
| Streaming `usage`          | iter-8          | Always null in chunks                        |
| `response_format`          | iter-9          | Silently dropped (json_object/json_schema)   |
| `tool_choice`              | iter-12         | Silently dropped (`tools` itself is honored) |
| `image_url` content blocks | iter-13         | Silently dropped (capability-lacking)        |
| **`messages[].name`**      | **iter-20**     | **Silently dropped (this iter)**             |

The pattern is now 6/6: every OpenAI-spec parameter MiniMax doesn't fully implement gets HTTP 200 with silent omission, NOT HTTP 400. The taxonomy categories from iter-15 still hold:

- `name` falls into category 4 (pure control parameter, silently dropped)
- It does NOT trigger category 5 (strict 400 validation that web_search uses)

### Finding 5: For multi-user threading, MiniMax has NO native support

OpenAI's `messages[i].name` lets you distinguish multiple humans in a conversation:

```json
[
  { "role": "user", "name": "Alice", "content": "I think we should..." },
  { "role": "user", "name": "Bob", "content": "Disagree, here's why..." },
  { "role": "user", "name": "Alice", "content": "Fair point, but..." }
]
```

On MiniMax, all three messages would be merged into a single user-stream because `name` is dropped. **For multi-user apps on MiniMax, encode the speaker into content**:

```json
[
  { "role": "user", "content": "[Alice]: I think we should..." },
  { "role": "user", "content": "[Bob]: Disagree, here's why..." },
  { "role": "user", "content": "[Alice]: Fair point, but..." }
]
```

Crude but works.

## Implications

### For amonic services

amonic doesn't currently have multi-user thread requirements. If a future service does (e.g., a group-chat assistant), this finding constrains the design to content-level speaker tagging.

### For migration from OpenAI

Code that uses `messages[].name`:

- For multi-user disambiguation: WILL silently break on MiniMax. The model can't see speaker boundaries. Refactor to content-prefix encoding.
- For tool/function call identification: typically tracked via `tool_call_id` (iter-12 confirmed `tool_calls` works); the `name` field of tool messages is separate.
- For assistant identity / persona: never worked anyway; use system prompts.

### For client-side handling

Don't store `message.name` from MiniMax responses as if it were user data. It's always `"MiniMax AI"`. If your storage layer cares about speaker identity, derive from `role` instead.

## Idiomatic patterns

### Pattern: Multi-user content encoding (MiniMax-safe)

```python
def format_multi_user_message(speaker: str, content: str) -> dict:
    """Format a user message with speaker tag in content (MiniMax-compatible)."""
    return {
        "role": "user",
        "content": f"[{speaker}]: {content}",
        # Don't bother with `name` — silently dropped
    }
```

### Pattern: Defensive name handling

```python
def get_assistant_identity(resp: dict) -> str:
    """Extract assistant identity, ignoring MiniMax's brand-locked name."""
    # message.name is always "MiniMax AI" — useless
    # Return role instead, or fall back to model
    return resp.get("model") or resp["choices"][0]["message"]["role"]
```

## Open questions for follow-up

- **Does `name` on the `tool` role get honored?** Untested. Tool-call messages have a different `name` semantics in OpenAI (matching the called function). Worth a probe in T3.x if multi-tool-call workflows surface.
- **What if the model is explicitly persona-instructed via system prompt to identify as a different name?** iter-3 showed persona prompts work — would the response `message.name` change, or stay `"MiniMax AI"`? Strong hypothesis is "stay" since the field is brand metadata.

## Provenance

| Probe | trace-id (in fixture) | http_status | message.name returned | Visible   | Tokens (p+c) |
| ----- | --------------------- | ----------- | --------------------- | --------- | ------------ |
| N1    | (in fixture)          | 200         | `"MiniMax AI"`        | "OK"      | 45+60        |
| N2    | (in fixture)          | 200         | `"MiniMax AI"`        | "MiniMax" | 62+17        |
| N3    | (in fixture)          | 200         | `"MiniMax AI"`        | "OK"      | 45+38        |

Fixtures:

- `fixtures/chat-completion-name-field-N1-user-name-Alice-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-name-field-N1-user-name-Alice-2026-04-28.json`)
- `fixtures/chat-completion-name-field-N2-assistant-name-CustomBot-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-name-field-N2-assistant-name-CustomBot-2026-04-28.json`)
- `fixtures/chat-completion-name-field-N3-user-name-user_123-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-name-field-N3-user-name-user_123-2026-04-28.json`)

Verifier: autonomous-loop iter-20 (closes Tier 2). 3 API calls.
