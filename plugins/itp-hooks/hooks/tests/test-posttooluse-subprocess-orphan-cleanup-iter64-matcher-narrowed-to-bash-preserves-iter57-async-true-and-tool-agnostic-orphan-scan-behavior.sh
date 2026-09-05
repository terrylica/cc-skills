#!/usr/bin/env bash
# test-posttooluse-subprocess-orphan-cleanup-iter64-matcher-narrowed-to-bash-preserves-iter57-async-true-and-tool-agnostic-orphan-scan-behavior.sh
#
# Regression test for the iter-64 PostToolUse matcher-narrowing perf
# optimization. Companion to iter-63 (which did the same on the
# PreToolUse stdin-inlet-guard twin).
#
# Background:
#   Before iter-64, posttooluse-subprocess-orphan-cleanup.ts was
#   registered in itp-hooks/hooks.json with matcher "*", meaning
#   Claude Code async-cold-started bun on every tool call (~12-17ms
#   CPU each). The hook is async:true (iter-57), so this didn't add
#   user-visible latency, but it wasted ~960-1360ms of CPU+battery
#   per typical 100-tool session.
#
#   Per the source's design (scans by ppid === claude_pid, not by
#   tool_name), the orphan-cleanup only finds orphans spawned by
#   Bash. Read/Glob/Grep are in-process; Edit/Write trigger
#   PostToolUse formatter hooks (ty, biome, oxlint, tsgo) but those
#   use Bun.spawnSync — synchronously awaited subprocesses cannot
#   orphan past the tool call boundary.
#
#   iter-64 narrows the hooks.json matcher to "Bash". This test
#   locks the invariant.
#
# Coverage matrix (8 assertions, 3 categories):
#
#   Category A — hooks.json invariants:
#     #01: matcher value is "Bash" (iter-64 invariant)
#     #02: async:true flag is preserved (iter-57 invariant)
#     #03: timeout is preserved (5 SECONDS, sanity)
#     #03b: timeout is inside the schema's 1-600 s ceiling, so the
#          millisecond spelling fails on meaning and not just equality
#
#   Category B — runtime behavior (clean state, no orphans):
#     #04: hook exits with code 0 (fail-open contract preserved)
#     #05: hook emits the "Scanning for zombie processes" diagnostic
#          on stderr (operator visibility)
#     #06: hook emits "No orphaned processes found" when no orphans
#          exist (clean-state happy path)
#     #07: hook emits NOTHING on stdout (informational hook; emitting
#          stray JSON to stdout would risk Claude Code mis-parsing it
#          as a hookSpecificOutput payload — verify stdout stays empty)
#
# Verbose filename encodes: WHAT (posttooluse-subprocess-orphan-
# cleanup), WHEN (iter-64), HOW (matcher narrowed to Bash), and
# WHICH INVARIANTS are preserved (iter-57 async:true + tool-agnostic
# orphan scan behavior). Future maintainers searching for "orphan
# cleanup test", "matcher narrowing iter-64", "PostToolUse async
# true", or "iter-57 async invariant" surface this regression guard.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../posttooluse-subprocess-orphan-cleanup.ts"
HOOKS_JSON="$SCRIPT_DIR/../hooks.json"

if [ ! -f "$HOOK_SCRIPT" ]; then
  echo "FATAL: hook script not found: $HOOK_SCRIPT" >&2
  exit 1
fi
if [ ! -f "$HOOKS_JSON" ]; then
  echo "FATAL: hooks.json not found: $HOOKS_JSON" >&2
  exit 1
fi

PASS=0
FAIL=0
assert_pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# Helper: extract the orphan-cleanup hook entry from hooks.json using
# jq (PostToolUse → entry whose command contains the script name).
extract_orphan_cleanup_entry_field() {
  local field="$1"
  jq -r --arg field "$field" '
    .hooks.PostToolUse[]
    | select(.hooks[].command | contains("posttooluse-subprocess-orphan-cleanup"))
    | (
        if $field == "matcher" then .matcher
        elif $field == "timeout" then .hooks[0].timeout
        elif $field == "async" then .hooks[0].async
        else "<UNKNOWN-FIELD>"
        end
      )
  ' "$HOOKS_JSON" 2>/dev/null | head -1
}

# ---------------------------------------------------------------------------
# Category A: hooks.json invariants
# ---------------------------------------------------------------------------
echo "=== Category A: hooks.json invariants ==="

# Test #01: iter-64 matcher narrowing
matcher_value=$(extract_orphan_cleanup_entry_field "matcher")
if [ "$matcher_value" = "Bash" ]; then
  assert_pass "hooks.json matcher for orphan-cleanup is 'Bash' (iter-64 invariant)"
else
  assert_fail "hooks.json matcher is '$matcher_value', expected 'Bash' (iter-64 narrowed from '*')"
fi

# Test #02: iter-57 async:true preserved
async_value=$(extract_orphan_cleanup_entry_field "async")
if [ "$async_value" = "true" ]; then
  assert_pass "hooks.json async:true preserved for orphan-cleanup (iter-57 invariant)"
else
  assert_fail "hooks.json async is '$async_value', expected 'true' (iter-57 invariant lost)"
fi

# Test #03: timeout is sane, and is SECONDS
#
# This assertion pinned '5000' until 2026-09-05. That was the millisecond
# spelling: the field is seconds (the shipped binary computes
# `hook.timeout * 1000` at 15 call sites), so 5000 meant 83 minutes, not 5
# seconds. #124 corrected every hooks.json but not this test, which was left
# demanding the defect back — a red gate that a future maintainer could
# "fix" by reintroducing the bug. Asserting the bound as well as the literal
# means the millisecond spelling now fails on meaning, not just on equality.
timeout_value=$(extract_orphan_cleanup_entry_field "timeout")
if [ "$timeout_value" = "5" ]; then
  assert_pass "hooks.json timeout is 5 SECONDS (sanity check preserved)"
else
  assert_fail "hooks.json timeout is '$timeout_value', expected '5' (SECONDS, not ms)"
fi

# Test #03b: timeout is inside the schema's 1-600 s ceiling
if [ -n "$timeout_value" ] \
  && [ "$timeout_value" -eq "$timeout_value" ] 2>/dev/null \
  && [ "$timeout_value" -ge 1 ] && [ "$timeout_value" -le 600 ]; then
  assert_pass "hooks.json timeout ${timeout_value}s is within the 1-600s schema bound"
else
  assert_fail "hooks.json timeout '$timeout_value' is outside 1-600 SECONDS (a 4-digit value is the millisecond spelling)"
fi

# ---------------------------------------------------------------------------
# Category B: runtime behavior (clean state)
# ---------------------------------------------------------------------------
echo ""
echo "=== Category B: runtime behavior on clean state (no Bash-spawned orphans) ==="

# The orphan-cleanup hook does not read stdin (it scans /proc by ppid).
# Invoke it with a minimal Bash-tool payload to mirror production
# invocation. Capture stdout, stderr, and exit code separately.
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo hello"},"tool_response":{}}'
STDOUT_FILE=$(mktemp)
STDERR_FILE=$(mktemp)
trap 'rm -f "$STDOUT_FILE" "$STDERR_FILE"' EXIT

set +e
echo "$PAYLOAD" | bun "$HOOK_SCRIPT" >"$STDOUT_FILE" 2>"$STDERR_FILE"
EXIT_CODE=$?
set -e

STDOUT_CONTENT=$(cat "$STDOUT_FILE")
STDERR_CONTENT=$(cat "$STDERR_FILE")

# Test #04: exit code 0 (fail-open contract)
if [ "$EXIT_CODE" = "0" ]; then
  assert_pass "Hook exits with code 0 (fail-open contract preserved)"
else
  assert_fail "Hook exited with code $EXIT_CODE, expected 0. stderr: $STDERR_CONTENT"
fi

# Test #05: scanning-diagnostic appears on stderr
if grep -q 'Scanning for zombie processes' <<<"$STDERR_CONTENT"; then
  assert_pass "Hook emits 'Scanning for zombie processes' diagnostic on stderr (operator visibility)"
else
  assert_fail "Hook did not emit expected scanning diagnostic. stderr was: $STDERR_CONTENT"
fi

# Test #06: clean-state happy path
# This test is conservative: we assert that EITHER "No orphaned processes found"
# OR "Cleaned up N orphaned process(es)" appears, because in CI there may be
# stray processes from other tests. Both messages indicate the hook ran to
# completion without crashing.
if grep -qE 'No orphaned processes found|Cleaned up [0-9]+ orphaned process' <<<"$STDERR_CONTENT"; then
  assert_pass "Hook reaches the orphan-scan completion path (clean state OR cleanup-done state)"
else
  assert_fail "Hook did not complete the orphan-scan path. stderr was: $STDERR_CONTENT"
fi

# Test #07: stdout must be empty (informational hook contract)
# The orphan-cleanup hook is informational-only — it scans processes and
# emits diagnostics to stderr. It must NEVER emit to stdout because any
# stdout content gets parsed by Claude Code as a hookSpecificOutput
# payload. Stray JSON or text on stdout could trigger schema-validation
# errors or worse — silently inject context Claude wasn't supposed to see.
if [ -z "$STDOUT_CONTENT" ]; then
  assert_pass "Hook emits NOTHING on stdout (informational contract preserved)"
else
  assert_fail "Hook unexpectedly emitted stdout. Content was: $STDOUT_CONTENT"
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
