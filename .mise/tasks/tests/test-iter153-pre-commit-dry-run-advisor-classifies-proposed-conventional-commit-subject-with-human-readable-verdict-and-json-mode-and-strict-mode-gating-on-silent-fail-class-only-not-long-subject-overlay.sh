#!/usr/bin/env bash
#MISE description="Iter-153 regression test pinning the pre-commit dry-run advisor. Asserts (a) advisor + mise wrapper exist + executable + bash-clean + shellcheck-clean, (b) reuses iter-82/iter-151 grammar (recognized type set, regex patterns, 50/72 thresholds) — single source of truth invariant, (c) all 4 verdicts emit correctly (COMMIT_READY, COMMIT_READY_WITH_READABILITY_WARNING, SILENT_FAIL_RISK on COMPOUND-PREFIX, SILENT_FAIL_RISK on MISSING-TYPE), (d) --json mode emits stable iter-153 schema fields, (e) --strict mode exits non-zero on silent-fail-class violations only — long-subject overlay remains informational even in strict mode per iter-151 design invariant, (f) breaking-change indicator detected via ! suffix, (g) scope extraction via parenthesized capture group, (h) remediation hints surface for each silent-fail-class subtype."
set -euo pipefail

ITER153_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER153_REPO_ROOT"

ITER153_ADVISOR_SCRIPT_RELATIVE_PATH="scripts/iter153-operator-facing-pre-commit-dry-run-advisor-classifying-proposed-conventional-commit-subject-through-iter82-grammar-and-iter151-overlay-with-human-readable-verdict-default-and-json-output-mode-for-ai-agent-automation-pipeline-consumption.sh"
ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH="$ITER153_REPO_ROOT/$ITER153_ADVISOR_SCRIPT_RELATIVE_PATH"
ITER153_MISE_TASK_WRAPPER_RELATIVE_PATH=".mise/tasks/commits/advise"
ITER153_MISE_TASK_WRAPPER_ABSOLUTE_PATH="$ITER153_REPO_ROOT/$ITER153_MISE_TASK_WRAPPER_RELATIVE_PATH"

ITER153_TOTAL_ASSERTIONS_EVALUATED=0
ITER153_TOTAL_ASSERTIONS_FAILED=0

iter153_assert_substring_present_in_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER153_TOTAL_ASSERTIONS_EVALUATED=$((ITER153_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:120}"
        ITER153_TOTAL_ASSERTIONS_FAILED=$((ITER153_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter153_assert_command_exit_code_matches_expectation() {
    local human_readable_assertion_label="$1"
    local expected_exit_code="$2"
    shift 2
    ITER153_TOTAL_ASSERTIONS_EVALUATED=$((ITER153_TOTAL_ASSERTIONS_EVALUATED + 1))
    # `|| true` defuses `set -e` so we can capture the non-zero exit code
    # of the command-under-test rather than aborting the whole test script.
    # We THEN check $? captured via the `&&` short-circuit pattern.
    local actual_exit_code=0
    "$@" >/dev/null 2>&1 || actual_exit_code=$?
    if [[ "$actual_exit_code" == "$expected_exit_code" ]]; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected exit code: $expected_exit_code, actual: $actual_exit_code"
        ITER153_TOTAL_ASSERTIONS_FAILED=$((ITER153_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter153_assert_advisor_output_contains_substring() {
    local human_readable_assertion_label="$1"
    local expected_substring="$2"
    shift 2
    ITER153_TOTAL_ASSERTIONS_EVALUATED=$((ITER153_TOTAL_ASSERTIONS_EVALUATED + 1))
    local captured_output
    captured_output=$("$@" 2>&1 || true)
    if [[ "$captured_output" == *"$expected_substring"* ]]; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:80}"
        ITER153_TOTAL_ASSERTIONS_FAILED=$((ITER153_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-153 PRE-COMMIT-DRY-RUN-ADVISOR REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Structural validity ────────────────────────────────────────────
echo ""
echo "GROUP A (4 assertions): advisor + mise wrapper structurally valid"

ITER153_TOTAL_ASSERTIONS_EVALUATED=$((ITER153_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -x "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" ]] && [[ -x "$ITER153_MISE_TASK_WRAPPER_ABSOLUTE_PATH" ]]; then
    echo "  ✓ A1: both advisor + mise wrapper exist and are executable"
else
    echo "  ✗ A1: advisor or mise wrapper missing or not executable"
    ITER153_TOTAL_ASSERTIONS_FAILED=$((ITER153_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER153_TOTAL_ASSERTIONS_EVALUATED=$((ITER153_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" 2>/dev/null && bash -n "$ITER153_MISE_TASK_WRAPPER_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A2: both advisor + mise wrapper pass bash -n syntax check"
else
    echo "  ✗ A2: bash -n syntax check failed"
    ITER153_TOTAL_ASSERTIONS_FAILED=$((ITER153_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER153_TOTAL_ASSERTIONS_EVALUATED=$((ITER153_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" >/dev/null 2>&1 && shellcheck "$ITER153_MISE_TASK_WRAPPER_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A3: both advisor + mise wrapper pass shellcheck (zero warnings)"
    else
        echo "  ✗ A3: shellcheck warnings detected"
        ITER153_TOTAL_ASSERTIONS_FAILED=$((ITER153_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A3: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER153_TOTAL_ASSERTIONS_EVALUATED=$((ITER153_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# shellcheck disable=SC2016
iter153_assert_substring_present_in_file \
    "A4: mise wrapper delegates via exec for clean signal propagation" \
    "$ITER153_MISE_TASK_WRAPPER_ABSOLUTE_PATH" \
    'exec "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH"'

# ─── Group B: Single source of truth invariant (iter-82/iter-151 grammar reuse)
echo ""
echo "GROUP B (4 assertions): advisor reuses iter-82/iter-151 grammar — SSoT invariant"

iter153_assert_substring_present_in_file \
    "B1: advisor declares the canonical recognized-types array matching iter-82 sem-rel set" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    "feat fix perf revert docs chore style refactor test build ci"

iter153_assert_substring_present_in_file \
    "B2: advisor reuses iter-82 standard conventional-commits header regex pattern" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    'ITER153_STANDARD_CONVENTIONAL_COMMITS_HEADER_REGEX='

iter153_assert_substring_present_in_file \
    "B3: advisor reuses iter-82 compound-prefix anti-pattern regex (silent-fail class)" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    'ITER153_COMPOUND_PREFIX_ANTI_PATTERN_REGEX='

iter153_assert_substring_present_in_file \
    "B4: advisor uses iter-150 50/72-rule thresholds (50 hard target, 72 hard cap)" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    "ITER153_SUBJECT_HARD_CAP_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE=72"

# ─── Group C: 4 verdict classifications fire correctly ───────────────────────
echo ""
echo "GROUP C (4 assertions): all 4 verdict classifications fire correctly"

iter153_assert_advisor_output_contains_substring \
    "C1: COMMIT-READY verdict for short conformant subject" \
    "verdict: COMMIT-READY (no violations detected)" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" -- "feat(release): short conformant subject"

iter153_assert_advisor_output_contains_substring \
    "C2: COMMIT-READY-with-READABILITY-WARNING verdict for 135-char long subject" \
    "READABILITY-WARNING" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" -- "feat(release): iter-149-pre-warm-the-openssh-controlmaster-session-to-github-com-at-release-full-mise-task-entry-point-when-knob-is-set"

iter153_assert_advisor_output_contains_substring \
    "C3: SILENT-FAIL-RISK + COMPOUND-PREFIX classification with remediation hint" \
    "classification:         COMPOUND-PREFIX" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" -- "feat(scope)+docs: compound prefix"

iter153_assert_advisor_output_contains_substring \
    "C4: SILENT-FAIL-RISK + MISSING-TYPE classification with remediation hint" \
    "classification:         MISSING-TYPE" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" -- "no type prefix"

# ─── Group D: --json mode emits stable schema ───────────────────────────────
echo ""
echo "GROUP D (5 assertions): --json mode emits stable iter-153 schema fields"

iter153_assert_advisor_output_contains_substring \
    "D1: JSON mode emits iter153_schema_version field" \
    "\"iter153_schema_version\": 1" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" --json -- "feat: foo"

iter153_assert_advisor_output_contains_substring \
    "D2: JSON mode emits classification field with bucket name" \
    "\"classification\": \"STANDARD-CONFORMANT\"" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" --json -- "feat: foo"

iter153_assert_advisor_output_contains_substring \
    "D3: JSON mode emits iter150_5072_rule_conformance nested object" \
    "\"iter150_5072_rule_conformance\"" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" --json -- "feat: foo"

iter153_assert_advisor_output_contains_substring \
    "D4: JSON mode emits verdict field with COMMIT_READY value for clean subject" \
    "\"verdict\": \"COMMIT_READY\"" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" --json -- "feat: foo"

iter153_assert_advisor_output_contains_substring \
    "D5: JSON mode detects breaking-change ! indicator" \
    "\"breaking\": true" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" --json -- "feat(release)!: breaking change"

# ─── Group E: --strict mode gating semantics ────────────────────────────────
echo ""
echo "GROUP E (4 assertions): --strict gates ONLY on silent-fail-class, not long-subject overlay"

iter153_assert_command_exit_code_matches_expectation \
    "E1: --strict + COMPOUND-PREFIX violation exits 1" \
    1 \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" --strict -- "feat(scope)+docs: compound"

iter153_assert_command_exit_code_matches_expectation \
    "E2: --strict + MISSING-TYPE violation exits 1" \
    1 \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" --strict -- "no type"

iter153_assert_command_exit_code_matches_expectation \
    "E3: --strict + long-subject overlay exits 0 (iter-151 informational-only invariant preserved)" \
    0 \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" --strict -- "feat(release): iter-149-pre-warm-the-openssh-controlmaster-session-to-github-com-at-release-full-mise-task-entry-point-when-knob-is-set"

iter153_assert_command_exit_code_matches_expectation \
    "E4: non-strict + any violation exits 0 (advisory default)" \
    0 \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" -- "feat(scope)+docs: compound"

# ─── Group F: scope + breaking + remediation hints ──────────────────────────
echo ""
echo "GROUP F (3 assertions): scope extraction, breaking-flag detection, remediation hints"

iter153_assert_advisor_output_contains_substring \
    "F1: scope extracted from parenthesized capture group" \
    "scope:                  release" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" -- "feat(release): foo"

iter153_assert_advisor_output_contains_substring \
    "F2: breaking-change indicator detected via ! suffix" \
    "breaking change:        ✓ yes" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" -- "feat(release)!: breaking"

iter153_assert_advisor_output_contains_substring \
    "F3: COMPOUND-PREFIX remediation hint mentions single-type-per-commit" \
    "use a single type per commit" \
    "$ITER153_ADVISOR_SCRIPT_ABSOLUTE_PATH" -- "feat(scope)+docs: compound"

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER153_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-153 REGRESSION TEST: ${ITER153_TOTAL_ASSERTIONS_EVALUATED}/${ITER153_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-153 REGRESSION TEST: $((ITER153_TOTAL_ASSERTIONS_EVALUATED - ITER153_TOTAL_ASSERTIONS_FAILED))/${ITER153_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER153_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
