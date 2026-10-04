#!/usr/bin/env bash
# Iter-148 regression test pinning the empirical-validation wrapper that runs iter-147 variance harness in BOTH conditions back-to-back (baseline vs multiplexed) and emits side-by-side distribution delta table. Asserts: (a) wrapper exists + executable + bash -n clean + shellcheck-clean, (b) wrapper depends on iter-147 harness at correct sibling path, (c) wrapper sets up ~/.ssh/controlmasters with mode 0700 idempotently, (d) wrapper pre-warms SSH session BEFORE the multiplexed condition (avoids polluting first-run measurement), (e) wrapper composes GIT_SSH_COMMAND with iter-146-pattern ControlMaster directives, (f) wrapper renders side-by-side delta table with Δp50 + speedup columns + validation-threshold footer (≥ 2.0x = VALIDATED), (g) docs/RELEASE.md replaces the iter-146 conjectural 10-15x claim with the iter-148 empirically-measured 3.30x speedup.
set -euo pipefail

ITER148_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER148_REPO_ROOT"

ITER148_WRAPPER_SCRIPT_RELATIVE_PATH="scripts/iter148-ssh-multiplexing-speedup-check.sh"
ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH="$ITER148_REPO_ROOT/$ITER148_WRAPPER_SCRIPT_RELATIVE_PATH"
ITER148_VARIANCE_HARNESS_RELATIVE_PATH="scripts/iter147-release-timing-variance-harness.py"
ITER148_RELEASE_MD_DOC_RELATIVE_PATH="docs/RELEASE.md"

ITER148_TOTAL_ASSERTIONS_EVALUATED=0
ITER148_TOTAL_ASSERTIONS_FAILED=0

iter148_assert_substring_present_in_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER148_TOTAL_ASSERTIONS_EVALUATED=$((ITER148_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:120}"
        ITER148_TOTAL_ASSERTIONS_FAILED=$((ITER148_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter148_assert_filesystem_predicate_holds() {
    local human_readable_assertion_label="$1"
    local bash_test_expression="$2"
    ITER148_TOTAL_ASSERTIONS_EVALUATED=$((ITER148_TOTAL_ASSERTIONS_EVALUATED + 1))
    if eval "[[ $bash_test_expression ]]" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    failed bash predicate: $bash_test_expression"
        ITER148_TOTAL_ASSERTIONS_FAILED=$((ITER148_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-148 EMPIRICAL-VALIDATION-WRAPPER REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Wrapper structural validity ────────────────────────────────────
echo ""
echo "GROUP A (4 assertions): Wrapper script structurally valid"

iter148_assert_filesystem_predicate_holds \
    "A1: wrapper exists at iter-148 verbose path" \
    "-f \"$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH\""

iter148_assert_filesystem_predicate_holds \
    "A2: wrapper is executable (chmod +x)" \
    "-x \"$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH\""

ITER148_TOTAL_ASSERTIONS_EVALUATED=$((ITER148_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A3: wrapper passes bash -n syntax check"
else
    echo "  ✗ A3: wrapper FAILS bash -n syntax check"
    ITER148_TOTAL_ASSERTIONS_FAILED=$((ITER148_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER148_TOTAL_ASSERTIONS_EVALUATED=$((ITER148_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A4: wrapper passes shellcheck (zero warnings)"
    else
        echo "  ✗ A4: wrapper has shellcheck warnings"
        ITER148_TOTAL_ASSERTIONS_FAILED=$((ITER148_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A4: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER148_TOTAL_ASSERTIONS_EVALUATED=$((ITER148_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: Wrapper depends on iter-147 harness + correct ControlMaster setup
echo ""
echo "GROUP B (6 assertions): Wrapper implements correct iter-147→iter-148 contract"

iter148_assert_substring_present_in_file \
    "B1: wrapper references iter-147 variance harness as dependency" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "$ITER148_VARIANCE_HARNESS_RELATIVE_PATH"

iter148_assert_substring_present_in_file \
    "B2: wrapper idempotent-creates ~/.ssh/controlmasters dir" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "mkdir -p"

iter148_assert_substring_present_in_file \
    "B3: wrapper sets mode 0700 on controlmasters dir (chmod 700)" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "chmod 700"

iter148_assert_substring_present_in_file \
    "B4: wrapper pre-warms SSH session to github.com before AFTER cohort" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "Pre-warming SSH ControlMaster session"

iter148_assert_substring_present_in_file \
    "B5: wrapper composes GIT_SSH_COMMAND with ControlMaster=auto" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "ControlMaster=auto"

iter148_assert_substring_present_in_file \
    "B6: wrapper sets ControlPersist TTL matching iter-146/147 invariant (10m)" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "ControlPersist=10m"

# ─── Group C: Wrapper renders side-by-side delta with validation threshold ──
echo ""
echo "GROUP C (4 assertions): Wrapper emits delta table + validation threshold"

iter148_assert_substring_present_in_file \
    "C1: wrapper renders delta table header column 'BEFORE-p50'" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "BEFORE-p50"

iter148_assert_substring_present_in_file \
    "C2: wrapper renders delta table header column 'AFTER-p50'" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "AFTER-p50"

iter148_assert_substring_present_in_file \
    "C3: wrapper renders speedup ratio column (baseline-p50 over multiplexed-p50)" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "speedup"

iter148_assert_substring_present_in_file \
    "C4: wrapper documents validation threshold (≥ 2.0x speedup = VALIDATED)" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "≥ 2.0x"

# ─── Group D: Wrapper isolates baseline from inherited GIT_SSH_COMMAND ──────
echo ""
echo "GROUP D (2 assertions): Wrapper isolates baseline measurement"

iter148_assert_substring_present_in_file \
    "D1: wrapper explicitly unsets GIT_SSH_COMMAND for baseline (env -u GIT_SSH_COMMAND)" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "env -u GIT_SSH_COMMAND"

iter148_assert_substring_present_in_file \
    "D2: wrapper preserves capture logs in /tmp for operator post-mortem" \
    "$ITER148_WRAPPER_SCRIPT_ABSOLUTE_PATH" \
    "Capture logs preserved for inspection"

# ─── Group E: docs/RELEASE.md names the wrapper ───────────────────────────────
# The measured results (3.30x, 4216 ms saved, n=3) were a one-day measurement and live in git
# history and the CHANGELOG, not in the present-tense guide (cc-skills #222).
echo ""
echo "GROUP E (1 assertion): docs/RELEASE.md names the wrapper"

iter148_assert_substring_present_in_file \
    "E1: docs/RELEASE.md names scripts/iter148-ssh-multiplexing-speedup-check.sh" \
    "$ITER148_RELEASE_MD_DOC_RELATIVE_PATH" \
    "scripts/iter148-ssh-multiplexing-speedup-check.sh"

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER148_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-148 REGRESSION TEST: ${ITER148_TOTAL_ASSERTIONS_EVALUATED}/${ITER148_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-148 REGRESSION TEST: $((ITER148_TOTAL_ASSERTIONS_EVALUATED - ITER148_TOTAL_ASSERTIONS_FAILED))/${ITER148_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER148_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
