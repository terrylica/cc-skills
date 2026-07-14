---
name: debug
description: Hypothesis-elimination debugging council - parallel falsifiable hypotheses, discriminating experiments, root cause proven by repro-then-fix-then-pass. TRIGGERS - council debug, hypothesis debugging, root cause hunt, falsify hypotheses.
allowed-tools: Workflow, Task, Bash, Read, Grep, Glob, TodoWrite
argument-hint: "[symptom] [--repro cmd] [--suspects paths] [--test-cmd cmd] [--max-rounds N] [--fix]"
disable-model-invocation: true
---

# /council:debug

Popperian debugging loop: parallel generators propose hypotheses that MUST ship a falsifiable prediction and a discriminating experiment (enforced at the schema level — vague hypotheses are rejected by validation, not judgment). Experiments run serially, greedily ordered by discrimination power; hypotheses are eliminated; the survivor is confirmed by **repro-then-fix-then-pass**.

**Surface-first by default.** The council proves the root cause by hypothesis elimination and **proposes** the fix (plain-English + technical) WITHOUT touching your code. Pass `--fix` to apply the minimal confirming fix and INDEPENDENTLY verify it (a separate agent re-runs the repro + suite) — the fix must flip the repro AND keep the suite non-red, or the hypothesis is demoted.

The elimination table is a deliverable, not waste — negative knowledge prevents the next debugger from re-walking dead ends (crucible doctrine).

## Arguments

| Arg | Workflow key | Default | Notes |
|---|---|---|---|
| positional | `symptom` | REQUIRED | What is wrong, observed where |
| `--repro <cmd>` | `repro` | null | Command that reproduces the failure — strongly recommended |
| `--suspects <paths>` | `suspects` | [] | Paths to focus evidence collection on |
| `--test-cmd <cmd>` | `testCmd` | null | Suite command to check the fix doesn't regress (only meaningful with `--fix`) |
| `--max-rounds <n>` | `maxRounds` | 3 | Hypothesis-refinement rounds |
| `--fix` | `fix` | **false** | Apply the minimal confirming fix and independently verify it. Default is surface-first: the root cause + a proposed fix are reported, nothing is edited |

## Step 1 — Preflight

```bash
/usr/bin/env bash << 'EOF'
set -euo pipefail
REPO="$(git rev-parse --show-toplevel)"
RUN_ID="$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "$REPO/tmp/council-$RUN_ID/experiments"
echo "REPO=$REPO RUN_ID=$RUN_ID"
EOF
```

If `--repro` is given, run it once yourself first — if it does NOT fail, stop and tell the user (nothing to debug, or wrong repro).

## Step 2 — Invoke the workflow

Call `Workflow` with `scriptPath: "$CLAUDE_PLUGIN_ROOT/skills/debug/scripts/debug.workflow.mjs"` and args per [schemas.md](../../references/schemas.md) (`repo`, `symptom`, `repro`, `suspects`, `maxRounds`, `fix`, `testCmd`, `runId`, `seed`). Note: by default nothing is edited (the fix is proposed). Only `--fix` (`fix: true`) edits tracked files, and only in the confirmation stage.

## Step 3 — Chairman postmortem (you)

Write the debug report per [report-template.md](../../references/report-template.md): the root cause in **plain English AND technical** terms (statement + mechanism + the experiment that proved it); the fix in **plain English + technical detail** (`proposedFix` when surface-first, `fixSummary` when `--fix`); the full elimination table; surviving uncertainty; and a "what you need to know" block. Default status is `ROOT-CAUSED-UNFIXED` — end by offering to apply the proposed fix. With `--fix`, only declare the bug fixed if the record shows `ROOT-CAUSED` (independent verify: repro `pass` + suite non-red). If `FIX-FAILED` or `UNRESOLVED`, lead with the strongest surviving hypotheses and the experiments a human should run next.

## Fallback — Workflow tool unavailable

Follow [fallback-fanout.md](../../references/fallback-fanout.md) debug procedure: run the repro yourself; ONE message with THREE parallel Task generators (state-corruption / causal-chain / environment lenses); YOU execute the experiments serially via Bash and record EXPERIMENT JSON under `tmp/council-<runId>/`; eliminate; one fixer Task; verify repro+suite yourself.

```
1. Preflight: run repro, capture baseline failure
2. Spawn 3 hypothesis generators in parallel (single message)
3. Validate schema-completeness (falsifiable prediction + experiment) — regenerate once if not
4. Execute experiments serially, greedy by discrimination power
5. Eliminate; refine (≤2 rounds in fallback)
6. Propose the fix (default) — or, with --fix, one fixer Task
7. With --fix: independently verify repro flips + suite non-red; else demote
8. Postmortem report with elimination table
```

## Troubleshooting

| Symptom | Action |
|---|---|
| Repro passes at preflight | Wrong repro or heisenbug — gather more evidence before invoking |
| All hypotheses eliminated | The workflow auto-regenerates with the elimination table as context; if rounds exhaust, the report lists what was ruled out — that IS progress |
| Multiple hypotheses supported | Strongest is confirmed via fix; others reported unresolved — consider a second run focused on them |
| Fix flips repro but suite red | FIX-FAILED by design; the fix regressed something — read the fixSummary and fix manually |
