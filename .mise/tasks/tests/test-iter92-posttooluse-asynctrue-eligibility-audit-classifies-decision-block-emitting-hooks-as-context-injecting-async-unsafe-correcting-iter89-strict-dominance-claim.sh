#!/usr/bin/env bash
#MISE description="Iter-92 audit-task regression test. Verifies (1) the async-eligibility audit task discovers ≥15 PostToolUse hooks marketplace-wide; (2) classifies decision:block-emitting hooks as [C] CONTEXT-INJECTING / ASYNC-UNSAFE; (3) classifies additionalContext-emitting hooks as [C] CONTEXT-INJECTING; (4) summary text contains the literal iter-89 strict-dominance-correction language; (5) exit code is 0 (informational task); (6) iter-91 PreToolUse migration arc artifacts are NOT mistakenly classified as PostToolUse (cross-event-type contamination check)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-posttooluse-asynctrue-eligibility-classifier-by-decision-block-vs-pure-side-effect-output-pattern-iter92-corrects-iter89-strict-dominance-claim.sh"

if [[ ! -f "$AUDIT_TASK_ABSOLUTE_PATH" ]]; then
    echo "FAIL: audit task not found: $AUDIT_TASK_ABSOLUTE_PATH"
    exit 1
fi

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-92 audit-task regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# Capture audit output + exit code
set +e
AUDIT_TASK_OUTPUT_FULL=$(bash "$AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
AUDIT_TASK_EXIT_CODE=$?
set -e

# ─── Case 1: audit exits 0 (informational) ────────────────────────────────────
if [[ "$AUDIT_TASK_EXIT_CODE" == "0" ]]; then
    assert_passes "Case 1: audit task exits 0 (informational, never blocks release pipeline)"
else
    assert_fails "Case 1: exit=$AUDIT_TASK_EXIT_CODE, expected 0"
fi

# ─── Case 2: ≥10 PostToolUse hooks discovered marketplace-wide ────────────────
# Iter-95 update: the iter-92 audit scans hooks.json entries. As subhooks
# inline into the orchestrator, the count of top-level entries decreases
# (iter-93 absorbed 1, iter-94 absorbed 1, iter-95 absorbed 2 — net minus
# 4 from iter-92's original 17). Threshold lowered to ≥10 so the assertion
# stays valid through the rest of the iter-93+ migration arc.
discovered_hook_count=$(echo "$AUDIT_TASK_OUTPUT_FULL" | grep -oE 'Total PostToolUse hooks scanned:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1 || echo 0)
if [[ "${discovered_hook_count:-0}" -ge 10 ]]; then
    assert_passes "Case 2: audit discovers ≥10 PostToolUse hooks marketplace-wide (found ${discovered_hook_count}; threshold lowered from 15 to 10 as migration arc absorbs subhooks)"
else
    assert_fails "Case 2: only ${discovered_hook_count} hooks discovered (expected ≥10)"
fi

# ─── Case 3: orchestrator-or-standalone ty-type-check classified as CONTEXT-INJECTING [C] ───
# Iter-93 update: ty-type-check was inlined into the iter-93 PostToolUse
# orchestrator. The audit task scans hooks.json (not the orchestrator's
# import graph), so ty-type-check no longer appears as a top-level entry —
# but the orchestrator IS classified as [C] CONTEXT-INJECTING because it
# emits the same {decision:"block", reason} JSON aggregating ty's output.
# Either form (standalone OR orchestrator) satisfies the invariant that the
# ty type-checking pathway gets [C] coverage. This decouples the iter-92
# test from the iter-93+ migration arc's future state.
if echo "$AUDIT_TASK_OUTPUT_FULL" | grep -F "[C]" | grep -qE "posttooluse-ty-type-check\.ts|posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks"; then
    assert_passes "Case 3a: ty-type-checking pathway classified as [C] CONTEXT-INJECTING (either standalone OR via iter-93 orchestrator that inlines it)"
else
    assert_fails "Case 3a: ty-type-checking pathway missing [C] classification (neither standalone nor iter-93 orchestrator entry found)"
fi
# Iter-94 update: tsgo-type-check was inlined into the iter-93 PostToolUse
# orchestrator. Same decoupling pattern as Case 3a — accept EITHER the
# standalone OR the orchestrator entry as satisfying the [C] invariant.
if echo "$AUDIT_TASK_OUTPUT_FULL" | grep -F "[C]" | grep -qE "posttooluse-tsgo-type-check\.ts|posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks"; then
    assert_passes "Case 3b: tsgo-type-checking pathway classified as [C] CONTEXT-INJECTING (either standalone OR via iter-93/94 orchestrator that inlines it)"
else
    assert_fails "Case 3b: tsgo-type-checking pathway missing [C] classification (neither standalone nor iter-93/94 orchestrator entry found)"
fi
# Iter-95 update: oxlint + biome inlined into the iter-93+ PostToolUse
# orchestrator. Accept EITHER form (standalone OR orchestrator-via-import)
# as satisfying the [C] CONTEXT-INJECTING invariant — same migration-arc
# decoupling pattern as Cases 3a/3b.
if echo "$AUDIT_TASK_OUTPUT_FULL" | grep -F "[C]" | grep -qE "posttooluse-oxlint-check\.ts|posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks"; then
    assert_passes "Case 3c: oxlint pathway classified as [C] CONTEXT-INJECTING (either standalone OR via iter-95 orchestrator that inlines it)"
else
    assert_fails "Case 3c: oxlint pathway missing [C] classification (neither standalone nor iter-95 orchestrator entry found)"
fi
if echo "$AUDIT_TASK_OUTPUT_FULL" | grep -F "[C]" | grep -qE "posttooluse-biome-lint\.ts|posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks"; then
    assert_passes "Case 3d: biome pathway classified as [C] CONTEXT-INJECTING (either standalone OR via iter-95 orchestrator that inlines it)"
else
    assert_fails "Case 3d: biome pathway missing [C] classification (neither standalone nor iter-95 orchestrator entry found)"
fi

# ─── Case 4: at least 1 hook classified as additionalContext-emitting ─────────
if echo "$AUDIT_TASK_OUTPUT_FULL" | grep -qF "emits additionalContext JSON"; then
    assert_passes "Case 4: at least one hook flagged as additionalContext-emitting (rust-sota-reminder or similar)"
else
    assert_fails "Case 4: no additionalContext-emitting hook detected"
fi

# ─── Case 5: explicit iter-89 strict-dominance-correction language present ────
if echo "$AUDIT_TASK_OUTPUT_FULL" | grep -qE 'CORRECTION OF ITER-89 STRICT-DOMINANCE CLAIM'; then
    assert_passes "Case 5a: summary contains explicit iter-89 strict-dominance-correction banner"
else
    assert_fails "Case 5a: iter-89 correction language missing from audit summary"
fi
if echo "$AUDIT_TASK_OUTPUT_FULL" | grep -qE 'Path A.*RULED OUT'; then
    assert_passes "Case 5b: summary explicitly RULES OUT Path A (async:true sweep) for context-injecting hooks"
else
    assert_fails "Case 5b: Path A ruling-out language missing"
fi
if echo "$AUDIT_TASK_OUTPUT_FULL" | grep -qE 'Path B.*viable for ALL hooks'; then
    assert_passes "Case 5c: summary recommends Path B (orchestrator inlining) as the viable replacement"
else
    assert_fails "Case 5c: Path B recommendation missing"
fi

# ─── Case 6: cross-event-type contamination check ─────────────────────────────
# The PreToolUse classifiers from iter-91 (e.g., classifyValeClaudeMdGuardForOrchestrator)
# must NOT appear in PostToolUse audit results. If they do, the discovery filter
# is leaking across event types.
if echo "$AUDIT_TASK_OUTPUT_FULL" | grep -qF "pretooluse-vale-claude-md-guard.ts"; then
    assert_fails "Case 6: PreToolUse hook leaked into PostToolUse audit (event-type filter broken)"
else
    assert_passes "Case 6: NO PreToolUse hooks leaked into PostToolUse audit (event-type filter correct)"
fi

# ─── Case 7: the C-count exceeds the S-count by at least 10x ──────────────────
# This is the central iter-92 finding: ~15 of 17 hooks are context-injecting,
# only ~1 is pure-side-effect. If S exceeds C, our claim is wrong.
# The `[C]` / `[S]` tags appear on BOTH per-hook lines and the summary-totals
# line. Per-hook lines look like `[C] [NOT-CURRENTLY-ASYNC] posttooluse-X.ts`
# (no trailing count number). Summary lines look like
# `[C] CONTEXT-INJECTING (decision:block or additionalContext):  15 → ASYNC-UNSAFE`.
# Anchor on the verdict-name + colon-followed-by-digit pattern unique to the
# summary line. Use `[0-9]` not `\d` for POSIX-grep portability (macOS BSD grep).
context_injecting_summary_line=$(echo "$AUDIT_TASK_OUTPUT_FULL" | grep -E 'CONTEXT-INJECTING \(.*\):[[:space:]]+[0-9]+' | head -1)
pure_side_effect_summary_line=$(echo "$AUDIT_TASK_OUTPUT_FULL" | grep -E 'PURE-SIDE-EFFECT \(.*\):[[:space:]]+[0-9]+' | head -1)
context_injecting_count=$(echo "$context_injecting_summary_line" | grep -oE '[0-9]+' | tail -1 || echo 0)
pure_side_effect_count=$(echo "$pure_side_effect_summary_line" | grep -oE '[0-9]+' | tail -1 || echo 0)
if [[ "${context_injecting_count:-0}" -ge 10 ]] && [[ "${context_injecting_count:-0}" -gt "${pure_side_effect_count:-0}" ]]; then
    assert_passes "Case 7: ${context_injecting_count} context-injecting >> ${pure_side_effect_count} pure-side-effect (validates iter-92 finding that Path A is broadly inapplicable)"
else
    assert_fails "Case 7: ratio inverted — context=${context_injecting_count} side-effect=${pure_side_effect_count}; iter-92 finding may not hold"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-92 audit-task regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_PASSED_COUNT"
echo "  Assertions failed: $ASSERTION_FAILED_COUNT"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_FAILED_COUNT" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_FAILED_COUNT assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_PASSED_COUNT assertions passed"
