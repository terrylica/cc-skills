# MiniMax Video Generation Endpoint Discovery

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/video-generation.md` (source-of-truth — read-only, source iter-16). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-9).

Verified 2026-04-29 with the same API key used for chat-completions and TTS. **Headline findings: video generation endpoint is `/v1/video_generation` (asynchronous task model with `task_id`), and like TTS, plan-gated on user's "Plus – High-Speed" tier.** Discovery value remains high despite no video bytes accessible.

This is the campaign's second non-chat-completion endpoint after iter-15's TTS discovery. The two endpoints use DIFFERENT URL naming conventions.

## Test setup

2 parallel endpoint discovery probes:

| Probe | URL                         | Body                                                                       |
| ----- | --------------------------- | -------------------------------------------------------------------------- |
| V1    | `POST /v1/t2v_v2`           | `{model: "video-01", prompt: "A serene mountain landscape at sunrise..."}` |
| V2    | `POST /v1/video_generation` | (same body)                                                                |

V1 was an educated guess based on iter-15's `/v1/t2a_v2` TTS pattern. V2 was the alternative full-word naming.

## Results

### V1: `/v1/t2v_v2` → HTTP 404

```
"404 page not found"
```

**The TTS naming convention does NOT generalize.** Despite TTS being at `/v1/t2a_v2`, video is NOT at `/v1/t2v_v2`.

### V2: `/v1/video_generation` → HTTP 200 + plan gated

```json
{
  "task_id": "",
  "base_resp": {
    "status_code": 2061,
    "status_msg": "your current token plan not support model, video-01"
  }
}
```

**The endpoint EXISTS, auth works, but the model is plan-gated** (same 2061 error code as TTS). Critical structural reveal: the response schema includes `task_id` — confirming **video API is asynchronous**.

## Headline findings

### Finding 1: 🆕 Video endpoint URL is `/v1/video_generation` — different naming convention than TTS

| Endpoint family | URL                    | Naming pattern                    |
| --------------- | ---------------------- | --------------------------------- |
| TTS (iter-15)   | `/v1/t2a_v2`           | Abbreviated + version suffix      |
| Video (iter-16) | `/v1/video_generation` | Full-word path, no version suffix |

So MiniMax doesn't have a single uniform URL convention — even within native (non-OpenAI-compat) endpoints, naming varies. Code that hardcodes a URL pattern won't generalize across endpoint families.

### Finding 2: 🆕 Video API is ASYNCHRONOUS via `task_id` polling pattern

The response contains a `task_id: ""` field (empty in the gating error, but its presence in the schema is the signal). This confirms the standard async-task pattern for video generation:

1. Client `POST /v1/video_generation` with prompt
2. Server immediately returns `{task_id: "abc123", base_resp: {status_code: 0, ...}}`
3. Client polls `GET /v1/query/video_generation?task_id=abc123` (or similar)
4. Eventually gets back the video URL or bytes

This is different from TTS which appears to be synchronous (no `task_id` in iter-15's responses). Video is computationally heavier — async is appropriate.

### Finding 3: Same plan-gating pattern as TTS (uniform error code 2061)

```
your current token plan not support model, video-01
```

Identical error code (2061) and wording structure as TTS gating from iter-15. Confirms iter-15's hypothesis that **MiniMax's plan-tier gating uses uniform error codes across native endpoint families**.

### Finding 4: `video-01` is a recognized valid model name

The error message echoes back `video-01` — confirming this is a known valid model (just not on this plan). Same pattern as iter-15's TTS model discovery: gated-but-valid models get echoed in error messages.

Likely additional model names (untested but high-confidence guesses):

- `video-02` (next generation)
- `MiniMax-Hailuo-...` (rumored Hailuo branding for video products)
- `T2V-01`, `I2V-01` (text-to-video, image-to-video alternative naming)

Per iter-15's plan-uniform-gating lesson, all candidates will gate identically — no value in probing further at this plan tier.

### Finding 5: Body shape accepted with minimum `{model, prompt}` keys

V2's body had only `model` and `prompt` — no required fields rejection (no 400). The full body shape likely supports more parameters:

- `duration` (seconds)
- `aspect_ratio` (16:9, 9:16, 1:1)
- `resolution` (e.g., 720p, 1080p)
- `seed` for reproducibility
- `start_image_url` for image-to-video

These are standard parameters for video generation APIs, but require plan access to verify.

### Finding 6: Confirms 6th category in compat taxonomy

Both TTS (iter-15) and Video (iter-16) follow the same pattern:

- Endpoint URL is MiniMax-canonical (NOT OpenAI-compat)
- HTTP 200 + `base_resp.status_code != 0` for errors
- Same plan-gating error code (2061)

This generalizes the iter-15 finding — the **MiniMax-native endpoint pattern** (HTTP 200 + base_resp envelope) is now confirmed across two endpoint families. Likely applies to embeddings, files, etc. too.

## Implications

### For amonic services contemplating video generation

**Cannot use video generation on the current plan.** Options:

1. **Upgrade MiniMax plan tier** to one that includes video
2. **Use a different video provider** — Runway, Pika, Stability AI, OpenAI Sora
3. **Defer video features** until plan upgrade or different roadmap priorities

For amonic specifically, video generation is unlikely a near-term priority — this finding is mostly informational.

### For migration testing

```python
def test_video_generation_accessible(model: str = "video-01"):
    body = {"model": model, "prompt": "test prompt"}
    resp = httpx.post(f"{BASE}/v1/video_generation", json=body, headers=auth_headers, timeout=30)
    assert resp.status_code == 200
    parsed = resp.json()
    base = parsed["base_resp"]
    assert base["status_code"] == 0, f"Video gated: {base['status_msg']}"
    assert parsed.get("task_id"), "Expected task_id for async video gen"
    # Will fail today; succeeds when plan upgraded
```

### For documentation completeness

This iter caps Tier 2 endpoint discovery for the major MiniMax-native APIs. Remaining T2.x items:

- T2.6 (embeddings) — likely `/v1/embeddings`, may be plan-gated like TTS/video
- T2.7 (files) — likely `/v1/files`, may have different auth/scope
- T2.8 (`name` field oddity) — chat-completion-specific, not endpoint discovery

After T2.6 and T2.7, Tier 2 closes.

## Idiomatic patterns

### Pattern: Async video generation (when accessible)

```python
def generate_video(prompt: str, model: str = "video-01") -> bytes:
    """Submit + poll until complete."""
    # Submit
    resp = httpx.post(f"{BASE}/v1/video_generation", json={
        "model": model,
        "prompt": prompt,
    }, headers=auth_headers, timeout=30)
    parsed = resp.json()
    if parsed["base_resp"]["status_code"] != 0:
        raise APIError(parsed["base_resp"]["status_msg"])
    task_id = parsed["task_id"]

    # Poll (URL pattern is hypothetical until plan-access confirmed)
    while True:
        time.sleep(5)
        status = httpx.get(
            f"{BASE}/v1/query/video_generation",
            params={"task_id": task_id},
            headers=auth_headers,
        ).json()
        if status["base_resp"]["status_code"] != 0:
            raise APIError(status["base_resp"]["status_msg"])
        if status.get("status") == "Success":
            video_url = status["video_url"]
            return httpx.get(video_url).content
        elif status.get("status") == "Fail":
            raise APIError("Video generation failed")
        # else: still processing, continue polling
```

The polling URL `/v1/query/video_generation` is hypothetical (untested) — will need confirmation when plan access is available.

### Pattern: Provider abstraction (recommended)

Same pattern as iter-15's TTS abstraction — wrap MiniMax video behind a `VideoProvider` Protocol:

```python
class VideoProvider(Protocol):
    def generate(self, prompt: str, **kwargs) -> bytes: ...

class MiniMaxVideo:
    def generate(self, prompt, model="video-01", **kwargs):
        # Async submit + poll, return mp4 bytes
        ...

class RunwayVideo:
    def generate(self, prompt, model="gen-3", **kwargs):
        # Different provider, same interface
        ...

provider: VideoProvider = MiniMaxVideo()  # or RunwayVideo() — caller doesn't care
video_bytes = provider.generate("a sunrise over mountains")
```

## Open questions for follow-up

- **Polling URL pattern**: untested. Likely `/v1/query/video_generation?task_id=X` based on common patterns.
- **Synchronous variant**: untested. Some video APIs offer both async and sync; MiniMax may too.
- **Image-to-video with `start_image_url`**: untested.
- **Video model namespace**: only `video-01` confirmed. Likely others exist (`video-02`, `MiniMax-Hailuo-XX`).
- **Output format**: mp4? webm? Resolution defaults?
- **Pricing per video**: relevant for plan-tier upgrade decisions.

## Provenance

| Probe | URL                    | http_status | Outcome                                             | Latency |
| ----- | ---------------------- | ----------- | --------------------------------------------------- | ------- |
| V1    | `/v1/t2v_v2`           | 404         | Path doesn't exist (TTS pattern doesn't generalize) | 0.33s   |
| V2    | `/v1/video_generation` | 200 + 2061  | Endpoint exists; plan-gated; async (`task_id`)      | 0.63s   |

Fixtures:

- `fixtures/video-V1-t2v-v2-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/video-V1-t2v-v2-2026-04-28.json`)
- `fixtures/video-V2-video-generation-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/video-V2-video-generation-2026-04-28.json`)

Verifier: autonomous-loop iter-16. 2 API calls.
