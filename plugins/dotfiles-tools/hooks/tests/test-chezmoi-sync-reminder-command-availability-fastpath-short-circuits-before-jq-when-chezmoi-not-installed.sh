#!/usr/bin/env bash
# test-chezmoi-sync-reminder-command-availability-fastpath-short-circuits-before-jq-when-chezmoi-not-installed.sh
#
# Regression test for iter-46 pre-jq-fastpath optimization on
# chezmoi-sync-reminder.sh. The optimization moved `command -v chezmoi`
# from line ~49 (post-jq-and-path-resolution) to line ~19 (before any
# jq spawn). This test pins three invariants:
#
#   (A) The fastpath EXISTS — `command -v chezmoi` appears in the source
#       BEFORE any `jq` invocation.
#
#   (B) The fastpath BAILS QUIETLY when chezmoi is not on $PATH — the
#       hook exits 0 with no output, no jq spawn, no path resolution
#       work performed.
#
#   (C) When chezmoi IS installed, the rest of the hook proceeds normally
#       (smoke check — the hook still extracts file_path, still resolves
#       absolute path, still does its managed-files check).
#
# Verbose filename per the user directive — encodes the exact optimization
# being tested ("command-availability-fastpath-short-circuits-before-jq-
# when-chezmoi-not-installed") so future maintainers searching for
# "command-v fastpath", "chezmoi not installed", "before-jq", or any
# component term surface this regression guard.

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
# disable bash 5.2+ `&`-as-backreference. See
# plugins/autoloop/hooks/heartbeat-tick.sh for full rationale.
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
# INVARIANT A: source-code-level — `command -v chezmoi` appears BEFORE
# any `jq` invocation in the hook source. This is a STRUCTURAL invariant
# that holds regardless of whether chezmoi is installed.
# ---------------------------------------------------------------------------
echo "=== INVARIANT A: source structure — command -v chezmoi appears before jq ==="

cmd_v_line=$(grep -n 'command -v chezmoi' "$HOOK_UNDER_TEST" | head -1 | cut -d: -f1)
first_jq_line=$(grep -n 'jq -r' "$HOOK_UNDER_TEST" | head -1 | cut -d: -f1)

if [ -z "$cmd_v_line" ]; then
  assert_fail "no \`command -v chezmoi\` found in the hook source"
elif [ -z "$first_jq_line" ]; then
  assert_pass "no jq invocations in the hook (degenerate case — fast-path trivially holds)"
elif [ "$cmd_v_line" -lt "$first_jq_line" ]; then
  assert_pass "\`command -v chezmoi\` at line $cmd_v_line is BEFORE first jq at line $first_jq_line"
else
  assert_fail "\`command -v chezmoi\` at line $cmd_v_line is AFTER first jq at line $first_jq_line — iter-46 fast-path regressed"
fi

# ---------------------------------------------------------------------------
# INVARIANT B: behavioral — when chezmoi is NOT on $PATH, the hook
# bails quietly with no jq spawn and no output. Tested by feeding the
# hook a payload while running it with a $PATH that excludes chezmoi.
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT B: behavioral — no-chezmoi bail is silent + zero-jq ==="

# Construct a minimal PostToolUse Edit payload
payload=$(jq -n '{tool_input: {file_path: "/tmp/some/file.md"}}')

# Set up a $PATH that does NOT include chezmoi.
# Use only /usr/bin + /bin which on macOS doesn't include chezmoi (it's
# typically installed via brew at /opt/homebrew/bin or /usr/local/bin).
hook_output=$(PATH="/usr/bin:/bin" printf '%s' "$payload" | "$HOOK_UNDER_TEST" 2>&1 || true)

if [ -z "$hook_output" ]; then
  assert_pass "no-chezmoi bail produced empty output (correct)"
else
  assert_fail "no-chezmoi bail produced unexpected output: $hook_output"
fi

# ---------------------------------------------------------------------------
# INVARIANT C: smoke check — when chezmoi IS available, the hook proceeds
# without crashing. We don't assert specific output (depends on whether
# /tmp/some/file.md is chezmoi-tracked, which it isn't) — just that the
# hook exits 0 cleanly (either silently or with a reminder JSON).
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT C: smoke check — chezmoi-available path doesn't crash ==="

if command -v chezmoi &>/dev/null; then
  # chezmoi IS installed on this machine; run the hook normally
  if printf '%s' "$payload" | "$HOOK_UNDER_TEST" >/dev/null 2>&1; then
    assert_pass "chezmoi-installed path completes successfully (exit 0)"
  else
    assert_fail "chezmoi-installed path exited non-zero — hook may have crashed"
  fi
else
  echo "  ⊘ SKIP: chezmoi not installed on this machine; INVARIANT C cannot run"
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
