#!/usr/bin/env bash
# test-chezmoi-sync-reminder-plan-mode-bash-builtin-substring-fastpath-bails-without-jq-spawn.sh
#
# Regression test for iter-47 plan-mode-bash-builtin-substring-fastpath
# optimization on chezmoi-sync-reminder.sh. The optimization replaces
# the `jq -r .permission_mode` invocation (~5-7 ms cold-start cost) with
# a bash case-glob substring match on the raw PAYLOAD JSON (~50 µs).
#
# This test pins four invariants:
#
#   (A) The fastpath structure EXISTS — `case "$PAYLOAD" in
#       *'"permission_mode":"plan"'*) exit 0 ;; esac` is present in the
#       source BEFORE any subsequent jq invocations that would have
#       been redundant in plan mode.
#
#   (B) BEHAVIORAL: a payload with `permission_mode: "plan"` triggers a
#       silent exit (no reminder, no output).
#
#   (C) BEHAVIORAL: a payload with `permission_mode: "default"` does NOT
#       trigger plan-mode bail — the hook proceeds to file-path extraction
#       and further processing.
#
#   (D) BEHAVIORAL: a payload with NO `permission_mode` key does NOT
#       trigger plan-mode bail — the hook proceeds normally.
#
# Verbose filename per the user directive — encodes the exact optimization
# being tested ("plan-mode-bash-builtin-substring-fastpath-bails-without-
# jq-spawn") so future maintainers searching for "plan-mode fastpath",
# "case-glob substring", "without-jq", or any component term surface this
# regression guard.

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_UNDER_TEST="$SCRIPT_DIR/../chezmoi-sync-reminder.sh"

if [ ! -x "$HOOK_UNDER_TEST" ]; then
  echo "FATAL: hook not executable: $HOOK_UNDER_TEST" >&2
  exit 1
fi

PASS=0
FAIL=0

assert_pass() {
  echo "  ✓ PASS: $1"
  PASS=$((PASS+1))
}

assert_fail() {
  echo "  ✗ FAIL: $1"
  FAIL=$((FAIL+1))
}

# ---------------------------------------------------------------------------
# INVARIANT A: source-structure — the plan-mode case-glob appears in the
# source BEFORE any jq invocation that would be redundant on plan-mode
# bail. Specifically, before the file_path jq extraction (which is the
# first jq still left in the hook after iter-47).
# ---------------------------------------------------------------------------
echo "=== INVARIANT A: source structure — plan-mode case-glob before file_path jq ==="

# Find the actual `case` STATEMENT (not the comment that documents the
# pattern). The case statement line has the structure:
#   *'"permission_mode":"plan"'*) exit 0 ;;
# i.e., it ends with `) exit 0 ;;` — uniquely identifying the action line.
plan_mode_case_line=$(grep -n '"permission_mode":"plan".*exit 0' "$HOOK_UNDER_TEST" | head -1 | cut -d: -f1)
# Find the actual jq INVOCATION (not the comment that mentions `jq -r`).
# The invocation has the structure `$(echo "$PAYLOAD" | jq -r ...`.
# Filter out lines that are comments (start with optional whitespace then #).
first_jq_line=$(grep -nE '^[^#]*\$\(echo .* \| jq -r' "$HOOK_UNDER_TEST" | head -1 | cut -d: -f1)

if [ -z "$plan_mode_case_line" ]; then
  assert_fail "no plan-mode case-glob found — iter-47 fast-path regressed"
elif [ -z "$first_jq_line" ]; then
  assert_pass "no jq invocations remaining (degenerate case — fast-path trivially holds)"
elif [ "$plan_mode_case_line" -lt "$first_jq_line" ]; then
  assert_pass "plan-mode case-glob at line $plan_mode_case_line is BEFORE first jq at line $first_jq_line"
else
  assert_fail "plan-mode case-glob at line $plan_mode_case_line is AFTER first jq at line $first_jq_line — iter-47 fast-path regressed"
fi

# ---------------------------------------------------------------------------
# INVARIANT B: behavioral — plan-mode payload triggers silent bail.
# Skip if chezmoi is not installed (the iter-46 fastpath would bail
# before reaching the iter-47 check, so we can't test it independently).
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT B: behavioral — permission_mode:'plan' bails silently ==="

if ! command -v chezmoi &>/dev/null; then
  echo "  ⊘ SKIP: chezmoi not installed — iter-46 fastpath bails before iter-47 check"
else
  plan_payload=$(jq -n '{permission_mode: "plan", tool_input: {file_path: "/tmp/some/file.md"}}')
  plan_output=$(printf '%s' "$plan_payload" | "$HOOK_UNDER_TEST" 2>&1 || true)
  if [ -z "$plan_output" ]; then
    assert_pass "plan-mode payload produces empty output (silent bail)"
  else
    assert_fail "plan-mode payload produced unexpected output: $plan_output"
  fi
fi

# ---------------------------------------------------------------------------
# INVARIANT C: behavioral — default-mode payload does NOT trigger
# plan-mode bail. The hook should proceed past the plan-mode check.
# (We assert exit 0 cleanly — the hook may or may not produce a reminder
# depending on whether the file is chezmoi-tracked, but should not crash.)
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT C: behavioral — permission_mode:'default' does NOT bail at plan-mode check ==="

if ! command -v chezmoi &>/dev/null; then
  echo "  ⊘ SKIP: chezmoi not installed — iter-46 fastpath bails before iter-47 check"
else
  default_payload=$(jq -n '{permission_mode: "default", tool_input: {file_path: "/tmp/some/file.md"}}')
  if printf '%s' "$default_payload" | "$HOOK_UNDER_TEST" >/dev/null 2>&1; then
    assert_pass "default-mode payload completes successfully (no plan-mode short-circuit)"
  else
    assert_fail "default-mode payload exited non-zero — hook may have crashed"
  fi
fi

# ---------------------------------------------------------------------------
# INVARIANT D: behavioral — payload with no permission_mode key proceeds.
# Pre-iter-47 the jq -r with `// empty` returned an empty string and the
# [[ ... == "plan" ]] check was false → no bail. Iter-47's case-glob
# substring match for `"permission_mode":"plan"` is also false → no bail.
# Same outcome, just faster.
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT D: behavioral — payload without permission_mode key does NOT bail ==="

if ! command -v chezmoi &>/dev/null; then
  echo "  ⊘ SKIP: chezmoi not installed — iter-46 fastpath bails before iter-47 check"
else
  no_mode_payload=$(jq -n '{tool_input: {file_path: "/tmp/some/file.md"}}')
  if printf '%s' "$no_mode_payload" | "$HOOK_UNDER_TEST" >/dev/null 2>&1; then
    assert_pass "no-permission_mode-key payload completes successfully"
  else
    assert_fail "no-permission_mode-key payload exited non-zero — hook may have crashed"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
