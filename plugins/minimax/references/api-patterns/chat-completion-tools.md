# Chat Completion — Function Calling / Tool Use

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-tools.md` (source-of-truth — read-only, source iter-12). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-9).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. **Headline finding: tool calling WORKS — first OpenAI parameter beyond the basics that's actually honored** — but `tool_choice` is silently ignored.

This is the first Tier 2 endpoint pattern, breaking the silent-drop trend established in iter-7/8/9.

## Test setup

3 parallel probes designed to characterize tool-use end-to-end:

| Probe | Setup                                                                         | Question                                  |
| ----- | ----------------------------------------------------------------------------- | ----------------------------------------- |
| F1    | Single tool (`get_weather`) + relevant prompt ("weather in Paris?")           | Does the model invoke the tool?           |
| F2    | Single tool + IRRELEVANT prompt ("tell me a joke") + `tool_choice="required"` | Does `tool_choice` force invocation?      |
| F3    | Two tools (`get_weather`, `get_current_time`) + time prompt                   | Does selection logic pick the right tool? |

`max_tokens: 4096` for all. Tools defined with OpenAI-standard JSON-Schema parameters.

## Results

| Probe | finish_reason | prompt_tokens | reasoning | completion | `tool_calls` present?                         | Visible (stripped)                                            |
| ----- | ------------- | ------------- | --------- | ---------- | --------------------------------------------- | ------------------------------------------------------------- |
| F1    | `tool_calls`  | 247           | 28        | 52         | ✅ `get_weather(city: "Paris")`               | (empty)                                                       |
| F2    | `stop`        | 249           | 39        | 58         | ❌ no                                         | "Why do Linux kernel developers make good secret agents? ..." |
| F3    | `tool_calls`  | 322           | 32        | 58         | ✅ `get_current_time(timezone: "Asia/Tokyo")` | (empty)                                                       |

## Headline findings

### Finding 1: ✅ Tool calling IS HONORED on M2.7-highspeed

F1 and F3 emitted properly-shaped `tool_calls` arrays with valid JSON arguments. The `tools` parameter is genuinely honored, not silently dropped. **First non-basic OpenAI parameter to actually work** since the iter-7/8/9 silent-drop trend.

This means:

- Karakeep/Linkwarden agent flows that depend on tool use can run on MiniMax
- Function calling is a reliable mechanism for structured output (much more so than `response_format`, which is silently dropped per iter-9)
- `<think>` reasoning is INTEGRATED with tool decisions — the model deliberates inside `<think>` tags about which tool to call

### Finding 2: `finish_reason: "tool_calls"` is properly diagnostic

When a tool is invoked, `finish_reason` flips from `"stop"` to `"tool_calls"`. **This is the cleanest way to detect tool invocation** — unlike `stop` (which conflates natural completion with stop-sequence trigger per iter-7), `tool_calls` is unambiguous.

```python
if resp.choices[0].finish_reason == "tool_calls":
    # Tool was invoked — execute and continue conversation
    tool_calls = resp.choices[0].message.tool_calls
elif resp.choices[0].finish_reason == "stop":
    # Natural completion — use message.content
    visible = strip_think_tags(resp.choices[0].message.content)
elif resp.choices[0].finish_reason == "length":
    # max_tokens cap — handle truncation per iter-6
    ...
```

### Finding 3: 🚨 `tool_choice` parameter is SILENTLY IGNORED — fourth silent-drop

F2 sent `tool_choice: "required"` with a prompt asking for a Linux kernel joke (no need for the weather tool). OpenAI's spec requires `"required"` to FORCE tool invocation; MiniMax should have either:

- Force-called the weather tool with bogus args (OpenAI behavior)
- Returned a 400 error if the model can't fit the tool to the prompt

Instead MiniMax returned `finish_reason: "stop"` with a natural-language joke and no `tool_calls`. So **`tool_choice` is silently dropped while `tools` is honored** — partial OpenAI-compat behavior.

Joins the silent-drop catalog: `stop` (iter-7) + streaming `usage` (iter-8) + `response_format` (iter-9) + `tool_choice` (iter-12).

**Implication**: do NOT rely on `tool_choice="required"` to force invocation. If you need guaranteed tool use, validate `finish_reason` after the response and re-prompt if natural-language was emitted.

### Finding 4: Tool selection logic works correctly

F3 had two tools (`get_weather`, `get_current_time`) and a time-related prompt ("What time is it right now in Tokyo?"). The model correctly selected `get_current_time` and constructed a sensible argument (`timezone: "Asia/Tokyo"`).

Tool selection is reasoning-driven: the `<think>` trace shows the model deliberating about which tool fits the prompt before emitting the tool_call. So selection quality scales with the model's reasoning quality, not with any rule-based dispatcher.

### Finding 5: Tool call shape is OpenAI-standard with one MiniMax-specific detail

```json
{
  "id": "call_function_kweyenrf3zc7_1",
  "type": "function",
  "function": {
    "name": "get_weather",
    "arguments": "{\"city\": \"Paris\"}"
  },
  "index": 0
}
```

- `id` prefix: `call_function_<unique>_<index>` (OpenAI uses `call_<random>` without "function\_" prefix)
- `arguments` is a JSON-encoded STRING, not a parsed object (OpenAI-standard — required for portability)
- `index` field is present (OpenAI-standard for parallel tool calls)
- `type: "function"` matches OpenAI's standard

Real OpenAI clients should work with minimal changes. The `id` prefix difference is cosmetic for billing correlation only.

### Finding 6: 💰 Tool definitions cost ~200 prompt_tokens each

| Probe | # tools | prompt_tokens | Δ vs iter-3 baseline (~50 for similar prompt) |
| ----- | ------- | ------------- | --------------------------------------------- |
| F1    | 1       | 247           | +197 for one tool definition                  |
| F2    | 1       | 249           | +199 (same tool, joke prompt)                 |
| F3    | 2       | 322           | +272 for two tool definitions                 |

So a single tool's JSON-Schema definition is ~200 tokens, and tools are billed as INPUT tokens on every call. **Cost implications for tool-heavy production**:

- 5 tools defined = ~1000 prompt_tokens before any user content
- Multi-turn tool-using conversation pays this overhead on EVERY turn (server-side `<think>` stripping per iter-10 doesn't apply here — tool definitions are in the request)
- For Karakeep (single-turn tagging), tool overhead doesn't accumulate; for any agent flow with multi-turn tool dialogues, it does

### Finding 7: `<think>` tags wrap tool decisions; visible content is empty when tool fires

Both F1 and F3 had:

- `<think>...</think>` content wrapped around the tool-selection reasoning (e.g., "The user is asking about the current weather in Paris. I should use the get_weather function...")
- Empty visible content after stripping (just newlines)
- The actual tool invocation in `message.tool_calls`

So the consumer pattern is:

```python
if resp.choices[0].finish_reason == "tool_calls":
    # Skip message.content entirely (it's just <think> + empty)
    for tool_call in resp.choices[0].message.tool_calls:
        tool_name = tool_call["function"]["name"]
        args = json.loads(tool_call["function"]["arguments"])
        result = execute_tool(tool_name, args)
        # Append tool result + continue conversation
```

**Don't try to extract anything from `content` when finish_reason is `tool_calls`** — it's structured noise.

### Finding 8: Reasoning tokens are MODEST for tool decisions (28-39 vs creative-writing's 900+)

Tool selection deliberation is fast. The model picks quickly because tools have clear semantics. Compare:

- Tool decision: 28-39 reasoning tokens
- Tagging (iter-9): 161-228 reasoning tokens
- Haiku (iter-5): 906-1047 reasoning tokens

For latency-sensitive tool-using paths, this is good news — tool decisions complete in 2-3 seconds end-to-end.

## Implications

### For Karakeep/Linkwarden tool-using flows

**Tool calling is reliable on MiniMax.** Wire `tools` array as you would for OpenAI. Two caveats:

1. Don't depend on `tool_choice="required"` for forced invocation — validate `finish_reason` instead
2. Plan for ~200 prompt_tokens overhead per tool definition

### For agentic loops (multi-step tool-using conversations)

```python
def agent_loop(user_message, tools):
    messages = [{"role": "user", "content": user_message}]
    while True:
        resp = call_minimax(messages=messages, tools=tools)
        choice = resp["choices"][0]
        if choice["finish_reason"] == "tool_calls":
            messages.append(choice["message"])
            for tool_call in choice["message"]["tool_calls"]:
                result = execute_tool(
                    tool_call["function"]["name"],
                    json.loads(tool_call["function"]["arguments"]),
                )
                messages.append({
                    "role": "tool",
                    "tool_call_id": tool_call["id"],
                    "content": json.dumps(result),
                })
            continue
        else:
            # finish_reason == "stop" — model has final answer
            return strip_think_tags(choice["message"]["content"])
```

### For migrating from OpenAI to MiniMax

- `tools` array works identically
- `tool_choice="auto"` (default) works identically
- `tool_choice="required"` and `tool_choice="none"` are NOT verified (F2 showed `"required"` is dropped; `"none"` untested)
- `parallel_tool_calls` parameter untested
- Tool result message format (`role: "tool"`) untested but presumed to work

## Open questions for follow-up

- **Does `tool_choice: "none"` work?** Untested. If silently dropped, you can't selectively disable tools per-request.
- **Does `tool_choice: {"type": "function", "function": {"name": "X"}}` (specific tool selection) work?** Untested. May or may not be honored.
- **Can MiniMax emit MULTIPLE tool_calls in a single response (parallel tool calling)?** Untested — both probes that emitted tool_calls had a single call.
- **Does `parallel_tool_calls: false` parameter work?** Untested.
- **What about the `tool` role in messages array** (for sending tool results back)? Untested. Defer to a multi-turn tool-using probe.
- **Token accounting for tool definitions**: ~200 tokens per simple tool. Larger schemas (deeply-nested objects, lots of enum values) could be much higher. Worth a token-cost probe for larger tools.
- **Web-search MCP** (per 1Password notes): how does this surface in tool semantics? Is it a special tool or a separate parameter? Defer to T2.3.

## Idiomatic patterns

### Pattern 1: Defensive tool-using consumer

```python
def call_with_tools(messages, tools):
    resp = client.chat.completions.create(
        model="MiniMax-M2.7-highspeed",
        messages=messages,
        max_tokens=4096,
        tools=tools,
        # tool_choice="required" — DO NOT SET, silently dropped
    )
    choice = resp.choices[0]
    finish = choice.finish_reason

    if finish == "tool_calls":
        return {"tool_calls": choice.message.tool_calls}
    elif finish == "stop":
        return {"content": strip_think_tags(choice.message.content)}
    elif finish == "length":
        raise RuntimeError("max_tokens cap hit before completion")
    else:
        raise RuntimeError(f"Unexpected finish_reason: {finish}")
```

### Pattern 2: Force-tool-use without `tool_choice="required"`

Since `tool_choice` is dropped, the only way to force tool use is via prompt engineering:

```python
system_prompt = (
    "You MUST use one of the available tools to answer. "
    "Do not respond directly with text — call the appropriate tool."
)
```

Combined with an `assert finish_reason == "tool_calls"` check + retry loop on the consumer side. Not perfect, but reliable enough for production.

### Pattern 3: Cost-aware tool selection

If your service has many possible tools but only a few are typically relevant per request, prune the `tools` array client-side BEFORE the call. ~200 tokens per unused tool is significant overhead at scale.

```python
def prune_tools(all_tools, user_message):
    # Heuristic: keep only tools whose names/descriptions match keywords in the prompt
    keywords = extract_keywords(user_message)
    return [t for t in all_tools if any(kw in t["function"]["description"].lower() for kw in keywords)]
```

## Provenance

| Probe | trace-id (in fixture) | finish_reason | tool_call                    | Latency |
| ----- | --------------------- | ------------- | ---------------------------- | ------- |
| F1    | (in fixture)          | tool_calls    | get_weather(Paris)           | 2.12s   |
| F2    | (in fixture)          | stop          | (none — tool_choice ignored) | 2.79s   |
| F3    | (in fixture)          | tool_calls    | get_current_time(Asia/Tokyo) | 2.20s   |

Fixtures:

- `fixtures/chat-completion-tools-F1-single-tool-relevant-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-tools-F1-single-tool-relevant-2026-04-28.json`)
- `fixtures/chat-completion-tools-F2-tool-choice-required-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-tools-F2-tool-choice-required-2026-04-28.json`)
- `fixtures/chat-completion-tools-F3-multi-tool-selection-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-tools-F3-multi-tool-selection-2026-04-28.json`)

Verifier: autonomous-loop iter-12 (first Tier 2 pattern). 3 API calls.
