# Chat Completion — `response_format` (JSON Mode + Structured Outputs)

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-json.md` (source-of-truth — read-only, source iter-9). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-8).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. Probes the OpenAI-compatible `response_format` parameter in three modes (`json_object`, `json_schema`, baseline) plus a definitive disambiguating probe. **Headline finding: `response_format` is silently dropped on MiniMax — but explicit prompt engineering produces clean JSON anyway.**

## Test setup

4 probes total: 3 parallel + 1 disambiguating follow-up.

| Probe | Prompt requests JSON? | `response_format`                       | Question                                            |
| ----- | --------------------- | --------------------------------------- | --------------------------------------------------- |
| J1    | ✅ Yes (explicit)     | none (baseline)                         | Default output format when prompt is explicit       |
| J2    | ✅ Yes (explicit)     | `{"type": "json_object"}`               | Does json_object give different/better output?      |
| J3    | ✅ Yes (explicit)     | `{"type": "json_schema", strict: true}` | Does the strict schema mode work?                   |
| J4    | ❌ No (asks for joke) | `{"type": "json_object"}`               | **Definitive**: is the parameter actually enforced? |

`max_tokens: 4096` for all probes. Default temperature/top_p.

## Results

### J1-J3 (prompt explicitly requests JSON)

| Probe | finish_reason | reasoning_tokens | completion_tokens | Visible output                             | Valid JSON? |
| ----- | ------------- | ---------------- | ----------------- | ------------------------------------------ | ----------- |
| J1    | stop          | 191              | 202               | `{"tags":["linux","kernel","scheduling"]}` | ✅          |
| J2    | stop          | 161              | 172               | `{"tags":["linux","kernel","scheduling"]}` | ✅          |
| J3    | stop          | 228              | 238               | `{"tags":["linux","kernel","scheduler"]}`  | ✅          |

All three returned valid JSON. The visible outputs are nearly identical except J3 used "scheduler" instead of "scheduling" (likely sampling variance).

### J4 (prompt does NOT request JSON, `response_format=json_object` set)

```
prompt: "Tell me a one-line joke about Linux kernels. Just the joke, nothing else."
response_format: {"type": "json_object"}
```

**Output**: `"The Linux kernel walked into a bar, ordered a byte, and said, "Just keep the stack overflow to a minimum.""`

- HTTP 200 (no validation error)
- `finish_reason: stop`
- Output is plain natural-language text — **NOT JSON**
- `json.loads(visible)` raises `JSONDecodeError`

## Headline findings

### Finding 1: 🚨 `response_format` is silently dropped on MiniMax M2.7-highspeed

J4 is the smoking gun. When the prompt asks for a joke and `response_format=json_object` is set, MiniMax should either:

- (OpenAI-strict): return HTTP 400 with "messages must contain the word 'json'"
- (Honored): return a JSON-formatted joke like `{"joke": "..."}`

Instead MiniMax returned HTTP 200 + a plain-text joke. The parameter has **no enforcement effect** when the prompt doesn't already drive JSON output.

This adds `response_format` to the list of OpenAI-compat parameters silently dropped on MiniMax (alongside `stop` from iter-7 and `usage` in streaming from iter-8).

### Finding 2: Explicit prompt instructions DO produce clean JSON (no `response_format` needed)

J1 (no `response_format` but with explicit prompt) returned `{"tags":["linux","kernel","scheduling"]}` — clean, parseable, no markdown wrapping, no `<think>` tags in output (those are stripped on the client side).

So the production pattern that actually works on MiniMax:

```python
system_prompt = "Output ONLY a JSON object. No markdown. No explanation. No code fences."
user_prompt = "Tag this bookmark: <content>"
# Don't bother with response_format — use prompt engineering instead
```

For Karakeep/Linkwarden tagging, this is the recommended pattern.

### Finding 3: Reasoning tokens varied across modes (191 / 161 / 228) — possible hint-level effect

J1: 191 reasoning tokens; J2 (json_object): 161; J3 (json_schema): 228.

If `response_format` were fully ignored, you'd expect random sampling variance. But:

- J2 used **15% fewer** reasoning tokens than J1
- J3 used **20% more** reasoning tokens than J1

Possible interpretation: the parameter might be partially injected into the model's context as a hint (reducing reasoning when the format is "obvious", increasing it when a schema must be considered) — without ENFORCING the output format server-side. This would mean response_format has a _hint_ effect but no _guarantee_ effect.

Alternative interpretation: just sampling variance (iter-5 confirmed temp=0 isn't deterministic on M-series). Three samples isn't enough to distinguish.

**Open follow-up**: run the same probe N=5 times each with/without response_format and compare reasoning_tokens distributions. If the means differ significantly, the parameter is a hint; if not, dropped.

### Finding 4: `json_schema` strict mode does NOT enforce schema either

J3 sent a strict schema requiring `tags: array of exactly 3 strings`. The response was `{"tags":["linux","kernel","scheduler"]}` — happens to satisfy the schema, but only because the prompt also requested 3 tags. There's no evidence of server-side schema validation.

If MiniMax were enforcing schema strictly, you'd expect:

- Either rejection of malformed responses (re-sampling internally)
- Or `finish_reason: content_filter` / `tool_calls` / similar
- Or an error in the response if the model can't satisfy the schema

J3 just returned `finish_reason: stop` like the others. So `json_schema` is also dropped.

### Finding 5: Default formatting habit confirmed: model wraps in JSON when explicitly asked

iter-3 found MiniMax defaults to Markdown + emoji formatting. J1 shows it WILL produce clean JSON if the prompt says "no markdown, no explanation, output ONLY JSON". So prompt engineering can override the default formatting habit reliably.

This is the saving grace: even though `response_format` is broken, prompt engineering works.

## Implications

### For Karakeep / Linkwarden tagging

**Don't use `response_format`.** It's silently dropped. Instead:

```yaml
# Karakeep INFERENCE_TEXT_PROMPT (or system message)
system: |
  You generate concise tags for bookmarked content. Output ONLY a JSON
  object with key "tags" mapping to an array of 3-5 lowercase strings.
  No markdown, no code fences, no explanation. Example output format:
  {"tags": ["one", "two", "three"]}
```

Then on the client side:

```python
resp = client.chat.completions.create(
    model="MiniMax-M2.7-highspeed",
    messages=[
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": page_content},
    ],
    max_tokens=2048,  # iter-5 floor for sentence answers
    # No response_format — silently dropped
)

content = resp.choices[0].message.content
visible = strip_think_tags(content)
try:
    tags_obj = json.loads(visible)
except json.JSONDecodeError:
    log.warning("MiniMax returned non-JSON; retrying with stricter prompt")
    # retry, or fall back to regex extraction
```

### For tools that auto-set `response_format` (e.g., Karakeep / Linkwarden's structured-output paths)

If the consuming application has a "structured outputs" code path that sets `response_format=json_schema` automatically when wired to OpenAI, that path will SILENTLY produce non-validated output on MiniMax. Need to check whether application tests cover this OR whether the prompt is independently strong enough.

### For migration testing

Add explicit assertions: "send a prompt that does NOT mention JSON, set response_format=json_object, expect HTTP 400 OR JSON output". If you get neither (HTTP 200 + natural language), you're hitting a silent-drop provider.

## Idiomatic patterns

### Pattern 1: Reliable JSON output via prompt engineering

```python
def get_json_response(content: str, schema_description: str) -> dict:
    system = (
        f"Output ONLY a JSON object matching this shape: {schema_description}. "
        f"No markdown. No code fences. No explanation. Just JSON."
    )
    resp = client.chat.completions.create(
        model="MiniMax-M2.7-highspeed",
        messages=[{"role": "system", "content": system},
                  {"role": "user", "content": content}],
        max_tokens=2048,
    )
    visible = strip_think_tags(resp.choices[0].message.content)
    return json.loads(visible)
```

### Pattern 2: With retry-on-parse-failure

```python
def get_json_with_retry(content: str, schema_description: str, max_retries: int = 2) -> dict:
    for attempt in range(max_retries + 1):
        try:
            return get_json_response(content, schema_description)
        except json.JSONDecodeError as e:
            if attempt == max_retries:
                raise
            log.warning(f"MiniMax JSON parse failed (attempt {attempt + 1}): {e}")
```

### Pattern 3: Few-shot priming for consistent format

Per iter-4 learning, fabricated assistant turns work as few-shot examples. For tagging, prepend 1-2 user/assistant pairs showing the desired JSON output — cheaper than persona system prompts and more reliable for format-critical use cases.

```python
messages = [
    {"role": "system", "content": "Output JSON only."},
    {"role": "user", "content": "Page about Python web frameworks"},
    {"role": "assistant", "content": '{"tags":["python","web","frameworks","django","flask"]}'},
    {"role": "user", "content": page_content_to_tag},
]
```

## Open questions for follow-up

- **Does `response_format` have a measurable hint-level effect?** Reasoning_tokens varied 191/161/228 across J1/J2/J3. Run N=5+ samples each with/without to determine if the means differ statistically. Promote to T3.x if useful.
- **Does the newer `response_format: {type:"json_schema", strict:true}` work on a different MiniMax model?** Tested only M2.7-highspeed. Maybe newer models will support it, but that's a future-proofing question.
- **What does MiniMax return for `response_format: {"type":"text"}`?** OpenAI's default; untested on MiniMax. Probably also a no-op.
- **Does explicit `tools` + `tool_choice` (T2.1) honor or silently drop?** Same generalization question. Defer to T2.1.

## Provenance

| Probe | trace-id (in fixture) | Visible output                              | finish_reason | reasoning | latency |
| ----- | --------------------- | ------------------------------------------- | ------------- | --------- | ------- |
| J1    | (in fixture)          | `{"tags":["linux","kernel","scheduling"]}`  | stop          | 191       | 4.59s   |
| J2    | (in fixture)          | `{"tags":["linux","kernel","scheduling"]}`  | stop          | 161       | 4.12s   |
| J3    | (in fixture)          | `{"tags":["linux","kernel","scheduler"]}`   | stop          | 228       | 5.51s   |
| J4    | (in fixture)          | natural-language joke (definitive non-JSON) | stop          | 871       | 20.51s  |

Fixtures:

- [`fixtures/chat-completion-jsonmode-J1-no-format-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-jsonmode-J1-no-format-2026-04-28.json)
- [`fixtures/chat-completion-jsonmode-J2-json-object-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-jsonmode-J2-json-object-2026-04-28.json)
- [`fixtures/chat-completion-jsonmode-J3-json-schema-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-jsonmode-J3-json-schema-2026-04-28.json)
- [`fixtures/chat-completion-jsonmode-J4-no-json-in-prompt-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-jsonmode-J4-no-json-in-prompt-2026-04-28.json)

Verifier: autonomous-loop iter-9. 4 API calls.
