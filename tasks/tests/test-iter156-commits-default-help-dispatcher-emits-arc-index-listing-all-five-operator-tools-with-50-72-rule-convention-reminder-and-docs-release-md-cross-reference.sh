#!/usr/bin/env bash
#MISE description="Iter-156 regression test pinning the operator-facing commits arc discoverability entry point. Asserts (a) .mise/tasks/commits/_default exists + executable + bash-clean + shellcheck-clean, (b) default-dispatcher output mentions all 5 operator tools by name (release:history, commits:health, commits:health --json, commits:advise, commits:advise --json) plus the iter-154 COMMIT_EDITMSG auto-detect mode, (c) iter-150 50/72 convention reminder is present with both thresholds (50 + 72), (d) canonical spec URLs are cited (conventionalcommits.org + cbea.ms), (e) docs/RELEASE.md cross-reference is present, (f) docs/RELEASE.md contains the Conventional-Commits Operator Toolkit Index section."
set -euo pipefail

ITER156_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER156_REPO_ROOT"

ITER156_DISPATCHER_RELATIVE_PATH=".mise/tasks/commits/_default"
ITER156_DISPATCHER_ABSOLUTE_PATH="$ITER156_REPO_ROOT/$ITER156_DISPATCHER_RELATIVE_PATH"
ITER156_DOCS_RELEASE_MD_ABSOLUTE_PATH="$ITER156_REPO_ROOT/docs/RELEASE.md"

ITER156_TOTAL_ASSERTIONS_EVALUATED=0
ITER156_TOTAL_ASSERTIONS_FAILED=0

iter156_assert_dispatcher_output_contains_substring() {
    local human_readable_assertion_label="$1"
    local expected_substring="$2"
    ITER156_TOTAL_ASSERTIONS_EVALUATED=$((ITER156_TOTAL_ASSERTIONS_EVALUATED + 1))
    local captured_output
    captured_output=$("$ITER156_DISPATCHER_ABSOLUTE_PATH" 2>&1 || true)
    if [[ "$captured_output" == *"$expected_substring"* ]]; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:100}"
        ITER156_TOTAL_ASSERTIONS_FAILED=$((ITER156_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter156_assert_substring_present_in_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER156_TOTAL_ASSERTIONS_EVALUATED=$((ITER156_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:100}"
        ITER156_TOTAL_ASSERTIONS_FAILED=$((ITER156_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-156 COMMITS-ARC-DISCOVERABILITY REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Structural validity ────────────────────────────────────────────
echo ""
echo "GROUP A (3 assertions): default-help dispatcher structurally valid"

ITER156_TOTAL_ASSERTIONS_EVALUATED=$((ITER156_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -x "$ITER156_DISPATCHER_ABSOLUTE_PATH" ]]; then
    echo "  ✓ A1: dispatcher exists at .mise/tasks/commits/_default and is executable"
else
    echo "  ✗ A1: dispatcher missing or not executable"
    ITER156_TOTAL_ASSERTIONS_FAILED=$((ITER156_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER156_TOTAL_ASSERTIONS_EVALUATED=$((ITER156_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER156_DISPATCHER_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A2: dispatcher passes bash -n syntax check"
else
    echo "  ✗ A2: dispatcher FAILS bash -n"
    ITER156_TOTAL_ASSERTIONS_FAILED=$((ITER156_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER156_TOTAL_ASSERTIONS_EVALUATED=$((ITER156_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER156_DISPATCHER_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A3: dispatcher passes shellcheck (zero warnings)"
    else
        echo "  ✗ A3: dispatcher has shellcheck warnings"
        ITER156_TOTAL_ASSERTIONS_FAILED=$((ITER156_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A3: shellcheck not installed — SKIPPED"
    ITER156_TOTAL_ASSERTIONS_EVALUATED=$((ITER156_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: All 5 operator tools mentioned + COMMIT_EDITMSG auto-detect ──
echo ""
echo "GROUP B (6 assertions): dispatcher lists all 5 operator tools + iter-154 auto-detect mode"

iter156_assert_dispatcher_output_contains_substring \
    "B1: lists release:history (iter-150 readable view)" \
    "mise run release:history"

iter156_assert_dispatcher_output_contains_substring \
    "B2: lists commits:health (iter-152 dashboard human mode)" \
    "mise run commits:health"

iter156_assert_dispatcher_output_contains_substring \
    "B3: lists commits:health --json (iter-155 AI-agent dashboard mode)" \
    "mise run commits:health --json"

iter156_assert_dispatcher_output_contains_substring \
    "B4: lists commits:advise (iter-153 dry-run advisor human mode)" \
    'mise run commits:advise -- "<proposed subject>"'

iter156_assert_dispatcher_output_contains_substring \
    "B5: lists commits:advise --json (iter-153 AI-agent advisor mode)" \
    'mise run commits:advise --json -- "<subject>"'

iter156_assert_dispatcher_output_contains_substring \
    "B6: documents iter-154 COMMIT_EDITMSG auto-detect path" \
    "COMMIT_EDITMSG"

# ─── Group C: Convention reminder + canonical spec URLs ─────────────────────
echo ""
echo "GROUP C (4 assertions): iter-150 50/72 convention reminder + canonical spec URLs"

iter156_assert_dispatcher_output_contains_substring \
    "C1: dispatcher cites the 50-char hard target threshold" \
    "≤50 chars hard target"

iter156_assert_dispatcher_output_contains_substring \
    "C2: dispatcher cites the 72-char hard cap threshold" \
    "≤72 chars hard cap"

iter156_assert_dispatcher_output_contains_substring \
    "C3: dispatcher cites the conventional-commits.org canonical spec URL" \
    "https://www.conventionalcommits.org/"

iter156_assert_dispatcher_output_contains_substring \
    "C4: dispatcher cites the cbea.ms Seven Rules essay URL" \
    "https://cbea.ms/git-commit/"

# ─── Group D: Cross-reference to canonical docs/RELEASE.md section ─────────
echo ""
echo "GROUP D (2 assertions): cross-reference to docs/RELEASE.md canonical index section"

iter156_assert_dispatcher_output_contains_substring \
    "D1: dispatcher cross-references docs/RELEASE.md as the canonical deep-dive surface" \
    "docs/RELEASE.md"

iter156_assert_substring_present_in_file \
    "D2: docs/RELEASE.md contains the Conventional-Commits Operator Toolkit Index section" \
    "$ITER156_DOCS_RELEASE_MD_ABSOLUTE_PATH" \
    "Conventional-Commits Operator Toolkit Index"

# ─── Group E: Arc lifecycle stages enumerated ───────────────────────────────
echo ""
echo "GROUP E (4 assertions): arc lifecycle stages named for operator orientation"

iter156_assert_dispatcher_output_contains_substring \
    "E1: VIEW stage named for iter-150" \
    "VIEW (iter-150)"

iter156_assert_dispatcher_output_contains_substring \
    "E2: DETECT stage named for iter-151" \
    "DETECT (iter-151)"

iter156_assert_dispatcher_output_contains_substring \
    "E3: HEALTH SUMMARY stage named for iter-152 + iter-155 fusion" \
    "HEALTH SUMMARY (iter-152, with iter-155 --json)"

iter156_assert_dispatcher_output_contains_substring \
    "E4: PRE-COMMIT ADVISE stage named for iter-153 + iter-154 fusion" \
    "PRE-COMMIT ADVISE (iter-153, with iter-154 hardening)"

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER156_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-156 REGRESSION TEST: ${ITER156_TOTAL_ASSERTIONS_EVALUATED}/${ITER156_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-156 REGRESSION TEST: $((ITER156_TOTAL_ASSERTIONS_EVALUATED - ITER156_TOTAL_ASSERTIONS_FAILED))/${ITER156_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER156_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
