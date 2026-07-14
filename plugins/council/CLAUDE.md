# CLAUDE.md — council (maintainer SSoT)

**Hub**: [/CLAUDE.md](/CLAUDE.md) · **Plugins spoke**: [/plugins/CLAUDE.md](/plugins/CLAUDE.md) · **User docs**: [README.md](./README.md)

Multi-agent LLM council for code, in the lineage of [karpathy/llm-council](https://github.com/karpathy/llm-council) (parallel first opinions → anonymized peer review → chairman synthesis), upgraded with execution-based evidence gating. Full mechanism→source map: [references/sota-provenance.md](./references/sota-provenance.md).

```
goal → invariants → finder lenses → blind cross-exam → evidence tribunal → chairman (main session) → operator
       hard/soft     loop-until-dry   refute-first       CONFIRMED only        surface-first report:    directs
                                      quorum kill        if proven by execution  plain + technical + ctx  the fixes
```

## Load-bearing invariants (break these and the design breaks)

1. **Schema sync**: JSON schemas are inlined as consts in each `skills/*/scripts/*.workflow.mjs`; the prose SSoT is [references/schemas.md](./references/schemas.md). Any change must land in BOTH.
2. **`export const meta = {…}` stays the first statement** of every workflow script, and stays a pure literal (harness requirement).
3. **Skeptics never see provenance.** `PUBLIC_KEYS`/`publicFields()` is the single anonymization gate; lens/model/round/confidence live in a side-table and rejoin only at chairman-report time. Finder prompts forbid self-reference in output fields.
4. **A kill requires a cross-framing majority** (⌈2S/3⌉ REFUTED spanning both PROSECUTE and DEFEND framings), else a tie-break skeptic on the other framing. Single-framing majorities are anchor bias, not evidence.
5. **Provers never modify tracked files** (taint guard: `git status --porcelain` compared before/after each execution probe — the review tribunal waves, the debug experiments, AND the goal-audit probes; drift ⇒ evidence downgraded to opinion, never auto-reverted). A warden check that cannot run (`agent()` → null) is treated conservatively as tainted, not clean. The **review** workflow never edits the tree at all (surface-first). The only agent allowed to edit tracked files is the **debug `--fix`** confirmation fixer — and its result is judged by an INDEPENDENT verify agent, never the fixer's self-report.
6. **The main session is the chairman.** Workflow scripts return a council record; they must NOT synthesize the final report. Chairman rule: synthesize rationales, never tally labels.
7. **Surface-first is the ONLY review mode — the workflow never fixes anything.** `/council:review` always returns `REPORT_ONLY`; there is no autonomous fix loop and no `fix` arg. The operator reads the report and directs fixes per finding (SKILL.md Step 4), where each CONFIRMED finding's failing repro is that fix's acceptance test. PLAUSIBLE is reported with a proposed fix but never fixed without a tribunal probe first. (`/council:debug` defaults the same way — it proposes the fix; `--fix` applies it and independently verifies.)
8. **No Date.now()/Math.random()/new Date() in workflow scripts** (harness forbids them — breaks resume). `runId` arrives via args from the skill preflight; shuffles use the seeded mulberry32 PRNG.
9. **No Python argparse CLIs in this plugin.** Adding one obligates regenerating the repo-root `cli_spec.json` and keeping `mise run cli-spec-check` green.

## Files

| Path | Purpose |
|---|---|
| `skills/review/SKILL.md` + `scripts/review.workflow.mjs` | `/council:review` — the flagship surface-first gate (P0 pack → P1 invariants → P2 finders → P3 cross-exam → P4 tribunal → chairman report; no fix loop) |
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
| Finders (most lenses), skeptics, provers, debug fixer, experimenters | sonnet / high |
| Inversion lens, invariant decomposition, disagreement mapper, defend-framing + tie-break skeptics, contested provers, letter+spirit decomposers | opus / high |

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
- `scratch` isolation trusts the taint guard rather than preventing writes; truly hostile probes need `--isolation clone` (which `git clone --local`s into `$TMPDIR` at the START of P0 and points every reviewer/prover there). Review is surface-first and edits nothing, so `clone` is pure, fully-sandboxed investigation.
- Repro tests live in scratch by default; promotion into the real suite is a human decision offered by the chairman.
- Fallback mode (no Workflow tool) uses reduced defaults and main-session orchestration — slower and less parallel by design.

## Evolution log

- 2026-07-13 — **Surface-first is now the ONLY review mode; the autonomous fix loop was removed entirely** (operator directive: the council surfaces, the operator directs fixes). `review.workflow.mjs` dropped the `fix`/`maxFixRounds` args and the whole P6 loop (~165 lines) and always returns `REPORT_ONLY`; `debug` now defaults to *proposing* the fix (`--fix` applies it, and an INDEPENDENT verify agent replaces the fixer's self-report — the suite gate now fails on `not-run`/`red`, not only `red`). Reporting rebuilt: every finding surfaces with a plain-English explanation + a plain-English & technical fix + operator context (new `proposed_fix`/`fix_summary_plain` on EVIDENCE; `report-template.md` rewritten around a four-block surfacing contract). Gaps closed from the PR-#5 audit: goal-audit gained the taint-guard warden it lacked (invariant #5 is now genuinely plugin-wide); `--isolation clone` is created *before* the context pack (ordering bug) and no longer interacts with any fix loop; `changedLines` is required in `PACK_OUT`; `fingerprint()` keys on line + a 12-word stem (recall); the defend-seat opus skeptic runs at full effort (F-20); the single-framing tie-break routes each finding to its correct opposite framing; dead code and `INV-07` mis-refs removed; docs de-drifted (SKILL argument-hints, quorum-math SSoT moved into `lenses.md`, the "Judging the Judges" citation split into its two real papers, evidence-ladder CONFIRMED wording disambiguated); added the missing `.claude-plugin/plugin.json`.
- 2026-07-09 — Initial build: three skills, six lens cards, cross-framing quorum, evidence tribunal with taint guard, loop-until-green fix cycle. Toy-repo acceptance run + self-dogfood performed pre-merge.
- 2026-07-09 — Dogfood fixes to `review.workflow.mjs`: budget guards use `budget.total - budget.spent()` (no `remaining()` — matches the probed harness contract); `--isolation clone` now actually clones into `$TMPDIR` and redirects reviewers/provers; skeptic panel clamps to ≥2 and hands the opus reasoner the defend framing; the fix-loop reprove call is taint-guarded like tribunal waves; an inconclusive (null) warden downgrades evidence; NON-FLIPPABLE fix-acceptance resolves per-finding via touched-file overlap rather than one global flag; final status BLOCKs on a red suite; a `violated` coverage vote is downgraded once its supporting findings are refuted; tribunal provers namespace repros under `repro/<anonId>/`.
- 2026-07-09 — **Surface-first default** (operator decision after observing the dogfood fix loop chase its own repro artifacts): `/council:review` now stops after the tribunal and reports (`REPORT_ONLY`); the autonomous loop requires explicit `--fix` (`fix: true`; legacy `noFix` honored). New SKILL.md Step 4: selective fixing — the human names finding IDs, each CONFIRMED finding's failing repro is the fix's acceptance test; PLAUSIBLE selections get a tribunal probe before any fix.
