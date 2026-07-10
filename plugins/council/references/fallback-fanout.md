# Fallback fan-out (no Workflow tool)

When the `Workflow` tool is unavailable or denied, the main session replicates the council with parallel `Task` batches and performs the deterministic steps itself. House precedent: `plugins/quality-tools/skills/multi-agent-performance-profiling/SKILL.md` ("spawn agents in parallel using single message with multiple Task tool calls") and `plugins/quality-tools/skills/dead-code-detector/SKILL.md:191-268` (multi-perspective validation subagents).

**Never ask the user to install anything.** Fall back silently and say so in the final report's budget footer.

## Reduced defaults (manual orchestration must stay tractable)

| Knob | Workflow mode | Fallback |
|---|---|---|
| Finder rounds | loop-until-dry (≤4) | 1 (2 only if round 1 found ≥3 critical/major) |
| Lenses | fleet-sized (3/6/11) | 3: inversion · spec-conformance · adversarial-input |
| Skeptics | 3–5 | 2 (1 PROSECUTE + 1 DEFEND) |
| Tribunal | all survivors | top-5 by severity |
| Fix rounds | ≤3 | ≤2 |

## Bookkeeping

All state lives under `tmp/council-<runId>/` in the target repo (create `runId` as `fb-<UTC yyyymmdd-HHMMSS>`):

```
tmp/council-<runId>/
├── context-pack.md      # diff stat, touched-file git log, test inventory, blast radius notes
├── invariants.json      # INVARIANT[]
├── findings.json        # FINDING[] with provenance — the side-table IS this file
├── anon-map.json        # F-NN → findings.json index (chairman-only)
├── verdicts.json        # VERDICT[] per skeptic
├── evidence/            # EVIDENCE records + repro tests + trace outputs
└── fixlog.json          # FIXROUND[]
```

## Procedure (review mode)

1. **Preflight + context pack** (main session, Bash/Read/Grep): as in the SKILL.md preflight; write `context-pack.md`.
2. **Invariants**: ONE Task (general-purpose, opus if available): decompose the goal per [schemas.md](./schemas.md) INVARIANT; write `invariants.json`.
3. **Finders**: ONE message, THREE parallel Task calls — lens cards verbatim from [lenses.md](./lenses.md) (inversion, spec-conformance, adversarial-input), each given: context pack, invariants, output contract (FINDING JSON array in the final message). Parse into `findings.json`.
4. **Dedup + anonymize** (main session, deterministic): fingerprint = normalized file + nearest symbol + category + first 8 stemmed summary tokens; merge duplicates (keep both on doubt, flag `possible-duplicate`). Build `anon-map.json`; produce the PUBLIC_FIELDS-only anonymized list; shuffle it TWICE into two different orders (any deterministic shuffle — e.g., sort by sha256 of `F-NN + skeptic index`).
5. **Skeptics**: ONE message, TWO parallel Task calls — one PROSECUTE, one DEFEND framing (cards in [lenses.md](./lenses.md)), each receiving a differently-ordered anonymized batch. Parse into `verdicts.json`.
6. **Quorum (S=2)**: kill only on 2/2 REFUTED (which is automatically cross-framing); 1/2 split → contested → keep, flag for tribunal priority. Apply severity ordering; select top-5 for tribunal.
7. **Tribunal**: sequential Task calls (one prover at a time — no wave management manually), each with the taint rule ("create files ONLY under tmp/council-<runId>/; never modify tracked files") and the [evidence-ladder.md](./evidence-ladder.md) classification rules. Main session checks `git status --porcelain` between provers; on drift, discard that evidence as tainted.
8. **Fix loop** (only with `--fix`; the default is surface-first — report and stop): per CONFIRMED finding-group, one fixer Task (may edit the real tree); then main session re-runs repros + `testCmd`; scoped re-review = ONE adversarial-input Task on the fix diff + the 2-skeptic pass on anything new. Max 2 rounds; STALLED on identical confirmed set.
9. **Chairman report**: main session renders [report-template.md](./report-template.md) from the JSON files; note "fallback mode" and the reduced defaults in the budget footer.

## Procedure (debug mode)

1. Run `--repro` once; save baseline output to scratch.
2. ONE message, THREE parallel Task generators (state-corruption / causal-chain / environment lenses) → HYPOTHESIS[] (schema-complete or rejected by the main session — regenerate once on schema failure).
3. Main session orders experiments greedily by `discriminates_against` count; executes them **itself** via Bash, serially; records EXPERIMENT[]; eliminates.
4. Survivor → fixer Task → repro must flip fail→pass, suite green. Elimination table in the report.

## Procedure (goal-audit mode)

1. TWO parallel Task decomposers (letter-of-spec / spirit-of-spec) → main session merges + tags hard/soft.
2. Auditor Tasks per file-locality cluster (≤4, one message) → per-invariant status + FINDINGs for violations.
3. 2-skeptic pass on violations only; tribunal probes (≤3, sequential) for hard violations.
4. Coverage-matrix report; offer chaining into /council:review.
