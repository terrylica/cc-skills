---
name: review
description: LLM-council review gate - parallel finder lenses, blind cross-examination, execution-based evidence tribunal. Surface-first - each finding is reported with execution proof, a plain-English + technical fix, and operator context; the human directs which findings to fix. TRIGGERS - council review, final review gate, evidence-based review, surface findings.
allowed-tools: Workflow, Task, Bash, Read, Grep, Glob, TodoWrite
argument-hint: "[goal-or-spec-file] [--base ref] [--scope paths] [--fleet small|standard|large] [--isolation scratch|clone]"
disable-model-invocation: true
---

# /council:review

Brute-force final review gate for a feature implementation. Pipeline (details: [../../references/](../../references/)):

```
goal ──► invariants ──► finder fleet ──► blind cross-exam ──► evidence tribunal ──► chairman report
         (hard/soft)    (diverse lenses,  (anonymized,          (CONFIRMED only      (you write it:
                         loop-until-dry)   refute-first quorum)   if proven by execution)  plain + technical + context)
```

Findings are **CONFIRMED** only when proven by execution (failing-test repro or runtime trace); everything else is reported as **PLAUSIBLE**. See [evidence-ladder.md](../../references/evidence-ladder.md).

**Surface-first — this gate never edits code.** The pipeline runs through the tribunal, then STOPS and reports: every finding gets a plain-English explanation, a plain-English + technical fix, and operator context (Step 3). The operator then directs which findings to fix (Step 4). There is intentionally no autonomous fix loop — a loop's termination signal inherits every imperfection of its own repro artifacts, so a human between "report" and "fix" is the control point.

## When to use / when not

- USE as the final gate before merging a feature implementation, or on a PR branch, or after a large refactor.
- DO NOT use for tiny cosmetic diffs (use the built-in `code-review` skill), or for diagnosing a known failure (use `/council:debug`), or for auditing without a diff (use `/council:goal-audit`).
- Cost: small/standard/large fleet ≈ 10/25/45+ subagent calls. This is deliberate — the user invoked a brute-force gate.

## Arguments

| Arg | Workflow key | Default | Notes |
|---|---|---|---|
| positional | `goal` | REQUIRED | Goal/spec text, or a path — if a readable file, inline its full contents as `goal` |
| `--base <ref>` | `base` | merge-base vs origin default | The diff base |
| `--scope <paths>` | `scope` | `[]` | Optional path globs restricting the review surface |
| `--fleet <s>` | `fleet` | `auto` | auto: <200 changed lines→small, <1500→standard, else large |
| `--isolation <m>` | `isolation` | `scratch` | `scratch`: provers work in the real tree, writes only under the scratch dir (taint-guarded). `clone`: `git clone --local` to `$TMPDIR` first (use when probes must install/mutate). Either way the real tree is never edited — this gate only surfaces. |

## Step 1 — Preflight (you, before invoking the workflow)

```bash
/usr/bin/env bash << 'EOF'
set -euo pipefail
REPO="$(git rev-parse --show-toplevel)"          # run inside the target repo
git -C "$REPO" rev-parse HEAD >/dev/null          # sanity: it is a git repo
# dirty tree is advisory only — the taint guard baselines the current status, so a dirty
# tree is safe; it just makes taint messages noisier. Prefer a clean tree.
if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
  echo "NOTE: working tree is dirty — review proceeds (taint guard baselines the current state)" >&2
fi
RUN_ID="$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "$REPO/tmp/council-$RUN_ID"
git -C "$REPO" check-ignore -q "tmp/council-$RUN_ID" \
  || echo "WARN: tmp/ not gitignored in this repo — scratch dir will show as untracked (taint guard accounts for it, but prefer ignoring tmp/)"
echo "REPO=$REPO RUN_ID=$RUN_ID"
EOF
```

Also: if the positional argument is a file path, read it and use its contents as the goal. If there is no diff vs the base, stop and tell the user.

## Step 2 — Invoke the workflow

Call the `Workflow` tool with `scriptPath: "$CLAUDE_PLUGIN_ROOT/skills/review/scripts/review.workflow.mjs"` and args assembled from the table (full args schema: [schemas.md](../../references/schemas.md)). Do **not** re-implement the stages inline when the Workflow tool is available. Example:

```json
{
  "repo": "/abs/path/to/repo",
  "goal": "<full goal/spec text>",
  "base": "origin/main",
  "fleet": "auto",
  "isolation": "scratch",
  "runId": "<RUN_ID from preflight>",
  "seed": "<RUN_ID>",
  "testCmd": null
}
```

The workflow runs in the background; you are notified on completion. While waiting, do not start conflicting work in the same repo. This gate never edits tracked files — only scratch files under `tmp/council-<runId>/` are created.

## Step 3 — Chairman synthesis (you, the main session)

You are the chairman. From the returned council record (status is always `REPORT_ONLY` — nothing was changed), write the final report per [report-template.md](../../references/report-template.md). Render, for EVERY finding, the four-block **surfacing contract**:

1. **What's wrong — plain English.** Explain the defect to a smart non-specialist: what breaks, the exact trigger, the real-world impact. Readable, **not oversimplified** — keep the real mechanism, just say it in words. Define any load-bearing jargon in half a clause.
2. **How sure we are — evidence.** Evidence class + what was observed (repro command + failing output for CONFIRMED; the file:line chain for PLAUSIBLE, marked "not yet proven by execution — treat as a lead"). Votes S/R/U and framing are metadata; give the strongest refutation raised and why it failed.
3. **How to fix it — plain English + technical.** First the plain-English fix (`fix_summary_plain`: what it does and why it removes the problem), then the **technical fix** (`proposed_fix`: file(s), root cause, exact change). For PLAUSIBLE findings, mark the fix a *proposed direction* that needs a tribunal probe before anyone edits code.
4. **What you need to know — operator context.** Blast radius, fix risk/cost, whether a repro can be promoted into the suite, any A/B judgment call the operator must settle — or "No special considerations."

Also non-negotiable: **synthesize rationales, never tally labels**; render the full invariant coverage map (including satisfied invariants); present contested findings as disagreement maps settled by execution (never "majority won"); include the refuted appendix (negative knowledge); offer to promote repro tests under `tmp/council-<runId>/repro/`. End with a recommendation **in words** plus the Step 4 fix-direction offer. **Never merge, push, apply a fix, or declare shippable on the user's behalf — the human decides.**

## Step 4 — Directed fixing (you apply, the operator decides)

Surface-first: nothing is fixed until the operator names finding IDs ("fix F-03 and F-07"). For each selected finding:

1. **Acceptance test.** A CONFIRMED finding backed by a `failing-test-repro` ships with a failing repro under `tmp/council-<runId>/repro/<id>/` — that repro is the fix's acceptance test (must flip fail→pass). A `runtime-trace`, or a repro tagged **NON-FLIPPABLE** (e.g. a demonstrated test-gap), has no flip to check — accept it by re-running the trace / a scoped re-review instead, and say which you used.
2. **Apply at root cause** using the finding's `proposed_fix` — yourself, or one fixer subagent per finding. If you fan out fixers, run them **serially**: a finding anchored in one file is often fixed in another (a test-gap anchored in `tests/` fixed in `src/`), so file-keyed grouping does NOT guarantee disjoint edits — serial execution is the only collision-proof option.
3. **Verify.** Re-run the finding's repro (flip fail→pass) and the project suite (must stay green, excluding the scratch dir).
4. **Report per finding**: files touched, repro before/after, suite result. PLAUSIBLE findings the operator selects get a tribunal probe FIRST — never fix on an unproven claim.

## Fallback — Workflow tool unavailable

Fall back silently (never ask the user to install anything) to the manual fan-out in [fallback-fanout.md](../../references/fallback-fanout.md): parallel `Task` batches in a single message, bookkeeping JSON under `tmp/council-<runId>/`, you perform the deterministic steps (dedup fingerprinting, anonymization, permutation, quorum) yourself. Reduced defaults: 1 finder round · 3 lenses · 2 skeptics · tribunal top-5. Surface-first still holds — no fix loop; you report, the operator directs fixes. Use this TodoWrite template:

```
1. Preflight: scope diff, detect test cmd, scratch dir
2. Build context pack (diff, history, tests, blast radius) → context-pack.md
3. Decompose goal into hard/soft invariants (1 Task) → invariants.json
4. Spawn 3 finder lenses in parallel (single message) → findings.json
5. Dedup + anonymize (PUBLIC_FIELDS only) → anon-map.json
6. Spawn 2 skeptics (PROSECUTE + DEFEND, different orders) → verdicts.json
7. Quorum 2/2 kills; contested flagged; select top-5 for tribunal
8. Tribunal provers sequentially; taint-check git status between each → evidence/ (capture proposed_fix per finding)
9. Chairman report per report-template.md — four-block surfacing per finding; note fallback mode. Fixes only on operator direction (Step 4).
```

## Troubleshooting

| Symptom | Action |
|---|---|
| No test command detected | Pass `testCmd` explicitly; without one, tribunal still works (runtime traces) but suite checks report `unavailable` |
| Dirty tree at preflight | Advisory only — the taint guard baselines the current state; prefer a clean tree to keep taint messages quiet |
| Workflow schema validation errors | The harness retries the agent; persistent failure returns null and the stage degrades — check the run journal |
| Tribunal wave tainted (tracked-file drift) | Evidence auto-downgraded; inspect `git status`, clean up, re-run with `--isolation clone` |
| Budget exhausted mid-tribunal | Expected degradation: un-probed survivors report as PLAUSIBLE with a "not probed" note |

## Post-execution reflection

After the report is delivered, note in one line what the council missed or over-flagged (if known) — feed real misses back into [lenses.md](../../references/lenses.md) as lens-card refinements via a dated evolution-log entry in the plugin CLAUDE.md.
