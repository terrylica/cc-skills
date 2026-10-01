# Chat Completion — Web-Search MCP Discovery

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/web-search.md` (source-of-truth — read-only, source iter-14). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-9).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed` (and plain `MiniMax-M2.7` for disambiguation). **Headline finding: built-in `web_search` tool type is NOT SUPPORTED on the chat-completions endpoint for either M2.7 model** — first 400 error in the campaign across 14 iterations of probing. Workaround: custom-function tools (per iter-12) work fine.

## Test setup

4 probes total:

| Probe | Setup                                                          | Model                      | Question                                                |
| ----- | -------------------------------------------------------------- | -------------------------- | ------------------------------------------------------- |
| W1    | `tools: [{"type": "web_search"}]` (OpenAI built-in style)      | `MiniMax-M2.7-highspeed`   | Does MiniMax recognize this tool type?                  |
| W2    | `tools: [{"type": "web_search_preview"}]` (alternative naming) | `MiniMax-M2.7-highspeed`   | Test alternative type name                              |
| W3    | No tools (baseline)                                            | `MiniMax-M2.7-highspeed`   | What does the model say without web access?             |
| W4    | `tools: [{"type": "web_search"}]` (same as W1)                 | **`MiniMax-M2.7`** (plain) | Disambiguate — is gating model-specific or cross-model? |

All used the prompt: "What is the current temperature in Paris, France right now? I need today's actual current value."

## Results

### W1: built-in `web_search` on M2.7-highspeed → **HTTP 400**

```json
{
  "type": "error",
  "error": {
    "type": "bad_request_error",
    "message": "invalid params, web_search is not support (2013)",
    "http_code": "400"
  }
}
```

**First 400 error in the campaign across 14 iterations.** All prior unsupported-parameter probes (iter-7 through iter-13) returned HTTP 200 with silent drops. This is a meaningful exception to the silent-drop pattern.

### W2: built-in `web_search_preview` on M2.7-highspeed → **HTTP 400**

```json
{
  "type": "error",
  "error": {
    "type": "bad_request_error",
    "message": "invalid params, invalid tool type: web_search_preview (2013)",
    "http_code": "400"
  }
}
```

**Different error message wording** vs W1: "invalid tool type" vs "is not support". This suggests:

- `web_search` is a known, tracked feature name internally (just disabled/unavailable)
- `web_search_preview` is genuinely unrecognized

Both share error code `(2013)` — likely the generic "invalid params" code.

### W3: baseline (no tools) → HTTP 200, polite refusal

```
"I'm sorry, but I don't have access to real-time weather information,
so I can't give you the current temperature in Paris right now. You can
check the current conditions on a weather-service site (e.g.,
weather.com, accuweather.com, or the French Météo-France website) or by
searching 'Paris temperature now' in your browser."
```

482 reasoning_tokens spent on this answer. Model is honest about its limitations and suggests external resources. **Doesn't hallucinate** — good UX baseline.

### W4: built-in `web_search` on plain `MiniMax-M2.7` → **HTTP 400 (same error)**

```
"invalid params, web_search is not support (2013)"
```

Identical error to W1. **Gating is cross-model**, not specific to the highspeed variant.

## Headline findings

### Finding 1: 🆕 First 400 error in the campaign — silent-drop pattern has an exception

Across iter-7 through iter-13, MiniMax returned HTTP 200 for SIX distinct unsupported scenarios (`stop`, streaming `usage`, `response_format`, `tool_choice`, `image_url`, etc.). iter-14's `tools[].type` validation is the first parameter that returns proper 400 errors.

**Refines the campaign taxonomy** — there's now a 4th category alongside silent-drop variants:

- **400-validated parameters** — strict enum, returns informative error (with internal code 2013)

The `tool.type` enum is strictly validated — only certain types are recognized. Compare to `tool_choice` (silently dropped per iter-12) — interesting asymmetry within the tools system itself.

### Finding 2: `web_search` is recognized as a feature name (not just an unknown string)

W1's error wording ("web_search is not support") differs from W2's ("invalid tool type: web_search_preview"). MiniMax's validator clearly distinguishes:

- **Known but disabled**: `web_search` → "is not support"
- **Unknown type**: `web_search_preview` → "invalid tool type: ..."

This strongly suggests **MiniMax has the `web_search` capability somewhere** in their product (per the 1Password notes), but it's not enabled for:

- Either of the M2.7 models (M2.7 + M2.7-highspeed both 400)
- The user's plan tier ("Plus – High-Speed")
- The chat-completions endpoint (might be on a separate endpoint)
- Or it's announced but not yet deployed

Without docs access or a higher plan tier, we can't determine which.

### Finding 3: Cross-model gating, not model-specific

W1 (M2.7-highspeed) and W4 (plain M2.7) returned IDENTICAL errors. So `web_search` support is gated at a higher layer than per-model. Likely candidates:

- Plan tier (need Pro/Enterprise instead of Plus)
- Endpoint (separate `/v1/web-search/...` or MCP server endpoint)
- Feature deployment status

### Finding 4: M2.7 baseline behavior is HONEST about limitations

Without web-search (W3), M2.7 doesn't hallucinate weather data — it explicitly says "I don't have access to real-time weather information" and suggests external resources. Good production behavior. This is in contrast to vision (iter-13) where the model also said "no image provided" — both modalities have honest-refusal patterns when missing.

### Finding 5: Custom-function tools (iter-12) provide a workaround

Per iter-12, user-defined `tools: [{"type": "function", "function": {...}}]` is honored. Production code can implement its own web-search by:

1. Defining a `search_web(query)` function tool
2. When the model calls it, the consumer executes the search (DuckDuckGo, Tavily, Bing Search API, custom scraper)
3. Return results to the model as `{role: "tool", content: ...}`

This works on M2.7-highspeed today and matches iter-12's verified agent-loop pattern.

## Implications

### For Karakeep / Linkwarden grounded-tagging features

If you want the LLM to ground its tags/summaries in current web content:

- **Cannot use built-in `web_search` on M2.7** — 400 errors
- **Use custom-function tools instead** — implement search via your own provider (Tavily, Bing Search API, etc.) and pass results to MiniMax via the standard agent-loop pattern from iter-12
- Or: **pre-fetch web content client-side** and pass as context in `messages` — simpler if you don't need agentic search

### For migration testing

The strict 400 validation for tool types is a **migration safety net** — if you accidentally try to use OpenAI's built-in `web_search` on MiniMax, you'll get a clear error rather than silent malfunction. This is better than the silent-drop pattern of other parameters.

Add to migration test suite:

```python
def test_built_in_web_search_works_on_minimax():
    try:
        resp = client.chat.completions.create(
            model="MiniMax-M2.7-highspeed",
            messages=[{"role": "user", "content": "What's the news today?"}],
            tools=[{"type": "web_search"}],
        )
        # If we get here, web_search is now supported — celebrate
    except APIError as e:
        if "web_search is not support" in str(e):
            # Expected as of 2026-04-29 — implement custom function tool instead
            pass
```

### For the broader OpenAI-compat picture

iter-14 shows MiniMax has selective strict validation:

- **`tool.type` enum**: STRICT (400 on unknown values)
- **Top-level params** (`stop`, `response_format`, `tool_choice`, `image_url` content blocks): SILENT DROPS

This asymmetry matters for production: you can't rely on getting 400 errors for misconfiguration. Continue behavior-testing every parameter you depend on.

## Idiomatic patterns

### Pattern: Custom-function web-search via Tavily

```python
from tavily import TavilyClient

tavily = TavilyClient(api_key=os.environ["TAVILY_API_KEY"])

WEB_SEARCH_TOOL = {
    "type": "function",
    "function": {
        "name": "search_web",
        "description": "Search the web for current information about a topic.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query"},
            },
            "required": ["query"],
        },
    },
}

def execute_search_web(args: dict) -> str:
    results = tavily.search(args["query"], max_results=5)
    return json.dumps([{"title": r["title"], "snippet": r["content"][:300], "url": r["url"]} for r in results["results"]])

# Standard agent loop from iter-12 / chat-completion-tools.md applies
```

### Pattern: Pre-fetched context (simpler, no agent loop)

```python
def grounded_tag(content_url: str) -> list[str]:
    # Fetch the web page client-side
    page_text = requests.get(content_url, timeout=10).text
    # Strip HTML to plain text
    plain = strip_html_tags(page_text)[:8000]  # cap context size

    resp = client.chat.completions.create(
        model="MiniMax-M2.7-highspeed",
        messages=[
            {"role": "system", "content": "Generate 3-5 lowercase tags for this page. Output only a JSON array."},
            {"role": "user", "content": plain},
        ],
        max_tokens=1024,
    )
    return json.loads(strip_think_tags(resp.choices[0].message.content))
```

This is what Karakeep currently does — server-side scraping + LLM tagging. Doesn't need agentic search.

## Open questions for follow-up

- **Does MiniMax have a higher-tier plan that enables `web_search`?** Their pricing page would say. Worth checking docs.
- **Is there a separate `/v1/web-search/...` endpoint?** Untested. Would be a CAPABILITY-as-endpoint pattern (different from CAPABILITY-as-tool-type).
- **Does the MiniMax developer console expose any tool-type catalog?** If so, that's the source of truth for valid `tool.type` values.
- **Are there other built-in tool types we should test?** E.g., `code_interpreter`, `file_search`, `image_generation` — OpenAI's built-in tools. Each would either 400 or silently drop or work.

## Provenance

| Probe | trace-id (in fixture) | http_status | Behavior                                       | Latency |
| ----- | --------------------- | ----------- | ---------------------------------------------- | ------- |
| W1    | `064091727a64e888...` | 400         | "web_search is not support (2013)"             | 0.33s   |
| W2    | `064091721722f9c4...` | 400         | "invalid tool type: web_search_preview (2013)" | 0.33s   |
| W3    | (in fixture)          | 200         | Polite refusal, suggests external sites        | 12.83s  |
| W4    | `064091bcdc01fc89...` | 400         | Same as W1 (cross-model gating confirmed)      | 1.34s   |

Fixtures:

- `fixtures/chat-completion-websearch-W1-built-in-web-search-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-websearch-W1-built-in-web-search-2026-04-28.json`)
- `fixtures/chat-completion-websearch-W2-web-search-preview-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-websearch-W2-web-search-preview-2026-04-28.json`)
- `fixtures/chat-completion-websearch-W3-baseline-no-tools-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-websearch-W3-baseline-no-tools-2026-04-28.json`)
- `fixtures/chat-completion-websearch-W4-plain-m27-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-websearch-W4-plain-m27-2026-04-28.json`)

Verifier: autonomous-loop iter-14. 4 API calls.
