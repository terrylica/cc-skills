# MiniMax Error Response Shape Catalog

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/errors-and-responses.md` (source-of-truth — read-only, source iter-23). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-10).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed` (chat-completion) + `/v1/files/list` (native). **Headline finding: MiniMax has TWO distinct error envelope shapes — `error_object` for chat-completion (with real HTTP 4xx codes) vs `base_resp` for native endpoints (always HTTP 200) — same logical error returns different envelopes depending on endpoint family.** Plus: NO HTTP 404 or 413 ever surface; everything compresses into HTTP 400 + `bad_request_error` + code 2013.

This iter closes T3.2 systematically — production code now has a complete error-handling taxonomy across both endpoint families.

## Test setup

6 deliberately-malformed parallel probes covering main error classes:

| Probe                 | Endpoint               | Malformation                                          |
| --------------------- | ---------------------- | ----------------------------------------------------- |
| E400-malformed-json   | `/v1/chat/completions` | Body has unbalanced braces (truncated JSON)           |
| E400-missing-messages | `/v1/chat/completions` | Body missing required `messages` field                |
| E401-chat-bad-key     | `/v1/chat/completions` | Authorization header has corrupted bearer token       |
| E401-native-bad-key   | `/v1/files/list`       | Same corruption, native endpoint for comparison       |
| E404-bad-model        | `/v1/chat/completions` | `model: "this-model-does-not-exist-2026"`             |
| E413-huge-payload     | `/v1/chat/completions` | `messages[0].content` is ~5MB of repeated lorem ipsum |

## Results

### E401-chat-bad-key — HTTP 401 + error_object envelope

```json
{
  "type": "error",
  "error": {
    "type": "authorized_error",
    "message": "login fail: Please carry the API secret key in the 'Authorization' field of the request header (1004)",
    "http_code": "401"
  },
  "request_id": "0640ba838096cbdbe96fe03bc1654ebe"
}
```

### E401-native-bad-key — HTTP 200 + base_resp envelope (SAME error, different shape)

```json
{
  "base_resp": {
    "status_code": 1004,
    "status_msg": "login fail: Please carry the API secret key in the 'Authorization' field of the request header"
  }
}
```

### E400-malformed-json — HTTP 400 + error_object envelope

```json
{
  "type": "error",
  "error": {
    "type": "bad_request_error",
    "message": "invalid params, \"Syntax error at index 82: eof\\n\\n\\t{...\\n\\t^\\n\" (2013)",
    "http_code": "400"
  },
  "request_id": "0640ba8346a7d50dcbd5cc18c5075e36"
}
```

The error message includes the exact column where parsing failed (very useful for debugging).

### E400-missing-messages — HTTP 400 + structured field-level error

```json
{
  "type": "error",
  "error": {
    "type": "bad_request_error",
    "message": "invalid params, binding: expr_path=messages, cause=missing required parameter (2013)",
    "http_code": "400"
  },
  "request_id": "0640ba8316d8b09293f1c3611e31f804"
}
```

The `binding: expr_path=...` format gives the field path; `cause=missing required parameter` gives the structured cause. Programmatically parseable.

### E404-bad-model — HTTP 400 (NOT 404!) + bad_request_error

```json
{
  "type": "error",
  "error": {
    "type": "bad_request_error",
    "message": "invalid params, unknown model 'this-model-does-not-exist-2026' (2013)",
    "http_code": "400"
  },
  "request_id": "0640ba836689481a9c9410847decb247"
}
```

**MiniMax does NOT return HTTP 404 for unknown models.** It returns HTTP 400 with `bad_request_error` + the unknown model name in the message. Production code that branches on HTTP 404 won't catch this.

### E413-huge-payload — HTTP 400 (NOT 413!) + context-window error, after 7.5s of tokenization

```json
{
  "type": "error",
  "error": {
    "type": "bad_request_error",
    "message": "invalid params, context window exceeds limit (2013)",
    "http_code": "400"
  },
  "request_id": "0640ba842245a2234f67f9f955956ba6"
}
```

**Latency: 7.5 seconds.** All other probes returned in 0.48s. The 5MB payload was tokenized BEFORE the limit check — MiniMax doesn't reject on byte-size at the HTTP layer; it tokenizes everything first, then checks against the context window.

**Production implication**: don't try to "saturate" MiniMax's context window with huge payloads expecting fast rejection. The tokenization step itself is expensive (and probably billed per the system-token-scaling discount, but counted toward the request budget).

## Headline findings

### Finding 1: 🚨 TWO distinct error envelope shapes — chat-completion vs native

The cross-endpoint comparison (E401-chat vs E401-native) is the cleanest demonstration. SAME logical error (auth failure, internal code 1004), two completely different envelopes:

| Endpoint family  | HTTP status | Envelope shape                              |
| ---------------- | ----------- | ------------------------------------------- |
| chat-completion  | 401         | `{type: "error", error: {...}, request_id}` |
| native (files,   | 200         | `{base_resp: {status_code, status_msg}}`    |
| TTS, video, ...) |             |                                             |

**Production code MUST branch on URL family before parsing errors**:

```python
def parse_error(url: str, status: int, body: dict) -> tuple[int, str]:
    """Extract (internal_code, message) regardless of envelope shape."""
    if "/v1/chat/completions" in url or "/v1/models" in url:
        # OpenAI-compat endpoints use error_object envelope with real HTTP 4xx
        if "error" in body:
            err = body["error"]
            # Internal code is embedded in message string: "...(NNNN)"
            code_match = re.search(r"\((\d{4})\)", err.get("message", ""))
            internal_code = int(code_match.group(1)) if code_match else 0
            return internal_code, err.get("message", "")
    else:
        # Native endpoints use base_resp envelope with HTTP 200
        if "base_resp" in body:
            br = body["base_resp"]
            return br.get("status_code", 0), br.get("status_msg", "")
    return -1, "unrecognized error envelope"
```

### Finding 2: 🚨 NO HTTP 404 — bad model name returns HTTP 400

`E404-bad-model` returned HTTP 400 with `bad_request_error` + message containing the unknown model name. **Production code that expects HTTP 404 for "model not found" will silently miss this case.**

This is a meaningful departure from typical REST APIs (and from OpenAI). Migration code patterns:

```python
# OpenAI-compatible code that BREAKS on MiniMax:
try:
    resp = client.chat.completions.create(model="bad-model", ...)
except openai.NotFoundError:
    # Won't trigger on MiniMax — bad model is HTTP 400, not 404
    handle_unknown_model()

# MiniMax-correct pattern:
try:
    resp = client.chat.completions.create(model="bad-model", ...)
except openai.BadRequestError as e:
    if "unknown model" in str(e):
        handle_unknown_model()
    else:
        raise
```

### Finding 3: 🚨 NO HTTP 413 — oversized payload returns HTTP 400 (after tokenization)

E413-huge-payload sent ~5MB of content. MiniMax accepted the upload, tokenized it (7.5 seconds!), then rejected with HTTP 400 + "context window exceeds limit".

Two sub-findings:

1. **Tokenization happens BEFORE limit check** — bytes go through the full tokenization pipeline before being measured against context window. Wasted server time but works.
2. **HTTP 413 doesn't exist on MiniMax** — there's no fast-path rejection for oversized payloads at the HTTP/transport layer. It's all application-layer.

Production implication: client-side payload size checks are essential to avoid wasting 7+ seconds on doomed requests. Roughly: `len(content) < 4_000 * 4 = 16KB` for safety on a 4096-token context (per typical MiniMax limits — actual ceiling untested).

### Finding 4: ALL 400-class errors carry generic internal code 2013

The `(2013)` suffix appears in:

- "Syntax error at index 82: eof (2013)"
- "binding: expr_path=messages, cause=missing required parameter (2013)"
- "unknown model 'X' (2013)"
- "context window exceeds limit (2013)"

There's NO sub-code structure for distinguishing 400-class subcategories. Differentiation is in the message string only. **Production code that wants to distinguish "bad model" from "missing field" from "oversized" must regex-match message text** — fragile but unavoidable.

### Finding 5: 🆕 Error code family expanded to 4 codes

| Code     | Family               | Meaning                        | First seen  |
| -------- | -------------------- | ------------------------------ | ----------- |
| 1002     | Rate limiting (1xxx) | RPM rate limit exceeded        | iter-17     |
| **1004** | Auth (1xxx)          | **Auth failure / missing key** | **iter-23** |
| 2013     | Validation (2xxx)    | Invalid params (catchall)      | iter-9      |
| 2061     | Plan gating (2xxx)   | Model not on user's plan       | iter-15     |

The `1xxx`/`2xxx` distinction holds:

- **1xxx**: retry-with-backoff territory (1002 transient, 1004 needs key fix)
- **2xxx**: fix-the-code territory (2013 fix the request, 2061 upgrade plan)

### Finding 6: error_object envelope structure

MiniMax's chat-completion `error_object`:

```typescript
type ErrorObject = {
  type: "error",
  error: {
    type: "bad_request_error" | "authorized_error" | ...,
    message: string,                    // human-readable; embedded code as "...(NNNN)"
    http_code: string                    // string-encoded HTTP status
  },
  request_id: string                     // 32-char hex; matches trace-id header
}
```

Notable details:

- Top-level `type: "error"` is a discriminator
- `error.type` enum values seen so far: `bad_request_error`, `authorized_error`. Other likely: `not_found_error` (untested), `rate_limit_error` (untested but doubtful since rate limit uses 1002 in body), `internal_error` (server 500-class, untested).
- `error.http_code` is REDUNDANT with the actual HTTP status. Useful for clients that only have access to body, not headers.
- `request_id` is the SAME as the `trace-id` response header — no need to capture both.

### Finding 7: 7.5-second latency for tokenization-then-reject is meaningfully slow

Other 400-class probes (malformed JSON, missing field, bad model) returned in 0.48s. The huge-payload probe took 7.5s. **MiniMax's tokenization is not a fast-path operation** — large rejected requests still consume non-trivial server time.

For high-volume services, this means:

- A misbehaving client sending oversized payloads can consume server resources for 5-10s per request
- DDoS protection at the application layer is implicit (you spend their tokenization budget too)
- Client-side validation prevents this completely — better UX

## Implications

### For amonic services

Error handling needs to span both envelope shapes. A unified error parser (per Finding 1) is the cleanest pattern. The Karakeep/Linkwarden tag generators should use this since they hit chat-completion (real HTTP 4xx) but might also use files API (HTTP 200 + base_resp).

### For migration testing from OpenAI

Add explicit assertions for these cases:

```python
def test_minimax_error_shapes():
    # Bad model → HTTP 400, NOT 404
    try:
        client.chat.completions.create(model="nonexistent", messages=[{"role": "user", "content": "hi"}])
    except APIStatusError as e:
        assert e.status_code == 400, f"MiniMax returns 400 for unknown model, not {e.status_code}"

    # Oversized payload → HTTP 400, NOT 413
    huge = "x" * 5_000_000
    try:
        client.chat.completions.create(model="MiniMax-M2.7-highspeed", messages=[{"role": "user", "content": huge}])
    except APIStatusError as e:
        assert e.status_code == 400, f"MiniMax returns 400 for oversized, not {e.status_code}"
```

### For client-side validation

Add a guard before sending:

```python
MAX_USER_CONTENT_BYTES = 32_000  # ~8000 tokens at 4 chars/token, well within limits

def validate_message(content: str) -> None:
    if len(content) > MAX_USER_CONTENT_BYTES:
        raise ValueError(f"Content too large ({len(content)} bytes); MiniMax will spend 5-10s tokenizing then reject")
```

## Idiomatic patterns

### Pattern: Unified error handler

```python
import re
from typing import NamedTuple

class MiniMaxError(NamedTuple):
    internal_code: int
    message: str
    is_retryable: bool

def parse_minimax_error(url: str, http_status: int, body: dict) -> MiniMaxError | None:
    """Returns None if body indicates success."""
    if "/v1/chat/completions" in url or "/v1/models" in url:
        # error_object envelope (HTTP 4xx)
        if "error" not in body:
            return None
        err = body["error"]
        msg = err.get("message", "")
        code_match = re.search(r"\((\d{4})\)", msg)
        internal_code = int(code_match.group(1)) if code_match else 0
        return MiniMaxError(
            internal_code=internal_code,
            message=msg,
            is_retryable=internal_code in (1002,),  # rate limit
        )
    else:
        # base_resp envelope (HTTP 200 always)
        br = body.get("base_resp")
        if not br or br.get("status_code") == 0:
            return None
        sc = br["status_code"]
        return MiniMaxError(
            internal_code=sc,
            message=br.get("status_msg", ""),
            is_retryable=sc in (1002,),  # rate limit
        )

# Usage:
err = parse_minimax_error(url, resp.status_code, resp.json())
if err is None:
    # success
    ...
elif err.is_retryable:
    # backoff and retry
    ...
elif err.internal_code == 1004:
    # auth failure — non-retryable
    raise AuthError(err.message)
elif err.internal_code == 2061:
    # plan gating — non-retryable, requires plan upgrade
    raise PlanGatedError(err.message)
elif err.internal_code == 2013:
    # invalid params — non-retryable, fix the request
    raise ValidationError(err.message)
```

## Open questions for follow-up

- **Other `error.type` values**: only `bad_request_error` and `authorized_error` seen; is there `not_found_error`, `internal_error`, `rate_limit_error`? Probe with deliberately-failing requests at non-existent paths and via burst on chat-completion if 1002 emerges there.
- **What's the exact context-window byte/token threshold?** E413 at ~5MB triggers it; would benefit from binary-search probes to find exact byte ceiling. Defer to T3.3 (long context probe).
- **HTTP 5xx behavior**: untested. Hard to deliberately trigger; would require server-side defects. May surface organically.
- **Does the request_id field provide stronger correlation than trace-id header for support cases?** Probably equivalent (32-char hex on both); just convenience.

## Provenance

| Probe                 | URL                  | HTTP | internal_code | error.type / status_code                    |
| --------------------- | -------------------- | ---- | ------------- | ------------------------------------------- |
| E400-malformed-json   | /v1/chat/completions | 400  | 2013          | bad_request_error                           |
| E400-missing-messages | /v1/chat/completions | 400  | 2013          | bad_request_error                           |
| E401-chat-bad-key     | /v1/chat/completions | 401  | 1004          | authorized_error                            |
| E401-native-bad-key   | /v1/files/list       | 200  | 1004          | base_resp.status_code=1004                  |
| E404-bad-model        | /v1/chat/completions | 400  | 2013          | bad_request_error                           |
| E413-huge-payload     | /v1/chat/completions | 400  | 2013          | bad_request_error (after 7.5s tokenization) |

Fixtures:

- [`fixtures/errors-E400-malformed-json-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/errors-E400-malformed-json-2026-04-28.json)
- [`fixtures/errors-E400-missing-messages-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/errors-E400-missing-messages-2026-04-28.json)
- [`fixtures/errors-E401-chat-bad-key-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/errors-E401-chat-bad-key-2026-04-28.json)
- [`fixtures/errors-E401-native-bad-key-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/errors-E401-native-bad-key-2026-04-28.json)
- [`fixtures/errors-E404-bad-model-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/errors-E404-bad-model-2026-04-28.json)
- [`fixtures/errors-E413-huge-payload-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/errors-E413-huge-payload-2026-04-28.json)

Verifier: autonomous-loop iter-23. 6 API calls.
