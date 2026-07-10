---
name: goal-audit
description: Decompose an end goal or spec into hard/soft invariants and audit the implementation against each in depth, surfacing nuances. TRIGGERS - goal audit, invariant audit, spec conformance, does the code meet the goal.
allowed-tools: Workflow, Task, Bash, Read, Grep, Glob, TodoWrite
argument-hint: "[goal-or-spec-file] [--scope paths] [--depth standard|deep] [--base ref]"
disable-model-invocation: true
---

# /council:goal-audit

Given an end goal or spec, answer: **does the implementation actually meet it — letter AND spirit — and what nuances would its author want to know?** Dual decomposition (letter-of-spec: stated requirements read literally; spirit-of-spec: implied expectations — error paths, edge semantics, what would disappoint the author) → per-invariant auditors with file:line evidence → refute-first skeptic pass on claimed violations → execution probes for hard violations. **Report-only** — it never edits the tree; confirmed violations can be chained into `/council:review`'s fix loop.

## Arguments

| Arg | Workflow key | Default | Notes |
|---|---|---|---|
| positional | `goal` | REQUIRED | Goal text or a spec file path — if a readable file, inline its contents |
| `--scope <paths>` | `scope` | [] | Restrict the audit surface |
| `--depth <d>` | `depth` | `standard` | `deep`: read every relevant file fully, trace call chains, check tests; hard invariants get opus auditors |
| `--base <ref>` | `base` | working tree | Audit a specific ref instead |

## Step 1 — Preflight

```bash
/usr/bin/env bash << 'EOF'
set -euo pipefail
REPO="$(git rev-parse --show-toplevel)"
RUN_ID="$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "$REPO/tmp/council-$RUN_ID/repro"
echo "REPO=$REPO RUN_ID=$RUN_ID"
EOF
```

If the positional argument is a file path, read it and pass its contents as `goal`.

## Step 2 — Invoke the workflow

Call `Workflow` with `scriptPath: "$CLAUDE_PLUGIN_ROOT/skills/goal-audit/scripts/goal-audit.workflow.mjs"` and args per [schemas.md](../../references/schemas.md).

## Step 3 — Chairman report (you)

Render the goal-audit template from [report-template.md](../../references/report-template.md):
- **Coverage matrix** — every invariant with kind, letter/spirit origin (L-/S- id prefix), status, evidence citation, linked finding.
- **Nuances surfaced** — the auditors' non-violation observations; this section is the skill's differentiator, do not trim it away.
- **Confirmed violations** — Evidence/Root-cause blocks; PLAUSIBLE ones clearly separated.
- **Next step** — offer to chain confirmed violations into `/council:review` (its fix loop takes each violation as a CONFIRMED finding with the probe artifact as the acceptance test).
- Synthesize rationales, never tally labels; never declare conformance the human hasn't read.

## Fallback — Workflow tool unavailable

Per [fallback-fanout.md](../../references/fallback-fanout.md): TWO parallel decomposer Tasks (letter/spirit) → you merge + tag hard/soft → ≤4 auditor Tasks in one message → 2-skeptic pass on violations → ≤3 sequential probe Tasks for hard violations → coverage-matrix report (note fallback mode).

## Troubleshooting

| Symptom | Action |
|---|---|
| Goal too vague to decompose | The decomposers will produce mostly `spirit` invariants — confirm the checklist with the user before trusting the audit |
| Everything "unverifiable" | Scope too broad or code not present at the audited ref — narrow `--scope` or check `--base` |
| Violation refuted on cross-exam | Its invariant resets to `partial` with a note — read the refutation before celebrating |
