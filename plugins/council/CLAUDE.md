# CLAUDE.md — council (maintainer SSoT)

**Hub**: [/CLAUDE.md](/CLAUDE.md) · **Plugins spoke**: [/plugins/CLAUDE.md](/plugins/CLAUDE.md) · **User docs**: [README.md](./README.md)

Multi-agent LLM council for code, in the lineage of [karpathy/llm-council](https://github.com/karpathy/llm-council) (parallel first opinions → anonymized peer review → chairman synthesis), upgraded with execution-based evidence gating. Full mechanism→source map: [references/sota-provenance.md](./references/sota-provenance.md).

```
goal → invariants → finder lenses → blind cross-exam → evidence tribunal → fix loop → chairman (main session)
       hard/soft     loop-until-dry   refute-first       CONFIRMED only       until green
                                      quorum kill        if proven by execution
```

## Load-bearing invariants (break these and the design breaks)

1. **Schema sync**: JSON schemas are inlined as consts in each `skills/*/scripts/*.workflow.mjs`; the prose SSoT is [references/schemas.md](./references/schemas.md). Any change must land in BOTH.
2. **`export const meta = {…}` stays the first statement** of every workflow script, and stays a pure literal (harness requirement).
3. **Skeptics never see provenance.** `PUBLIC_KEYS`/`publicFields()` is the single anonymization gate; lens/model/round/confidence live in a side-table and rejoin only at chairman-report time. Finder prompts forbid self-reference in output fields.
4. **A kill requires a cross-framing majority** (⌈2S/3⌉ REFUTED spanning both PROSECUTE and DEFEND framings), else a tie-break skeptic on the other framing. Single-framing majorities are anchor bias, not evidence.
5. **Provers never modify tracked files** (taint guard: `git status --porcelain` compared before/after each tribunal wave; drift ⇒ evidence downgraded to opinion, never auto-reverted). **Fixers are the only agents allowed to edit the real tree**, and only in the fix loop / debug confirmation.
6. **The main session is the chairman.** Workflow scripts return a council record; they must NOT synthesize the final report. Chairman rule: synthesize rationales, never tally labels.
7. **Only CONFIRMED findings (failing-test-repro or runtime-trace, `reproduced: true`) enter the autonomous fix loop.** PLAUSIBLE is reported, never auto-fixed.
8. **No Date.now()/Math.random()/new Date() in workflow scripts** (harness forbids them — breaks resume). `runId` arrives via args from the skill preflight; shuffles use the seeded mulberry32 PRNG.
9. **No Python argparse CLIs in this plugin.** Adding one obligates regenerating the repo-root `cli_spec.json` and keeping `mise run cli-spec-check` green.

## Files

| Path | Purpose |
|---|---|
| `skills/review/SKILL.md` + `scripts/review.workflow.mjs` | `/council:review` — the flagship gate (P0 pack → P1 invariants → P2 finders → P3 cross-exam → P4 tribunal → P6 fix loop) |
| `skills/debug/SKILL.md` + `scripts/debug.workflow.mjs` | `/council:debug` — falsifiable hypotheses → discriminating experiments → repro-then-fix-then-pass |
| `skills/goal-audit/SKILL.md` + `scripts/goal-audit.workflow.mjs` | `/council:goal-audit` — letter/spirit decomposition → per-invariant audit → coverage matrix (report-only) |
| `references/schemas.md` | Prose SSoT for all JSON schemas + workflow args |
| `references/lenses.md` | Finder lens prompt-cards (SSoT), fleet composition, rotation, skeptic framings |
| `references/evidence-ladder.md` | Evidence classes, classification rules, CONFIRMED/PLAUSIBLE dial, downgrade policy |
| `references/report-template.md` | Chairman report skeletons (all 3 modes) |
| `references/sota-provenance.md` | Mechanism → paper/source → implementation-site map |
| `references/fallback-fanout.md` | Manual Task fan-out when the Workflow tool is unavailable |

## Model/effort matrix (tuning SSoT)

| Stage | Model / effort |
|---|---|
| Context pack, warden, verifier | haiku / low–medium |
| Finders (most lenses), skeptics, provers, fixers, experimenters | sonnet / high |
| Inversion lens, invariant decomposition, disagreement mapper, tie-break skeptic, contested provers, letter+spirit decomposers | opus / high |

Fleet sizes (review): small <200 changed lines (3 finders) · standard <1500 (6) · large (9 finders + 5 skeptics). Change lens cards in [references/lenses.md](./references/lenses.md) first, then mirror the condensed versions in the scripts.

## Cost tiers & degradation ladder

Typical subagent calls: small ≈ 10 · standard ≈ 25 · large ≈ 45+. Under budget pressure (when the user set a token target) the scripts degrade in order: end finder loop early → cap tribunal to top-5 by severity (rest report PLAUSIBLE "not probed") → stop fix loop with `BLOCKED`. Degradations are always logged, never silent.

## Probed Workflow-tool contract (re-probe on harness upgrades)

Verified 2026-07-09 via a live probe run: `agent()` with `schema` returns validated objects (retry-on-mismatch at the tool layer) · `parallel()` of thunks works with null-on-failure semantics · `args` round-trips objects/arrays verbatim · `budget.total` is `null` when no token target was set; `budget.spent()` returns a number · scripts execute with top-level `return` under an async wrapper (plain `node --check` false-fails; parse-check with an `AsyncFunction` constructor instead).

## Edit conventions

- Append dated entries to the evolution log below; don't rewrite history (supersede-not-rewrite).
- Real-world council misses/over-flags feed back into lens cards via the review skill's post-execution reflection.
- Keep SKILL.md descriptions ending with `TRIGGERS - …`; all three skills stay `disable-model-invocation: true` (expensive — explicit `/council:*` only).

## Known limitations

- Reviewer diversity is intra-Claude (lens × tier × effort), not cross-provider; correlated blind spots are mitigated, not eliminated — the evidence tribunal is the backstop.
- `scratch` isolation trusts the taint guard rather than preventing writes; truly hostile probes need `--isolation clone`.
- Repro tests live in scratch by default; promotion into the real suite is a human decision offered by the chairman.
- Fallback mode (no Workflow tool) uses reduced defaults and main-session orchestration — slower and less parallel by design.

## Evolution log

- 2026-07-09 — Initial build: three skills, six lens cards, cross-framing quorum, evidence tribunal with taint guard, loop-until-green fix cycle. Toy-repo acceptance run + self-dogfood performed pre-merge.
