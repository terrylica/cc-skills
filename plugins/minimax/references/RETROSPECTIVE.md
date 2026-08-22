# MiniMax M2.7-highspeed Campaign — 41-Iteration Retrospective

**Campaign**: `minimax-m27-explore` autonomous-loop
**Duration**: 2026-04-28 23:52 UTC → 2026-04-29 08:25 UTC (~8.5 hours wall-clock; 41 iterations)
**Outcome**: 40 verified hands-on patterns + 1 consolidated quirks reference + 1 production OPS tool. Tier F (financial engineering) COMPLETE 10/10. Tier 4 (forward-looking) at 75%. Production-ready for amonic deployment.

> **Aggregated copy** of `~/own/amonic/minimax/RETROSPECTIVE.md` (source-of-truth — read-only). Cross-references retargeted to plugin-relative paths. Aggregated 2026-04-29 (iter-5 of cc-skills minimax aggregation campaign — see [`../LOOP_CONTRACT.md`](../LOOP_CONTRACT.md)).

This doc is the navigable summary for any future amonic-service author wanting to wire MiniMax. Read this first; drill into [`api-patterns/`](./api-patterns/), [`quirks/CLAUDE.md`](./quirks.md), or [`LOOP_CONTRACT.md`](~/own/amonic/minimax/LOOP_CONTRACT.md) only when this doc points you there.

---

## Quick orient — what did the campaign learn?

MiniMax exposes an OpenAI-compatible chat-completion endpoint that **looks** like OpenAI but **silently drops** ~6 OpenAI parameters (`stop`, `tool_choice`, `response_format`, streaming `usage`, `image_url`, `messages[].name`). Beyond chat-completion, the API surface is MiniMax-native — different URLs, different body shapes, different error envelopes (HTTP 200 + `base_resp.status_code` instead of HTTP 4xx).

The model itself is a **competent reasoning model** for finance/quant work — graduate-level theory knowledge, reliable structured-JSON output, working tool calls — but **cannot do raw math** on realistic data sizes (saturates reasoning budget) and **hallucinates plausible details** under input uncertainty (6 documented instances).

For amonic services: M2.7 is a strong "qualitative judge + theory explainer + tool orchestrator." Pair it with Python for math, with sandbox validators for code, and with deterministic detectors for pattern recognition.

---

## Campaign metrics

| Metric                                    | Value                                                                                                                |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Iterations completed                      | 41                                                                                                                   |
| Verified hands-on pattern docs            | 40 (under [`api-patterns/`](./api-patterns/))                                                                        |
| Consolidated quirks references            | 1 ([`quirks/CLAUDE.md`](./quirks.md), v1 from iter-11)                                                        |
| OPS tools shipped                         | 1 (`mise run minimax:check-upgrade` from iter-41)                                                                    |
| Critical findings                         | 35                                                                                                                   |
| Non-Obvious Learnings                     | ~155 (5 per iter avg × 41 iters minus dupes)                                                                         |
| Documented failure modes                  | 11 (6 hallucination + 4 saturation + 1 cross-language asymmetry)                                                     |
| API error code families catalogued        | 4 (1002 RPM, 1004 auth, 2013 invalid params, 2061 plan-gated)                                                        |
| Compat envelope categories                | 6 (full OpenAI-compat, capability-honored, capability-lacked-input-drop, control-drop, strict-400, native-base_resp) |
| MiniMax-native URL conventions discovered | 4 (`/v1/<feature>_v<N>`, `/v1/<feature>_generation`, `/v1/<feature>` plural, `/v1/<feature>/<verb>`)                 |
| Cumulative API calls                      | ~230 (well within 300/5h plan budget across the campaign)                                                            |
| Tier F (financial engineering) primitives | 10/10 ✅ — canonical agentic stack formed                                                                            |

---

## Top 10 production rules (the must-knows)

If an amonic service author can only read 10 things, read these:

1. **Always set a system prompt — it's at-most break-even, often net-positive.** Long instructions in `messages[0]` (system role) are billed at ~70% of user-content rate and replace MiniMax's hidden ~30-token default. Detailed instructions belong in system role, NEVER user content. (iter-21)

2. **Strip `<think>...</think>` tags from `content` before displaying to users.** M-series exposes its reasoning trace as literal tags inside the content string. Production clients MUST `re.sub(r"<think>[\s\S]*?</think>\s*", "", content)`. Server-side stripping happens for billing on assistant replay (iter-10) but not for client display. (iter-2, iter-10)

3. **Set `max_tokens` ≥ 1024 for any non-trivial task — 512 is a silent-empty footgun.** Reasoning tokens consume budget BEFORE visible content. At max_tokens=512 with a haiku prompt, the entire budget went to reasoning and zero visible output appeared. Branch on `finish_reason="length"`. (iter-5, iter-6)

4. **Trust capability params, suspect control params** — MiniMax honors `tools`, `messages`, `max_tokens`, `temperature`, `stream`. It silently drops `stop`, `tool_choice`, `response_format`, streaming `usage`, `image_url`, `messages[].name`. For any non-trivial OpenAI parameter, write a behavior test before depending on it. (iter-7 through iter-13)

5. **For JSON output, use prompt engineering — `response_format` is silently dropped.** Strict system prompt ("Output ONLY a JSON object. No markdown.") + `temperature=0.2` + `max_tokens=4096` + try/except `json.loads` achieves 100% reliability (iter-30 verified 6/6). (iter-9, iter-30)

6. **Use `MiniMax-M2.7` (plain) for short-output workloads (<150 visible tokens); use `MiniMax-M2.7-highspeed` for long-form generation.** The "highspeed" suffix is COUNTERINTUITIVELY slower for short outputs (Karakeep tagging at 5-15 tokens: plain 2.5× faster). For long outputs, highspeed is 1.5-1.6× faster. Cross-over ~150 tokens. (iter-28)

7. **Caching is COST-only on MiniMax, not LATENCY.** Add `cache_control: {type: "ephemeral"}` to system messages for ~95% input-token cost reduction on repeated prompts; don't expect interactive-UX latency benefits (warm calls within ±1s of cold). Caching activates at ~600+ prompt_tokens. Prefix-match works (varies-user-stable-system flow gets ~70% hit rate). (iter-39, iter-40)

8. **For financial math, route to Python — M2.7 saturates on QP / numerical integration / matrix operations.** 4 documented saturation instances (Sharpe at 4K, Black-Scholes at 16K, Markowitz at 8K, Sortino on N=252 returns at 8K). Pre-summarize aggregates (mean/stdev/n) before passing; M2.7 handles the final-step formula. Define financial primitives as TOOLS for agent-loop orchestration. (iter-29, iter-36, iter-37)

9. **NEVER trust M2.7-generated code without sandbox validation — `compile()` is INSUFFICIENT.** L1+L2 (extract + compile) pass 100% but L3 (runtime) fails at fabricated library imports. M2.7 invented `SMA`, `RSI`, `BollingerBands` from `backtesting.lib` (do not exist). Every code-gen pipeline must include execution validation in subprocess + iterative repair on failure. (iter-33)

10. **NO HTTP 429 — rate-limited responses are HTTP 200 + `base_resp.status_code=1002`.** Standard retry middleware that watches HTTP status won't catch MiniMax throttling. Use code-prefix-based handler: `1xxx` family = retry with backoff; `2xxx` family = fix the request, don't retry. (iter-22, iter-23)

---

## The canonical Tier F agentic stack

After 10 financial-engineering probes (F1-F10), the production-ready amonic-quant agentic flow is:

```
F4: long-context retrieval         → M2.7 finds facts from filings/research
        ↓
F2: structured judgment as JSON    → M2.7 emits trade signal
        ↓
F6: tool orchestration             → M2.7 selects + calls tools (parallel + chained)
        ↓
F1+F8+F9: Python math layer        → numpy/scipy/cvxpy compute deterministically
        ↓
F3: textbook explanation           → M2.7 narrates the result with theory
        ↓
F5: sandbox-validated code         → M2.7 scaffolds; subprocess validates
```

| Primitive    | M2.7's role                                    | Python's role                                       | Verdict                  |
| ------------ | ---------------------------------------------- | --------------------------------------------------- | ------------------------ |
| F1 Math      | ❌ saturates on Black-Scholes / Sharpe at N≥50 | ✅ scipy/numpy compute                              | Python only              |
| F2 JSON      | ✅ 6/6 trade signals across scenarios          | parse + validate + execute                          | M2.7 + Python            |
| F3 Theory    | ✅ graduate-level Black-Scholes / FTAP / KKT   | render markdown                                     | M2.7 only                |
| F4 Long-ctx  | ✅ 4/4 needle retrieval at 27K tokens          | ❌ pre-tag Items client-side to prevent fabrication | M2.7 + Python guard      |
| F5 Codegen   | scaffold only — invents library imports        | ✅ subprocess validation mandatory                  | M2.7 + Python validator  |
| F6 Tools     | ✅ 4/4 orchestration + parallel calls          | execute the tool bodies                             | M2.7 + Python            |
| F7 Patterns  | ❌ DO NOT USE — hallucinates in random walks   | ✅ TA-Lib / CV / classical algos                    | Python only              |
| F8 Optim     | ❌ saturates on QP                             | ✅ scipy.optimize / cvxpy                           | Python only              |
| F9 Risk      | ❌ saturates on N=252 returns                  | ✅ numpy returns/drawdowns                          | Python only              |
| F10 Mandarin | ✅ matches/exceeds English on quant content    | translate + pass through                            | M2.7 only (with caveats) |

The pattern: **M2.7 for judgment / theory / orchestration; Python for math / validation / pattern detection.** Never mix "explain + compute" in one prompt for complex problems — saturation is the failure mode.

---

## 11 documented failure modes

Production code must defend against these:

### Hallucination (6 instances) — fabricates plausible details under input uncertainty

| Iter    | Domain                 | What was fabricated                                                                          |
| ------- | ---------------------- | -------------------------------------------------------------------------------------------- |
| iter-9  | JSON enforcement       | Returned JSON-shaped natural language without `response_format`                              |
| iter-13 | Vision input           | Deliberated about missing image instead of refusing                                          |
| iter-30 | Confidence calibration | (Counter-example — confidence WAS calibrated; pattern is about uncertainty handling broadly) |
| iter-32 | 10-K source citations  | Invented "Source: ITEM 3" attributions; substantive retrieval was correct                    |
| iter-33 | Library imports        | `SMA`, `RSI`, `BollingerBands` from `backtesting.lib` (do not exist)                         |
| iter-35 | Chart patterns         | "Descending Triangle bullish breakout" in PURE GBM noise                                     |

**Defense**: constrain output to enums where possible; cross-validate with deterministic alternatives; pre-tag inputs to prevent attribution fabrication; sandbox-execute generated code; flag `reasoning_tokens > 2.5× baseline` for review.

### Saturation (4 instances) — exhausts reasoning budget on impossible math

| Iter    | Task                                  | Budget | Symptom                                        |
| ------- | ------------------------------------- | ------ | ---------------------------------------------- |
| iter-29 | Sharpe ratio (later succeeded at 16K) | 4K     | Empty visible + `finish_reason=length`         |
| iter-29 | Black-Scholes                         | 16K    | Same — N(d1)/N(d2) computation never converged |
| iter-36 | Markowitz QP                          | 8K     | KKT solve attempted; budget exhausted          |
| iter-37 | Sortino on N=252                      | 8K     | Per-value tracking burned reasoning tokens     |

**Defense**: `is_saturated = (finish_reason=='length' AND len(visible)<50 AND reasoning_tokens >= 0.95*max_tokens)`. Don't retry with higher budget — route to Python instead. Pre-summarize numerical aggregates (mean / stdev / n) before passing to M2.7; ask only for the final-step formula.

### Cross-language asymmetry (1 instance) — language-dependent content filtering

| Iter       | Query          | English response                           | Mandarin response                             |
| ---------- | -------------- | ------------------------------------------ | --------------------------------------------- |
| iter-27/38 | Tiananmen 1989 | Full historical narrative incl. "massacre" | Graceful deflection ("我不太清楚...换个话题") |

**Defense**: detect non-substantive responses (short + uncertainty language) for amonic services with multilingual users. For financial use cases specifically, this is unlikely to bite. The international `api.minimax.io` endpoint applies Chinese-language-specific filtering on politically-sensitive content; English equivalents are unfiltered.

---

## API surface map — what's accessible on Plus-High-Speed plan

| Endpoint           | URL                              | Body shape                         | Plan-gated? | Notes                                           |
| ------------------ | -------------------------------- | ---------------------------------- | ----------- | ----------------------------------------------- |
| Chat completion    | `/v1/chat/completions`           | OpenAI-compat                      | No          | Primary interface; 6 silent-dropped params      |
| Models catalog     | `/v1/models`                     | OpenAI-compat                      | No          | 7 models on this tier                           |
| Embeddings         | `/v1/embeddings`                 | MiniMax (`texts`/`type`/`vectors`) | RPM-gated   | Multi-min cooldown; impractical for bulk RAG    |
| Files (CRUD)       | `/v1/files/{list,upload,delete}` | Sub-resource verbs                 | No          | Full CRUD; int64 file_id (JS precision risk)    |
| TTS                | `/v1/t2a_v2`                     | MiniMax-native                     | Yes         | All 6 speech models gated (2061)                |
| Video              | `/v1/video_generation`           | MiniMax-native, async              | Yes         | task_id polling pattern (untested)              |
| Vision (image_url) | (drops at input)                 | OpenAI-compat                      | N/A         | NOT supported on M2.7 — text-only model         |
| Web search MCP     | `tools: [{type: "web_search"}]`  | OpenAI-compat                      | Yes         | First HTTP 400 in campaign (2013 "not support") |

For amonic services on the current plan: **chat-completion + files + (gated) embeddings**. Vision and TTS need plan upgrade or alternative providers.

---

## Operational facts amonic deployments need

| Topic                  | Finding                                                                                                 | Source iter |
| ---------------------- | ------------------------------------------------------------------------------------------------------- | ----------- |
| Concurrency sweet spot | `p=10` for chat-completion (true parallelism, ~5x throughput vs serial). p=20 only buys 25% more.       | iter-25     |
| TPS asymptote          | ~50 tokens/sec on highspeed (NOT the 100 TPS plan claim). Use 40 TPS as production capacity baseline.   | iter-26     |
| Min latency floor      | ~1.5s per call (network + tokenization + reasoning preamble) — can't go below regardless of prompt size | iter-25     |
| Context ceiling        | 200K tokens (between 142K and 262K). Safe operating: 100K. Token-byte ratio: 3.6 chars/token English    | iter-24     |
| Cache activation       | Auto-cache at ~600+ prompt_tokens; explicit `cache_control` works; ~70% hit rate on prefix match        | iter-39, 40 |
| Cache TTL              | ≥ 3 minutes (zero decay across 185s tested); upper bound likely 5min                                    | iter-40     |
| Rate-limit detection   | NO `x-ratelimit-*` headers, NO HTTP 429. Parse `base_resp.status_code == 1002` from body.               | iter-22     |
| Stream chunk shape     | Coarse-grained (~125 chars/chunk, ~2/sec). Not per-token. `<think>` splits across chunks.               | iter-8      |
| Mandarin token cost    | 1.4-1.5× English for equivalent semantic content (BPE behavior on CJK)                                  | iter-38     |

---

## OPS tooling shipped

| Artifact                                                                                                            | Purpose                                                        |
| ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| [`bin/minimax-check-upgrade`](../scripts/minimax-check-upgrade)                                                         | Polls `/v1/models`, diffs against locked snapshot, exits 0/1/2 |
| [`tasks/minimax/check-upgrade`](~/own/amonic/tasks/minimax/check-upgrade)                                         | `mise run minimax:check-upgrade` (alias: `mm:check-upgrade`)   |
| [`config/plists/com.terryli.minimax-check-upgrade.plist`](../templates/launchd-check-upgrade.plist) | launchd plist for daily 09:00 polling (manual install)         |
| [`minimax/api-patterns/fixtures/models-list-locked.json`](./fixtures/models-list-locked.json)          | Frozen reference for diff comparison                           |

This is the FIRST production OPS deliverable from the campaign. Future amonic services should add `mise run minimax:check-upgrade` to their CI gate to refuse merges when MiniMax has shipped a new model the codebase hasn't reviewed.

---

## Open questions / future work

The campaign achieved its Core Directive but left these worth-probing-later:

| Topic                                    | Why deferred                                       | Suggested probe                                                |
| ---------------------------------------- | -------------------------------------------------- | -------------------------------------------------------------- |
| T4.5 plan-tier comparison                | Requires access to higher plan tiers we don't have | Map plan-gating signals (2061 errors) across endpoints         |
| Cache TTL upper bound                    | iter-40 only tested to 185s                        | Run replays at 5/10/15/30 min gaps                             |
| Vision model discovery                   | Public `/v1/models` showed no VL variants          | Probe `MiniMax-VL-X` style names; check docs at upgrade        |
| Streaming `stream_options.include_usage` | iter-8 deferred                                    | Test if usage chunk arrives at end of stream                   |
| Long-context cache interaction           | Caching + 27K-token F4 untested together           | Re-run iter-32 needle test with `cache_control` on system      |
| Concurrent cache writes                  | Untested                                           | p=10 parallel calls with same cache_control — race?            |
| Mandarin endpoint differences            | Only tested international `api.minimax.io`         | Compare with mainland `api.minimax.chat` for political content |
| TTS / video plan upgrade                 | Both plan-gated on Plus-High-Speed                 | Need plan upgrade to verify functional behavior                |
| Real-time streaming `<think>`            | Buffer-then-strip pattern works but has TTFB cost  | Server-side reasoning hide via opt-in flag (untested)          |

---

## How to read this library

1. **Quick wiring**: read this doc + [`quirks/CLAUDE.md`](./quirks.md) (5 critical findings up top). That's enough to ship Karakeep tagging.
2. **Specific feature**: drill into [`api-patterns/`](./api-patterns/) — table-of-contents in [`api-patterns/CLAUDE.md`](./api-patterns/INDEX.md).
3. **Edge case / failure**: search the failure-mode catalog in this doc, then drill into the source iter's pattern doc.
4. **Model upgrade audit**: run `mise run minimax:check-upgrade`. If exit 1, re-run the relevant probes against the new model name before bumping the lock.

---

## Campaign provenance

- **Loop contract**: [`LOOP_CONTRACT.md`](~/own/amonic/minimax/LOOP_CONTRACT.md) — 41-iter revision log, queue, accumulated learnings
- **Initial bootstrap**: 2026-04-28 23:52 UTC — `/autonomous-loop:start` invocation
- **User-redirected pivot**: post-iter-28 — "gear towards financial engineering" → Tier F priority
- **Campaign close**: iter-42 (this retrospective) — Core Directive criteria a/b/c all substantially met

The campaign is at maturity. Further iterations should be triggered by SPECIFIC needs (model upgrade detected, new amonic service requires new probe, plan tier upgrade unlocks new endpoints) rather than continuing speculative exploration. The remaining T4.5 is partly unprobeable on the current plan.
