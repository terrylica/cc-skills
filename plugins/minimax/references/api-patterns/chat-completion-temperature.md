# Chat Completion — Temperature Sweep + Determinism Floor

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-temperature.md` (source-of-truth — read-only, source iter-5). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-8).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. Tests temperature behavior at 0.0, 0.5, 1.0 plus a determinism re-run at temp=0.0.

## Test setup

- Prompt: `"Write a 3-line haiku about rain. Output only the haiku, no explanation."`
- 4 parallel calls: temp ∈ {0.0, 0.5, 1.0, 0.0 (rerun)}
- `max_tokens: 4096` (first run with 512 hit budget cap before producing visible output — see Finding 3)

## Headline findings

### Finding 1: ⚠️ temp=0.0 is NOT deterministic on MiniMax M-series

Two identical requests at temp=0.0 produced **completely different haikus**:

| Run            | Visible output                                                                    |
| -------------- | --------------------------------------------------------------------------------- |
| temp=0.0 first | `"Soft drops on the roof / Muddy rivers gently flow / Morning sun appears"`       |
| temp=0.0 rerun | `"Gentle rain whispers / Through the quiet night it sings / Petals bow to earth"` |

This is a meaningful **deviation from OpenAI norm** where temp=0 is treated as effectively deterministic (modulo MoE routing variance). On MiniMax M2.7-highspeed, temp=0 still introduces variance — likely because of:

1. The `<think>` reasoning trace itself uses sampling regardless of `temperature` for the user-facing output
2. Backend MoE routing or batch nondeterminism
3. Server-side seeding that isn't user-controllable

**Practical implication**: do NOT rely on temp=0 for repeatable outputs. If you need determinism (e.g., for testing, deduplication, content-hash-based caching), MiniMax may not be the right provider — consider a non-reasoning model or a provider with explicit `seed` parameter support.

### Finding 2: All temperature values produce valid output; quality doesn't degrade at temp=1.0

| Temp        | Visible output                                                                               | Reasoning tokens | Completion tokens |
| ----------- | -------------------------------------------------------------------------------------------- | ---------------- | ----------------- |
| 0.0 (first) | `"Soft drops on the roof / Muddy rivers gently flow / Morning sun appears"`                  | 906              | 921 (15 visible)  |
| 0.5         | `"Gentle rain falls slow, / Puddles ripple, sky's soft sigh, / Earth drinks the soft mist."` | 654              | 676 (22 visible)  |
| 1.0         | `"Gentle rain drips down / On the empty street's soft ground / Moss drinks the night rain"`  | 793              | 814 (21 visible)  |
| 0.0 (rerun) | `"Gentle rain whispers / Through the quiet night it sings / Petals bow to earth"`            | 1047             | 1064 (17 visible) |

All 4 outputs:

- Recognizable haiku structure (5-7-5 syllable form approximated)
- No degradation at temp=1.0
- No "stuck" or repetitive output

**Practical implication**: M-series at higher temperature does NOT degrade catastrophically. Safe to use temp=0.7-1.0 for creative/varied output.

### Finding 3: 🚨 Reasoning tokens dominate creative tasks — budget HEAVILY

A 3-line haiku (15-22 visible tokens) consumed 654-1047 reasoning tokens. **Reasoning is 95-99% of completion budget for this prompt class.**

Initial probe at `max_tokens=512` produced ZERO visible output — model burned entire 512-token budget on reasoning, hitting the cap before emitting any content. Required `max_tokens=4096` to actually see haikus.

**Updated `max_tokens` floor recommendations** (revising iter-2's table):

| Use case                       | Suggested `max_tokens` floor | Why                                        |
| ------------------------------ | ---------------------------- | ------------------------------------------ |
| Tagging (5-15 tokens visible)  | **1024** (was 256-512)       | Reasoning eats 200-1000 tokens easily      |
| Sentence answers               | **2048** (was 512-1024)      |                                            |
| Creative writing (haiku, joke) | **4096**                     | Reasoning tokens scale with task ambiguity |
| Paragraph summaries            | **4096**                     |                                            |
| Long generation                | **8192+**                    |                                            |

For Karakeep tagging: revise the recommendation in `chat-completion-system-prompt.md` from `max_tokens: 512` to `max_tokens: 1024` minimum.

### Finding 4: Latency for creative prompts is 13-22 seconds

Compared to ~3s for factual lookup (iter-2), creative tasks take 5-7x longer due to reasoning token volume.

| Latency | Probe                    |
| ------- | ------------------------ |
| 12.9s   | temp=0.5 (lowest)        |
| 15.4s   | temp=1.0                 |
| 17.4s   | temp=0.0 first           |
| 21.7s   | temp=0.0 rerun (longest) |

The "~100 TPS sustained" plan claim from 1Password notes likely refers to **output token streaming throughput on the visible portion**, not reasoning-token generation speed. Worth probing under T3.5 with explicit timing instrumentation.

## Idiomatic patterns by use case

### High-determinism need

```json
{
  "temperature": 0.0,
  "max_tokens": 4096,
  ...
}
```

Output will likely vary across calls regardless. Consider client-side normalization (lowercase, strip whitespace, truncate to first sentence) for use cases like tag-matching where minor variance is tolerable.

### Default for production tagging/summarization

```json
{
  "temperature": 0.3,
  "max_tokens": 1024,
  ...
}
```

Low-but-not-zero temperature gives predictable-ish output with enough variance to handle ambiguous inputs gracefully.

### Creative variety

```json
{
  "temperature": 0.8,
  "max_tokens": 4096,
  ...
}
```

Used by chat assistants, story generation, etc.

## Open questions for follow-up iterations

- **Is there a `seed` parameter?** OpenAI added explicit seeding for reproducibility — does MiniMax support `seed` or `request_id` as a determinism handle? Not tested yet.
- **Does `top_p` interact differently?** Pure temp sweep tested; combinations untested.
- **Do system prompts affect temp determinism?** Tested without system message; possible the persona/instruction context changes determinism behavior.

Add to T3.x queue if/when these become priorities.

## Provenance

| Probe            | Visible      | Reasoning tokens | Latency |
| ---------------- | ------------ | ---------------- | ------- |
| temp=0.0 (first) | (in fixture) | 906              | 17.4s   |
| temp=0.5         | (in fixture) | 654              | 12.9s   |
| temp=1.0         | (in fixture) | 793              | 15.4s   |
| temp=0.0 (rerun) | (in fixture) | 1047             | 21.7s   |

Fixtures (max_tokens=4096 versions, the empty 512-cap responses were not saved):

- [`fixtures/chat-completion-temp-0.0-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-temp-0.0-2026-04-28.json)
- [`fixtures/chat-completion-temp-0.5-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-temp-0.5-2026-04-28.json)
- [`fixtures/chat-completion-temp-1.0-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-temp-1.0-2026-04-28.json)
- [`fixtures/chat-completion-temp-0.0-rerun-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-temp-0.0-rerun-2026-04-28.json)

Verifier: autonomous-loop iter-5. Total API calls used: 8 (4 wasted at max_tokens=512, 4 productive at max_tokens=4096).
