# Council data schemas (SSoT)

Prose source of truth for every JSON schema used by the council workflows. **The executable copies are inlined as consts inside each `skills/*/scripts/*.workflow.mjs`** (self-contained scripts; no cross-file imports at runtime). Any change here MUST be mirrored into the inline copies, and vice versa — this is a load-bearing invariant listed in [../CLAUDE.md](../CLAUDE.md).

Conventions: all schemas are JSON Schema (draft 2020-12 subset the Workflow tool validates); `additionalProperties: false` everywhere; agents that return data are ALWAYS called with a `schema` option so validation happens at the tool-call layer and the model retries on mismatch.

## FINDING

Emitted by finder lenses (review P2) and auditors (goal-audit P2).

| Field | Type | Required | Semantics |
|---|---|---|---|
| `file` | string | yes | Repo-relative path |
| `line` | integer | yes | 1-indexed anchor line |
| `symbol` | string | no | Nearest enclosing function/class |
| `category` | enum | yes | `correctness` \| `spec-violation` \| `regression` \| `security` \| `data-integrity` \| `concurrency` \| `performance` \| `test-gap` \| `boundary-contract` |
| `severity` | enum | yes | `critical` \| `major` \| `minor` |
| `summary` | string ≤200 | yes | One-sentence defect statement |
| `failure_scenario` | string | yes | Concrete inputs/state → wrong output/crash. No scenario, no finding. |
| `invariant_ids` | string[] | yes | Which invariants this violates (may be empty for out-of-scope discoveries) |
| `evidence_pointers` | string[] | no | `file:line` refs, tool-output excerpts supporting the claim |
| `suggested_probe` | string | yes | How a tribunal prover could PROVE this (test sketch or command) |
| `confidence` | number 0–1 | yes | Finder's own confidence. **Stripped before skeptics see the finding.** |

## PUBLIC_FIELDS (anonymization whitelist)

The ONLY fields a skeptic ever sees: `file`, `line`, `symbol`, `category`, `severity`, `summary`, `failure_scenario`, `evidence_pointers`, `suggested_probe` — plus the anon id `F-NN`. Provenance (lens name, model, round, confidence) lives in a side-table keyed by anon id and rejoins the record only at chairman-report time. This whitelist is the single anonymization gate.

## INVARIANT

Produced by goal decomposition (review P1, goal-audit P1).

| Field | Type | Required | Semantics |
|---|---|---|---|
| `id` | string | yes | `INV-NN` |
| `statement` | string | yes | Testable assertion about the implementation |
| `kind` | enum | yes | `hard` (violation = defect) \| `soft` (quality preference) |
| `source` | enum | yes | `explicit-goal` \| `implied` \| `regression-guard` |
| `probe` | string | yes | How to check it (test, command, inspection rule) |
| `files` | string[] | no | Paths where it lives |
| `status` | enum | — | `unverified` \| `satisfied` \| `violated` \| `partial` (script-managed, not agent-set at creation) |

## VERDICT (one per finding × skeptic)

| Field | Type | Required | Semantics |
|---|---|---|---|
| `finding_id` | string | yes | Anon id `F-NN` |
| `verdict` | enum | yes | `REFUTED` \| `STANDS` \| `UNCERTAIN` |
| `strongest_refutation` | string | yes | Mandatory EVEN when verdict is STANDS (refute-first discipline: the skeptic must articulate the best case against the finding before judging) |
| `refutation_evidence` | string[] | no | `file:line` refs backing the refutation attempt |
| `residual_risk` | string | no | What remains worrying even if refuted |
| `confidence` | number 0–1 | yes | |

## EVIDENCE (tribunal output, one per surviving finding)

| Field | Type | Required | Semantics |
|---|---|---|---|
| `finding_id` | string | yes | |
| `evidence_class` | enum | yes | `failing-test-repro` \| `runtime-trace` \| `static-trace` \| `opinion` — see [evidence-ladder.md](./evidence-ladder.md) |
| `artifact_path` | string | no | Repro test / trace script under `tmp/council-<runId>/` |
| `command` | string | no | Exact command that demonstrates the failure |
| `output_excerpt` | string ≤2000 | no | Captured failing output |
| `reproduced` | boolean | yes | Did the probe actually demonstrate the defect |
| `notes` | string | no | Caveats, environment assumptions |
| `proposed_fix` | string ≤2000 | no | Surface-first remediation: the technical root-cause fix (files + change). Proposed only — never applied by the workflow. |
| `fix_summary_plain` | string ≤1000 | no | 1-2 plain-language sentences describing what the fix does and why (feeds the chairman's plain-English fix block) |

Only `failing-test-repro` and `runtime-trace` with `reproduced: true` yield **CONFIRMED**. Everything else is **PLAUSIBLE** — reported with full reasoning and a proposed fix, but never fixed without the operator's direction (there is no autonomous fix loop).

## COVERAGE (finder → invariant, per round)

| Field | Type | Required | Semantics |
|---|---|---|---|
| `invariant_id` | string | yes | |
| `status` | enum | yes | `ok` \| `violated` \| `unclear` \| `not-checked` |

A finder round is not "dry" while any `hard` invariant is still `unverified` overall.

## HYPOTHESIS (debug mode)

Falsifiability is enforced at the schema level — a hypothesis without a discriminating experiment is rejected by validation, not by judgment.

| Field | Type | Required | Semantics |
|---|---|---|---|
| `id` | string | yes | `H-NN` |
| `statement` | string | yes | What is broken |
| `mechanism` | string | yes | Causal chain from cause to observed symptom |
| `falsifiable_prediction` | string | yes | Observable that MUST hold if the hypothesis is true |
| `discriminating_experiment` | object | yes | `{setup, command, expected_if_true, expected_if_false}` — all four required |
| `discriminates_against` | string[] | no | Other hypothesis ids this experiment also splits |
| `prior` | number 0–1 | yes | Generator's prior |

## EXPERIMENT (debug mode)

| Field | Type | Required | Semantics |
|---|---|---|---|
| `hypothesis_id` | string | yes | |
| `command` | string | yes | What was actually run |
| `observed` | string | yes | What actually happened |
| `verdict` | enum | yes | `SUPPORTS` \| `ELIMINATES` \| `INCONCLUSIVE` |
| `artifact_path` | string | no | Saved output under scratch |

## Workflow args schemas

### review.workflow.mjs

```jsonc
{
  "repo": "string (REQUIRED) — absolute path to the repo under review (workflow agents inherit the session cwd, which may differ)",
  "goal": "string (REQUIRED) — spec/issue text; the skill preflight inlines file contents",
  "base": "string — diff base ref; default: merge-base of HEAD and origin default branch",
  "head": "string = HEAD",
  "scope": "string[] = [] — optional path globs restricting review",
  "testCmd": "string|null — auto-detected in P0 when null",
  "fleet": "auto|small|standard|large = auto  (auto: <200 changed lines→small, <1500→standard, else large)",
  "dryRounds": "int = 2 — consecutive novelty-free rounds that end the finder loop",
  "maxFinderRounds": "int = 4",
  "skeptics": "int = 3 (5 for large fleet)",
  "isolation": "scratch|clone = scratch — tribunal prover isolation. SURFACE-FIRST: neither mode edits tracked files, status is always REPORT_ONLY, and there is intentionally no fix arg.",
  "budget": "int|null — token target; phases degrade gracefully near ceilings",
  "seed": "string|null — PRNG seed for reproducible shuffles",
  "runId": "string (REQUIRED) — supplied by the skill preflight (timestamps are unavailable inside Workflow scripts)"
}
```

### debug.workflow.mjs

```jsonc
{
  "repo": "string (REQUIRED) — absolute path to the target repo",
  "symptom": "string (REQUIRED)",
  "repro": "string|null — command that reproduces the failure",
  "suspects": "string[] = [] — paths to focus on",
  "maxHypotheses": "int = 6",
  "maxRounds": "int = 3",
  "testCmd": "string|null",
  "fix": "bool = false — SURFACE-FIRST DEFAULT: the root cause is proven by elimination and the fix is PROPOSED, not applied. fix=true applies the minimal confirming fix and INDEPENDENTLY verifies it (repro-then-fix-then-pass). Legacy noFix honored when fix is absent.",
  "budget": "int|null",
  "seed": "string|null",
  "runId": "string (REQUIRED)"
}
```

### goal-audit.workflow.mjs

```jsonc
{
  "repo": "string (REQUIRED) — absolute path to the target repo",
  "goal": "string (REQUIRED) — goal text; the skill preflight inlines file contents",
  "scope": "string[] = []",
  "depth": "standard|deep = standard",
  "base": "string|null — null audits the working tree",
  "budget": "int|null",
  "seed": "string|null",
  "runId": "string (REQUIRED)"
}
```

## Council record (review return value)

Surface-first: the record is a report, not an action log. Each finding carries its evidence (including `proposed_fix` / `fix_summary_plain`) so the chairman can explain both the defect and its remediation. `status` is always `REPORT_ONLY` — the workflow never fixes anything.

```jsonc
{
  "runId": "...", "goal": "...",
  "refs": { "base": "...", "head": "...", "snapshot": "git stash create hash" },
  "fleet": "small | standard | large",
  "invariants": ["INVARIANT with final status"],
  "coverageMap": ["COVERAGE aggregated"],
  "finderRounds": "int",
  "findings": ["lifecycle: finding + verdicts[] + evidence (with proposed_fix) + state (CONFIRMED | PLAUSIBLE)"],
  "refuted": ["killed findings WITH their refutations — kept, never deleted"],
  "disagreementMaps": ["contested-finding disagreement analyses"],
  "status": "REPORT_ONLY",
  "budgetSpent": "int",
  "scratchDir": "tmp/council-<runId>"
}
```
