#!/usr/bin/env bash
# test-iter63-stdin-inlet-guard-bash-only-matcher.sh
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
# Coverage matrix (9 assertions, 6 inputs):
#
#   # | Input                                | Expected hookSpecificOutput          | Bash STDIN wrap?
#   --|--------------------------------------|--------------------------------------|------------------
#   01| Bash with simple command             | allow + `exec < /dev/null` prefix    | YES — prefix line
#   02| Bash with SSH remote command         | bare allow (no updatedInput)         | NO — SSH skip
#   03| Bash already containing < /dev/null  | allow, command unchanged             | NO — already redirected
#   04| Bash with no `command` field         | bare allow                           | n/a — defensive
#   05| non-Bash (Read) → defensive exit     | bare allow (no updatedInput)         | n/a — iter-63 guard
#   06| stderr emits the diagnostic emoji    | "🛡️  Subprocess Inlet Guard"           | only on Bash
#   07| Non-Bash emits no stderr diagnostic  | (silent)                             | n/a
#   08| Bash ending in a `# comment`         | rewritten command still runs         | YES
#   09| compound `cat; echo done | cat`      | every part reads /dev/null           | YES
#
# The prefix replaced a `( … ) < /dev/null` subshell wrap on 2026-09-28: Claude
# Code's worktree isolation cannot verify git inside that construct and refused
# every git command in worktree sessions (details in the hook source).
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

# Assertion: updatedInput.command is the `exec < /dev/null` PREFIX form.
# INVERTED 2026-09-28: this asserted the old `(echo hello) < /dev/null` subshell
# wrap, which made Claude Code's worktree isolation refuse every git command
# (it cannot verify git inside a subshell with a redirect) and broke any
# command ending in a `#` comment. See the hook source for the measurements.
if grep -qF '"updatedInput":{"command":"exec < /dev/null\necho hello"}' <<<"$STDOUT_01"; then
  assert_pass "Bash command prefixed with 'exec < /dev/null' on its own line"
else
  assert_fail "Bash command not prefixed correctly. Got: $STDOUT_01"
fi

# Assertion #06: stderr emits the diagnostic emoji
if grep -q 'Subprocess Inlet Guard: Pre-disconnecting stdin' <<<"$STDERR_01"; then
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

if grep -q '"permissionDecision":"allow"' <<<"$STDOUT_02" && \
   ! grep -q 'updatedInput' <<<"$STDOUT_02"; then
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

# The hook still emits allowWithInput, with the command passed through unchanged.
if grep -qF '"updatedInput":{"command":"echo x < /dev/null"}' <<<"$STDOUT_03"; then
  assert_pass "Command containing < /dev/null is passed through unchanged (no prefix)"
else
  assert_fail "Command containing < /dev/null was altered. Got: $STDOUT_03"
fi

# ---------------------------------------------------------------------------
# Test #08: a command ending in a `#` comment still yields a valid command.
# The old `( … ) < /dev/null` wrap put the closing parenthesis inside the
# comment, so bash saw an unterminated subshell.
# ---------------------------------------------------------------------------
echo ""
echo "=== Test #08: trailing '# comment' survives the rewrite ==="
run_hook_capture_stdout_and_stderr_separately \
  '{"tool_name":"Bash","tool_input":{"command":"echo ok # trailing note"}}' \
  STDOUT_08 STDERR_08
REWRITTEN_08=$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$STDOUT_08" 2>/dev/null || true)
if [ -n "$REWRITTEN_08" ] && [ "$(bash -c "$REWRITTEN_08" 2>&1)" = "ok" ]; then
  assert_pass "Rewritten command with a trailing comment parses and runs"
else
  assert_fail "Rewritten command with a trailing comment failed. Got: $REWRITTEN_08"
fi

# ---------------------------------------------------------------------------
# Test #09: the rewrite really disconnects stdin for a compound command.
# ---------------------------------------------------------------------------
echo ""
echo "=== Test #09: stdin is /dev/null for every part of a compound command ==="
run_hook_capture_stdout_and_stderr_separately \
  '{"tool_name":"Bash","tool_input":{"command":"cat; echo done | cat"}}' \
  STDOUT_09 STDERR_09
REWRITTEN_09=$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$STDOUT_09" 2>/dev/null || true)
if [ "$(echo SHOULD-NOT-BE-READ | bash -c "$REWRITTEN_09" 2>&1)" = "done" ]; then
  assert_pass "Compound command reads /dev/null, not the caller's stdin"
else
  assert_fail "Compound command still read the caller's stdin. Rewritten: $REWRITTEN_09"
fi

# ---------------------------------------------------------------------------
# Test #04: Bash with no command field → bare allow
# ---------------------------------------------------------------------------
echo ""
echo "=== Test #04: Bash with no command field → bare allow ==="
run_hook_capture_stdout_and_stderr_separately \
  '{"tool_name":"Bash","tool_input":{}}' \
  STDOUT_04 STDERR_04

if grep -q '"permissionDecision":"allow"' <<<"$STDOUT_04" && \
   ! grep -q 'updatedInput' <<<"$STDOUT_04"; then
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

if grep -q '"permissionDecision":"allow"' <<<"$STDOUT_05" && \
   ! grep -q 'updatedInput' <<<"$STDOUT_05"; then
  assert_pass "Non-Bash (Read) tool returns bare allow (iter-63 defensive early-exit)"
else
  assert_fail "Non-Bash tool did not return bare allow. Got: $STDOUT_05"
fi

# Assertion #07: non-Bash does NOT emit the stderr diagnostic
# (The diagnostic only fires when actively wrapping a Bash command.)
if ! grep -q 'Subprocess Inlet Guard' <<<"$STDERR_05"; then
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
