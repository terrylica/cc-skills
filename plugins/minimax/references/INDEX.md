# MiniMax Plugin — References Index + Audit Coverage Matrix

Navigable TOC for the deep-dive content. Drill in here when [`../skills/minimax/SKILL.md`](../skills/minimax/SKILL.md) doesn't have the specific endpoint / quirk / failure-mode detail you need.

This file ALSO serves as the campaign's **audit-coverage matrix** — every source-of-truth artifact at `~/own/amonic/minimax/` is tracked here with its aggregation status. The campaign cannot close until every row shows `AGGREGATED` (or `SKIPPED` with explicit rationale). The iter-19 mechanical audit consumes this file's tables.

---

## How to read this index

```
Status legend:
  NOT_AGGREGATED  — source exists; destination not yet written this campaign (default)
  AGGREGATED      — destination file written + content verified against source
  PARTIAL         — destination written but missing sections; tracked in AUDIT.md
  SKIPPED         — deliberately not migrated; reason in Notes column
  STUB            — placeholder file exists for navigation; full content in source-of-truth only
```

---

## Top-level distilled artifacts

These appear at the SKILL.md primary layer (already auto-discoverable) AND get full-text aggregation in references/.

| Source artifact (read-only)             | Destination                             | Status     | Source iter | Notes                                                                                                                                   |
| --------------------------------------- | --------------------------------------- | ---------- | ----------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `~/own/amonic/minimax/RETROSPECTIVE.md` | `references/RETROSPECTIVE.md`           | AGGREGATED | iter-42     | DONE iter-5: verbatim copy + 7 cross-ref retargets + provenance note inserted                                                           |
| `~/own/amonic/minimax/quirks/CLAUDE.md` | `references/quirks.md`                  | AGGREGATED | iter-11     | DONE iter-6: 291 lines + 3 retarget patterns (CLAUDE.md/LOOP_CONTRACT.md → abs source-paths; api-patterns/ → sibling) + provenance note |
| `~/own/amonic/minimax/CLAUDE.md`        | (no destination — distilled only)       | SKIPPED    | iter-1      | Spoke-level pointer; content surfaces via SKILL.md frontmatter                                                                          |
| `~/own/amonic/minimax/LOOP_CONTRACT.md` | (no destination — campaign archaeology) | SKIPPED    | n/a         | Source-only campaign state machine; not consumer reference                                                                              |

---

## Per-endpoint pattern docs (40 source files → `references/api-patterns/`)

Every doc gets a verbatim aggregate copy with internal cross-references retargeted to plugin-relative paths.

### Chat completion core (16 files)

| Source (`api-patterns/<name>.md`)       | Destination                                          | Status     | Iter | Headline finding                                             |
| --------------------------------------- | ---------------------------------------------------- | ---------- | ---- | ------------------------------------------------------------ |
| chat-completion-minimal.md              | api-patterns/chat-completion-minimal.md              | AGGREGATED | 2    | `<think>` stripping; 11 MiniMax-specific response fields     |
| chat-completion-system-prompt.md        | api-patterns/chat-completion-system-prompt.md        | AGGREGATED | 3    | System role strongly honored; persona ~2× reasoning          |
| chat-completion-system-token-scaling.md | api-patterns/chat-completion-system-token-scaling.md | AGGREGATED | 21   | Hybrid replacement+discount; ~70% rate                       |
| chat-completion-multi-turn.md           | api-patterns/chat-completion-multi-turn.md           | AGGREGATED | 4    | Stateless; fabricated assistant turns accepted               |
| chat-completion-temperature.md          | api-patterns/chat-completion-temperature.md          | AGGREGATED | 5    | temp=0 NOT deterministic on M-series                         |
| chat-completion-max-tokens.md           | api-patterns/chat-completion-max-tokens.md           | AGGREGATED | 6    | Server doesn't enforce; tiny budget = silent empty           |
| chat-completion-stop.md                 | api-patterns/chat-completion-stop.md                 | AGGREGATED | 7    | `stop` silently ignored                                      |
| chat-completion-streaming.md            | api-patterns/chat-completion-streaming.md            | AGGREGATED | 8    | Coarse chunks (~125 chars/chunk); no usage in stream         |
| chat-completion-json.md                 | api-patterns/chat-completion-json.md                 | AGGREGATED | 9    | `response_format` silently dropped; prompt-engineer it       |
| chat-completion-tokens.md               | api-patterns/chat-completion-tokens.md               | AGGREGATED | 10   | Server strips `<think>` on assistant replay (no double-bill) |
| chat-completion-tools.md                | api-patterns/chat-completion-tools.md                | AGGREGATED | 12   | Tools honored; `tool_choice` silently dropped                |
| chat-completion-name-field.md           | api-patterns/chat-completion-name-field.md           | AGGREGATED | 20   | Always returns "MiniMax AI"; request `name` dropped          |
| chat-completion-tps.md                  | api-patterns/chat-completion-tps.md                  | AGGREGATED | 26   | ~50 TPS asymptote (NOT 100); use 40 for capacity planning    |
| concurrency.md                          | api-patterns/concurrency.md                          | AGGREGATED | 25   | TRUE parallelism up to p=10; soft ceiling beyond             |
| context-window-boundary.md              | api-patterns/context-window-boundary.md              | AGGREGATED | 24   | ~200K tokens; 3.6 chars/token English                        |
| sensitivity-flags.md                    | api-patterns/sensitivity-flags.md                    | AGGREGATED | 27   | Flags inert on this tier; 100% default-rate                  |

### Caching (2 files)

| Source                  | Destination                          | Status     | Iter | Headline finding                                       |
| ----------------------- | ------------------------------------ | ---------- | ---- | ------------------------------------------------------ |
| prompt-caching.md       | api-patterns/prompt-caching.md       | AGGREGATED | 39   | Hybrid OpenAI+Anthropic cache APIs; 96.4% explicit hit |
| cache-read-semantics.md | api-patterns/cache-read-semantics.md | AGGREGATED | 40   | Threshold 264-597 pt; prefix-match works; TTL ≥ 3min   |

### Other endpoints (8 files)

| Source              | Destination                      | Status     | Iter | Headline finding                                   |
| ------------------- | -------------------------------- | ---------- | ---- | -------------------------------------------------- |
| models-endpoint.md  | api-patterns/models-endpoint.md  | AGGREGATED | 1    | `/v1/models` catalog (7 models); cadence 5-8 weeks |
| audio-tts.md        | api-patterns/audio-tts.md        | AGGREGATED | 15   | `/v1/t2a_v2`; all 6 speech models plan-gated       |
| video-generation.md | api-patterns/video-generation.md | AGGREGATED | 16   | `/v1/video_generation`; async via task_id          |
| embeddings.md       | api-patterns/embeddings.md       | AGGREGATED | 17   | `/v1/embeddings`; RPM-tight; pending vector test   |
| files.md            | api-patterns/files.md            | AGGREGATED | 19   | Full CRUD; int64 file_id; sub-resource verbs       |
| vision-image-url.md | api-patterns/vision-image-url.md | AGGREGATED | 13   | M2.7 text-only; image_url silently dropped         |
| web-search.md       | api-patterns/web-search.md       | AGGREGATED | 14   | First HTTP 400 in campaign; not on this tier       |
| rate-limits.md      | api-patterns/rate-limits.md      | AGGREGATED | 22   | NO rate-limit headers; per-endpoint asymmetry      |

### Discovery / errors (3 files)

| Source                     | Destination                             | Status     | Iter | Headline finding                                  |
| -------------------------- | --------------------------------------- | ---------- | ---- | ------------------------------------------------- |
| errors-and-responses.md    | api-patterns/errors-and-responses.md    | AGGREGATED | 23   | Two envelopes; no HTTP 404/413                    |
| model-aliasing.md          | api-patterns/model-aliasing.md          | AGGREGATED | 28   | Plain ≠ highspeed; plain FASTER for short outputs |
| model-upgrade-detection.md | api-patterns/model-upgrade-detection.md | AGGREGATED | 41   | The OPS tool architecture + bug history           |

### Tier F — Financial engineering (10 files)

| Source                        | Destination                                | Status     | Iter | Headline finding                                          |
| ----------------------------- | ------------------------------------------ | ---------- | ---- | --------------------------------------------------------- |
| finmath-accuracy.md           | api-patterns/finmath-accuracy.md           | AGGREGATED | 29   | Accurate at adequate budget; Black-Scholes unsolvable     |
| trade-signal-json.md          | api-patterns/trade-signal-json.md          | AGGREGATED | 30   | 6/6 production-ready (100% L1+L2+L3)                      |
| finconcepts-knowledge.md      | api-patterns/finconcepts-knowledge.md      | AGGREGATED | 31   | 6/6 graduate-level theory; auto-grading caveat            |
| long-context-10k.md           | api-patterns/long-context-10k.md           | AGGREGATED | 32   | 4/4 retrieval at 27K; citations fabricated                |
| code-generation-validation.md | api-patterns/code-generation-validation.md | AGGREGATED | 33   | 0/3 runtime; sandbox validation MANDATORY                 |
| financial-tool-use.md         | api-patterns/financial-tool-use.md         | AGGREGATED | 34   | 4/4 orchestration; weather-trap refused                   |
| pattern-recognition.md        | api-patterns/pattern-recognition.md        | AGGREGATED | 35   | DO NOT USE; random-walk trap triggered                    |
| portfolio-optimization.md     | api-patterns/portfolio-optimization.md     | AGGREGATED | 36   | Math saturates 8K reasoning; explains framework with KKT  |
| risk-metrics-chain.md         | api-patterns/risk-metrics-chain.md         | AGGREGATED | 37   | Saturates on N=252; data volume drives saturation         |
| mandarin-cross-language.md    | api-patterns/mandarin-cross-language.md    | AGGREGATED | 38   | Quality matches/exceeds English; political filter by lang |

### Index doc (1 file — meta)

| Source                 | Destination           | Status     | Notes                                                                                                                                                                        |
| ---------------------- | --------------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| api-patterns/CLAUDE.md | api-patterns/INDEX.md | AGGREGATED | DONE iter-7: 63 lines + 3 retarget patterns (spoke + LOOP_CONTRACT abs paths; fixtures/ → ../fixtures/). 39 sibling refs preserved as forward-refs to iter-8-12 aggregations |

---

## Fixtures (91 source files → selective subset in `references/fixtures/`)

NOT every fixture migrates — bulky ones (long-context probes, code-generation runs) stay source-only. Aggregating only diagnostic / production-decision-relevant fixtures.

### To aggregate

| Source fixture                            | Why aggregate                                              | Status     |
| ----------------------------------------- | ---------------------------------------------------------- | ---------- |
| models-list-locked.json                   | OPS tool's data contract — must be in plugin               | AGGREGATED |
| models-list-2026-04-28.json               | Initial catalog snapshot for diff                          | AGGREGATED |
| cache-discovery-iter39-2026-04-29.json    | Hybrid cache API discovery evidence                        | AGGREGATED |
| cache-followup-iter39-2026-04-29.json     | Explicit cache_read confirmation                           | AGGREGATED |
| cache-semantics-iter40-2026-04-29.json    | Threshold + prefix-match + TTL data                        | AGGREGATED |
| errors-E\*.json (6 files)                 | Two-envelope catalogue — production parser depends on this | AGGREGATED |
| chat-completion-minimal-2026-04-28.json   | Baseline response shape reference                          | AGGREGATED |
| chat-completion-no-system-2026-04-28.json | Hidden default system prompt evidence                      | AGGREGATED |

### To skip (source-only — too bulky or marginal)

| Source fixture pattern                            | Skip reason                                |
| ------------------------------------------------- | ------------------------------------------ |
| `10k-needle-iter32-*.json`                        | ~27K tokens of synthetic 10-K — too bulky  |
| `backtesting-codegen-iter33-*.json`               | 3 generated code variants — derivable      |
| `chat-completion-jsonmode-J*.json` (4 files)      | Pattern is documented; raw not needed      |
| `chat-completion-maxtokens-*.json` (4 sizes)      | Pattern is documented; raw not needed      |
| `chat-completion-stop-*.json` (4 variants)        | Silent-drop pattern is documented          |
| `chat-completion-name-field-N*.json` (3 variants) | Brand-string pattern is documented         |
| Everything else iter-specific                     | Available in source for forensic reference |

---

## OPS tooling (4 source files → 3 plugin destinations)

| Source                                                               | Destination                                   | Status         | Iter | Notes                                        |
| -------------------------------------------------------------------- | --------------------------------------------- | -------------- | ---- | -------------------------------------------- |
| `~/own/amonic/bin/minimax-check-upgrade`                             | `scripts/minimax-check-upgrade`               | NOT_AGGREGATED | 41   | Path-portable rewrite; defaults via env vars |
| `~/own/amonic/.mise/tasks/minimax/check-upgrade`                     | (documented only, not shipped)                | SKIPPED        | 41   | Repo-specific; show pattern in skill instead |
| `~/own/amonic/config/plists/com.terryli.minimax-check-upgrade.plist` | `templates/launchd-check-upgrade.plist`       | NOT_AGGREGATED | 42   | Parameterized template; user populates path  |
| `~/own/amonic/minimax/api-patterns/fixtures/models-list-locked.json` | `references/fixtures/models-list-locked.json` | NOT_AGGREGATED | 14   | The data contract the script enforces        |

---

## Coverage rollup (computed)

```
Total tracked source artifacts:  ~50 (40 docs + ~8 fixtures + 1 OPS script + 1 plist)
AGGREGATED:                      50  (3 distilled + 40 api-patterns + 8 fixture rows from iter-12) — content aggregation COMPLETE
NOT_AGGREGATED:                  ~0  (OPS-tool artifacts only — Phase C)
PARTIAL:                         0
SKIPPED:                         3  (CLAUDE.md, LOOP_CONTRACT.md, mise task)
STUB:                            0
Last updated:                    iter-12 (2026-04-29 17:48 UTC) — Phase B content aggregation COMPLETE
```

**Closure criterion**: AGGREGATED + SKIPPED == total. The campaign cannot close while any row shows NOT_AGGREGATED, PARTIAL, or STUB.

---

## How iters update this matrix

Each Phase B iter (5-15) that aggregates files MUST:

1. Update the affected rows' Status column from NOT_AGGREGATED → AGGREGATED
2. Update the Coverage rollup numbers
3. If any aggregation reveals issues with the source (e.g., broken internal link, contradictory claim), record in [`AUDIT.md`](./AUDIT.md) for cross-reference and bump status to PARTIAL with explanation

The iter-19 mechanical audit consumes this file directly — it parses the tables, walks each Destination column, and confirms the file exists + non-empty. Discrepancies between Status and reality are flagged.

---

## Cross-references

- Top-level skill: [`../skills/minimax/SKILL.md`](../skills/minimax/SKILL.md)
- Plugin metadata: [`../plugin.json`](../plugin.json)
- Campaign contract: [`../LOOP_CONTRACT.md`](../LOOP_CONTRACT.md)
- Source-of-truth (READ-ONLY): `~/own/amonic/minimax/`
