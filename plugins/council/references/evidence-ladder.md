# The evidence ladder

Every council finding is assigned an **evidence class**. The ladder, weakest to strongest:

```
opinion  <  static-trace  <  runtime-trace  <  failing-test-repro
```

| Rung | Qualifies when | Produced by |
|---|---|---|
| `opinion` | A claim with no verifiable trail beyond the reviewer's reasoning | Finder text alone |
| `static-trace` | A cited, checkable chain through the code (file:line data/control flow) that a human can follow without executing anything | Finder/skeptic citations |
| `runtime-trace` | An executed script/debugger run that demonstrates the wrong value, state, or behavior at runtime | Tribunal prover |
| `failing-test-repro` | A written test that FAILS on the current code for the stated reason — and becomes the fix's acceptance test | Tribunal prover |

## Classification rules (tribunal provers)

1. Prefer `failing-test-repro`. Write the test under `tmp/council-<runId>/repro/`, run it, capture the failure output. The test must fail **for the reason the finding states** — a test failing for an unrelated reason proves nothing.
2. If a test is impractical (needs unavailable infra, non-deterministic surface), fall back to `runtime-trace`: a script or command whose captured output shows the defective value/state, saved under scratch.
3. If neither is achievable within the probe budget, record the best `static-trace` and set `reproduced: false`.
4. **Never modify tracked files.** The workflow taint-guards each prover wave (`git status --porcelain` + `git stash create` hash before/after); any drift marks the evidence `tainted` and discards it.

## The CONFIRMED / PLAUSIBLE dial

- **CONFIRMED** = evidence class is `failing-test-repro` OR `runtime-trace`, AND `reproduced: true`. The `reproduced` flag is required for **both** classes — a repro or trace that did not actually demonstrate the defect is not CONFIRMED. These are the only findings the operator can direct a fix on.
- **PLAUSIBLE** = everything else (`static-trace`, `opinion`, or any class with `reproduced: false`). Reported to the human with full reasoning and a proposed fix, but never fixed without direction — and a PLAUSIBLE finding the operator selects gets a tribunal probe FIRST.

There is no autonomous fix loop: the council surfaces, the operator directs.

Rationale: LLM critics catch more bugs than human reviewers but also hallucinate plausible-sounding bugs (CriticGPT, arXiv:2407.00215); multi-agent consensus does not fix this — 80+ agents once unanimously endorsed a nonexistent OpenSSL vulnerability (Refute-or-Promote, arXiv:2604.19049). Execution is the only precision filter that does not share the model's blind spots — which is also why a human, not an autonomous loop, owns the fix decision. See [sota-provenance.md](./sota-provenance.md).

## Downgrade policy

Downgraded ≠ deleted. An unproven finding is reported as PLAUSIBLE with its votes and reasoning intact — the human may still act on it. A refuted finding moves to the report's refuted-appendix WITH its refutation (negative knowledge is a deliverable; supersede-not-rewrite doctrine from crucible).

## Repro-test retention

Default: repro tests stay in `tmp/council-<runId>/repro/` (scratch). The chairman's report offers promotion of fix-acceptance repros into the real test suite as permanent regression guards; the human decides.
