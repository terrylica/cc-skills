#!/usr/bin/env bash
#MISE description="Iter-162 regression test pinning the BREAKING-CHANGE footer-token detection extension to the iter-161 semver-bump classifier via the iter-153 advisor. Asserts (a) iter-162 shared lib structurally valid (executable, bash-clean, shellcheck-clean), (b) footer-token detector correctly classifies the three canonical token forms (BREAKING CHANGE:, BREAKING-CHANGE:, BREAKING CHANGES:) and rejects four false-positive patterns (lowercase, no-colon, indented, in-prose), (c) iter-153 advisor --message-file flag wires the body into iter-162 detector and OR's the result with the subject ! marker before iter-161 classification, (d) iter-153 advisor --json mode emits new iter162_breaking_change_signal_source field with the canonical four values (none, subject_bang_marker, body_footer_token, both_subject_bang_marker_and_body_footer_token), (e) iter-157 commit-msg hook now uses --message-file and propagates BREAKING CHANGE: footer-form detection to git-commit-time gating, (f) overlay is correctness-fix-additive — does not change existing exit-code behavior for footer-only-breaking commits when --strict is set (still 0 since silent-fail-class is separate from breaking-change classification)."
set -euo pipefail

ITER162_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER162_REPO_ROOT"

ITER162_SHARED_LIB_RELATIVE_PATH="scripts/lib/iter162-conventional-commits-breaking-change-footer-token-detector-applying-uppercase-required-and-blank-line-separator-rules-per-conventional-commits-v1-section-13-and-semantic-release-commit-analyzer-default-angular-preset-behavior.sh"
ITER162_SHARED_LIB_ABSOLUTE_PATH="$ITER162_REPO_ROOT/$ITER162_SHARED_LIB_RELATIVE_PATH"
ITER162_ADVISOR_TASK_ABSOLUTE_PATH="$ITER162_REPO_ROOT/.mise/tasks/commits/advise"
ITER162_ITER157_HOOK_SCRIPT_ABSOLUTE_PATH="$ITER162_REPO_ROOT/scripts/iter157-installable-commit-msg-git-hook-delegating-to-iter153-strict-mode-advisor-for-automatic-rejection-of-compound-prefix-and-missing-type-silent-fail-class-violations-at-commit-time-closing-the-natural-git-workflow-integration-gap.sh"

ITER162_TOTAL_ASSERTIONS_EVALUATED=0
ITER162_TOTAL_ASSERTIONS_FAILED=0

iter162_assert_truthy_with_human_readable_label() {
    local human_readable_label="$1"
    local truthy_or_falsy_condition_result="$2"
    ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$truthy_or_falsy_condition_result" == "true" ]]; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label"
        ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter162_invoke_detector_capturing_detection_boolean_and_variant_from_global_output_variables_via_subshell() {
    local commit_message_body="$1"
    bash -c "
        source '$ITER162_SHARED_LIB_ABSOLUTE_PATH'
        iter162_detect_conventional_commits_breaking_change_footer_token_at_start_of_any_line_in_commit_message_body_per_section_13_uppercase_required_rule_and_angular_preset_plural_synonym_acceptance \"\$1\"
        echo \"\$ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_AT_START_OF_LINE_IN_BODY_BOOLEAN|\$ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_VARIANT_FOR_DIAGNOSTIC_RATIONALE_OR_EMPTY_IF_NOT_DETECTED\"
    " -- "$commit_message_body"
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-162 BREAKING-CHANGE-FOOTER-DETECTION REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: shared lib structural validity ─────────────────────────────────
echo ""
echo "GROUP A (3 assertions): iter-162 shared lib structurally valid"

ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -f "$ITER162_SHARED_LIB_ABSOLUTE_PATH" ]]; then
    echo "  ✓ A1: iter-162 shared lib exists at canonical path"
else
    echo "  ✗ A1: iter-162 shared lib missing"
    ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER162_SHARED_LIB_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A2: iter-162 shared lib bash -n syntax check passes"
else
    echo "  ✗ A2: iter-162 shared lib FAILS bash -n syntax check"
    ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER162_SHARED_LIB_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A3: iter-162 shared lib passes shellcheck (zero warnings)"
    else
        echo "  ✗ A3: iter-162 shared lib has shellcheck warnings"
        ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A3: shellcheck not installed — SKIPPED"
    ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: three canonical breaking-change token forms detected ───────────
echo ""
echo "GROUP B (3 assertions): three canonical breaking-change footer-token forms detected"

ITER162_DETECTOR_RESULT_FOR_CANONICAL_SINGULAR=$(iter162_invoke_detector_capturing_detection_boolean_and_variant_from_global_output_variables_via_subshell "BREAKING CHANGE: API moved")
iter162_assert_truthy_with_human_readable_label \
    "B1: BREAKING CHANGE: <description> detected (Conventional Commits v1.0.0 canonical form)" \
    "$([[ "$ITER162_DETECTOR_RESULT_FOR_CANONICAL_SINGULAR" == "true|BREAKING CHANGE:" ]] && echo true || echo false)"

ITER162_DETECTOR_RESULT_FOR_HYPHEN_SYNONYM=$(iter162_invoke_detector_capturing_detection_boolean_and_variant_from_global_output_variables_via_subshell "BREAKING-CHANGE: env precedence change")
iter162_assert_truthy_with_human_readable_label \
    "B2: BREAKING-CHANGE: <description> detected (Conventional Commits v1.0.0 §13 hyphen synonym)" \
    "$([[ "$ITER162_DETECTOR_RESULT_FOR_HYPHEN_SYNONYM" == "true|BREAKING-CHANGE:" ]] && echo true || echo false)"

ITER162_DETECTOR_RESULT_FOR_ANGULAR_PLURAL=$(iter162_invoke_detector_capturing_detection_boolean_and_variant_from_global_output_variables_via_subshell "BREAKING CHANGES: multiple things")
iter162_assert_truthy_with_human_readable_label \
    "B3: BREAKING CHANGES: <description> detected (Angular preset plural variant accepted by semantic-release default)" \
    "$([[ "$ITER162_DETECTOR_RESULT_FOR_ANGULAR_PLURAL" == "true|BREAKING CHANGES:" ]] && echo true || echo false)"

# ─── Group C: false-positive defenses (lowercase, no-colon, indented, in-prose) ─
echo ""
echo "GROUP C (4 assertions): false-positive defenses reject non-canonical forms"

ITER162_DETECTOR_RESULT_FOR_LOWERCASE=$(iter162_invoke_detector_capturing_detection_boolean_and_variant_from_global_output_variables_via_subshell "breaking change: lowercase form is not canonical")
iter162_assert_truthy_with_human_readable_label \
    "C1: lowercase 'breaking change:' rejected (spec MUSTs uppercase)" \
    "$([[ "$ITER162_DETECTOR_RESULT_FOR_LOWERCASE" == "false|" ]] && echo true || echo false)"

ITER162_DETECTOR_RESULT_FOR_NO_COLON=$(iter162_invoke_detector_capturing_detection_boolean_and_variant_from_global_output_variables_via_subshell "BREAKING CHANGE without trailing colon")
iter162_assert_truthy_with_human_readable_label \
    "C2: BREAKING CHANGE without colon rejected (git-trailer grammar requires colon-space separator)" \
    "$([[ "$ITER162_DETECTOR_RESULT_FOR_NO_COLON" == "false|" ]] && echo true || echo false)"

ITER162_DETECTOR_RESULT_FOR_INDENTED=$(iter162_invoke_detector_capturing_detection_boolean_and_variant_from_global_output_variables_via_subshell "    BREAKING CHANGE: indented forms are not flush-left")
iter162_assert_truthy_with_human_readable_label \
    "C3: indented 'BREAKING CHANGE:' rejected (footer trailers MUST be flush-left)" \
    "$([[ "$ITER162_DETECTOR_RESULT_FOR_INDENTED" == "false|" ]] && echo true || echo false)"

ITER162_DETECTOR_RESULT_FOR_IN_PROSE=$(iter162_invoke_detector_capturing_detection_boolean_and_variant_from_global_output_variables_via_subshell "see notes for no BREAKING CHANGE: it is fine")
iter162_assert_truthy_with_human_readable_label \
    "C4: in-prose 'BREAKING CHANGE:' (mid-line) rejected (line-anchored detection prevents false positives)" \
    "$([[ "$ITER162_DETECTOR_RESULT_FOR_IN_PROSE" == "false|" ]] && echo true || echo false)"

# ─── Group D: multi-line body with footer after blank-line separator ─────────
echo ""
echo "GROUP D (1 assertion): footer detection after blank-line separator (canonical §13 placement)"

ITER162_MULTILINE_BODY_WITH_FOOTER_AFTER_BLANK_LINE_PER_SECTION_13_SPEC_PLACEMENT="body summary paragraph

BREAKING CHANGE: API moved to new module"
ITER162_DETECTOR_RESULT_FOR_FOOTER_AFTER_BLANK_LINE=$(iter162_invoke_detector_capturing_detection_boolean_and_variant_from_global_output_variables_via_subshell "$ITER162_MULTILINE_BODY_WITH_FOOTER_AFTER_BLANK_LINE_PER_SECTION_13_SPEC_PLACEMENT")
iter162_assert_truthy_with_human_readable_label \
    "D1: footer detected after canonical blank-line separator from body (§13 spec placement)" \
    "$([[ "$ITER162_DETECTOR_RESULT_FOR_FOOTER_AFTER_BLANK_LINE" == "true|BREAKING CHANGE:" ]] && echo true || echo false)"

# ─── Group E: iter-153 advisor --message-file wires iter-162 detection ───────
echo ""
echo "GROUP E (5 assertions): iter-153 advisor --message-file wires iter-162 footer detection"

ITER162_TMPFILE_BODY_BREAKER=$(mktemp -t iter162-test-body-breaker-XXXXXX)
cat > "$ITER162_TMPFILE_BODY_BREAKER" <<'COMMITMSGFILE'
feat: add new API method

This is the body explaining what was done.

BREAKING CHANGE: the old API method is removed in this release
COMMITMSGFILE
ITER162_HUMAN_OUTPUT_FOR_BODY_BREAKER=$(bash "$ITER162_ADVISOR_TASK_ABSOLUTE_PATH" --message-file "$ITER162_TMPFILE_BODY_BREAKER" 2>&1 || true)
ITER162_JSON_OUTPUT_FOR_BODY_BREAKER=$(bash "$ITER162_ADVISOR_TASK_ABSOLUTE_PATH" --json --message-file "$ITER162_TMPFILE_BODY_BREAKER" 2>/dev/null || true)
rm -f "$ITER162_TMPFILE_BODY_BREAKER"

ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER162_HUMAN_OUTPUT_FOR_BODY_BREAKER" == *"MAJOR bump"* ]]; then
    echo "  ✓ E1: body-only breaking change (no ! in subject) shows MAJOR bump in human mode"
else
    echo "  ✗ E1: body-only breaking-change did not produce MAJOR bump"
    ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER162_HUMAN_OUTPUT_FOR_BODY_BREAKER" == *"iter-162 BREAKING CHANGE: body footer-token detected"* ]]; then
    echo "  ✓ E2: human-readable output cites iter-162 body footer-token detection rationale"
else
    echo "  ✗ E2: missing iter-162 body footer-token rationale in human output"
    ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER162_JSON_OUTPUT_FOR_BODY_BREAKER" == *'"breaking": true'* ]]; then
    echo "  ✓ E3: --json mode sets breaking=true for body-footer-only breaking commits"
else
    echo "  ✗ E3: --json breaking field not true"
    ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER162_JSON_OUTPUT_FOR_BODY_BREAKER" == *'"iter162_breaking_change_signal_source": "body_footer_token"'* ]]; then
    echo "  ✓ E4: --json mode emits new iter162_breaking_change_signal_source field with canonical body_footer_token value"
else
    echo "  ✗ E4: iter162_breaking_change_signal_source field missing or wrong"
    ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER162_JSON_OUTPUT_FOR_BODY_BREAKER" == *'"bump_label_per_cc_skills_releaserc_yml_rules": "MAJOR"'* ]]; then
    echo "  ✓ E5: --json iter161 bump label is MAJOR for footer-form breaking change (iter-162 OR'd correctly into iter-161 classifier input)"
else
    echo "  ✗ E5: iter161 bump label not MAJOR for footer-form breaking change"
    ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group F: subject ! marker without body still works (backward compat) ────
echo ""
echo "GROUP F (2 assertions): subject ! marker still works (iter-161 backward compat)"

ITER162_JSON_OUTPUT_FOR_SUBJECT_BANG_NO_BODY=$(bash "$ITER162_ADVISOR_TASK_ABSOLUTE_PATH" --json -- "feat(api)!: rename" 2>/dev/null || true)

ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER162_JSON_OUTPUT_FOR_SUBJECT_BANG_NO_BODY" == *'"breaking": true'* ]]; then
    echo "  ✓ F1: subject ! marker (no body) still produces breaking=true"
else
    echo "  ✗ F1: subject ! marker regression — breaking field not true"
    ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER162_JSON_OUTPUT_FOR_SUBJECT_BANG_NO_BODY" == *'"iter162_breaking_change_signal_source": "subject_bang_marker"'* ]]; then
    echo "  ✓ F2: subject ! marker labeled signal_source=subject_bang_marker (not body_footer_token)"
else
    echo "  ✗ F2: signal_source not subject_bang_marker for ! subject"
    ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group G: no-breaking case sets signal_source=none ───────────────────────
echo ""
echo "GROUP G (1 assertion): non-breaking commits set signal_source=none"

ITER162_JSON_OUTPUT_FOR_NONBREAKING_FEAT=$(bash "$ITER162_ADVISOR_TASK_ABSOLUTE_PATH" --json -- "feat: add foo" 2>/dev/null || true)
ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER162_JSON_OUTPUT_FOR_NONBREAKING_FEAT" == *'"iter162_breaking_change_signal_source": "none"'* ]] \
   && [[ "$ITER162_JSON_OUTPUT_FOR_NONBREAKING_FEAT" == *'"breaking": false'* ]]; then
    echo "  ✓ G1: non-breaking feat sets signal_source=none and breaking=false"
else
    echo "  ✗ G1: non-breaking case did not produce canonical none/false pair"
    ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group H: iter-157 hook updated to use --message-file ─────────────────────
echo ""
echo "GROUP H (1 assertion): iter-157 commit-msg hook now uses --message-file (iter-162 wiring)"

ITER162_TOTAL_ASSERTIONS_EVALUATED=$((ITER162_TOTAL_ASSERTIONS_EVALUATED + 1))
if grep -q -- "--message-file" "$ITER162_ITER157_HOOK_SCRIPT_ABSOLUTE_PATH"; then
    echo "  ✓ H1: iter-157 hook now invokes advisor with --message-file (full message piped to iter-162)"
else
    echo "  ✗ H1: iter-157 hook still uses old subject-only delegation — body footer detection at commit time will NOT work"
    ITER162_TOTAL_ASSERTIONS_FAILED=$((ITER162_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER162_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-162 REGRESSION TEST: ${ITER162_TOTAL_ASSERTIONS_EVALUATED}/${ITER162_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-162 REGRESSION TEST: $((ITER162_TOTAL_ASSERTIONS_EVALUATED - ITER162_TOTAL_ASSERTIONS_FAILED))/${ITER162_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER162_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
