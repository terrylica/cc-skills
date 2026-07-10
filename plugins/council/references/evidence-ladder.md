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

- **CONFIRMED** = `failing-test-repro` or `runtime-trace` with `reproduced: true`. Only CONFIRMED findings enter the autonomous fix loop.
- **PLAUSIBLE** = everything below. Reported to the human with full reasoning, never auto-fixed.

Rationale: LLM critics catch more bugs than human reviewers but also hallucinate plausible-sounding bugs (CriticGPT, arXiv:2407.00215); multi-agent consensus does not fix this — 80+ agents once unanimously endorsed a nonexistent OpenSSL vulnerability (Refute-or-Promote, arXiv:2604.19049). Execution is the only precision filter that does not share the model's blind spots. See [sota-provenance.md](./sota-provenance.md).

## Downgrade policy

Downgraded ≠ deleted. An unproven finding is reported as PLAUSIBLE with its votes and reasoning intact — the human may still act on it. A refuted finding moves to the report's refuted-appendix WITH its refutation (negative knowledge is a deliverable; supersede-not-rewrite doctrine from crucible).

## Repro-test retention

Default: repro tests stay in `tmp/council-<runId>/repro/` (scratch). The chairman's report offers promotion of fix-acceptance repros into the real test suite as permanent regression guards; the human decides.
