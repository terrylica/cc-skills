---
name: review
description: LLM-council review gate - parallel finder lenses, blind cross-examination, evidence tribunal, autonomous fix loop until green. TRIGGERS - council review, final review gate, evidence-based review, loop until green.
allowed-tools: Workflow, Task, Bash, Read, Grep, Glob, TodoWrite
argument-hint: "[goal-or-spec-file] [--base ref] [--fleet small|standard|large] [--max-fix-rounds N] [--no-fix] [--isolation scratch|clone] [--allow-dirty]"
disable-model-invocation: true
---

# /council:review

Brute-force final review gate for a feature implementation. Pipeline (details: [../../references/](../../references/)):

```
goal ──► invariants ──► finder fleet ──► blind cross-exam ──► evidence tribunal ──► fix loop ──► chairman report
         (hard/soft)    (diverse lenses,  (anonymized,          (CONFIRMED only      (until green)   (you write it)
                         loop-until-dry)   refute-first quorum)   if proven by execution)
```

Findings are **CONFIRMED** only when proven by execution (failing-test repro or runtime trace); everything else is reported as **PLAUSIBLE** and never auto-fixed. See [evidence-ladder.md](../../references/evidence-ladder.md).

## When to use / when not

- USE as the final gate before merging a feature implementation, or on a PR branch, or after a large refactor.
- DO NOT use for tiny cosmetic diffs (use the built-in `code-review` skill), or for diagnosing a known failure (use `/council:debug`), or for auditing without a diff (use `/council:goal-audit`).
- Cost: small/standard/large fleet ≈ 10/25/45+ subagent calls. This is deliberate — the user invoked a brute-force gate.

## Arguments

| Arg | Workflow key | Default | Notes |
|---|---|---|---|
| positional | `goal` | REQUIRED | Goal/spec text, or a path — if a readable file, inline its full contents as `goal` |
| `--base <ref>` | `base` | merge-base vs origin default | The diff base |
| `--fleet <s>` | `fleet` | `auto` | auto: <200 changed lines→small, <1500→standard, else large |
| `--max-fix-rounds <n>` | `maxFixRounds` | 3 | |
| `--no-fix` | `noFix` | false | Report-only; skips the fix loop |
| `--isolation <m>` | `isolation` | `scratch` | `scratch`: provers work in the real tree, writes only under the scratch dir (taint-guarded). `clone`: `git clone --local` to `$TMPDIR` first (use when probes must install/mutate) |
| `--allow-dirty` | — | off | Permit a dirty working tree at preflight |

## Step 1 — Preflight (you, before invoking the workflow)

```bash
/usr/bin/env bash << 'EOF'
set -euo pipefail
REPO="$(git rev-parse --show-toplevel)"          # run inside the target repo
git -C "$REPO" rev-parse HEAD >/dev/null          # sanity: it is a git repo
# dirty check (skip when --allow-dirty)
if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
  echo "DIRTY TREE — pass --allow-dirty to proceed anyway" >&2
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
  "maxFixRounds": 3,
  "noFix": false,
  "isolation": "scratch",
  "runId": "<RUN_ID from preflight>",
  "seed": "<RUN_ID>",
  "testCmd": null
}
```

The workflow runs in the background; you are notified on completion. While waiting, do not start conflicting work in the same repo (fixers edit tracked files unless `--no-fix`).

## Step 3 — Chairman synthesis (you, the main session)

You are the chairman. From the returned council record, write the final report per [report-template.md](../../references/report-template.md). Non-negotiables:

1. **Synthesize rationales — never tally labels.** Vote counts are metadata; your verdict rests on the strongest surviving reasoning plus the execution evidence.
2. Render per-finding: evidence class, votes S/R/U, framing spread, the strongest refutation raised and why it failed.
3. Render the invariant coverage map — every invariant, including satisfied ones.
4. Contested findings: present the disagreement map and how execution settled it — never "majority won".
5. Include the refuted appendix (negative knowledge — stops the next reviewer from re-raising).
6. Offer promotion of repro tests under `tmp/council-<runId>/repro/` into the real suite.
7. End with SHIP / BLOCKED and the single strongest reason. **Never merge, push, or declare shippable on the user's behalf — the human decides.**

If the record status is `STALLED` or `BLOCKED`, lead with what is still confirmed-unfixed and why the loop stopped.

## Fallback — Workflow tool unavailable

Fall back silently (never ask the user to install anything) to the manual fan-out in [fallback-fanout.md](../../references/fallback-fanout.md): parallel `Task` batches in a single message, bookkeeping JSON under `tmp/council-<runId>/`, you perform the deterministic steps (dedup fingerprinting, anonymization, permutation, quorum) yourself. Reduced defaults: 1 finder round · 3 lenses · 2 skeptics · tribunal top-5 · ≤2 fix rounds. Use this TodoWrite template:

```
1. Preflight: scope diff, detect test cmd, scratch dir
2. Build context pack (diff, history, tests, blast radius) → context-pack.md
3. Decompose goal into hard/soft invariants (1 Task) → invariants.json
4. Spawn 3 finder lenses in parallel (single message) → findings.json
5. Dedup + anonymize (PUBLIC_FIELDS only) → anon-map.json
6. Spawn 2 skeptics (PROSECUTE + DEFEND, different orders) → verdicts.json
7. Quorum 2/2 kills; contested flagged; select top-5 for tribunal
8. Tribunal provers sequentially; taint-check git status between each → evidence/
9. Fix loop (≤2 rounds): fixers → re-run repros + suite → scoped re-review
10. Chairman report per report-template.md (note fallback mode in footer)
```

## Troubleshooting

| Symptom | Action |
|---|---|
| No test command detected | Pass `testCmd` explicitly; without one, tribunal still works (runtime traces) but suite checks report `unavailable` |
| Dirty tree at preflight | Commit/stash, or `--allow-dirty` (taint guard then treats the dirty state as baseline) |
| Workflow schema validation errors | The harness retries the agent; persistent failure returns null and the stage degrades — check the run journal |
| Tribunal wave tainted (tracked-file drift) | Evidence auto-downgraded; inspect `git status`, clean up, re-run with `--isolation clone` |
| Budget exhausted mid-tribunal | Expected degradation: un-probed survivors report as PLAUSIBLE with a "not probed" note |
| Fix loop STALLED | Same confirmed set two rounds — fixes aren't landing; review the fixLog and fix manually |

## Post-execution reflection

After the report is delivered, note in one line what the council missed or over-flagged (if known) — feed real misses back into [lenses.md](../../references/lenses.md) as lens-card refinements via a dated evolution-log entry in the plugin CLAUDE.md.
