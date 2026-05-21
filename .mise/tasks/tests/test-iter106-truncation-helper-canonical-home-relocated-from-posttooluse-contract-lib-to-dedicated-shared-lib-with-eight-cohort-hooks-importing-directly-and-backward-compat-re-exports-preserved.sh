#!/usr/bin/env bash
#MISE description="Iter-106 regression test for the truncation-helper canonical-home invariant. Verifies (1) audit-task existence + executability; (2) live audit passes; (3) iter-106 shared-lib file exists with literal exports; (4) PostToolUse contract lib re-exports from shared lib (backward compat) WITHOUT duplicating definitions; (5) all 8 iter-105 cohort hooks import helper from shared-lib canonical home; (6) helper signature + threshold (9000) unchanged from iter-104 baseline; (7) iter-105 audit still passes (canonical-home relocation did not break marketplace-wide invariant)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-truncation-helper-canonical-home-relocated-from-posttooluse-contract-lib-to-dedicated-cross-pretooluse-and-posttooluse-shared-lib-iter106-eliminates-iter105-cross-lib-import-awkwardness.sh"
SHARED_LIB_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts"
POSTTOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts"
ITER105_AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-pretooluse-and-posttooluse-hook-classifiers-for-unbounded-reason-emission-not-wrapped-in-canonical-truncation-helper-against-claude-file-spillover-threshold-iter105-marketplace-scale-of-iter104-single-hook-fix.sh"

declare -a EIGHT_COHORT_HOOK_ABSOLUTE_PATHS=(
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-vale-claude-md.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-ty-type-check.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-tsgo-type-check.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-oxlint-check.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-biome-lint.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-ssot-principles.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-vale-claude-md-guard.ts"
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"
)

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-106 truncation-helper canonical-home regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: iter-106 audit task exists + is executable ──────────────────
if [[ -x "$AUDIT_TASK_ABSOLUTE_PATH" ]]; then
    assert_passes "Case 1: iter-106 audit task exists + is executable"
else
    assert_fails "Case 1: iter-106 audit task not executable at expected path"
fi

# ─── Case 2: live iter-106 audit passes ──────────────────────────────────
set +e
audit_output=$(bash "$AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
audit_exit_code=$?
set -e
if [[ "$audit_exit_code" == "0" ]] && [[ "$audit_output" == *'AUDIT PASSED'* ]]; then
    assert_passes "Case 2: live iter-106 audit PASSES (canonical-home invariant established)"
else
    assert_fails "Case 2: live iter-106 audit FAILED (exit=$audit_exit_code)"
fi

# ─── Case 3: iter-106 shared-lib file exists with literal exports ────────
if [[ -f "$SHARED_LIB_ABSOLUTE_PATH" ]] && \
   grep -qE "^export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER" "$SHARED_LIB_ABSOLUTE_PATH" && \
   grep -qE "^export function truncateHookOutputToStayBelowClaudeFileSpilloverThreshold" "$SHARED_LIB_ABSOLUTE_PATH" && \
   grep -qE "^export const HOOK_OUTPUT_TRUNCATION_MARKER_SUFFIX_FOR_CLAUDE_VISIBLE_AWARENESS_OF_CONTEXT_LOSS" "$SHARED_LIB_ABSOLUTE_PATH"; then
    assert_passes "Case 3: iter-106 shared-lib file exists with all 3 literal exports (constant + marker + function)"
else
    assert_fails "Case 3: iter-106 shared-lib file missing or missing literal exports"
fi

# ─── Case 4: PostToolUse contract lib re-exports from iter-106 shared lib ─
if grep -q 'from "./shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106' "$POSTTOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH" && \
   ! grep -qE "^export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER" "$POSTTOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH"; then
    assert_passes "Case 4: PostToolUse contract lib re-exports from iter-106 shared lib (backward compat preserved, no duplicate definitions)"
else
    assert_fails "Case 4: PostToolUse contract lib re-export contract broken (missing re-export OR duplicate literal definition)"
fi

# ─── Case 5: all 8 cohort hooks import from the shared-lib canonical home ─
case5_cohort_hooks_with_direct_shared_lib_import=0
for cohort_hook_path in "${EIGHT_COHORT_HOOK_ABSOLUTE_PATHS[@]}"; do
    # Per-hook check: the helper must come from the shared-lib path. Detect
    # both single-line and multi-line import styles.
    if grep -q 'from "\./lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106' "$cohort_hook_path" && \
       grep -q "truncateHookOutputToStayBelowClaudeFileSpilloverThreshold" "$cohort_hook_path"; then
        case5_cohort_hooks_with_direct_shared_lib_import=$((case5_cohort_hooks_with_direct_shared_lib_import + 1))
    fi
done
if [[ "$case5_cohort_hooks_with_direct_shared_lib_import" == "8" ]]; then
    assert_passes "Case 5: all 8 cohort hooks import the helper directly from the iter-106 shared-lib canonical home"
else
    assert_fails "Case 5: only $case5_cohort_hooks_with_direct_shared_lib_import/8 cohort hooks import from iter-106 shared-lib canonical home"
fi

# ─── Case 6: helper signature + threshold (9000) unchanged from baseline ──
case6_threshold_value=$(grep -E "^export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER" "$SHARED_LIB_ABSOLUTE_PATH" | grep -oE '[0-9]+' | head -1 || echo "?")
if [[ "$case6_threshold_value" == "9000" ]]; then
    assert_passes "Case 6: iter-104 helper threshold preserved across iter-105/iter-106 relocations (MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER = 9000)"
else
    assert_fails "Case 6: helper threshold changed from iter-104 baseline (value = $case6_threshold_value)"
fi

# ─── Case 7: iter-105 audit still passes (no regression on marketplace invariant) ─
set +e
iter105_audit_output=$(bash "$ITER105_AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
iter105_audit_exit_code=$?
set -e
if [[ "$iter105_audit_exit_code" == "0" ]] && [[ "$iter105_audit_output" == *'AUDIT PASSED'* ]]; then
    assert_passes "Case 7: iter-105 marketplace-wide truncation-helper audit still PASSES (iter-106 canonical-home relocation did not break the iter-105 marketplace invariant)"
else
    assert_fails "Case 7: iter-105 audit broken by iter-106 relocation (regression on marketplace invariant)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-106 regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_PASSED_COUNT"
echo "  Assertions failed: $ASSERTION_FAILED_COUNT"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_FAILED_COUNT" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_FAILED_COUNT assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_PASSED_COUNT assertions passed"
echo ""
echo "  🚀 Iter-106 canonical-home invariant established. The truncation helper"
echo "     now lives in a dedicated cross-Pre/PostToolUse shared lib:"
echo "       plugins/itp-hooks/hooks/lib/shared-truncation-helper-..."
echo "     ...-cross-pretooluse-and-posttooluse-iter106.ts"
echo "  🚀 PostToolUse contract lib transitive re-exports preserve the iter-104"
echo "     API surface for backward compat (no breaking change for external"
echo "     consumers that reference the original iter-104 import-source)."
echo "  🚀 All 8 iter-105 cohort hooks now import directly from the canonical"
echo "     home — cross-lib import awkwardness eliminated."
echo "  🚀 Iter-107+ candidates: (a) extract the iter-95 async-spawn helper to"
echo "     the cross-Pre/PostToolUse shared lib once more PreToolUse classifiers"
echo "     adopt async subprocess execution; (b) add a shared escape-hatch-marker"
echo "     detection helper that all per-classifier opt-out comments converge on;"
echo "     (c) promote the iter-105 + iter-106 audits from informational to"
echo "     strict-block once a marketplace-wide refactor pass establishes the"
echo "     invariants as universally true."
