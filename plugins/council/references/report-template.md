# Chairman report templates

The main Claude Code session is the chairman: it receives the workflow's council record and writes the final report. **Synthesize rationales — never tally labels.** Vote counts are metadata for the reader; the chairman's verdict rests on the strongest surviving reasoning and the execution evidence (rationale-based synthesis beats label voting; see [sota-provenance.md](./sota-provenance.md)). The chairman NEVER merges, pushes, applies a fix, or declares the work shippable on the user's behalf — the council **surfaces**; the human reads the report and **directs** the fixes.

## The surfacing contract (applies to every mode)

Every finding is written for a human who will decide what to do about it. Render **all four** blocks per finding, in this order:

1. **What's wrong — plain English.** Explain the defect the way you would to a smart colleague who did not write this code: what actually breaks, the concrete situation that triggers it, and why it matters (what the user/operator would experience). Readable prose, 2–5 sentences. **Not oversimplified** — keep the real mechanism, just say it in words a non-specialist can follow. No unexplained jargon; if a term is load-bearing, define it in half a clause.
2. **How sure we are — evidence.** State the evidence class and what was actually observed: the repro command + the failing output for CONFIRMED; the file:line reasoning chain for PLAUSIBLE. Give the vote spread (S/R/U) and framing as *supporting metadata only*, then the strongest refutation a skeptic raised and why it did not hold. For PLAUSIBLE, say plainly: **"not yet proven by execution — treat as a lead, not a fact."**
3. **How to fix it — plain English + the technical fix.** First the plain-English version (what the fix does and why it removes the problem — from `fix_summary_plain`), then **Technical fix:** the precise change — file(s), the root cause, and exactly what to change (from `proposed_fix`). If the finding is PLAUSIBLE/unproven, mark the fix as a *proposed direction* and note it should be tribunal-proved before anyone edits code.
4. **What you need to know — operator context.** Anything the operator needs to make the call: blast radius (what else touches this), the risk/cost of the fix, whether a regression test already exists or its repro can be promoted, and any judgment call the operator must settle (e.g. "the fix could be A or B; A is safer but wider"). If there is nothing extra, write "No special considerations."

Nothing in any mode is fixed automatically. Every report ends by telling the operator how to direct fixes.

## /council:review report

```markdown
# Council review — <goal, one line>
Run <runId> · base <ref> → head <ref> · fleet <size> · <N> finder rounds · status: **REPORT_ONLY (surface-first)**

## Verdict
<2–5 plain-English sentences: is this implementation sound against the goal, what was
 proven, what remains open. End with a recommendation IN WORDS ("I'd hold the merge until
 F-02 and F-05 are resolved") — never SHIP/BLOCK on the user's behalf; the human decides.>

## Findings at a glance
| ID | file:line | Severity | Evidence | 1-line plain-English summary | State |
|----|-----------|----------|----------|------------------------------|-------|
<one row per non-refuted finding, CONFIRMED first then PLAUSIBLE; State ∈ CONFIRMED / PLAUSIBLE>

---

### <finding id> — <short title> · **<CONFIRMED | PLAUSIBLE>** · <severity>

**What's wrong (plain English).**
<2–5 sentences per the surfacing contract: the defect, the exact trigger, the real-world impact.>

**How sure we are.**
- Evidence: <class — failing-test-repro / runtime-trace / static-trace / opinion>. <For CONFIRMED: the repro path + command + the failing output excerpt. For PLAUSIBLE: the file:line reasoning chain, and the sentence "not yet proven by execution — treat as a lead.">
- Cross-exam: skeptics <S stands / R refuted / U uncertain>, framings <prosecute/defend spread>. Strongest refutation raised: <…> — it did not hold because <…>.

**How to fix it.**
- Plain English: <fix_summary_plain — what the fix does and why it removes the problem.>
- Technical fix: <proposed_fix — the file(s), the root cause, and the exact change. Minimal, in-convention, at root cause — not a symptom patch.>
<if PLAUSIBLE: "Proposed direction only — prove it with `/council:review` on this finding, or a targeted repro, before editing code.">

**What you need to know.**
<blast radius · fix risk/cost · is a repro available to promote into the suite · any A/B judgment call. Or "No special considerations.">

---

## Invariant coverage map
| Invariant | Kind | Status | Checked by / evidence |
|-----------|------|--------|-----------------------|
<every invariant, including satisfied ones; status ∈ satisfied / violated / partial / unverified; violations link to finding ids>

## Contested findings — disagreement maps
<per contested finding: WHAT the skeptics disagreed about (assumption / mechanism / severity /
 scope) and how the execution evidence settled it — never "majority won">

## Refuted appendix (negative knowledge)
<killed findings WITH the refutation that killed them — kept so the next reviewer doesn't re-raise them>

## Repro tests available for promotion
<paths under tmp/council-<runId>/repro/ that could become permanent regression tests — offer, the human decides>

## How to direct fixes (surface-first — nothing was changed)
Name the finding IDs to fix (e.g. "fix F-02 and F-05"). For each, I will: apply the change at
root cause · re-run that finding's repro (must flip fail→pass) as the acceptance test · re-run
the project suite (must stay green). PLAUSIBLE findings you pick get a tribunal probe FIRST — I
never edit code on an unproven lead. Say the word and name the IDs.

## Budget
<agents spawned per phase; tokens if available; any degradations applied and what they dropped>
```

## /council:debug report (postmortem)

```markdown
# Council debug — <symptom, one line>
Run <runId> · <N> hypotheses · <M> experiments · status: **ROOT-CAUSED-UNFIXED (surface-first) | ROOT-CAUSED (--fix) | FIX-FAILED | UNRESOLVED**

## Root cause
**Plain English.** <what is actually broken and the causal chain from cause to symptom, in words.>
**Technical.** <confirmed hypothesis: statement + mechanism + the discriminating experiment that proved it (and what it observed).>

## The fix
- Plain English: <fix_summary_plain — what the fix does and why it removes the root cause.>
- Technical fix: <proposedFix.description — file(s) + exact change.>
- Status: default surface-first, the fix is **proposed, not applied** — say the word to apply it.
  With `--fix`: fix applied and INDEPENDENTLY verified — repro flipped fail→pass; suite <green | unavailable>.

## Elimination table  ← the product, not waste (negative knowledge)
| Hypothesis | Prediction | Experiment | Observed | Verdict | Round |
|------------|-----------|------------|----------|---------|-------|
<every hypothesis, including eliminated ones — stops the next debugger re-walking dead ends>

## Surviving uncertainty
<anything INCONCLUSIVE; the discriminating experiments a human should run next>

## What you need to know
<blast radius of the fix · regression-test opportunity · any judgment call. Or "No special considerations.">
```

## /council:goal-audit report

```markdown
# Goal audit — <goal, one line>
Run <runId> · depth <standard|deep> · <N> invariants (<H> hard / <S> soft) · status: **REPORT_ONLY (surface-first)**

## Conformance verdict
<2–5 plain-English sentences: does the implementation meet the goal — letter AND spirit — and
 the nuances that matter. A recommendation in words; never declare conformance the human hasn't read.>

## Coverage matrix
| Invariant | Kind | Letter/Spirit | Status | Evidence | Finding |
|-----------|------|---------------|--------|----------|---------|
<every invariant; status ∈ satisfied / violated / partial / unverified>

## Nuances surfaced
<spirit-of-spec observations: implied expectations, edge semantics, quality gaps that are
 not violations but the goal's author would want to know — the skill's differentiator; do not trim>

## Violations
<per violation, the full four-block surfacing contract: What's wrong (plain English) · How sure we
 are (CONFIRMED vs PLAUSIBLE) · How to fix it (plain English + technical) · What you need to know.>

## How to direct fixes (surface-first — nothing was changed)
Name the violation IDs to fix; each CONFIRMED violation ships with a failing repro that becomes
its fix's acceptance test. PLAUSIBLE violations get a tribunal probe first. Say the word.
```
