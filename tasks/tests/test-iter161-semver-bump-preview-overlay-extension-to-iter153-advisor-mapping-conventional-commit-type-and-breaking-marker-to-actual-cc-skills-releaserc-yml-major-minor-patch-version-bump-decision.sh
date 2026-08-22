#!/usr/bin/env bash
#MISE description="Iter-161 regression test pinning the semver-bump preview overlay extension to the iter-153 pre-commit advisor. Asserts (a) iter-161 shared lib structurally valid (executable, bash-clean, shellcheck-clean), (b) classifier function maps feat→MINOR, feat!→MAJOR, fix→PATCH, docs→PATCH per cc-skills .releaserc.yml override, refactor!→MAJOR, unknown-type→NONE, missing-type→NONE through direct invocation, (c) iter-153 advisor sources the iter-161 lib and emits the new human-readable preview block with bump label + rationale, (d) iter-153 advisor --json mode includes the new iter161_semver_bump_preview nested object with stable iter161_schema_version=1 + bump_label_per_cc_skills_releaserc_yml_rules + rationale fields, (e) preview overlay does NOT change exit code semantics — informational only, mirrors iter-151 long-subject overlay design invariant, (f) bump label populated correctly for the four canonical cases (MAJOR/MINOR/PATCH/NONE)."
set -euo pipefail

ITER161_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER161_REPO_ROOT"

ITER161_SHARED_LIB_RELATIVE_PATH="scripts/lib/iter161-semantic-release-version-bump-classifier-mapping-conventional-commit-type-and-breaking-change-marker-to-the-actual-major-minor-patch-bump-per-cc-skills-releaserc-yml-bump-rules-for-pre-commit-preview-overlay.sh"
ITER161_SHARED_LIB_ABSOLUTE_PATH="$ITER161_REPO_ROOT/$ITER161_SHARED_LIB_RELATIVE_PATH"
ITER161_ADVISOR_TASK_RELATIVE_PATH=".mise/tasks/commits/advise"
ITER161_ADVISOR_TASK_ABSOLUTE_PATH="$ITER161_REPO_ROOT/$ITER161_ADVISOR_TASK_RELATIVE_PATH"

ITER161_TOTAL_ASSERTIONS_EVALUATED=0
ITER161_TOTAL_ASSERTIONS_FAILED=0

iter161_assert_truthy_with_human_readable_label() {
    local human_readable_label="$1"
    local truthy_or_falsy_condition_result="$2"
    ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$truthy_or_falsy_condition_result" == "true" ]]; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label"
        ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter161_invoke_classifier_capturing_bump_label_from_global_output_variable() {
    local conventional_commit_type="$1"
    local breaking_change_marker_boolean="$2"
    bash -c "
        source '$ITER161_SHARED_LIB_ABSOLUTE_PATH'
        iter161_classify_semantic_release_version_bump_from_conventional_commit_type_and_breaking_change_marker_against_cc_skills_releaserc_yml_release_rules '$conventional_commit_type' '$breaking_change_marker_boolean'
        echo \"\$ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES\"
    "
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-161 SEMVER-BUMP-PREVIEW-OVERLAY REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: shared lib structural validity ─────────────────────────────────
echo ""
echo "GROUP A (3 assertions): iter-161 shared lib structurally valid"

ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -f "$ITER161_SHARED_LIB_ABSOLUTE_PATH" ]]; then
    echo "  ✓ A1: iter-161 shared lib exists at canonical path"
else
    echo "  ✗ A1: iter-161 shared lib missing"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER161_SHARED_LIB_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A2: iter-161 shared lib bash -n syntax check passes"
else
    echo "  ✗ A2: iter-161 shared lib FAILS bash -n syntax check"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER161_SHARED_LIB_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A3: iter-161 shared lib passes shellcheck (zero warnings)"
    else
        echo "  ✗ A3: iter-161 shared lib has shellcheck warnings"
        ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A3: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: classifier function correctness across 6 canonical bump paths ──
echo ""
echo "GROUP B (6 assertions): classifier function maps each canonical bump path correctly"

ITER161_FEAT_NO_BREAKING_CLASSIFIED_BUMP_LABEL=$(iter161_invoke_classifier_capturing_bump_label_from_global_output_variable "feat" "false")
iter161_assert_truthy_with_human_readable_label \
    "B1: feat without ! marker → MINOR bump" \
    "$([[ "$ITER161_FEAT_NO_BREAKING_CLASSIFIED_BUMP_LABEL" == "MINOR" ]] && echo true || echo false)"

ITER161_FEAT_WITH_BREAKING_CLASSIFIED_BUMP_LABEL=$(iter161_invoke_classifier_capturing_bump_label_from_global_output_variable "feat" "true")
iter161_assert_truthy_with_human_readable_label \
    "B2: feat WITH ! marker → MAJOR bump (breaking-change override per conventional-commits §10)" \
    "$([[ "$ITER161_FEAT_WITH_BREAKING_CLASSIFIED_BUMP_LABEL" == "MAJOR" ]] && echo true || echo false)"

ITER161_FIX_NO_BREAKING_CLASSIFIED_BUMP_LABEL=$(iter161_invoke_classifier_capturing_bump_label_from_global_output_variable "fix" "false")
iter161_assert_truthy_with_human_readable_label \
    "B3: fix without ! marker → PATCH bump (per semantic-release/commit-analyzer defaults)" \
    "$([[ "$ITER161_FIX_NO_BREAKING_CLASSIFIED_BUMP_LABEL" == "PATCH" ]] && echo true || echo false)"

ITER161_DOCS_NO_BREAKING_CLASSIFIED_BUMP_LABEL=$(iter161_invoke_classifier_capturing_bump_label_from_global_output_variable "docs" "false")
iter161_assert_truthy_with_human_readable_label \
    "B4: docs without ! marker → PATCH bump (per cc-skills .releaserc.yml override)" \
    "$([[ "$ITER161_DOCS_NO_BREAKING_CLASSIFIED_BUMP_LABEL" == "PATCH" ]] && echo true || echo false)"

ITER161_REFACTOR_WITH_BREAKING_CLASSIFIED_BUMP_LABEL=$(iter161_invoke_classifier_capturing_bump_label_from_global_output_variable "refactor" "true")
iter161_assert_truthy_with_human_readable_label \
    "B5: refactor WITH ! marker → MAJOR bump (breaking-change override applies to any recognized type)" \
    "$([[ "$ITER161_REFACTOR_WITH_BREAKING_CLASSIFIED_BUMP_LABEL" == "MAJOR" ]] && echo true || echo false)"

ITER161_EMPTY_TYPE_CLASSIFIED_BUMP_LABEL=$(iter161_invoke_classifier_capturing_bump_label_from_global_output_variable "" "false")
iter161_assert_truthy_with_human_readable_label \
    "B6: empty type (silent-fail class MISSING-TYPE/COMPOUND-PREFIX) → NONE (semantic-release skip)" \
    "$([[ "$ITER161_EMPTY_TYPE_CLASSIFIED_BUMP_LABEL" == "NONE" ]] && echo true || echo false)"

# ─── Group C: unrecognized type maps to NONE (typo defense) ──────────────────
echo ""
echo "GROUP C (2 assertions): unrecognized type variants both map to NONE"

ITER161_TYPO_FEET_CLASSIFIED_BUMP_LABEL=$(iter161_invoke_classifier_capturing_bump_label_from_global_output_variable "feet" "false")
iter161_assert_truthy_with_human_readable_label \
    "C1: type 'feet' (typo of 'feat') → NONE (not in release rule set)" \
    "$([[ "$ITER161_TYPO_FEET_CLASSIFIED_BUMP_LABEL" == "NONE" ]] && echo true || echo false)"

ITER161_TYPO_DOCS2_CLASSIFIED_BUMP_LABEL=$(iter161_invoke_classifier_capturing_bump_label_from_global_output_variable "docs2" "false")
iter161_assert_truthy_with_human_readable_label \
    "C2: type 'docs2' (typo of 'docs') → NONE (not in release rule set)" \
    "$([[ "$ITER161_TYPO_DOCS2_CLASSIFIED_BUMP_LABEL" == "NONE" ]] && echo true || echo false)"

# ─── Group D: iter-153 advisor sources lib + emits human-readable preview ────
echo ""
echo "GROUP D (3 assertions): iter-153 advisor sources iter-161 lib and emits preview"

ITER161_HUMAN_OUTPUT_FOR_FEAT=$(bash "$ITER161_ADVISOR_TASK_ABSOLUTE_PATH" -- "feat(scope): minor-only subject" 2>&1 || true)

ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER161_HUMAN_OUTPUT_FOR_FEAT" == *"iter-161 semver-bump preview"* ]]; then
    echo "  ✓ D1: human-readable output contains 'iter-161 semver-bump preview' block header"
else
    echo "  ✗ D1: human-readable output missing iter-161 preview block header"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER161_HUMAN_OUTPUT_FOR_FEAT" == *"MINOR bump — new feature release"* ]]; then
    echo "  ✓ D2: feat subject in human mode shows MINOR bump label"
else
    echo "  ✗ D2: feat subject did not show MINOR bump label"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER161_HUMAN_OUTPUT_FOR_BREAKING=$(bash "$ITER161_ADVISOR_TASK_ABSOLUTE_PATH" -- "feat(api)!: breaking change" 2>&1 || true)
ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER161_HUMAN_OUTPUT_FOR_BREAKING" == *"MAJOR bump"* ]]; then
    echo "  ✓ D3: feat! subject in human mode shows MAJOR bump label"
else
    echo "  ✗ D3: feat! subject did not show MAJOR bump label"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: --json mode embeds nested iter161_semver_bump_preview object ───
echo ""
echo "GROUP E (5 assertions): --json mode embeds iter161_semver_bump_preview nested object"

ITER161_JSON_OUTPUT_FOR_FEAT=$(bash "$ITER161_ADVISOR_TASK_ABSOLUTE_PATH" --json -- "feat: foo" 2>/dev/null || true)

ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER161_JSON_OUTPUT_FOR_FEAT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "  ✓ E1: --json output parses cleanly via independent python3 json.loads"
else
    echo "  ✗ E1: --json output does NOT parse cleanly"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER161_JSON_OUTPUT_FOR_FEAT" == *'"iter161_semver_bump_preview"'* ]]; then
    echo "  ✓ E2: --json output includes iter161_semver_bump_preview field key"
else
    echo "  ✗ E2: iter161_semver_bump_preview field missing"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER161_JSON_OUTPUT_FOR_FEAT" == *'"iter161_schema_version": 1'* ]]; then
    echo "  ✓ E3: --json preview object emits stable iter161_schema_version=1 (AI-agent consumer contract)"
else
    echo "  ✗ E3: iter161_schema_version field missing or wrong value"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER161_JSON_OUTPUT_FOR_FEAT" == *'"bump_label_per_cc_skills_releaserc_yml_rules": "MINOR"'* ]]; then
    echo "  ✓ E4: --json preview object shows MINOR bump for feat subject"
else
    echo "  ✗ E4: --json preview missing MINOR bump label for feat"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER161_JSON_OUTPUT_FOR_COMPOUND_PREFIX_SILENT_FAIL=$(bash "$ITER161_ADVISOR_TASK_ABSOLUTE_PATH" --json -- "feat(scope)+docs: bad compound prefix" 2>/dev/null || true)
ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER161_JSON_OUTPUT_FOR_COMPOUND_PREFIX_SILENT_FAIL" == *'"bump_label_per_cc_skills_releaserc_yml_rules": "NONE"'* ]]; then
    echo "  ✓ E5: compound-prefix silent-fail subject in --json shows NONE bump (semantic-release will skip)"
else
    echo "  ✗ E5: compound-prefix subject did NOT show NONE bump in JSON"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group F: overlay is INFORMATIONAL — does not change exit-code semantics ─
echo ""
echo "GROUP F (2 assertions): iter-161 overlay is informational — does not change advisor exit code"

# Conformant subject still exits 0 with preview present.
ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash "$ITER161_ADVISOR_TASK_ABSOLUTE_PATH" -- "feat: foo" >/dev/null 2>&1; then
    echo "  ✓ F1: conformant subject still exits 0 with iter-161 preview present"
else
    echo "  ✗ F1: conformant subject erroneously exits non-zero"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Strict-mode silent-fail still exits non-zero (preview does not mask the gate).
ITER161_TOTAL_ASSERTIONS_EVALUATED=$((ITER161_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER161_STRICT_MODE_EXIT_FOR_SILENT_FAIL_SUBJECT=0
bash "$ITER161_ADVISOR_TASK_ABSOLUTE_PATH" --strict -- "not a conventional commit" >/dev/null 2>&1 \
    || ITER161_STRICT_MODE_EXIT_FOR_SILENT_FAIL_SUBJECT=$?
if [[ "$ITER161_STRICT_MODE_EXIT_FOR_SILENT_FAIL_SUBJECT" -ne 0 ]]; then
    echo "  ✓ F2: strict-mode silent-fail still exits non-zero (preview overlay does not suppress gate)"
else
    echo "  ✗ F2: strict-mode silent-fail erroneously exited 0"
    ITER161_TOTAL_ASSERTIONS_FAILED=$((ITER161_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER161_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-161 REGRESSION TEST: ${ITER161_TOTAL_ASSERTIONS_EVALUATED}/${ITER161_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-161 REGRESSION TEST: $((ITER161_TOTAL_ASSERTIONS_EVALUATED - ITER161_TOTAL_ASSERTIONS_FAILED))/${ITER161_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER161_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
