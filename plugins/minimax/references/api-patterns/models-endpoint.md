# GET /v1/models — Model Catalog

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/models-endpoint.md` (source-of-truth — read-only, source iter-1). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-11).

Verified 2026-04-28 against `https://api.minimax.io/v1/models` with the user's "Plus – High-Speed" plan key.

## Minimum-viable request

```bash
curl -sS -H "Authorization: Bearer $API_KEY" https://api.minimax.io/v1/models
```

That's it — no body, no other headers needed. HTTP 200, ~620 bytes, ~400ms latency from a North-American egress.

## Full request capture pattern (with headers + timing)

```bash
API_KEY=$(op read "op://<vault>/<item>/password" --account <account>)
curl -sS -D /tmp/mm-models.headers -o /tmp/mm-models.json \
  -w "HTTP %{http_code} | %{time_total}s | %{size_download}B\n" \
  -H "Authorization: Bearer $API_KEY" \
  https://api.minimax.io/v1/models
```

## Response shape (verified 2026-04-28)

```json
{
  "object": "list",
  "data": [
    {
      "id": "MiniMax-M2.7",
      "object": "model",
      "created": 1773799200,
      "owned_by": "minimax"
    },
    {
      "id": "MiniMax-M2.7-highspeed",
      "object": "model",
      "created": 1773799200,
      "owned_by": "minimax"
    },
    {
      "id": "MiniMax-M2.5",
      "object": "model",
      "created": 1770948000,
      "owned_by": "minimax"
    },
    {
      "id": "MiniMax-M2.5-highspeed",
      "object": "model",
      "created": 1770948000,
      "owned_by": "minimax"
    },
    {
      "id": "MiniMax-M2.1",
      "object": "model",
      "created": 1766455200,
      "owned_by": "minimax"
    },
    {
      "id": "MiniMax-M2.1-highspeed",
      "object": "model",
      "created": 1766455200,
      "owned_by": "minimax"
    },
    {
      "id": "MiniMax-M2",
      "object": "model",
      "created": 1761530400,
      "owned_by": "minimax"
    }
  ]
}
```

Full fixture: [`fixtures/models-list-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/models-list-2026-04-28.json).

## Decoded creation timestamps (release cadence)

| Model id (plain + highspeed paired) | `created` (epoch) | `created` (UTC)      | Δ from previous    |
| ----------------------------------- | ----------------- | -------------------- | ------------------ |
| MiniMax-M2.7 / M2.7-highspeed       | 1773799200        | 2026-03-18 02:00 UTC | +33 days from M2.5 |
| MiniMax-M2.5 / M2.5-highspeed       | 1770948000        | 2026-02-13 02:00 UTC | +52 days from M2.1 |
| MiniMax-M2.1 / M2.1-highspeed       | 1766455200        | 2025-12-23 02:00 UTC | +57 days from M2   |
| MiniMax-M2 (no highspeed pair)      | 1761530400        | 2025-10-27 02:00 UTC | (genesis)          |

**Cadence**: roughly **5-8 week intervals** between major release dates. Next release expected window: late April / early-to-mid May 2026.

**Numbering quirk**: MiniMax skipped M2.2/2.3/2.4/2.6 — they release at non-monotonic cadence. Don't assume `M2.<n+1>` follows `M2.<n>`.

**Pairing rule**: every model post-M2 ships in plain + `-highspeed` pair on the same day. The original `MiniMax-M2` is the only un-paired entry — perhaps because the highspeed track was introduced later.

## Non-obvious response headers (MiniMax-specific, useful for support)

```
trace-id: 06407cb17dfc38ecdb57b61cc7d6319c
minimax-request-id: 8683b4b01b91dc345997bbc4bc536dff
alb_receive_time: 1777420721.695
alb_request_id: ab3376c354f36683973cfd47b1a0f21edad90567
```

- **`trace-id`** + **`minimax-request-id`** are MiniMax-specific. Capture these in any production logging — they're the ID you'd quote in a support ticket.
- **`alb_receive_time`** + **`alb_request_id`** reveal MiniMax's edge runs on AWS ALB. Useful info for debugging regional latency, but not load-bearing on the contract.
- Standard OpenAI APIs DON'T send these headers — they're MiniMax-only. Don't depend on them in cross-provider clients without per-provider switches.

## Use cases for this endpoint

1. **Health check** — cheapest auth-validating call. No tokens billed (only request count, if anything). Use as a key-validation step in setup scripts.
2. **Model upgrade detection** — diff today's catalog against yesterday's; alert when a new entry appears. The 5-8 week cadence makes a daily poll cheap and timely.
3. **Plan-tier verification** — does YOUR key see all 7 models? The "coding_plan" tier sees them all; lower tiers might not. Useful in deploys to detect plan-tier surprises.

## Suggested upgrade-detection script (for future implementation)

When iterating on **T4.4 — model upgrade detection**, structure should be:

1. Persist current catalog to `fixtures/models-list-<date>.json` once daily
2. `jq -r '.data[].id'` produces a sorted list of model ids
3. `diff` against yesterday's list — non-empty diff means a release event
4. On non-empty diff: emit a notification (Telegram via the existing amonic infra) AND auto-add a queue item to `LOOP_CONTRACT.md` to verify the new model
5. Also persist headers — track if MiniMax changes their `trace-id` format or drops `alb_*` headers (would indicate infra migration)

## Failure modes (untested — promote to T3.2 queue if hit)

- **401 Unauthorized**: bad API key. Response body shape unknown — covered by T3.2.
- **403 Forbidden**: key valid but plan tier doesn't allow this endpoint? Unverified.
- **429 Rate limit**: untested at the 300/5h boundary — covered by T3.1.
- **500-class**: untested.

## Provenance

| Verification call    | Value                                      |
| -------------------- | ------------------------------------------ |
| Date                 | 2026-04-28 (UTC 23:58:41)                  |
| HTTP status          | 200                                        |
| Latency              | 0.415s                                     |
| Response size        | 621 bytes                                  |
| `trace-id`           | `06407cb17dfc38ecdb57b61cc7d6319c`         |
| `minimax-request-id` | `8683b4b01b91dc345997bbc4bc536dff`         |
| `alb_request_id`     | `ab3376c354f36683973cfd47b1a0f21edad90567` |
| Plan tier            | Plus – High-Speed (per 1Password Notes)    |
| Verifier             | autonomous-loop iter-1                     |
