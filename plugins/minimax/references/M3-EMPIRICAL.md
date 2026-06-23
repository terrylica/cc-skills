# MiniMax-M3 — Empirical Option / Capability Map

**Probed live 2026-06-01** on the same Plus-High-Speed key as the M2.7 campaign
(`https://api.minimax.io/v1`). This is the **evidence-first** companion to
[`../skills/minimax/SKILL.md`](../skills/minimax/SKILL.md) (M2.7) and the new
[`../skills/m3/SKILL.md`](../skills/m3/SKILL.md). Where the official docs and the live
API disagree, **the live API wins** — discrepancies are flagged explicitly below.

> **Re-verify, don't trust this file blindly.** Everything here is reproducible via the
> Bun CLI `scripts/m3-cli.ts`: `probe` (options/capabilities), `context-probe` (ceiling +
> retrieval), `bench` (speed/quality). Drift tripwire:
> `m3-cli.ts verify` diffs a fast live re-probe against
> `fixtures/m3-capabilities-locked-2026-06-23.json` and exits non-zero on change.

---

## TL;DR — what changed vs M2.7

| Dimension                | M2.7 / M2.7-highspeed                 | M3 (this key)                                                                                       |
| ------------------------ | ------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `<think>` in `content`   | yes, always strip                     | **yes by default** — _or_ set `reasoning_split:true` for clean                                      |
| Reasoning control        | none                                  | **rich**: `reasoning_split` / `reasoning` / `reasoning_effort`                                      |
| Vision (`image_url`)     | ❌ silently dropped (text-only)       | ✅ **works** — read text off a PNG correctly                                                        |
| `response_format`        | ❌ silently dropped                   | ✅ **accepted** (still wraps with `<think>`/fences — see caveat)                                    |
| `tool_choice`            | ❌ silently dropped                   | partial — `"none"` respected; **forced did not compel** a call                                      |
| `n > 1`                  | (untested)                            | ⚠️ **silently dropped** — accepted but ignored, still 1 choice (was `2013`-rejected pre-2026-06-23) |
| Output ceiling           | (max_tokens not enforced server-side) | ✅ **hard 524,288**; > 524288 → `invalid params … > 524288` (was 512,000 pre-2026-06-23)            |
| Input context            | ~200K                                 | **~1M** (to ~1,000,000; 1,048,576 → 2013) as of 2026-06-23 — but reliable retrieval ≤ ~256K         |
| Speed (default thinking) | ~40–50 TPS (highspeed)                | ~20–27 TPS — **slower unless thinking is reduced/disabled**                                         |

**Headline:** M3 is a **capability upgrade** (vision, structured-output acceptance,
clean-reasoning split, larger 512K context + bigger output cap) but is **slower by
default**. Speed parity with M2.7-highspeed comes from reducing/disabling thinking.

---

## 1. Thinking / reasoning control — the big new lever

All variants below were **accepted** (HTTP 200, no error) except `thinking:<bool>`.
Token/latency figures are from a single fixed reasoning prompt (`max_tokens=2048`, `temp=0.2`).

| Setting (request body)                      | Effect (measured)                                                                 |
| ------------------------------------------- | --------------------------------------------------------------------------------- |
| _(default)_                                 | `<think>…</think>` inside `content` (must strip); ~136 comp tok, ~4.6 s           |
| **`"reasoning_split": true`** ⭐            | **`content` is CLEAN** (no `<think>`); reasoning moves to a separate field        |
| `"reasoning": "disabled"`                   | fewer tokens (~76), faster (~2.7 s) — `<think>` may still appear, so strip anyway |
| `"reasoning": {"enabled": false}`           | same intent; ~60 tok, ~2.6 s                                                      |
| `"reasoning_effort": "low"` (OpenAI-style)  | accepted; ~78 tok, ~2.9 s                                                         |
| `"reasoning": "adaptive"`                   | middle ground; ~116 tok, ~3.6 s                                                   |
| `"thinking": {…}` (native `ThinkingConfig`) | accepted **as an object only** — `"thinking": false` → `2013` type error          |

**`reasoning_split` field shape** (the clean-output win — no regex needed):

```jsonc
// message when reasoning_split:true
{
  "role": "assistant",
  "content": "**40 km/h**\n\nTotal distance: 120 km ... ", // ← clean, ready to display
  "reasoning_content": "Average speed = total distance / total time ...",
  "reasoning_details": [
    {
      "type": "reasoning.text",
      "id": "reasoning-text-1",
      "format": "MiniMax-response-v1",
      "index": 0,
      "text": "Average speed = ...",
    },
  ],
}
```

**Rule of thumb:** `reasoning_split:true` for clean content; add `reasoning:"disabled"` (or
`reasoning_effort:"low"`) on top when the task is short/simple and you want M2.7-highspeed-class
latency. Keep thinking ON (default / `adaptive`) for hard reasoning, coding, agentic loops.

---

## 2. Capabilities

### Vision — ✅ works (new)

`image_url` with a `data:image/png;base64,…` payload is honored. M3 correctly read
`BANANA-7295` rendered into a PNG. Route OCR / chart / screenshot tasks here (M2.7 could not).
Note the answer is still preceded by a `<think>` block unless `reasoning_split:true`.

### `response_format` — ✅ accepted, ⚠️ not a hard JSON guarantee

`{"type":"json_object"}` and `{"type":"json_schema",...}` are both accepted (M2.7 silently
dropped them). **But** M3 still emits a `<think>` block and may wrap JSON in ` ```json `
fences and append a prose "Note:". So:

> For reliable JSON: `response_format` **＋** `reasoning_split:true` **＋** a defensive
> extractor (strip fences / `json.loads` in try/except). Do **not** assume `content` is pure JSON.

### Tools / `tool_choice` — partial

`tools` accepted; `tool_choice:"none"` respected (no call emitted). **`tool_choice` forced**
to a named function on a `"Hi"` prompt did **not** emit `tool_calls` — M3 reasoned "no tools
needed" and replied conversationally. This contradicts the docs. **Before relying on forced
tool calls, re-test with a tool-relevant prompt** (`m3-cli probe` uses a trivial prompt by design).

---

## 3. Parameter honoring

| Param                                                                                       | Result                                                                                     |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `temperature`, `top_p`, `stop`, `seed`, `presence_penalty`, `frequency_penalty`, `logprobs` | accepted                                                                                   |
| `response_format`, `tools`, `reasoning*`, `reasoning_split`                                 | accepted                                                                                   |
| **`n > 1`**                                                                                 | ⚠️ silently dropped (accepted, ignored — 1 choice; was `2013`-rejected pre-2026-06-23)     |
| **`max_tokens > 524288`**                                                                   | ❌ `invalid params` "does not support max tokens > 524288" (was `> 512000` pre-2026-06-23) |
| **`thinking: <bool>`**                                                                      | ❌ `2013` expects `ThinkingConfig` object                                                  |

---

## 4. Context & output ceilings (this plan — empirically pinned)

| Probe                              | Result                                                                                               |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Input 128K – 1M tokens             | **accepted** through `prompt_tokens` 1,000,180 (2026-06-23)                                          |
| Input 1,048,576 / 1.2M tokens      | **rejected** — `context window exceeds limit (2013)`                                                 |
| **→ Input ceiling**                | **≈ 1,000,000 tokens** — the docs' 1M now holds (was ~512K on 2026-06-01)                            |
| Output `max_tokens`                | **≤ 524,288** (524,289 rejected; was 512,000 pre-2026-06-23)                                         |
| Needle retrieval @128K/@256K/@400K | **128K & 256K retrieved (2/2); 400K MISSED (2/2)** on 2026-06-23 — deep-retrieval regressed vs 06-01 |
| Latency vs size                    | ~6 s @128K, ~30 s @800K, **~235 s @1M** (prefill cost)                                               |

With thinking disabled + `max_tokens≥256`, retrieval is accurate at 128K and 256K (2/2 each on
2026-06-23). At **400K it now MISSES (2/2)** — a deep-retrieval regression vs 2026-06-01 (which
retrieved at 400K). The effective "reliable retrieval" depth on this key is **≤ ~256K**, even
though the raw input window now accepts up to ~1M.

**1M context now holds (2026-06-23):** the key accepts payloads through ~1,000,000 tokens
(1,048,576 → `context window exceeds limit`), up from the ~512K cap pinned on 2026-06-01 — the
docs' 1M claim is now real. Caveats: 1M-context latency is brutal (~235 s prefill) and deep
retrieval degrades well before the ceiling, so **operate at ≤ ~256K for retrieval-critical work.**

---

## 5. Docs ⨯ live discrepancies (trust the live column)

| Official docs say             | This key actually does                                                    |
| ----------------------------- | ------------------------------------------------------------------------- |
| 1M context window             | ✅ **now ~1M** (accepts to ~1,000,000; 1,048,576 → 2013) as of 2026-06-23 |
| `MiniMax-M3-highspeed` exists | **`2013 unknown model 'minimax-m3-highspeed'`** — not in catalog          |
| `tool_choice` supported       | forced choice **did not compel** a call (one trivial-prompt data point)   |
| reasoning configurable/hidden | ✅ confirmed — `reasoning_split` moves `<think>` → separate field         |

---

## 6. Copy-paste wiring snippets

### A. Clean-output default profile ⭐ (the chosen switch profile)

```python
# M3 with thinking ON but moved out of content — no <think> to strip.
body = {
    "model": "MiniMax-M3",
    "messages": messages,
    "max_tokens": 4096,          # >=1024; thinking eats budget before visible content
    "temperature": 0.2,
    "reasoning_split": True,     # content is clean; reasoning in reasoning_content/_details
}
resp = call_with_retry(post, body)            # reuse the M2.7 base_resp retry handler
msg = resp["choices"][0]["message"]
answer = msg["content"]                        # already clean — display directly
reasoning = msg.get("reasoning_content")       # optional: keep for debugging/logging
```

### B. Speed profile (short/simple tasks — closest to old highspeed)

```python
body = {
    "model": "MiniMax-M3", "messages": messages,
    "max_tokens": 1024, "temperature": 0.2,
    "reasoning": "disabled",     # ~2x fewer tokens, ~2x faster
}
# <think> can still appear with "disabled" — keep the M2.7 strip as a safety net:
answer = re.sub(r"<think>[\s\S]*?</think>\s*", "", resp["choices"][0]["message"]["content"]).strip()
```

### C. Structured JSON (accept + harden)

````python
body = {
    "model": "MiniMax-M3", "messages": messages,
    "max_tokens": 4096, "temperature": 0.2,
    "reasoning_split": True,                         # clean content
    "response_format": {"type": "json_object"},      # accepted (not a hard guarantee)
}
raw = resp["choices"][0]["message"]["content"]
m = re.search(r"```(?:json)?\s*(\{.*?\}|\[.*?\])\s*```", raw, re.S) or re.search(r"(\{.*\}|\[.*\])", raw, re.S)
data = json.loads(m.group(1) if m else raw)          # defensive: fences/notes still possible
````

### D. Vision (new on M3)

```python
body = {"model": "MiniMax-M3", "max_tokens": 512, "reasoning_split": True, "messages": [
    {"role": "user", "content": [
        {"type": "text", "text": "Read the exact text in this image."},
        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
    ]}]}
```

### E. Guard rails (hard limits)

```python
assert body.get("max_tokens", 0) <= 524_288, "M3 output cap is 524288"
# n stays 1 (M3 silently drops n>1 — 1 choice regardless). Keep input <= ~512K tokens (~512K * 4.5 chars on this filler).
```

The `<think>`-stripping, `base_resp` rate-limit retry, and cached-token reader snippets in
[`../skills/minimax/SKILL.md`](../skills/minimax/SKILL.md) (§ "Defensive code snippets") apply
unchanged to M3 — only the model string and the reasoning controls differ.

---

## 7. Re-verification commands

```bash
# From the plugin source checkout (scripts/ is stripped from the runtime cache):
cd ~/eon/cc-skills/plugins/minimax
export MINIMAX_API_KEY=...            # or rely on the 1Password op-path default (see `bun scripts/m3-cli.ts verify --help`)

bun scripts/m3-cli.ts probe          # full option/capability map (writes JSON)
bun scripts/m3-cli.ts context-probe  # ceiling + needle
bun scripts/m3-cli.ts bench          # speed/quality: default thinking vs reasoning:"disabled"

bun scripts/m3-cli.ts verify    # fast drift check vs the locked capability snapshot (exit 0/1/2)
./scripts/minimax-check-upgrade # catalog drift (now includes MiniMax-M3 in the lock)
```

---

## Evolution log

- **2026-06-23** — Re-locked the capability snapshot and ported the probe scripts to a single Bun
  CLI (`scripts/m3-cli.ts`). Live re-probe: output ceiling **512000 → 524288**; `n>1` now
  **silently dropped** (no longer a 2013 error, still 1 choice); **input ceiling rose ~512K → ~1M**
  (accepts to ~1,000,180; 1,048,576 → `context window exceeds limit`) — the 06-01 "does 1M need a
  higher tier?" follow-up is **answered: 1M now works on this key**. But **deep-retrieval
  regressed** — the 400K needle now misses (2/2) where it retrieved on 06-01, so reliable retrieval
  is ≤ ~256K. 1M prefill latency ~235 s.
- **2026-06-01** — Initial M3 empirical characterization. Live-probed thinking controls,
  vision, response_format, tool_choice, param honoring, 512K input ceiling, 512K output cap,
  retrieval accuracy. Catalog lock refreshed to include `MiniMax-M3`. Open follow-ups: confirm
  whether 1M context / `M3-highspeed` need a different tier; re-test forced `tool_choice` with a
  tool-relevant prompt.
