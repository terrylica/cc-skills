#!/usr/bin/env bash
# test-subprocess-stdin-inlet-guard-iter63-matcher-narrowed-to-bash-wraps-with-dev-null-redirect-skips-ssh-and-defensively-early-exits-on-non-bash-tool-names.sh
#
# Regression test for the iter-63 matcher-narrowing perf optimization on
# plugins/itp-hooks/hooks/pretooluse-subprocess-stdin-inlet-guard.ts.
#
# Background:
#   Before iter-63 the hook was registered with matcher "*" (fires on
#   every tool call: Read/Glob/Grep/Edit/Write/mcp__*/Bash/etc.). The
#   non-Bash branches were no-op stubs that just called allow(), but
#   Claude Code still cold-started bun on every call (~12-17ms each).
#
#   iter-63 narrowed the hooks.json matcher to "Bash" and refactored
#   the source to use a defensive non-Bash early-exit guard (in case
#   an operator widens the matcher later without also widening the
#   handler branches). This test locks in BOTH the Bash behavior AND
#   the defensive guard so neither regresses.
#
# Coverage matrix (7 assertions, 4 inputs):
#
#   # | Input                                | Expected hookSpecificOutput          | Bash STDIN wrap?
#   --|--------------------------------------|--------------------------------------|------------------
#   01| Bash with simple command             | allow + updatedInput.command wrapped | YES — < /dev/null
#   02| Bash with SSH remote command         | bare allow (no updatedInput)         | NO — SSH skip
#   03| Bash already containing < /dev/null  | bare allow (no double-wrap)          | NO — already wrapped
#   04| Bash with no `command` field         | bare allow                           | n/a — defensive
#   05| non-Bash (Read) → defensive exit     | bare allow (no updatedInput)         | n/a — iter-63 guard
#   06| stderr emits the diagnostic emoji    | "🛡️  Subprocess Inlet Guard"           | only on Bash
#   07| Non-Bash emits no stderr diagnostic  | (silent)                             | n/a
#
# Verbose filename encodes: WHAT (subprocess-stdin-inlet-guard), WHEN
# (iter-63), HOW (matcher narrowed to Bash), and WHICH defensive
# semantics (wraps Bash, skips SSH, early-exits non-Bash). Future
# maintainers searching for "stdin inlet guard test", "matcher narrowing
# regression", "iter-63", or "non-Bash early exit" surface this guard.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../pretooluse-subprocess-stdin-inlet-guard.ts"

if [ ! -f "$HOOK_SCRIPT" ]; then
  echo "FATAL: hook script not found: $HOOK_SCRIPT" >&2
  exit 1
fi

PASS=0
FAIL=0
assert_pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# Helper: run hook with a JSON payload, capture stdout + stderr separately.
run_hook_capture_stdout_and_stderr_separately() {
  local payload="$1" stdout_var="$2" stderr_var="$3"
  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  echo "$payload" | bun "$HOOK_SCRIPT" >"$stdout_file" 2>"$stderr_file" || true
  # Use indirect assignment via printf -v for clean variable export.
  printf -v "$stdout_var" '%s' "$(cat "$stdout_file")"
  printf -v "$stderr_var" '%s' "$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# ---------------------------------------------------------------------------
# Test #01: Bash simple command gets wrapped with < /dev/null
# ---------------------------------------------------------------------------
echo "=== Test #01: Bash 'echo hello' → wrapped command ==="
run_hook_capture_stdout_and_stderr_separately \
  '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' \
  STDOUT_01 STDERR_01

# Assertion: updatedInput.command must contain "< /dev/null"
if echo "$STDOUT_01" | grep -q '"updatedInput":{"command":"(echo hello) < /dev/null"}'; then
  assert_pass "Bash command wrapped with parenthesized < /dev/null redirect"
else
  assert_fail "Bash command not wrapped correctly. Got: $STDOUT_01"
fi

# Assertion #06: stderr emits the diagnostic emoji
if echo "$STDERR_01" | grep -q 'Subprocess Inlet Guard: Pre-disconnecting stdin'; then
  assert_pass "Diagnostic 'Subprocess Inlet Guard' message on stderr (operator visibility)"
else
  assert_fail "Diagnostic message missing on stderr. Got: $STDERR_01"
fi

# ---------------------------------------------------------------------------
# Test #02: Bash SSH remote command is NOT wrapped (skip)
# ---------------------------------------------------------------------------
echo ""
echo "=== Test #02: Bash 'ssh bigblack uptime' → SSH skip (bare allow) ==="
run_hook_capture_stdout_and_stderr_separately \
  '{"tool_name":"Bash","tool_input":{"command":"ssh bigblack uptime"}}' \
  STDOUT_02 STDERR_02

if echo "$STDOUT_02" | grep -q '"permissionDecision":"allow"' && \
   ! echo "$STDOUT_02" | grep -q 'updatedInput'; then
  assert_pass "SSH command returns bare allow (no updatedInput mutation)"
else
  assert_fail "SSH command was wrapped (should have skipped). Got: $STDOUT_02"
fi

# ---------------------------------------------------------------------------
# Test #03: Bash already containing < /dev/null is NOT double-wrapped
# ---------------------------------------------------------------------------
echo ""
echo "=== Test #03: Bash 'cmd < /dev/null' → not double-wrapped ==="
run_hook_capture_stdout_and_stderr_separately \
  '{"tool_name":"Bash","tool_input":{"command":"echo x < /dev/null"}}' \
  STDOUT_03 STDERR_03

# The hook DOES still emit allowWithInput (it wraps once but does not double-wrap).
# Check: command does NOT contain "(echo x < /dev/null) < /dev/null"
if ! echo "$STDOUT_03" | grep -q '< /dev/null) < /dev/null'; then
  assert_pass "Command containing < /dev/null is not double-wrapped"
else
  assert_fail "Double-wrap detected. Got: $STDOUT_03"
fi

# ---------------------------------------------------------------------------
# Test #04: Bash with no command field → bare allow
# ---------------------------------------------------------------------------
echo ""
echo "=== Test #04: Bash with no command field → bare allow ==="
run_hook_capture_stdout_and_stderr_separately \
  '{"tool_name":"Bash","tool_input":{}}' \
  STDOUT_04 STDERR_04

if echo "$STDOUT_04" | grep -q '"permissionDecision":"allow"' && \
   ! echo "$STDOUT_04" | grep -q 'updatedInput'; then
  assert_pass "Bash with empty tool_input returns bare allow (defensive)"
else
  assert_fail "Bash empty tool_input did not return bare allow. Got: $STDOUT_04"
fi

# ---------------------------------------------------------------------------
# Test #05: iter-63 defensive non-Bash early-exit
# This is the load-bearing iter-63 regression: if the matcher ever gets
# widened back to "*" (or a future tool type is added without a handler
# branch), the defensive guard ensures non-Bash tools still get a clean
# bare allow() instead of crashing or fail-opening with a schema error.
# ---------------------------------------------------------------------------
echo ""
echo "=== Test #05: iter-63 defensive non-Bash early-exit (Read) → bare allow ==="
run_hook_capture_stdout_and_stderr_separately \
  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' \
  STDOUT_05 STDERR_05

if echo "$STDOUT_05" | grep -q '"permissionDecision":"allow"' && \
   ! echo "$STDOUT_05" | grep -q 'updatedInput'; then
  assert_pass "Non-Bash (Read) tool returns bare allow (iter-63 defensive early-exit)"
else
  assert_fail "Non-Bash tool did not return bare allow. Got: $STDOUT_05"
fi

# Assertion #07: non-Bash does NOT emit the stderr diagnostic
# (The diagnostic only fires when actively wrapping a Bash command.)
if ! echo "$STDERR_05" | grep -q 'Subprocess Inlet Guard'; then
  assert_pass "Non-Bash tool does not emit stderr diagnostic (silent early-exit)"
else
  assert_fail "Non-Bash tool emitted unexpected diagnostic. Got: $STDERR_05"
fi

# ---------------------------------------------------------------------------
# Sanity check: confirm hooks.json matcher is "Bash" (iter-63 invariant)
# ---------------------------------------------------------------------------
echo ""
echo "=== Sanity check: hooks.json matcher for stdin-inlet-guard is 'Bash' (iter-63) ==="
HOOKS_JSON="$SCRIPT_DIR/../hooks.json"
matcher_value=$(jq -r '
  .hooks.PreToolUse[]
  | select(.hooks[].command | contains("pretooluse-subprocess-stdin-inlet-guard"))
  | .matcher
' "$HOOKS_JSON" 2>/dev/null | head -1)

if [ "$matcher_value" = "Bash" ]; then
  assert_pass "hooks.json matcher for stdin-inlet-guard is 'Bash' (iter-63 invariant)"
else
  assert_fail "hooks.json matcher is '$matcher_value', expected 'Bash' (iter-63 narrowed it from '*')"
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
