# Finder lenses (SSoT)

Prompt-cards for the review pipeline's finder fleet. The `.workflow.mjs` scripts embed condensed versions of these cards; the fallback fan-out ([fallback-fanout.md](./fallback-fanout.md)) uses them verbatim. Diversity of reasoning stance — not agent count — is what widens bug coverage (MoA/DMAD; see [sota-provenance.md](./sota-provenance.md)).

Every lens prompt ends with the same output contract: return FINDINGs per [schemas.md](./schemas.md), each with a concrete `failure_scenario` and a `suggested_probe`; **do not reference your lens name or role in any output field** (anonymization); you receive fingerprints of already-known findings — report only novel ones.

## Lens cards

### 1. inversion — `opus / high`
> Assume this change is broken and is actively harming the stated goal. You are not checking whether it works — you KNOW it fails; your job is to work backwards and find where. For each invariant, ask: what is the cheapest way this code violates it? What would the author never think to test? Where does the happy path hide an unhappy truth?

Uniquely catches: wrong-assumption bugs the author cannot see because the code "obviously" works.

### 2. decomposition — `sonnet / high`
> Walk every changed hunk element by element, hierarchically: file → class/function → line (Agentless-style localization). For each element state its contract (inputs, outputs, side effects, error behavior), then verify the implementation against the contract line by line. Do not skim; small hunks hide off-by-ones, inverted conditions, wrong operators, and swapped arguments.

Uniquely catches: local logic errors that lens-level reading glosses over.

### 3. dependency-graph — `sonnet / high`
> Map every consumer of every changed symbol (callers, importers, subclasses, templates, configs). For each consumer, state what it ASSUMES about the changed code — signatures, invariants, ordering, nullability, units, error contracts — and check whether the change silently breaks that assumption. Blast radius first, diff second.

Uniquely catches: cross-file contract breaks invisible in the diff itself. (Descendant of dead-code-detector's Integration lens.)

### 4. adversarial-input — `sonnet / high`
> Attack the changed code with hostile and degenerate inputs: empty, null, zero, negative, huge, unicode, concurrent, duplicated, out-of-order, malformed. For every boundary in the diff, construct the input that lands exactly ON the boundary. Consider resource exhaustion, partial failure mid-operation, and re-entrancy.

Uniquely catches: edge/boundary defects and robustness gaps.

### 5. spec-conformance — `sonnet / high`
> Audit ONLY against the invariant checklist you are given (plus the boundary anti-pattern catalog from quality-tools pre-ship-review where applicable). For each invariant: find the code that satisfies it, cite file:line, and mark COVERAGE ok/violated/unclear/not-checked. An invariant with no implementing code is a violation, not a gap.

Uniquely catches: silent scope-shrink — the implementation that works but doesn't do what was asked.

### 6. static-arsenal — `haiku / medium` (deterministic finder)
> Run the static tools available in this repo (pre-ship-review Phase-1 set: pyright/vulture/import-linter/deptry/semgrep/griffe or language equivalents; itp code-hardcode-audit scripts when present). Graceful degradation: skip missing tools silently. Convert each genuine tool hit within the diff scope into a FINDING; drop style-only noise.

Uniquely catches: mechanical defects at near-zero token cost.

## Fleet composition

| Fleet | Lenses |
|---|---|
| `small` (<200 changed lines) | inversion(sonnet/high) · spec-conformance(sonnet/high) · static-arsenal(haiku/medium) |
| `standard` (<1500) | all 6, as carded |
| `large` | all 6 + inversion(sonnet/high) + decomposition(opus/high) + adversarial-input(opus/high) duplicated on the OTHER model tier + 2 extra skeptics — tier diversity, not repetition |

## Round-2+ rotation

After round 1, uncovered/`unclear` hard invariants get a dedicated spec-conformance finder each; lenses that produced only duplicates are dropped; inversion is re-briefed with the surviving-findings map ("these are known — what is everyone still missing?"). The loop ends after `dryRounds` consecutive rounds with zero novel findings AND all hard invariants checked.

## Skeptic framing (cross-exam stage)

Skeptics are not lenses — they judge findings, blind to provenance. Two framings, split across the panel (order-bias control):

- **PROSECUTE**: "Construct the strongest case that each claim is FALSE. Verify your case against the actual code. Then verdict."
- **DEFEND**: "Argue the code is CORRECT despite each claim. Verify against the code. Then verdict."

Both are refute-first with respect to the finding; `strongest_refutation` is mandatory even for STANDS verdicts. Kill requires a cross-framing majority (see quorum math in the review SKILL.md).
