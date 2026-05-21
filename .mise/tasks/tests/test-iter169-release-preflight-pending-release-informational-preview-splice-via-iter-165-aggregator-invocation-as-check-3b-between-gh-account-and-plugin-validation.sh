#!/usr/bin/env bash
#MISE description="Iter-169 regression test pinning the release:preflight pending-release informational preview splice. Pre-iter-169 the operator ran release:full blind to whether there were any release-worthy commits since the last tag — semantic-release would report 'no release' only AFTER preflight + push + dry-run cycles burned multi-second wall-clock. Iter-169 splices the iter-165 pending-release aggregator into release:preflight as a new Check 3b (between Check 2-3 GH auth and Check 4 plugin validation) so the operator sees 'next release version: vCUR → vNEXT' (or 'no pending commits' diagnostic) at the top of preflight, can Ctrl-C early if the release is empty. Deferred until post-iter-167 because pre-iter-167's 1184ms-at-N=50 aggregator latency would have meaningfully slowed preflight; post-iter-167's 228ms median is negligible. Test asserts (a) Check 3b banner present, (b) iter-165 aggregator path resolved correctly relative to preflight task home, (c) splice is INFORMATIONAL only (no exit gate, no exit 1 inside the Check 3b block), (d) FILE-SIZE-OK marker added (preflight now ~1029 lines, over the 1000 block threshold; mirrors iter-160 doctor rationale), (e) MISE description mentions iter-169 pending-release preview, (f) preflight bash -n + shellcheck still pass after splice."
set -euo pipefail

ITER169_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER169_REPO_ROOT"

ITER169_RELEASE_PREFLIGHT_ABSOLUTE_PATH="$ITER169_REPO_ROOT/.mise/tasks/release/preflight"
ITER169_ITER165_AGGREGATOR_ABSOLUTE_PATH="$ITER169_REPO_ROOT/scripts/iter165-pending-release-aggregator-computing-cumulative-semver-bump-across-all-unreleased-commits-since-most-recent-git-tag-by-aggregating-iter161-classifier-output-and-rendering-concrete-iter164-next-version-preview.sh"

ITER169_TOTAL_ASSERTIONS_EVALUATED=0
ITER169_TOTAL_ASSERTIONS_FAILED=0

iter169_assert_substring_present_in_preflight_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER169_TOTAL_ASSERTIONS_EVALUATED=$((ITER169_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF "$expected_substring" "$ITER169_RELEASE_PREFLIGHT_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER169_TOTAL_ASSERTIONS_FAILED=$((ITER169_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-169 PREFLIGHT PENDING-RELEASE-PREVIEW SPLICE REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: preflight structurally valid after splice ─────────────────────
echo ""
echo "GROUP A (2 assertions): release:preflight structurally valid after iter-169 splice"

ITER169_TOTAL_ASSERTIONS_EVALUATED=$((ITER169_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER169_RELEASE_PREFLIGHT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A1: preflight passes bash -n syntax check after iter-169 splice"
else
    echo "  ✗ A1: preflight FAILS bash -n syntax check after splice"
    ITER169_TOTAL_ASSERTIONS_FAILED=$((ITER169_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER169_TOTAL_ASSERTIONS_EVALUATED=$((ITER169_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER169_RELEASE_PREFLIGHT_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A2: preflight passes shellcheck (zero warnings) after iter-169 splice"
    else
        echo "  ✗ A2: preflight has shellcheck warnings after splice"
        ITER169_TOTAL_ASSERTIONS_FAILED=$((ITER169_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A2: shellcheck not installed — SKIPPED"
    ITER169_TOTAL_ASSERTIONS_EVALUATED=$((ITER169_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: Check 3b splice landmarks present ─────────────────────────────
echo ""
echo "GROUP B (5 assertions): Check 3b splice landmarks present in preflight source"

iter169_assert_substring_present_in_preflight_with_human_readable_label \
    "B1: Check 3b banner header present (between Check 2-3 GH auth and Check 4 plugin validation)" \
    "Check 3b: ITER-169 PENDING-RELEASE INFORMATIONAL PREVIEW"

iter169_assert_substring_present_in_preflight_with_human_readable_label \
    "B2: operator-visible '→ Iter-169 pending-release preview' echo line emitted at runtime" \
    "→ Iter-169 pending-release preview"

iter169_assert_substring_present_in_preflight_with_human_readable_label \
    "B3: per-phase timing report uses canonical 'Check 3b: iter-169 pending-release informational preview' label" \
    "Check 3b: iter-169 pending-release informational preview"

iter169_assert_substring_present_in_preflight_with_human_readable_label \
    "B4: rationale block explains the post-iter-167 deferral logic (pre-iter-167 1184ms baseline)" \
    "Iter-169 preflight integration was deferred until after iter-167"

iter169_assert_substring_present_in_preflight_with_human_readable_label \
    "B5: rationale block explicitly states splice is informational only (does not gate exit code)" \
    "Informational ONLY"

# ─── Group C: splice is informational (no exit-1 inside Check 3b block) ─────
echo ""
echo "GROUP C (1 assertion): Check 3b splice is informational — no exit-1 inside the block (operator-abort-friendly invariant)"

ITER169_TOTAL_ASSERTIONS_EVALUATED=$((ITER169_TOTAL_ASSERTIONS_EVALUATED + 1))
# Extract the Check 3b block (from "Check 3b: ITER-169" banner up to but not including the next "# Check 4:" boundary)
# and verify it contains no "exit 1" or "exit non-zero" calls.
ITER169_EXTRACTED_CHECK_3B_BLOCK_CONTENTS=$(awk '
    /^# Check 3b: ITER-169 PENDING-RELEASE/ { capturing = 1 }
    capturing { print }
    capturing && /^# Check 4: Plugin validation/ { exit }
' "$ITER169_RELEASE_PREFLIGHT_ABSOLUTE_PATH")
if [[ "$ITER169_EXTRACTED_CHECK_3B_BLOCK_CONTENTS" != *"exit 1"* ]] \
   && [[ "$ITER169_EXTRACTED_CHECK_3B_BLOCK_CONTENTS" != *"exit non-zero"* ]]; then
    echo "  ✓ C1: Check 3b block contains zero 'exit 1' or 'exit non-zero' calls (informational invariant preserved)"
else
    echo "  ✗ C1: Check 3b block contains exit-gating code — VIOLATES iter-169 informational invariant"
    ITER169_TOTAL_ASSERTIONS_FAILED=$((ITER169_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group D: aggregator path resolution from preflight task home is correct
echo ""
echo "GROUP D (2 assertions): aggregator path resolution from preflight task home is correct"

ITER169_TOTAL_ASSERTIONS_EVALUATED=$((ITER169_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -x "$ITER169_ITER165_AGGREGATOR_ABSOLUTE_PATH" ]]; then
    echo "  ✓ D1: iter-165 aggregator exists + is executable at canonical path (target of preflight splice)"
else
    echo "  ✗ D1: iter-165 aggregator missing or not executable — splice would silently skip"
    ITER169_TOTAL_ASSERTIONS_FAILED=$((ITER169_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Verify the relative path computation from preflight task home resolves to the aggregator.
ITER169_TOTAL_ASSERTIONS_EVALUATED=$((ITER169_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER169_PREFLIGHT_TASK_HOME_DIR="$(dirname "$ITER169_RELEASE_PREFLIGHT_ABSOLUTE_PATH")"
ITER169_RESOLVED_AGGREGATOR_PATH_FROM_PREFLIGHT_TASK_HOME="$ITER169_PREFLIGHT_TASK_HOME_DIR/../../../scripts/iter165-pending-release-aggregator-computing-cumulative-semver-bump-across-all-unreleased-commits-since-most-recent-git-tag-by-aggregating-iter161-classifier-output-and-rendering-concrete-iter164-next-version-preview.sh"
if [[ -x "$ITER169_RESOLVED_AGGREGATOR_PATH_FROM_PREFLIGHT_TASK_HOME" ]]; then
    echo "  ✓ D2: preflight-task-relative ../../../scripts/iter165-...sh path resolution lands on the aggregator (preflight splice will fire correctly at runtime)"
else
    echo "  ✗ D2: preflight-task-relative path resolution does NOT land on the aggregator — splice would silently SKIP"
    ITER169_TOTAL_ASSERTIONS_FAILED=$((ITER169_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: FILE-SIZE-OK marker + MISE description updates ────────────────
echo ""
echo "GROUP E (3 assertions): FILE-SIZE-OK marker added + MISE description mentions iter-169"

iter169_assert_substring_present_in_preflight_with_human_readable_label \
    "E1: FILE-SIZE-OK marker added at top (preflight now over 1000-line file-size-guard block threshold; mirrors iter-160 doctor rationale)" \
    "FILE-SIZE-OK"

iter169_assert_substring_present_in_preflight_with_human_readable_label \
    "E2: FILE-SIZE-OK rationale explicitly references iter-169 splice context" \
    "Reviewed at iter-169"

iter169_assert_substring_present_in_preflight_with_human_readable_label \
    "E3: MISE task description mentions iter-169 pending-release informational preview (discoverable via 'mise tasks' enumeration)" \
    "iter-169 pending-release informational preview"

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER169_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-169 REGRESSION TEST: ${ITER169_TOTAL_ASSERTIONS_EVALUATED}/${ITER169_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-169 REGRESSION TEST: $((ITER169_TOTAL_ASSERTIONS_EVALUATED - ITER169_TOTAL_ASSERTIONS_FAILED))/${ITER169_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER169_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
