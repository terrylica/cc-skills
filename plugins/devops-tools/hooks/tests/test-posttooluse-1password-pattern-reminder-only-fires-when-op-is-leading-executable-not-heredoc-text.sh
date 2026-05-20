#!/usr/bin/env bash
# test-posttooluse-1password-pattern-reminder-only-fires-when-op-is-leading-executable-not-heredoc-text.sh
#
# Regression test for iter-39 false-positive fix in
# posttooluse-1password-pattern-reminder.sh. The hook used to fire on
# any command containing the word `op` after whitespace, which falsely
# matched commit-message heredocs that referenced `op read` as
# documentation (iter-37 and iter-38 commits hit this twice).
#
# This test pins the invariant: the hook MUST fire only when `op` is
# the leading executable token of the command (after optional env-var
# assignments) — NEVER when `op` appears inside argument strings,
# heredoc bodies, comments, or quoted blocks.
#
# Verbose filename per user directive: encodes the exact behavior
# being verified so the test surfaces in `grep`/`find` searches for
# "false positive", "heredoc", "leading executable", or any of the
# related concepts.

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
# disable bash 5.2+ `&`-as-backreference. See
# plugins/autoloop/hooks/heartbeat-tick.sh for full rationale.
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# iter-40 layout: this test file lives in plugins/devops-tools/hooks/tests/
# (moved from hooks/ so the plugin validator's `plugins/*/hooks/*.{sh,...}`
# glob does NOT misclassify it as a Claude Code hook). The hook under
# test is one directory up at plugins/devops-tools/hooks/.
HOOK_UNDER_TEST="$SCRIPT_DIR/../posttooluse-1password-pattern-reminder.sh"

if [ ! -x "$HOOK_UNDER_TEST" ]; then
  echo "FATAL: hook not executable: $HOOK_UNDER_TEST" >&2
  exit 1
fi

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Test harness: feed a tool_input.command payload, check whether the hook
# emitted a reminder block (exit-0 with `decision: "block"` in stdout) or
# stayed silent (exit-0 with empty stdout).
# ---------------------------------------------------------------------------

# Feed PAYLOAD as JSON via stdin; capture stdout. Hook always exits 0 (per
# cc-skills hook convention); the distinction between "fire" and "skip" is
# whether stdout contains a `decision` field.
hook_emits_reminder() {
  local command_to_test="$1"
  local payload
  payload=$(jq -n --arg cmd "$command_to_test" '{tool_input: {command: $cmd}}')
  local hook_stdout
  hook_stdout=$(printf '%s' "$payload" | "$HOOK_UNDER_TEST" 2>/dev/null || true)
  if echo "$hook_stdout" | grep -q '"decision"'; then
    return 0  # reminder emitted
  else
    return 1  # silent (no reminder)
  fi
}

assert_emits_reminder() {
  local desc="$1"
  local command_to_test="$2"
  if hook_emits_reminder "$command_to_test"; then
    echo "  ✓ PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ FAIL: $desc (expected reminder, got silence)"
    echo "    command: $command_to_test"
    FAIL=$((FAIL+1))
  fi
}

assert_silent() {
  local desc="$1"
  local command_to_test="$2"
  if ! hook_emits_reminder "$command_to_test"; then
    echo "  ✓ PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ FAIL: $desc (expected silence, got reminder)"
    echo "    command: $command_to_test"
    FAIL=$((FAIL+1))
  fi
}

# ---------------------------------------------------------------------------
# INVARIANT A: True positives — hook MUST fire when op is the leading
# executable (the documented cc-skills credential-pattern violations)
# ---------------------------------------------------------------------------
echo "=== INVARIANT A: hook fires on true-positive bare op invocations ==="

assert_emits_reminder \
  "bare op read invocation (most common 1P call)" \
  'op read "op://Engineering/SomeItem/credential"'

assert_emits_reminder \
  "bare op item get invocation" \
  'op item get "MyItem" --vault Engineering'

assert_emits_reminder \
  "op with absolute path doesn't matter — first token is still op" \
  'op vault list'

# ---------------------------------------------------------------------------
# INVARIANT B: True negatives via canonical-pattern skip rules
# (op IS the leading executable but the command already follows the
# documented SA-token or biometric-fallback pattern)
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT B: hook skips canonical-pattern invocations ==="

assert_silent \
  "SA-token env-var prefix is the documented canonical pattern" \
  'OP_SERVICE_ACCOUNT_TOKEN=secret op item get foo --vault "Claude Automation"'

assert_silent \
  "version meta-command — no SA reminder needed" \
  'op --version'

assert_silent \
  "help meta-command" \
  'op --help'

assert_silent \
  "signin meta-command (interactive auth, no SA needed)" \
  'op signin'

assert_silent \
  "account list meta-command (read-only enumeration)" \
  'op account list'

assert_silent \
  "biometric-fallback pattern (unset SA, then op) — explicitly documented" \
  'unset OP_SERVICE_ACCOUNT_TOKEN; op item get foo'

# ---------------------------------------------------------------------------
# INVARIANT C: FALSE POSITIVES the iter-39 regex anchoring fixes
# (op appears in the command body but is NOT the leading executable —
# these are NOT op invocations at the shell level)
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT C: hook does NOT fire on op-in-string-literal false positives (iter-39 fix) ==="

# This is the EXACT shape that fired the false positive on iter-37 + iter-38
# commits. The git command builds its commit message via a heredoc, and the
# heredoc body contains documentation that references `op read`. Pre-iter-39
# the hook keyword-matched `op` in the heredoc body and fired spuriously.
#
# shellcheck disable=SC2016
# The single-quoted string is INTENTIONAL: this is a literal command-payload
# fixture being fed to the test harness, NOT a command for the shell to
# execute. The $(cat <<EOF...) is part of the fixture data, not expandable
# shell syntax. SC2016 ("Expressions don't expand in single quotes") is a
# false positive in this test-fixture context.
assert_silent \
  "git commit with heredoc body referencing op read in documentation" \
  'git commit -m "$(cat <<EOF
docs(devops): use op read --vault Engineering to fetch credentials
EOF
)"'

assert_silent \
  "echo string mentioning op as documentation" \
  'echo "use op read to access 1Password"'

assert_silent \
  "grep for op-related lines in a file (op is search term, not command)" \
  'grep -E "^op " /var/log/credential.log'

assert_silent \
  "comment-line in shell script (full command is a comment)" \
  '# Use op read for credential fetch'

assert_silent \
  "ripgrep with op as the pattern" \
  'rg --type bash "op read" plugins/'

assert_silent \
  "cat-ing a file that happens to contain the literal word op" \
  'cat 1password-credential-registry.md  # mentions op read everywhere'

# ---------------------------------------------------------------------------
# INVARIANT D: Word-boundary preserved — op-prefixed words still excluded
# (these existed pre-iter-39 and must still pass)
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT D: hook does NOT match op-prefixed words (open, optical, etc.) ==="

assert_silent \
  "open command (starts with op letters but full word is open)" \
  'open ~/Documents/notes.md'

assert_silent \
  "optical-disk command (starts with op letters)" \
  'optical-disk-stats /dev/disk2'

assert_silent \
  "stop service (contains op but not at start)" \
  'sudo service nginx stop'

assert_silent \
  "loop command (contains op but not at start)" \
  '/loop check the deploy'

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
