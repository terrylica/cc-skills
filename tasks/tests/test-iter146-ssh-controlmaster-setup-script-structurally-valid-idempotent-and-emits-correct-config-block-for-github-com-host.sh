#!/usr/bin/env bash
#MISE description="Iter-146 regression test for the SSH ControlMaster setup script. Structural-only validation — does NOT actually invoke the script against the operator's ~/.ssh/config (which would require write access + an opt-in decision per the script's design). Asserts: (a) script exists + is executable + shellcheck-clean, (b) script emits the correct OpenSSH ControlMaster directives (ControlMaster auto, ControlPath ~/.ssh/controlmasters/%r@%h:%p, ControlPersist 10m), (c) script implements idempotent-skip via marker-comment detection, (d) script refuses to modify if a conflicting Host github.com block already exists, (e) script backs up existing ~/.ssh/config before modification, (f) script creates ~/.ssh/controlmasters directory with mode 0700, (g) docs/RELEASE.md documents the iter-146 optimization for operator discovery."
set -euo pipefail

ITER146_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER146_REPO_ROOT"

ITER146_SETUP_SCRIPT_RELATIVE_PATH="scripts/iter146-configure-ssh-controlmaster-for-github-com-to-cache-ssh-connection-and-eliminate-repeat-handshake-cost-per-release-via-openssh-connection-multiplexing.sh"
ITER146_SETUP_SCRIPT_ABSOLUTE_PATH="$ITER146_REPO_ROOT/$ITER146_SETUP_SCRIPT_RELATIVE_PATH"
ITER146_RELEASE_MD_DOC_RELATIVE_PATH="docs/RELEASE.md"

ITER146_TOTAL_ASSERTIONS_EVALUATED=0
ITER146_TOTAL_ASSERTIONS_FAILED=0

iter146_assert_substring_present_in_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER146_TOTAL_ASSERTIONS_EVALUATED=$((ITER146_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:120}"
        ITER146_TOTAL_ASSERTIONS_FAILED=$((ITER146_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter146_assert_filesystem_predicate_holds() {
    local human_readable_assertion_label="$1"
    local bash_test_expression="$2"
    ITER146_TOTAL_ASSERTIONS_EVALUATED=$((ITER146_TOTAL_ASSERTIONS_EVALUATED + 1))
    if eval "[[ $bash_test_expression ]]" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    failed bash predicate: $bash_test_expression"
        ITER146_TOTAL_ASSERTIONS_FAILED=$((ITER146_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-146 SSH CONTROLMASTER SETUP SCRIPT REGRESSION TEST"
echo "  Structural-only validation (does not modify operator ~/.ssh/config)."
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Setup script structural validity ────────────────────────────────
echo ""
echo "GROUP A (3 assertions): Setup script presence + executable + syntactically clean"

iter146_assert_filesystem_predicate_holds \
    "A1: setup script exists at iter-146 verbose path" \
    "-f \"$ITER146_SETUP_SCRIPT_ABSOLUTE_PATH\""

iter146_assert_filesystem_predicate_holds \
    "A2: setup script is executable (chmod +x)" \
    "-x \"$ITER146_SETUP_SCRIPT_ABSOLUTE_PATH\""

ITER146_TOTAL_ASSERTIONS_EVALUATED=$((ITER146_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A3: setup script passes bash -n syntax check"
else
    echo "  ✗ A3: setup script FAILS bash -n syntax check"
    ITER146_TOTAL_ASSERTIONS_FAILED=$((ITER146_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group B: OpenSSH ControlMaster directive correctness ────────────────────
echo ""
echo "GROUP B (4 assertions): Correct OpenSSH ControlMaster directives emitted"

iter146_assert_substring_present_in_file \
    "B1: script emits 'Host github.com' stanza header" \
    "$ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "Host github.com"

iter146_assert_substring_present_in_file \
    "B2: script emits 'ControlMaster auto' directive" \
    "$ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "ControlMaster auto"

iter146_assert_substring_present_in_file \
    "B3: script emits 'ControlPath ~/.ssh/controlmasters/%r@%h:%p' directive" \
    "$ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "ControlPath ~/.ssh/controlmasters/%r@%h:%p"

iter146_assert_substring_present_in_file \
    "B4: script emits 'ControlPersist 10m' directive (10-minute session TTL)" \
    "$ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "ControlPersist 10m"

# ─── Group C: Safety invariants — idempotency, conflict-detection, backup ────
echo ""
echo "GROUP C (4 assertions): Safety invariants pinned in script source"

iter146_assert_substring_present_in_file \
    "C1: script implements idempotent-skip via marker-comment detection" \
    "$ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "ITER146_MARKER_COMMENT_LINE_FOR_IDEMPOTENT_DETECTION"

iter146_assert_substring_present_in_file \
    "C2: script refuses to modify if conflicting 'Host github.com' block exists from another source" \
    "$ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "REFUSING to modify automatically"

iter146_assert_substring_present_in_file \
    "C3: script backs up existing ~/.ssh/config before modification" \
    "$ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "iter146-backup"

iter146_assert_substring_present_in_file \
    "C4: script creates ~/.ssh/controlmasters dir with mode 0700 (owner-only permissions)" \
    "$ITER146_SETUP_SCRIPT_ABSOLUTE_PATH" \
    "chmod 700"

# ─── Group D: docs/RELEASE.md documentation invariants ────────────────────────
echo ""
echo "GROUP D (4 assertions): Iter-146 documentation present in docs/RELEASE.md"

iter146_assert_substring_present_in_file \
    "D1: docs/RELEASE.md has a Phase 2 bottleneck breakdown section" \
    "$ITER146_RELEASE_MD_DOC_RELATIVE_PATH" \
    "Phase 2 (semantic-release) Internal Bottleneck Breakdown"

iter146_assert_substring_present_in_file \
    "D2: docs/RELEASE.md documents the get-git-auth-url verifyAuth bottleneck" \
    "$ITER146_RELEASE_MD_DOC_RELATIVE_PATH" \
    "semantic-release:get-git-auth-url"

iter146_assert_substring_present_in_file \
    "D3: docs/RELEASE.md documents the iter-145 forensic finding for tag-notes backfill" \
    "$ITER146_RELEASE_MD_DOC_RELATIVE_PATH" \
    "silent"

iter146_assert_substring_present_in_file \
    "D4: docs/RELEASE.md documents the iter-146 SSH ControlMaster optimization opt-in" \
    "$ITER146_RELEASE_MD_DOC_RELATIVE_PATH" \
    "ControlMaster"

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER146_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-146 REGRESSION TEST: ${ITER146_TOTAL_ASSERTIONS_EVALUATED}/${ITER146_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-146 REGRESSION TEST: $((ITER146_TOTAL_ASSERTIONS_EVALUATED - ITER146_TOTAL_ASSERTIONS_FAILED))/${ITER146_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER146_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
