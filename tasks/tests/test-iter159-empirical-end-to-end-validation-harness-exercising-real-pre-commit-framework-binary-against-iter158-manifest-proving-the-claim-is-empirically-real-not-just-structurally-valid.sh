#!/usr/bin/env bash
#MISE description="Iter-159 regression test wrapping the empirical end-to-end pre-commit-framework validation harness. Verifies (a) harness script exists + bash-clean + shellcheck-clean, (b) pre-commit binary is available (else skip gracefully), (c) harness runs end-to-end and exits 0 against the current cc-skills HEAD (which is the iter-158-manifest-language-script-bug-fix commit or later). This regression test gates against re-introducing the language:system bug iter-159 caught in iter-158, and catches any future regression in the entry-point's commit-msg-file extraction or iter-153 advisor delegation when invoked through the real pre-commit framework."
set -euo pipefail

ITER159_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER159_REPO_ROOT"

ITER159_EMPIRICAL_HARNESS_RELATIVE_PATH="scripts/iter159-empirical-end-to-end-validation-harness-exercising-iter158-pre-commit-framework-manifest-through-real-pre-commit-binary-invocation-proving-the-manifest-claim-is-empirically-real-not-just-structurally-valid.sh"
ITER159_EMPIRICAL_HARNESS_ABSOLUTE_PATH="$ITER159_REPO_ROOT/$ITER159_EMPIRICAL_HARNESS_RELATIVE_PATH"

ITER159_TOTAL_ASSERTIONS_EVALUATED=0
ITER159_TOTAL_ASSERTIONS_FAILED=0

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-159 EMPIRICAL HARNESS REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Harness structurally valid ────────────────────────────────────
echo ""
echo "GROUP A (3 assertions): empirical harness structurally valid"

ITER159_TOTAL_ASSERTIONS_EVALUATED=$((ITER159_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -x "$ITER159_EMPIRICAL_HARNESS_ABSOLUTE_PATH" ]]; then
    echo "  ✓ A1: harness exists at canonical iter-159 path + executable"
else
    echo "  ✗ A1: harness missing or not executable"
    ITER159_TOTAL_ASSERTIONS_FAILED=$((ITER159_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER159_TOTAL_ASSERTIONS_EVALUATED=$((ITER159_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER159_EMPIRICAL_HARNESS_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A2: harness passes bash -n syntax check"
else
    echo "  ✗ A2: harness FAILS bash -n"
    ITER159_TOTAL_ASSERTIONS_FAILED=$((ITER159_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER159_TOTAL_ASSERTIONS_EVALUATED=$((ITER159_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER159_EMPIRICAL_HARNESS_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A3: harness passes shellcheck (zero warnings)"
    else
        echo "  ✗ A3: harness has shellcheck warnings"
        ITER159_TOTAL_ASSERTIONS_FAILED=$((ITER159_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A3: shellcheck not installed — SKIPPED"
    ITER159_TOTAL_ASSERTIONS_EVALUATED=$((ITER159_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: Iter-158 manifest declares language=script ────────────────────
#
# This assertion gates against re-introducing the language=system bug
# iter-159 caught. The cc-skills .pre-commit-hooks.yaml MUST declare
# language=script for the manifest to function under the real pre-commit
# framework. Any drift away from this is a regression.

echo ""
echo "GROUP B (1 assertion): iter-158 manifest declares language=script (regression guard)"

ITER159_TOTAL_ASSERTIONS_EVALUATED=$((ITER159_TOTAL_ASSERTIONS_EVALUATED + 1))
if grep -qE '^[[:space:]]+language:[[:space:]]+script[[:space:]]*$' "$ITER159_REPO_ROOT/.pre-commit-hooks.yaml" 2>/dev/null; then
    echo "  ✓ B1: .pre-commit-hooks.yaml declares language=script (iter-159 bug-fix invariant pinned)"
else
    echo "  ✗ B1: .pre-commit-hooks.yaml lacks language=script — iter-159 regression"
    ITER159_TOTAL_ASSERTIONS_FAILED=$((ITER159_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group C: End-to-end harness invocation passes ──────────────────────────
#
# This is the heaviest assertion — it actually runs the harness against the
# current HEAD. Requires pre-commit binary; skips gracefully if absent (so
# this test does not fail on CI environments without pre-commit installed).

echo ""
echo "GROUP C (1 assertion): empirical harness exits 0 against current HEAD"

ITER159_TOTAL_ASSERTIONS_EVALUATED=$((ITER159_TOTAL_ASSERTIONS_EVALUATED + 1))
if ! command -v pre-commit >/dev/null 2>&1; then
    echo "  ⊘ C1: pre-commit binary not installed — empirical run SKIPPED"
    ITER159_TOTAL_ASSERTIONS_EVALUATED=$((ITER159_TOTAL_ASSERTIONS_EVALUATED - 1))
else
    ITER159_HARNESS_RUN_EXIT_CODE=0
    "$ITER159_EMPIRICAL_HARNESS_ABSOLUTE_PATH" >/dev/null 2>&1 \
        || ITER159_HARNESS_RUN_EXIT_CODE=$?
    if [[ "$ITER159_HARNESS_RUN_EXIT_CODE" -eq 0 ]]; then
        echo "  ✓ C1: empirical harness PASSED (4/4 subject variants validated through real pre-commit framework)"
    else
        echo "  ✗ C1: empirical harness FAILED (exit=$ITER159_HARNESS_RUN_EXIT_CODE) — iter-158 manifest may be broken"
        echo "      Run directly to diagnose: $ITER159_EMPIRICAL_HARNESS_RELATIVE_PATH"
        ITER159_TOTAL_ASSERTIONS_FAILED=$((ITER159_TOTAL_ASSERTIONS_FAILED + 1))
    fi
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER159_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-159 REGRESSION TEST: ${ITER159_TOTAL_ASSERTIONS_EVALUATED}/${ITER159_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-159 REGRESSION TEST: $((ITER159_TOTAL_ASSERTIONS_EVALUATED - ITER159_TOTAL_ASSERTIONS_FAILED))/${ITER159_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER159_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
