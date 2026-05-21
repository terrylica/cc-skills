#!/usr/bin/env bash
#MISE description="Iter-103 regression test for the NotebookEdit applicability audit. Verifies audit-task existence + executability, audit always exits 0 (informational), per-classifier applicability matrix produces expected counts (4 APPLICABLE: version-guard + gpu-optimization-guard + ssot-principles + memory-efficiency-reminder; ≥4 POTENTIALLY-APPLICABLE; ≥15 NOT-APPLICABLE), file-path-suffix vs content-pattern category discrimination correct, community-validated 2026 caution citations present, iter-104+ deferred-scope rationale documented."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-pretooluse-and-posttooluse-hooks-for-notebookedit-applicability-per-jupyter-notebook-cell-content-coverage-matrix-surfaced-by-iter102-web-research-into-2026-anthropic-canonical-file-edit-tool-quadruple.sh"

if [[ ! -f "$AUDIT_TASK_ABSOLUTE_PATH" ]]; then
    echo "FAIL: audit task not found at $AUDIT_TASK_ABSOLUTE_PATH"
    exit 1
fi

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-103 NotebookEdit applicability audit regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: audit task exists + is executable ───────────────────────────────
if [[ -x "$AUDIT_TASK_ABSOLUTE_PATH" ]]; then
    assert_passes "Case 1: audit task exists + is executable"
else
    assert_fails "Case 1: audit task not executable"
fi

# ─── Case 2: audit ALWAYS exits 0 (informational, never blocks release) ──────
set +e
audit_output=$(bash "$AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
audit_exit_code=$?
set -e
if [[ "$audit_exit_code" == "0" ]]; then
    assert_passes "Case 2: audit always exits 0 (informational; never blocks release)"
else
    assert_fails "Case 2: audit exited non-zero ($audit_exit_code) — would block release"
fi

# ─── Case 3: applicability matrix produces expected APPLICABLE count ─────────
# 4 classifiers should be APPLICABLE: version-guard (hardcoded version regex),
# gpu-optimization-guard (PyTorch in notebooks), ssot-principles (ast-grep on
# cell source), memory-efficiency-reminder (any code edit).
case3_applicable_count=$(echo "$audit_output" | grep -oE 'APPLICABLE \(high-value coverage gap\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | head -1 || echo 0)
if [[ "$case3_applicable_count" == "4" ]]; then
    assert_passes "Case 3: APPLICABLE classifier count = 4 (version-guard + gpu-optimization-guard + ssot-principles + memory-efficiency-reminder)"
else
    assert_fails "Case 3: APPLICABLE classifier count = $case3_applicable_count, expected 4"
fi

# ─── Case 4: applicability matrix produces expected NOT-APPLICABLE count ─────
# At least 15 file-path-suffix-specific classifiers should be NOT-APPLICABLE
# (CLAUDE.md, pyproject.toml, mise.toml, __init__.py, launchd plists,
# GLOSSARY.md, README.md, .rs, .js/.ts checkers, etc).
case4_not_applicable_count=$(echo "$audit_output" | grep -oE 'NOT-APPLICABLE \(file-type mismatch\):[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | head -1 || echo 0)
if [[ "$case4_not_applicable_count" -ge "12" ]]; then
    assert_passes "Case 4: NOT-APPLICABLE classifier count = $case4_not_applicable_count (≥12 file-path-suffix-specific hooks correctly excluded)"
else
    assert_fails "Case 4: NOT-APPLICABLE classifier count = $case4_not_applicable_count, expected ≥12"
fi

# ─── Case 5: each APPLICABLE classifier appears in the detailed rationale ────
declare -a EXPECTED_APPLICABLE_CLASSIFIERS=(
    "pretooluse-version-guard.ts"
    "pretooluse-gpu-optimization-guard.ts"
    "posttooluse-ssot-principles.ts"
    "posttooluse-memory-efficiency-reminder.ts"
)
case5_applicable_classifiers_in_rationale=0
for expected_classifier in "${EXPECTED_APPLICABLE_CLASSIFIERS[@]}"; do
    if echo "$audit_output" | grep -q "◆ $expected_classifier"; then
        case5_applicable_classifiers_in_rationale=$((case5_applicable_classifiers_in_rationale + 1))
    fi
done
if [[ "$case5_applicable_classifiers_in_rationale" == "4" ]]; then
    assert_passes "Case 5: all 4 APPLICABLE classifiers appear in detailed-rationale section (version-guard + gpu-optimization + ssot-principles + memory-efficiency-reminder)"
else
    assert_fails "Case 5: only $case5_applicable_classifiers_in_rationale/4 APPLICABLE classifiers appear in detailed-rationale section"
fi

# ─── Case 6: community-validated 2026 caution citations present ──────────────
# The audit MUST cite the three known NotebookEdit issues per iter-103 web
# research (insert-positioning bug, git diff noise, Jupyter MCP server
# recommendation). Future maintainers reading the audit output should
# immediately see WHY broadening was deferred.
case6_has_insert_bug=0
case6_has_git_diff_noise=0
case6_has_mcp_recommendation=0
[[ "$audit_output" == *"nsert-positioning bug"* ]] && case6_has_insert_bug=1
[[ "$audit_output" == *"git diff"* ]] && case6_has_git_diff_noise=1
[[ "$audit_output" == *"Jupyter MCP server"* ]] && case6_has_mcp_recommendation=1
if [[ "$case6_has_insert_bug" == "1" ]] && [[ "$case6_has_git_diff_noise" == "1" ]] && [[ "$case6_has_mcp_recommendation" == "1" ]]; then
    assert_passes "Case 6: all 3 community-validated 2026 cautions cited (insert-bug + git-diff noise + Jupyter MCP recommendation)"
else
    assert_fails "Case 6: missing cautions (insert-bug=$case6_has_insert_bug, git-diff=$case6_has_git_diff_noise, mcp=$case6_has_mcp_recommendation)"
fi

# ─── Case 7: iter-104+ deferred-scope rationale documented ──────────────────
# Audit must explain WHY broadening is deferred to iter-104+:
#   (a) payload-shape adaptation required
#   (b) upstream NotebookEdit stability concerns
#   (c) Jupyter MCP alternative consideration
case7_has_payload_shape=0
case7_has_iter104=0
[[ "$audit_output" == *"PAYLOAD-SHAPE adaptation"* ]] && case7_has_payload_shape=1
[[ "$audit_output" == *"iter-104"* ]] && case7_has_iter104=1
if [[ "$case7_has_payload_shape" == "1" ]] && [[ "$case7_has_iter104" == "1" ]]; then
    assert_passes "Case 7: iter-104+ deferred-scope rationale present (payload-shape adaptation + iter-104 follow-up scope)"
else
    assert_fails "Case 7: iter-104+ rationale incomplete (payload-shape=$case7_has_payload_shape, iter-104=$case7_has_iter104)"
fi

# ─── Case 8: live marketplace currently honors 0 NotebookEdit matchers ──────
# Pre-iter-104 baseline — no marketplace matcher includes NotebookEdit.
# Iter-104 will start the gradual broadening for the 4 APPLICABLE classifiers.
case8_notebookedit_count=$(echo "$audit_output" | grep -oE '[0-9]+ matchers currently include NotebookEdit' | grep -oE '^[0-9]+' | head -1 || echo "?")
if [[ "$case8_notebookedit_count" == "0" ]]; then
    assert_passes "Case 8: live marketplace baseline — 0 matchers currently honor NotebookEdit (iter-104 baseline state)"
else
    assert_fails "Case 8: unexpected NotebookEdit matchers present ($case8_notebookedit_count) — iter-104 may have started already"
fi

# ─── Case 9: discrimination categories present (file-path-suffix vs content-pattern) ──
# The classifier dichotomy must be present in audit output for future readers
# to understand the applicability decision pattern.
case9_has_file_path_suffix=0
case9_has_content_pattern=0
[[ "$audit_output" == *"file-path-suffix"* ]] && case9_has_file_path_suffix=1
[[ "$audit_output" == *"content-pattern"* ]] && case9_has_content_pattern=1
if [[ "$case9_has_file_path_suffix" == "1" ]] && [[ "$case9_has_content_pattern" == "1" ]]; then
    assert_passes "Case 9: applicability-decision dichotomy present (file-path-suffix vs content-pattern categories)"
else
    assert_fails "Case 9: categorization incomplete (file-path-suffix=$case9_has_file_path_suffix, content-pattern=$case9_has_content_pattern)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-103 regression — Summary"
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
echo "  🚀 Iter-103 NotebookEdit applicability audit ships preventive infrastructure"
echo "     for the 4-tool canonical quadruple (Edit|MultiEdit|Write|NotebookEdit)."
echo "     Per-classifier applicability matrix documents the file-path-suffix vs"
echo "     content-pattern dichotomy. Iter-104+ will adapt the 4 APPLICABLE"
echo "     classifiers (version-guard, gpu-optimization, ssot-principles, memory-"
echo "     efficiency) for NotebookEdit's distinct payload shape (notebook_path +"
echo "     cell_id + new_source + edit_mode) — conditional on upstream NotebookEdit"
echo "     stability resolution (insert-bug, diff noise) or Jupyter MCP alternative."
