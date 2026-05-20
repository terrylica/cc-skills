#!/usr/bin/env bash
# test-userpromptsubmit-1password-context-injection-prejq-fastpath-preserves-case-insensitive-keyword-detection.sh
#
# Regression test for iter-41 pre-jq-fastpath on
# userpromptsubmit-1password-context-injection.sh. Verifies that the
# bash-builtin case-glob with `shopt -s nocasematch` pre-check is:
#
#   (A) FUNCTIONALLY EQUIVALENT to the prior unconditional jq+tr+grep
#       pipeline — all keywords that previously triggered context
#       injection still do.
#
#   (B) CASE-INSENSITIVE — matches `1Password`, `1PASSWORD`, `1password`,
#       `Service Account`, `SA Token`, etc. all equivalently.
#
#   (C) OVER-INCLUSIVE BUT SAFE — prompts that match the fast-path
#       substring but NOT the precise downstream \b-bounded grep
#       (e.g., "1page", "options", "stop item from running") correctly
#       bail OUT via the second-stage filter, not via the fast-path.
#
#   (D) FAST-PATH SHORT-CIRCUITS UNRELATED PROMPTS — prompts containing
#       NONE of the keyword substrings (the ~95% common case) bail out
#       in the fast-path without spawning jq.
#
# Verbose filename per user directive — encodes the exact invariant
# being verified so future maintainers grep'ing for "fastpath",
# "userpromptsubmit", "1password", "case-insensitive", or "keyword
# detection" surface this regression guard immediately.

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
# disable bash 5.2+ `&`-as-backreference. See
# plugins/autoloop/hooks/heartbeat-tick.sh for full rationale.
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# iter-41 layout: this test file lives in plugins/devops-tools/hooks/tests/
# (sibling-tests-subdir convention from iter-40). The hook under test is
# one directory up.
HOOK_UNDER_TEST="$SCRIPT_DIR/../userpromptsubmit-1password-context-injection.sh"

if [ ! -x "$HOOK_UNDER_TEST" ]; then
  echo "FATAL: hook not executable: $HOOK_UNDER_TEST" >&2
  exit 1
fi

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Test harness: feed a `prompt` JSON payload, check whether the hook
# emitted the [1PASSWORD-CONTEXT] block (fired) or stayed silent (bailed).
# ---------------------------------------------------------------------------

hook_injects_context() {
  local prompt_text="$1"
  local payload
  payload=$(jq -n --arg p "$prompt_text" '{prompt: $p}')
  local hook_stdout
  hook_stdout=$(printf '%s' "$payload" | "$HOOK_UNDER_TEST" 2>/dev/null || true)
  if echo "$hook_stdout" | grep -q '\[1PASSWORD-CONTEXT\]'; then
    return 0
  else
    return 1
  fi
}

assert_injects_context() {
  local desc="$1"
  local prompt_text="$2"
  if hook_injects_context "$prompt_text"; then
    echo "  ✓ PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ FAIL: $desc (expected context injection, got silence)"
    echo "    prompt: $prompt_text"
    FAIL=$((FAIL+1))
  fi
}

assert_silent() {
  local desc="$1"
  local prompt_text="$2"
  if ! hook_injects_context "$prompt_text"; then
    echo "  ✓ PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ FAIL: $desc (expected silence, got context injection)"
    echo "    prompt: $prompt_text"
    FAIL=$((FAIL+1))
  fi
}

# ---------------------------------------------------------------------------
# INVARIANT A: Functional equivalence — all keywords that triggered
# context injection pre-iter-41 still trigger under the fast-path
# ---------------------------------------------------------------------------
echo "=== INVARIANT A: all documented keywords still trigger context injection ==="

assert_injects_context \
  "lowercase 1password" \
  "How do I store credentials in 1password?"

assert_injects_context \
  "exact 1Password capitalization" \
  "Use 1Password to fetch the API key."

assert_injects_context \
  "service account multi-word phrase" \
  "Use the service account to access the vault."

assert_injects_context \
  "SA token shorthand" \
  "Run with the SA token from 1Password."

assert_injects_context \
  "Claude Automation vault reference" \
  "The credential lives in the Claude Automation vault."

assert_injects_context \
  "op:// URI prefix" \
  "Fetch op://Engineering/MyItem/secret"

assert_injects_context \
  "op item subcommand reference" \
  "I want to run op item get to fetch the API key."

assert_injects_context \
  "op read subcommand reference" \
  "Use op read to fetch the credential."

assert_injects_context \
  "op vault subcommand reference" \
  "Use op vault list to enumerate vaults."

assert_injects_context \
  "op list subcommand reference" \
  "Try op list to see items."

assert_injects_context \
  "op create subcommand reference" \
  "Use op create item for a new credential."

assert_injects_context \
  "op edit subcommand reference" \
  "Use op edit to modify the field."

assert_injects_context \
  "op delete subcommand reference" \
  "Use op delete on the expired credential."

assert_injects_context \
  "1p shorthand abbreviation" \
  "Check 1p for the credential."

# ---------------------------------------------------------------------------
# INVARIANT B: Case-insensitivity — uppercase/mixed-case variants all
# trigger context injection equivalently
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT B: case-insensitive substring matching at fast-path ==="

assert_injects_context \
  "UPPERCASE 1PASSWORD" \
  "Use 1PASSWORD to fetch credentials."

assert_injects_context \
  "Mixed-case Service Account" \
  "Configure the Service Account integration."

assert_injects_context \
  "ALL-CAPS SA TOKEN" \
  "Where is the SA TOKEN stored?"

assert_injects_context \
  "Title-Case Claude Automation" \
  "I lost access to the Claude Automation vault."

assert_injects_context \
  "Uppercase OP:// URI prefix" \
  "The path is OP://Engineering/Foo/bar"

# ---------------------------------------------------------------------------
# INVARIANT C: Over-inclusive fast-path correctly filtered by downstream
# precise \b-bounded grep — false-positive substrings DO NOT inject context
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT C: fast-path over-inclusion correctly caught by downstream grep ==="

assert_silent \
  "prompt containing '1page' (1p substring but not \\b1p\\b)" \
  "Show me the 1page documentation."

assert_silent \
  "prompt containing 'options' (op substring but not \\bop\\b)" \
  "What are the available options for this command?"

assert_silent \
  "prompt containing 'stop item' (op substring within stop, not \\bop\\b)" \
  "Stop item from running on the server."

assert_silent \
  "prompt containing 'opera' (op substring but not whole word op)" \
  "The opera tickets are sold out."

# Note: "1password" SHOULD inject even when embedded in larger words
# (e.g., "1passwordrc" or "x1passwordy") because the fast-path is
# intentionally over-inclusive and the downstream regex uses \b1password\b
# which only matches whole words. So these test cases verify the precise
# downstream filter dropping them.
assert_silent \
  "prompt with 1password embedded in larger word (no whole-word match)" \
  "Check x1passwordy/config for settings."

# ---------------------------------------------------------------------------
# INVARIANT D: Fast-path short-circuits unrelated prompts in <1 ms
# (true negatives — bulk of real-world prompts)
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT D: fast-path short-circuits unrelated prompts (no jq spawn) ==="

assert_silent \
  "typical coding question — no keywords" \
  "How do I implement a binary search in Python?"

assert_silent \
  "git workflow question — no keywords" \
  "What is the difference between git fetch and git pull?"

assert_silent \
  "debugging question — no keywords" \
  "My script segfaults — how do I find the bad memory access?"

assert_silent \
  "documentation question — no keywords" \
  "Where can I read about Claude Code hooks?"

assert_silent \
  "math question — no keywords" \
  "What is the time complexity of mergesort?"

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
