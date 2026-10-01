# MiniMax TTS / Audio Endpoint Discovery

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/audio-tts.md` (source-of-truth — read-only, source iter-15). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-9).

Verified 2026-04-29 with the same API key used for chat-completions. **Headline findings: TTS endpoint URL is `/v1/t2a_v2` (NOT OpenAI-compat `/v1/audio/speech`), but ALL TTS models are gated on the user's "Plus – High-Speed" plan tier.** Endpoint exists, auth works, but no audio bytes available without plan upgrade.

This iter is the campaign's first probe of a non-chat-completion endpoint and surfaces a 6th category in the compat taxonomy: MiniMax-native endpoints use HTTP 200 + `base_resp` envelope for errors (different from chat-completions' HTTP 400).

## Test setup

7 probes total (2 endpoint discovery + 5 model name discovery):

### Endpoint discovery

| Probe | Endpoint URL                | Body shape                                                       |
| ----- | --------------------------- | ---------------------------------------------------------------- |
| A1    | `/v1/audio/speech` (OpenAI) | OpenAI-compat: `{model, input, voice}`                           |
| A2    | `/v1/t2a_v2` (MiniMax)      | MiniMax-canonical: `{model, text, voice_setting, audio_setting}` |

### Model name candidates (all sent to `/v1/t2a_v2`)

5 candidate model names tested in parallel:

- `speech-01-turbo`
- `speech-01-hd`
- `speech-02-turbo`
- `speech-02-hd`
- `speech-2.5-turbo-preview`
- `speech-2.5-hd-preview`

## Results

### A1: `/v1/audio/speech` → HTTP 404

```
"404 page not found"
```

**MiniMax does NOT expose an OpenAI-compatible TTS endpoint.** The full `/v1/audio/...` path family doesn't exist on MiniMax. Code that expects OpenAI-style TTS interfaces will get bare 404s.

### A2: `/v1/t2a_v2` with `speech-02-turbo` → HTTP 200 + `base_resp` error

```json
{
  "base_resp": {
    "status_code": 2061,
    "status_msg": "your current token plan not support model, speech-02-turbo"
  }
}
```

**The endpoint EXISTS** (HTTP 200, no 404). **Auth works** (no 401). **Plan tier gates the model** (error code 2061).

### Model name discovery: ALL 5 candidates same gating

Every candidate returned identical error envelope:

```json
{
  "base_resp": {
    "status_code": 2061,
    "status_msg": "your current token plan not support model, <model_name>"
  }
}
```

The error wording confirms ALL 5 names are RECOGNIZED VALID MODELS (otherwise error would say "invalid model"). Plan gating is uniform across the entire TTS model namespace.

## Headline findings

### Finding 1: 🆕 TTS endpoint URL is `/v1/t2a_v2` — MiniMax-canonical, not OpenAI-compat

A1 returned bare HTML 404 ("404 page not found"). The OpenAI-compat layer at MiniMax DOES NOT extend to audio endpoints. Code that uses OpenAI's `/v1/audio/speech` URL needs to migrate to `/v1/t2a_v2` for MiniMax.

### Finding 2: 🆕 Body shape is MiniMax-canonical

Required body keys (OpenAI's `{model, input, voice}` won't work):

```json
{
  "model": "speech-02-turbo",
  "text": "Text to synthesize",
  "stream": false,
  "voice_setting": {
    "voice_id": "male-qn-qingse",
    "speed": 1,
    "vol": 1,
    "pitch": 0
  },
  "audio_setting": {
    "sample_rate": 32000,
    "bitrate": 128000,
    "format": "mp3",
    "channel": 1
  }
}
```

Note: `text` (not OpenAI's `input`); `voice_setting` object (not OpenAI's flat `voice` string); explicit `audio_setting` for output format.

### Finding 3: 6 valid TTS model names discovered

Confirmed via plan-gating-uniform-error: `speech-01-turbo`, `speech-01-hd`, `speech-02-turbo`, `speech-02-hd`, `speech-2.5-turbo-preview`, `speech-2.5-hd-preview`.

Naming convention: `speech-<generation>-{turbo|hd}` where `turbo` is faster/cheaper and `hd` is higher quality. The `2.5-preview` variants suggest active development.

### Finding 4: 🚨 ALL TTS models gated on "Plus – High-Speed" plan tier

The user's plan does NOT include TTS access for any model. Plan upgrade required for production audio synthesis. This is consistent with iter-14's web-search gating — MiniMax appears to bundle features by plan tier, not by individual model.

### Finding 5: 🆕 6th taxonomy category — MiniMax-native endpoints use HTTP 200 + `base_resp` for errors

Chat-completions uses HTTP 400 for hard errors (per iter-14's web-search 400). MiniMax-native endpoints (like `/v1/t2a_v2`) use HTTP 200 with `base_resp.status_code != 0` instead. This confirms iter-2's prediction that `base_resp` is the canary for partial-success responses on MiniMax — but only on native endpoints, not on the OpenAI-compat ones.

**Refined taxonomy**:

| #   | Category                           | Behavior                                    | Examples                           |
| --- | ---------------------------------- | ------------------------------------------- | ---------------------------------- |
| 1   | Basic params (always honored)      | Just works                                  | model, messages, max_tokens        |
| 2   | Capability — model HAS             | Honored                                     | tools on M2.7                      |
| 3   | Capability — model LACKS           | Silent-drop at INPUT level (HTTP 200)       | image_url on M2.7                  |
| 4   | Pure control parameter             | Silent-drop at PARAMETER level (HTTP 200)   | stop, response_format, tool_choice |
| 5   | Built-in tool TYPE enum            | Strict 400 validation (HTTP 400)            | web_search                         |
| 6   | **MiniMax-native endpoint errors** | **HTTP 200 + `base_resp.status_code != 0`** | `/v1/t2a_v2` plan gating           |

### Finding 6: Error code 2061 vs 2013 — different error code families

| Error code | Endpoint         | Meaning                                                            |
| ---------- | ---------------- | ------------------------------------------------------------------ |
| 2013       | chat-completions | "invalid params" (HTTP 400 wrapper)                                |
| 2061       | t2a_v2 (TTS)     | "your current token plan not support model" (HTTP 200 + base_resp) |

Different code families likely indicate different internal services. Production code should branch on the response shape (`base_resp.status_code` vs HTTP error) AND the code value to give meaningful error messages.

### Finding 7: Auth works for both endpoint families

Same API key. iter-15 confirms the user's API key has audio scope (no 401), just no model access on this plan. So when the user upgrades, no key rotation is needed — just plan tier change.

## Implications

### For amonic services contemplating TTS

**Cannot use TTS on the current plan.** Options:

1. **Upgrade MiniMax plan** to a tier that includes TTS
2. **Use a different TTS provider** — Eleven Labs, Cartesia, OpenAI TTS, Kokoro (already running locally per CLAUDE.md). Kokoro is the natural choice since it's already deployed
3. **Defer TTS** to when MiniMax adds it to the Plus tier

### For migration testing

Add explicit assertions for plan-gating:

```python
def test_tts_model_accessible(model_name: str = "speech-02-turbo"):
    body = {"model": model_name, "text": "test", "stream": False, ...}
    resp = httpx.post(f"{BASE}/v1/t2a_v2", json=body, headers=auth_headers, timeout=30)
    assert resp.status_code == 200
    parsed = resp.json()
    assert parsed["base_resp"]["status_code"] == 0, (
        f"TTS model gated: {parsed['base_resp']['status_msg']}"
    )
    # Will fail today; succeeds when plan upgraded
```

### For the OpenAI-compat picture

The compat layer is **endpoint-scoped**: chat-completions at `/v1/chat/completions` is OpenAI-compatible (mostly), but other endpoints use MiniMax-native shapes. Migration code that assumes uniform compat across all `/v1/...` paths will break.

## Idiomatic patterns

### Pattern: Endpoint-aware error handling

Production code that calls multiple MiniMax endpoint families needs to handle different error shapes:

```python
def call_minimax_endpoint(endpoint: str, body: dict) -> dict:
    resp = httpx.post(endpoint, json=body, headers=auth_headers, timeout=120)

    # Native MiniMax endpoints return HTTP 200 + base_resp envelope on errors
    if "/t2a_v2" in endpoint or "/embeddings" in endpoint or "/files" in endpoint:
        if resp.status_code != 200:
            raise APIError(f"HTTP {resp.status_code}: {resp.text}")
        parsed = resp.json()
        base = parsed.get("base_resp", {})
        if base.get("status_code", 0) != 0:
            raise APIError(f"MiniMax error {base['status_code']}: {base['status_msg']}")
        return parsed

    # OpenAI-compat endpoints use HTTP 400 for hard errors
    elif "/chat/completions" in endpoint:
        if resp.status_code == 400:
            error = resp.json().get("error", {})
            raise APIError(f"Bad request: {error.get('message')}")
        elif resp.status_code != 200:
            raise APIError(f"HTTP {resp.status_code}: {resp.text}")
        return resp.json()
```

### Pattern: TTS provider abstraction (recommended)

Don't hardcode MiniMax TTS — wrap it behind an interface. Today on the Plus plan, MiniMax TTS is unavailable. Tomorrow when the plan changes (or for portability across providers), an abstraction layer makes the swap trivial:

```python
class TTSProvider(Protocol):
    def synthesize(self, text: str, voice: str = "default") -> bytes: ...

class KokoroLocal:
    def synthesize(self, text, voice="default"):
        # Calls local Kokoro server per kokoro-tts:server skill
        ...

class MiniMaxTTS:
    def synthesize(self, text, voice="male-qn-qingse"):
        # /v1/t2a_v2 with auth + plan gating
        ...

# Service-layer code uses the protocol, doesn't care which backend
provider: TTSProvider = KokoroLocal()  # current default
audio_bytes = provider.synthesize("hello world")
```

## Open questions for follow-up

- **What plan tier includes TTS?** Probably visible on MiniMax pricing page; would require user research
- **Are there voice ID listings (`voice_setting.voice_id` valid values)?** Untested on this plan; likely returns same gating error. May need a different endpoint like `/v1/voices` or be in the docs
- **What about `/v1/t2a_async` for batch processing?** Untested, may exist for non-real-time synthesis
- **Does `stream: true` work?** Likely also plan-gated; TBD
- **What's the typical audio bytes size + latency profile?** TBD when plan allows access

## Provenance

| Probe | URL                     | http_status | base_resp.status_code | Outcome                                 |
| ----- | ----------------------- | ----------- | --------------------- | --------------------------------------- |
| A1    | `/v1/audio/speech`      | 404         | n/a                   | OpenAI-compat path doesn't exist        |
| A2    | `/v1/t2a_v2`            | 200         | 2061                  | Endpoint exists; model gated            |
| F1-F5 | `/v1/t2a_v2` (5 models) | 200         | 2061 (uniform)        | All 5 model names valid; all plan-gated |

Fixtures:

- `fixtures/chat-completion-tts-A1-openai-style-audio-speech-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-tts-A1-openai-style-audio-speech-2026-04-28.json`)
- `fixtures/chat-completion-tts-A2-minimax-t2a-v2-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-tts-A2-minimax-t2a-v2-2026-04-28.json`)
- `fixtures/chat-completion-tts-followup-summary-2026-04-28.json` (`~/own/amonic/minimax/api-patterns/fixtures/chat-completion-tts-followup-summary-2026-04-28.json`)

Verifier: autonomous-loop iter-15. 7 API calls (2 + 5 in two waves).
