# Chairman report templates

The main Claude Code session is the chairman: it receives the workflow's council record and writes the final report. **Synthesize rationales — never tally labels.** Vote counts are metadata for the reader; the chairman's verdict rests on the strongest surviving reasoning and the execution evidence (rationale-based synthesis beats label voting; see [sota-provenance.md](./sota-provenance.md)). The chairman NEVER merges, pushes, or declares the work shippable on the user's behalf — the human reads the report first.

## /council:review report

```markdown
# Council review — <goal, one line>
Run <runId> · base <ref> → head <ref> · fleet <size> · <N> finder rounds · status: **GREEN | BLOCKED | STALLED | REPORT_ONLY**

## Verdict
<2-5 sentences: is this implementation sound against the goal, what was proven,
 what remains open. SHIP / BLOCKED recommendation with the single strongest reason.>

## Findings
| ID | file:line | Severity | Evidence class | Votes S/R/U | Framing spread | State |
|----|-----------|----------|----------------|-------------|----------------|-------|
<one row per non-refuted finding; State ∈ FIXED-VERIFIED / CONFIRMED-UNFIXED / PLAUSIBLE>

### <finding id> — <summary>
- **Evidence**: <class; artifact path; command; output excerpt>       ← e2e-validation report format
- **Root cause**: <mechanism>
- **Fix**: <what was changed, files touched> (omit if unfixed)
- **Verification**: <repro before/after; suite result>
- **Cross-exam**: <strongest refutation raised and why it did not hold>

## Invariant coverage map
| Invariant | Kind | Status | Checked by |
|-----------|------|--------|------------|
<every invariant; violations link to findings>

## Contested findings — disagreement maps
<per contested finding: WHAT the skeptics disagreed about (assumption / mechanism /
 severity) and how execution evidence resolved it — never "majority won">

## Refuted appendix (negative knowledge)
<killed findings WITH their refutations — kept so the next reviewer doesn't re-raise them>

## Fix log
| Round | Finding | Files | Repro before→after | Suite |
|-------|---------|-------|--------------------|-------|

## Repro tests available for promotion
<paths under tmp/council-<runId>/repro/ that could become permanent regression tests — ask the user>

## Budget
<agents spawned per phase; tokens if available; degradations applied>
```

## /council:debug report (postmortem)

```markdown
# Council debug — <symptom, one line>
Run <runId> · <N> hypotheses · <M> experiments · status: **ROOT-CAUSED | UNRESOLVED**

## Root cause
<confirmed hypothesis: statement + mechanism + the experiment that proved it>

## Fix & verification
<fix applied; repro flipped fail→pass; suite green>  (or --no-fix: confirmed but unfixed)

## Elimination table  ← the product, not waste (negative knowledge)
| Hypothesis | Prediction | Experiment | Observed | Verdict | Round |
|------------|-----------|------------|----------|---------|-------|

## Surviving uncertainty
<anything INCONCLUSIVE; recommended follow-ups>
```

## /council:goal-audit report

```markdown
# Goal audit — <goal, one line>
Run <runId> · depth <standard|deep> · <N> invariants (<H> hard / <S> soft)

## Conformance verdict
<does the implementation meet the goal; the nuances that matter>

## Coverage matrix
| Invariant | Kind | Letter/Spirit | Status | Evidence | Finding |
|-----------|------|---------------|--------|----------|---------|
<status ∈ satisfied / violated / partial / unverified>

## Nuances surfaced
<spirit-of-spec observations: implied expectations, edge semantics, quality gaps
 that are not violations but the goal's author would want to know>

## Confirmed violations
<per finding: Evidence / Root cause blocks as in the review template>

## Next step
<offer: chain confirmed violations into /council:review's fix loop>
```
