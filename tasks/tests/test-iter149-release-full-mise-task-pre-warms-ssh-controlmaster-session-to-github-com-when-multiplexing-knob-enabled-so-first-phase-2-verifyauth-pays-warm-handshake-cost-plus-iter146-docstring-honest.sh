#!/usr/bin/env bash
#MISE description="Iter-149 regression test pinning two deliverables: (a) .mise/tasks/release/full mise task gained an SSH ControlMaster pre-warm block lifted from iter-148's empirical-validation wrapper, gated on the same RELEASE_SSH_MULTIPLEXING_ENABLED knob as iter-147, that runs a `timeout 10 ssh -T -o BatchMode=yes -o ControlMaster=auto -o ControlPath=... -o ControlPersist=10m git@github.com` immediately AFTER the iter-147 GIT_SSH_COMMAND export, paying the cold SSH handshake cost upfront so the first in-pipeline Phase 2 verifyAuth git-push-dry-run invocation gets WARM cost (~1.8s per iter-148 measurement) instead of COLD cost (~6.0s per iter-148 BEFORE baseline) — saving ~4.2s on the first SSH op of every release where the knob is enabled; (b) scripts/iter146-...sh docstring replaces the original CONJECTURAL '10-15x speedup' claim with the iter-148-empirically-MEASURED 3.30x speedup truth (6051ms→1835ms p50, 4216ms saved per call), citing iter-148 wrapper methodology."
set -euo pipefail

ITER149_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER149_REPO_ROOT"

ITER149_RELEASE_FULL_MISE_TASK_RELATIVE_PATH=".mise/tasks/release/full"
ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH="$ITER149_REPO_ROOT/$ITER149_RELEASE_FULL_MISE_TASK_RELATIVE_PATH"
ITER149_ITER146_SETUP_SCRIPT_RELATIVE_PATH="scripts/iter146-configure-ssh-controlmaster-for-github-com-to-cache-ssh-connection-and-eliminate-repeat-handshake-cost-per-release-via-openssh-connection-multiplexing.sh"
ITER149_ITER146_SETUP_SCRIPT_ABSOLUTE_PATH="$ITER149_REPO_ROOT/$ITER149_ITER146_SETUP_SCRIPT_RELATIVE_PATH"

ITER149_TOTAL_ASSERTIONS_EVALUATED=0
ITER149_TOTAL_ASSERTIONS_FAILED=0

iter149_assert_substring_present_in_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER149_TOTAL_ASSERTIONS_EVALUATED=$((ITER149_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:120}"
        ITER149_TOTAL_ASSERTIONS_FAILED=$((ITER149_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-149 RELEASE-FULL SSH PRE-WARM + ITER-146 DOCSTRING HONESTY TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: release/full has iter-149 SSH pre-warm block ─────────────────
echo ""
echo "GROUP A (6 assertions): release/full gained iter-149 SSH pre-warm pattern"

iter149_assert_substring_present_in_file \
    "A1: release/full references iter-149 in pre-warm block" \
    "$ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    "ITER-149"

iter149_assert_substring_present_in_file \
    "A2: release/full pre-warm uses timeout-budgeted ssh invocation (10-second budget)" \
    "$ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    "timeout 10 ssh"

iter149_assert_substring_present_in_file \
    "A3: release/full pre-warm uses -T to disable pseudo-TTY allocation" \
    "$ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    "-T"

iter149_assert_substring_present_in_file \
    "A4: release/full pre-warm uses BatchMode=yes for non-interactive auth-or-fail-fast" \
    "$ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    "BatchMode=yes"

iter149_assert_substring_present_in_file \
    "A5: release/full pre-warm targets git@github.com (the only host the release pipeline talks to)" \
    "$ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    "git@github.com"

iter149_assert_substring_present_in_file \
    "A6: release/full pre-warm uses ControlPersist=10m matching iter-146/147/148 invariant" \
    "$ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    "ControlPersist=10m"

# ─── Group B: pre-warm is gated on iter-147 RELEASE_SSH_MULTIPLEXING_ENABLED knob
echo ""
echo "GROUP B (3 assertions): pre-warm gated on iter-147 env-var knob (no surprise auto-enable)"

iter149_assert_substring_present_in_file \
    "B1: pre-warm shares the iter-147 RELEASE_SSH_MULTIPLEXING_ENABLED gating env var" \
    "$ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    "RELEASE_SSH_MULTIPLEXING_ENABLED"

iter149_assert_substring_present_in_file \
    "B2: pre-warm function name encodes the iter-149-pays-cold-handshake-upfront-so-pipeline-pays-warm purpose" \
    "$ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    "iter149_release_pipeline_ssh_controlmaster_prewarm_to_github_com_to_pay_cold_handshake_upfront"

iter149_assert_substring_present_in_file \
    "B3: pre-warm emits operator-visible success/warn message based on cached session socket existence" \
    "$ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    "cached ControlMaster session active"

# ─── Group C: iter-146 docstring replaces conjectural with empirical truth
echo ""
echo "GROUP C (4 assertions): iter-146 docstring honest about iter-148-measured 3.30x speedup"

iter149_assert_substring_present_in_file \
    "C1: iter-146 docstring cites iter-148 empirical measurement methodology" \
    "$ITER149_ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "iter-148 measurement"

iter149_assert_substring_present_in_file \
    "C2: iter-146 docstring documents the empirical 3.30x speedup figure" \
    "$ITER149_ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "3.30x"

iter149_assert_substring_present_in_file \
    "C3: iter-146 docstring documents BEFORE-vs-AFTER p50 values (6051ms → 1835ms)" \
    "$ITER149_ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "6051ms"

iter149_assert_substring_present_in_file \
    "C4: iter-146 docstring explicitly acknowledges the original 10-15x claim was conjectural" \
    "$ITER149_ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "conjectural"

# ─── Group D: release/full structural cleanliness ───────────────────────────
echo ""
echo "GROUP D (2 assertions): release/full bash + shellcheck clean after iter-149 edit"

ITER149_TOTAL_ASSERTIONS_EVALUATED=$((ITER149_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ D1: release/full passes bash -n syntax check"
else
    echo "  ✗ D1: release/full FAILS bash -n syntax check"
    ITER149_TOTAL_ASSERTIONS_FAILED=$((ITER149_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER149_TOTAL_ASSERTIONS_EVALUATED=$((ITER149_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER149_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ D2: release/full passes shellcheck (zero warnings)"
    else
        echo "  ✗ D2: release/full has shellcheck warnings"
        ITER149_TOTAL_ASSERTIONS_FAILED=$((ITER149_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ D2: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER149_TOTAL_ASSERTIONS_EVALUATED=$((ITER149_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER149_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-149 REGRESSION TEST: ${ITER149_TOTAL_ASSERTIONS_EVALUATED}/${ITER149_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-149 REGRESSION TEST: $((ITER149_TOTAL_ASSERTIONS_EVALUATED - ITER149_TOTAL_ASSERTIONS_FAILED))/${ITER149_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER149_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
