# Chat Completion — Vision (`image_url` Content Blocks)

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/vision-image-url.md` (source-of-truth — read-only, source iter-13). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-9).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. **Headline finding: vision is NOT supported on M2.7-highspeed.** `image_url` content blocks are silently dropped at the input level — the model doesn't even know an image was attached.

This is a major production finding for any amonic service contemplating image-based tagging/summarization (Karakeep image-bookmarks, Linkwarden snapshots, etc.).

## Test setup

2 parallel probes designed to test both common image-input formats:

| Probe | Setup                                                              | Question                      | Ground truth |
| ----- | ------------------------------------------------------------------ | ----------------------------- | ------------ |
| V1    | `image_url` with base64-inline 100×100 solid red PNG (synthesized) | "What is the dominant color?" | "red"        |
| V2    | `image_url` with public Wikimedia URL (cat photo)                  | "What animal is shown?"       | "cat"        |

Used multi-content array shape per OpenAI vision spec:

```json
{
  "role": "user",
  "content": [
    { "type": "text", "text": "..." },
    { "type": "image_url", "image_url": { "url": "..." } }
  ]
}
```

`max_tokens: 4096`, default temperature.

## Results

| Metric              | V1 (base64 red PNG) | V2 (external URL)   |
| ------------------- | ------------------- | ------------------- |
| HTTP status         | 200                 | 200                 |
| `prompt_tokens`     | 55                  | 54                  |
| `reasoning_tokens`  | 440                 | 430                 |
| `completion_tokens` | 441                 | 431                 |
| `finish_reason`     | `stop`              | `stop`              |
| Visible answer      | `"Missing"`         | `"Sorry"`           |
| Correct?            | ❌ (expected "red") | ❌ (expected "cat") |

The model's `<think>` reasoning trace explicitly stated:

> V1: "The user is presumably referencing an image, but there's no image provided in this conversation."
>
> V2: "The user didn't provide an image. So presumably we need to respond... we cannot see the image."

## Headline findings

### Finding 1: 🚨 `image_url` content blocks are silently dropped on M2.7-highspeed

The smoking gun is the `prompt_tokens` count. iter-3 confirmed a similar text-only prompt ("What is the capital of France?") produced 48 prompt_tokens. V1 and V2 had 55 and 54 — accounting only for the additional text instruction, NOT for any image content.

If the image were reaching the model:

- A 100×100 PNG at typical OpenAI vision token-counts would add ~85 tokens (low-detail mode) to ~750 tokens (high-detail mode)
- A typical Wikimedia photo would add similar token counts

Instead, the prompt_tokens delta is +7 (the text instruction only). **The image bytes are being stripped before tokenization.**

The model's own `<think>` trace confirms: it doesn't know an image was attached. It's deliberating about the missing image and asking itself how to respond.

### Finding 2: M2.7-highspeed is a text-only reasoning model

Despite the OpenAI-compat layer accepting the multi-content array shape (HTTP 200, no validation error), M2.7-highspeed is fundamentally a text-only model. The `image_url` block is parsed and accepted at the request boundary, then dropped before reaching the model.

This is consistent with iter-1's catalog — all 7 listed models are `MiniMax-M2.x` (or `-highspeed`), with no `-vl` or `-vision` variants. **No vision-capable model exists in the public MiniMax catalog as of 2026-04-28.**

### Finding 3: Refines the iter-12 generalization with a third axis

iter-12 established that MiniMax honors capability parameters (`tools`) and drops control parameters (`stop`, `tool_choice`, `response_format`). This iter introduces a third category:

| Category                     | Behavior            | Example                                  |
| ---------------------------- | ------------------- | ---------------------------------------- |
| Capabilities the model HAS   | ✅ Honored          | `tools` (M2.7 supports)                  |
| Capabilities the model LACKS | ❌ Silently dropped | `image_url` (M2.7 lacks vision)          |
| Pure control parameters      | ❌ Silently dropped | `stop`, `tool_choice`, `response_format` |

So the rule isn't just "capability vs control" — it's "supported capability vs unsupported capability vs control". Both unsupported categories silently drop, but the consequence differs:

- Unsupported capability: model produces garbage (deliberates about the missing input)
- Unsupported control: model produces correct output (just without the requested control behavior)

### Finding 4: Cost waste — probes burned 430-440 reasoning tokens

The model spent ~10x more reasoning tokens than an equivalent text-only prompt would have. iter-3's similar text-only prompt used 38 reasoning tokens. Vision probes used 430-440. The model is deliberating about how to handle the missing image — wasted budget that you'd pay for in production.

**Implication**: production code that accidentally sends `image_url` to a non-vision model loses both the image processing AND wastes ~10x reasoning tokens explaining the absence.

### Finding 5: No 400 error — silent-drop pattern continues

The OpenAI spec defines `image_url` content blocks. If MiniMax's compat layer wanted to be strict, it would return HTTP 400 ("model does not support vision"). Instead it accepts the request and routes to text-only processing. This is consistent with the broader silent-drop pattern from iter-7/8/9/12.

## Implications

### For Karakeep / Linkwarden image-tagging features

**Cannot use M2.7-highspeed for image-based tasks.** If image tagging is needed:

1. Find a MiniMax vision model (none currently visible in public catalog)
2. Use a separate vision provider (OpenAI gpt-4-vision, Anthropic Claude vision)
3. Pre-process images with OCR or alt-text generation outside MiniMax, then feed text into M2.7-highspeed for the LLM step

### For migration testing

When porting OpenAI vision code to MiniMax, the request will appear to succeed (HTTP 200) but produce nonsense responses. Add explicit assertions:

```python
def test_vision_works_on_minimax():
    resp = client.chat.completions.create(
        model="MiniMax-M2.7-highspeed",
        messages=[{
            "role": "user",
            "content": [
                {"type": "text", "text": "What color is this?"},
                {"type": "image_url", "image_url": {"url": SOLID_RED_PNG}},
            ],
        }],
    )
    visible = strip_think_tags(resp.choices[0].message.content)
    assert "red" in visible.lower(), f"Expected 'red' for solid red image; got: {visible}"
```

This assertion will FAIL on M2.7-highspeed today and surface the silent-drop early.

## Open questions for follow-up

- **Does MiniMax have a vision-capable model not in the public `/v1/models` listing?** Try named models like `MiniMax-VL-...`, `abab-7-vision-...`, or check the official docs page. Promote to T2.x.
- **Is there a separate `/v1/vision/...` or `/v1/images/...` endpoint for image understanding?** The 1Password Notes field mentioned "image understanding" — but it's unclear whether that's on the chat-completion endpoint or a separate one.
- **Does base64 vs URL distinction matter when vision IS supported?** Both V1 and V2 silently dropped here. If a vision model is found, re-run both probes against it to verify both formats work.
- **What about `image_url.detail` parameter** (`"low"`, `"high"`, `"auto"` per OpenAI spec)? Untested. Would only matter if vision is actually supported.

## Idiomatic patterns

### Pattern: Vision-capability detection (defensive)

```python
def has_vision_support(model: str) -> bool:
    """Detect if a MiniMax model supports vision via a known-color test."""
    red_png_b64 = SOLID_RED_PNG_BASE64  # 100×100 solid red, ~270 bytes
    resp = client.chat.completions.create(
        model=model,
        messages=[{
            "role": "user",
            "content": [
                {"type": "text", "text": "What color? One word."},
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{red_png_b64}"}},
            ],
        }],
        max_tokens=512,
    )
    visible = strip_think_tags(resp.choices[0].message.content).lower().strip(" .!\"'\n")
    return "red" in visible
```

Run this once at service startup to fail-fast if a non-vision model is misconfigured.

### Pattern: Pre-OCR fallback for text-only models

For services that need to "read" images but only have text-only MiniMax access:

```python
def describe_image_via_ocr(image_path: str) -> str:
    """Extract text from image, then summarize via M2.7-highspeed."""
    text = subprocess.check_output(["tesseract", image_path, "-"], text=True)
    if not text.strip():
        return "(no text detected in image)"
    resp = client.chat.completions.create(
        model="MiniMax-M2.7-highspeed",
        messages=[{
            "role": "user",
            "content": f"Summarize this OCR text in 1 sentence:\n\n{text}",
        }],
        max_tokens=2048,
    )
    return strip_think_tags(resp.choices[0].message.content)
```

This is a reasonable workaround for receipt/document images but NOT for general scene understanding.

## Provenance

| Probe | trace-id (in fixture) | finish_reason | prompt_tokens | reasoning_tokens | Visible   |
| ----- | --------------------- | ------------- | ------------- | ---------------- | --------- |
| V1    | (in fixture)          | stop          | 55            | 440              | "Missing" |
| V2    | (in fixture)          | stop          | 54            | 430              | "Sorry"   |

Fixtures (image bytes elided from request_body for size; model received the same bytes):

- `fixtures/chat-completion-vision-V1-base64-red-png-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-vision-V1-base64-red-png-2026-04-28.json`)
- `fixtures/chat-completion-vision-V2-external-url-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-vision-V2-external-url-2026-04-28.json`)

Verifier: autonomous-loop iter-13. 2 API calls.
