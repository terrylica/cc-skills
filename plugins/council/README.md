# council

Multi-agent LLM council for code. In the lineage of [Karpathy's llm-council](https://github.com/karpathy/llm-council) — parallel first opinions, **anonymized** peer review, chairman synthesis — rebuilt for code review with one decisive upgrade: **findings must be proven by execution before anything acts on them.**

```
            ┌─ inversion ─────────┐
goal ──► invariants ─► ┌─ decomposition ─┐ ──► blind cross-exam ──► evidence tribunal ──► chairman report
        (hard/soft)    ├─ dependency-graph┤     anonymized,          failing-test repro     (main session, surface-first:
                       │                  │                                                  plain + technical + context;
                       ├─ adversarial ───┤     refute-first          or runtime trace        you direct the fixes)
                       ├─ spec-conform ──┤     quorum kill           = CONFIRMED
                       └─ static tools ──┘     (loop until dry)      else PLAUSIBLE
```

## Skills

| Command | What it does |
|---|---|
| `/council:review <goal> [--base ref] [--scope paths] [--fleet small\|standard\|large]` | Final review gate for a feature implementation: diverse finder lenses → blind cross-examination → evidence tribunal → **surface-first report** with a plain-English + technical fix per finding. The council never edits code; you direct which findings to fix |
| `/council:debug <symptom> [--repro cmd] [--test-cmd cmd] [--fix]` | Hypothesis-elimination debugging: falsifiable hypotheses, discriminating experiments, root cause. Surface-first: proposes the fix; `--fix` applies it and independently verifies (repro-then-fix-then-pass) |
| `/council:goal-audit <goal> [--depth deep]` | Letter + spirit spec decomposition, per-invariant conformance audit, nuance surfacing — report-only |

## What makes it different

- **Blind cross-examination** — findings are anonymized and order-shuffled before skeptics see them; skeptics must articulate the strongest refutation even when agreeing; a kill requires a majority spanning both PROSECUTE and DEFEND framings (order/anchor-bias controls from the LLM-judge literature).
- **Evidence tribunal** — a finding is **CONFIRMED** only when a prover reproduces it (failing test or runtime trace) in your repo, under a taint guard that forbids touching tracked files. Everything unproven is reported as **PLAUSIBLE** and never fixed without your direction — LLM critics over-report, and execution is the only precision filter that doesn't share their blind spots.
- **Surface-first, human in charge** — the review council reports and stops; it never edits code. Every finding arrives with a plain-English explanation, a plain-English + technical fix, and the operator context you need to decide. You then name the finding IDs to fix, and each CONFIRMED finding's failing repro becomes that fix's acceptance test. There is no autonomous fix loop — a loop's stop signal inherits every flaw of its own repro artifacts, so a human owns the fix decision.
- **Negative knowledge kept** — refuted findings ship in the report with their refutations; eliminated debug hypotheses ship in an elimination table.
- **You stay in charge** — the main session writes the final report as chairman and never merges; the human reads the report and decides.

Full research provenance for every mechanism: [references/sota-provenance.md](./references/sota-provenance.md).

## Quickstart

```
/council:review docs/specs/checkout-v2.md --base origin/main
/council:review "Add rate limiting to the API per the issue #142 spec" --fleet large
/council:debug "pipeline crashes on empty parquet partitions" --repro "pytest tests/test_ingest.py -k empty"
/council:goal-audit docs/adr/0042-caching.md --depth deep
```

## Cost expectations

| Fleet | Trigger (auto) | Typical subagent calls |
|---|---|---|
| small | <200 changed lines | ~10 |
| standard | <1500 | ~25 |
| large | ≥1500 (or `--fleet large`) | 45+ |

This is a deliberate brute-force gate — use the built-in `code-review` skill for quick passes. Review runs are always report-only (surface-first) — no fixer agents; you direct the fixes afterward.

## When NOT to use

- Tiny cosmetic diffs (built-in `code-review` is cheaper and fine)
- Diagnosing a known failure → `/council:debug`, not `/council:review`
- No git repo / no diff → `/council:goal-audit` audits a working tree against a goal

## Fallback behavior

If the Workflow tool is unavailable, each skill falls back to a reduced manual fan-out (parallel Task batches, 2 skeptics, tribunal top-5) and says so in the report footer — no installation required. Details: [references/fallback-fanout.md](./references/fallback-fanout.md).
