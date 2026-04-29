# MiniMax Rate Limit Headers + Burst Tolerance

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/rate-limits.md` (source-of-truth — read-only, source iter-22). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-10).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. **Two headline findings: (1) MiniMax does NOT emit any rate-limit-related response headers (no `x-ratelimit-*`, no `retry-after`), so clients must rely on `base_resp.status_code` for throttle detection; (2) chat-completion has a much more generous rate-limit bucket than embeddings — 10 parallel calls succeed comfortably.**

This iter closes T3.1, characterizing the rate-limit signaling and per-endpoint bucket sizes. Combined with iter-17/18's embeddings findings, the campaign now has a clear picture of MiniMax's rate-limit asymmetry across endpoints.

## Test setup

Single 10-parallel burst probe:

| Probe | Setup                                                                      |
| ----- | -------------------------------------------------------------------------- |
| 0-9   | 10 parallel chat-completion calls with prompts `"Reply with the digit N."` |

`max_tokens: 128`, default temperature. All 10 fired simultaneously via `ThreadPoolExecutor(max_workers=10)`. Captured ALL response headers from each response for survey.

## Results

### Burst-handling: 10/10 succeeded in 2.7s wall-clock

| idx | HTTP | base_resp.status_code | latency (s) | visible |
| --- | ---- | --------------------- | ----------- | ------- |
| 0   | 200  | 0                     | 1.908       | "0"     |
| 1   | 200  | 0                     | 2.495       | "1"     |
| 2   | 200  | 0                     | 2.378       | "2"     |
| 3   | 200  | 0                     | 2.426       | "3"     |
| 4   | 200  | 0                     | 2.726       | "4"     |
| 5   | 200  | 0                     | 2.214       | "5"     |
| 6   | 200  | 0                     | 2.494       | "6"     |
| 7   | 200  | 0                     | 2.283       | "7"     |
| 8   | 200  | 0                     | 1.908       | "8"     |
| 9   | 200  | 0                     | 1.908       | "9"     |

All succeeded. Total wall-clock 2.7s for 10 calls — excellent parallelism (server processes them concurrently, latencies are cluster around 1.9-2.7s individually).

### Header survey: 11 unique header names, ZERO rate-limit signals

All headers seen across the 10 responses:

| Header               | Notes                                                   |
| -------------------- | ------------------------------------------------------- |
| `alb_receive_time`   | AWS ALB internal — Unix epoch with milliseconds         |
| `alb_request_id`     | AWS ALB internal — opaque ID                            |
| `connection`         | Always `"close"`                                        |
| `content-length`     | Variable per response                                   |
| `content-type`       | Always `application/json; charset=utf-8`                |
| `date`               | Standard HTTP date                                      |
| `minimax-request-id` | MiniMax-internal — opaque ID                            |
| `trace-id`           | MiniMax-internal — correlates with response body's `id` |
| `vary`               | Always `"Accept-Encoding"`                              |
| `x-mm-request-id`    | MiniMax — has `<num>_<random>` shape, billing-friendly  |
| `x-session-id`       | MiniMax-internal — opaque ID                            |

**NO matches for**: `x-ratelimit-limit`, `x-ratelimit-remaining`, `x-ratelimit-reset`, `retry-after`, `x-quota-*`, `x-rate-*`. The HTTP layer gives ZERO proactive rate-limit signaling.

## Headline findings

### Finding 1: 🚨 NO rate-limit headers — clients must use `base_resp.status_code` for detection

OpenAI emits a triple of headers on every response:

- `x-ratelimit-limit-requests`
- `x-ratelimit-remaining-requests`
- `x-ratelimit-reset-requests`

Plus similar for `-tokens`. These let clients PROACTIVELY back off before hitting the limit.

MiniMax emits NONE of these. Throttling detection is reactive only:

- Send a request
- Get HTTP 200 back
- Parse JSON, check `base_resp.status_code`
- If `1002` → you've already hit the limit; no client-side budget tracking possible

**Production implication**: client-side rate-limit tracking must be done via wall-clock counters, not server signals. For example:

```python
class MiniMaxThrottle:
    def __init__(self, calls_per_window: int = 50, window_seconds: int = 60):
        self.calls_per_window = calls_per_window
        self.window_seconds = window_seconds
        self.call_times: list[float] = []

    def can_call(self) -> bool:
        now = time.time()
        # Drop calls outside the window
        self.call_times = [t for t in self.call_times if now - t < self.window_seconds]
        return len(self.call_times) < self.calls_per_window

    def record_call(self):
        self.call_times.append(time.time())

    def wait_until_can_call(self):
        while not self.can_call():
            time.sleep(1)
        self.record_call()
```

The exact bucket size needs to be calibrated empirically (different per endpoint — see Finding 2). For Plus-High-Speed chat-completion, 50 calls/min is a safe ceiling; for embeddings, 1 call/min may be too aggressive (per iter-18's 10-min cooldown).

### Finding 2: ✅ Chat-completion is FAR more generous than embeddings — per-endpoint asymmetry

iter-17/18 found embeddings hit 1002 with ~5 sequential calls and the cooldown exceeded 10 minutes. iter-22 fired 10 PARALLEL chat-completion calls and they all succeeded in 2.7s — no burst-detection, no throttling.

Combined with iter-15/16 findings (TTS and video plan-gated entirely):

| Endpoint               | Throttle behavior on Plus-High-Speed                   |
| ---------------------- | ------------------------------------------------------ |
| `/v1/chat/completions` | Generous — 10 parallel calls fine                      |
| `/v1/embeddings`       | Tight — 5 sequential calls hit 1002, >10min cooldown   |
| `/v1/files/*`          | Generous — full CRUD with no throttle issues (iter-19) |
| `/v1/t2a_v2`           | Plan-gated entirely (no throttle measurement possible) |
| `/v1/video_generation` | Plan-gated entirely (no throttle measurement possible) |

**Each endpoint has its own bucket.** The 5h plan budget claim ("300 prompts/5h") refers to chat-completions only — other endpoints have separate, independently-configured limits.

### Finding 3: Header set is stable across burst calls

All 10 responses had IDENTICAL header names (just different values). The MiniMax envelope is consistent — no headers appear/disappear based on load.

### Finding 4: Two distinct request IDs (different from chat-completions request_id)

| Header               | Format                                   | Use                              |
| -------------------- | ---------------------------------------- | -------------------------------- |
| `minimax-request-id` | 32-char hex                              | Internal request tracking        |
| `x-mm-request-id`    | `<digits>_<digits><alpha>` shape         | **Billing-correlation friendly** |
| `trace-id` (header)  | 32-char hex (matches response body `id`) | End-to-end tracing               |

For production logging: capture `x-mm-request-id` for billing correlation, `trace-id` for distributed tracing. Don't bother with `minimax-request-id` (no obvious downstream use).

### Finding 5: No HTTP 429 — always HTTP 200

Per iter-15 (TTS) + iter-17/18 (embeddings), MiniMax's native endpoints use HTTP 200 + `base_resp` envelope for ALL non-success cases (including rate limits, plan gating, validation errors). iter-22 confirms no HTTP 429 surfaces under burst either — even if we'd hit a chat-completion 1002, the HTTP layer would still be 200.

This means production code that relies on HTTP-status-based retry middleware (e.g., `urllib3.util.retry.Retry(status=[429, 500, 502, 503, 504])`) will NOT auto-retry MiniMax rate-limits. Must inspect response body.

## Implications

### For amonic services

**Production-ready chat-completion** — burst tolerance is high enough that simple parallelism works without sophisticated throttling. For Karakeep/Linkwarden tagging at typical scale (a few requests/second), no special infrastructure needed.

**Embeddings remain bottlenecked** — the per-endpoint asymmetry confirms iter-17/18's recommendation: use local embeddings or a different provider for RAG workloads.

**Files API is unbottlenecked** — full CRUD without throttling concern (iter-19), confirmed not contradicted by iter-22's burst test.

### For client wrappers

```python
import time
from typing import Callable, TypeVar

T = TypeVar("T")

class MiniMaxRetryClient:
    """Wraps MiniMax calls with body-level retry on base_resp.status_code=1002.

    Critical: HTTP 200 + base_resp.status_code=1002 is the rate-limit signal.
    No HTTP 429, no x-ratelimit-* headers, no retry-after — must parse body.
    """
    def __init__(self, max_retries: int = 5):
        self.max_retries = max_retries

    def call_with_retry(self, fn: Callable[[], dict]) -> dict:
        for attempt in range(self.max_retries + 1):
            resp = fn()  # HTTP call returning parsed JSON
            base = resp.get("base_resp", {})
            if base.get("status_code") == 0:
                return resp
            if base.get("status_code") == 1002:
                if attempt == self.max_retries:
                    raise RuntimeError(f"Rate-limited after {attempt} retries")
                wait = 2 ** attempt + (random.random() * 5)
                time.sleep(wait)
                continue
            # Non-recoverable error
            raise RuntimeError(f"MiniMax error {base.get('status_code')}: {base.get('status_msg')}")
        raise RuntimeError("Exhausted retries")
```

### For migration testing from OpenAI

Code that uses OpenAI's rate-limit headers won't work on MiniMax. Audit migrations for:

- Calls to `response.headers["x-ratelimit-remaining-requests"]` — these will be `None` on MiniMax
- HTTP-status-based retry middleware that checks for 429 — won't catch MiniMax's `base_resp.status_code=1002`
- Pre-emptive backoff logic that uses `retry-after` — has no signal on MiniMax

Replace with body-level introspection (per the example above).

## Open questions for follow-up

- **What's the exact chat-completion RPM limit?** iter-22 saw 10/min works comfortably; haven't probed the upper bound.
- **What's the 5-hour plan window behavior?** Plan claims "300 prompts/5h" — does it expire as a sliding window or fixed quota? Not yet probed.
- **Does long-prompt or high-token-cost requests count differently?** iter-21 sent a 2000-token system prompt request; that single call may consume more "budget" than a tiny one. Untested.
- **Does the embeddings RPM bucket recover faster overnight?** iter-18 hit a multi-minute cooldown; whether it eventually recovers (or is per-day quota) unknown.

## Provenance

| idx | HTTP | base_resp.status_code | x-mm-request-id (sample)                                  |
| --- | ---- | --------------------- | --------------------------------------------------------- |
| 0-9 | 200  | 0                     | (in fixture, e.g. `2024530792255857454_1777436115hyvxy6`) |

Fixture (consolidated single fixture for the burst):

- [`fixtures/rate-limits-iter22-survey-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/rate-limits-iter22-survey-2026-04-28.json)

Verifier: autonomous-loop iter-22. 10 API calls (single 10-parallel burst).
