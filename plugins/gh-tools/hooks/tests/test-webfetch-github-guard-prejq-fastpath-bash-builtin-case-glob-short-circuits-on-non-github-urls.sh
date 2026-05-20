#!/usr/bin/env bash
# test-webfetch-github-guard-prejq-fastpath-bash-builtin-case-glob-short-circuits-on-non-github-urls.sh
#
# Regression test for iter-55 pre-jq-fastpath optimization on
# webfetch-github-guard.sh. The optimization made two changes:
#
#   1. Dropped the TOOL_NAME jq parse + equality guard entirely. The
#      hook's matcher is `"WebFetch"` exactly (see hooks.json), so
#      TOOL_NAME is guaranteed to be "WebFetch" by the time we fire.
#      The pre-iter-55 jq spawn was dead-weight (~7-10ms per call).
#
#   2. Added a bash-builtin-case-glob substring check on the raw $INPUT
#      for "github.com" BEFORE spawning jq to extract the URL. ~99% of
#      WebFetch traffic doesn't target github.com, and the slow path's
#      URL regex would reject it anyway — this short-circuits BEFORE
#      paying jq cold start, saving another ~7-10ms.
#
# This test pins four invariants:
#
#   (A) STRUCTURAL: The fastpath EXISTS in the hook source. Specifically,
#       (A1) no jq invocations appear before the `case "$INPUT"` glob,
#       (A2) the dropped `TOOL_NAME` variable + WebFetch equality check
#            from pre-iter-55 are gone (otherwise iter-55 regressed),
#       (A3) the github.com case-glob pattern is present.
#
#   (B) BEHAVIORAL FAST PATH: A WebFetch payload targeting a non-github
#       URL exits 0 silently with no jq spawn, no permissionDecision
#       JSON, no soft-block reminder.
#
#   (C) BEHAVIORAL SLOW PATH (github URL): A WebFetch payload targeting
#       a github.com URL exits 0 AND emits the `permissionDecision: deny`
#       JSON with a gh-CLI suggestion (slow path still works).
#
#   (D) BEHAVIORAL FALSE-POSITIVE GRACEFUL DEFERRAL: A WebFetch payload
#       whose URL is non-github but whose prompt text mentions
#       "github.com" (so the case-glob matches) must still exit 0
#       silently — the slow path's URL regex correctly distinguishes
#       prompt text from the actual fetch target.
#
# Verbose filename per the user directive — encodes the exact optimization
# being tested ("prejq-fastpath-bash-builtin-case-glob-short-circuits-on-
# non-github-urls") so future maintainers searching for "pre-jq fastpath",
# "github guard", "case-glob webfetch", "TOOL_NAME dead-weight", etc.
# surface this regression guard.

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
# disable bash 5.2+ `&`-as-backreference. See
# plugins/autoloop/hooks/heartbeat-tick.sh for full rationale.
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_UNDER_TEST="$SCRIPT_DIR/../webfetch-github-guard.sh"

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
# INVARIANT A: source-code-level structural checks
# ---------------------------------------------------------------------------
echo "=== INVARIANT A: source structure — fastpath exists before jq, TOOL_NAME gone ==="

# A1: no `jq` invocation appears before the `case "$INPUT"` glob.
# We look for the first `| jq ` (pipeline) or `jq -` (direct) occurrence
# and the first `case "$INPUT"` occurrence in the source.
#
# IMPORTANT: strip comment lines BEFORE grepping. The iter-55 comment
# block documents the dropped pre-iter-55 `jq -r '.tool_name // ""'`
# pattern verbatim, which would otherwise trigger a false "first jq"
# match inside the documentation. We use `grep -v '^[[:space:]]*#'` to
# exclude shell comment lines while preserving line numbers via `-n`
# applied AFTER stripping (cat -n + post-filter would also work but is
# more brittle to line-number drift). Instead we use awk: print
# `NR:LINE` only for non-comment lines, then grep the jq pattern.
# shellcheck disable=SC2016
# SC2016 intentional: the awk and grep patterns use `$` as literal
# regex/awk syntax (`$0`, awk field; `\$INPUT`, regex matching literal
# `$INPUT` in shell source), NOT shell expansion. Single quotes must be
# preserved so the patterns reach awk/grep verbatim.
first_jq_line=$(awk 'NF && $0 !~ /^[[:space:]]*#/ { print NR":"$0 }' "$HOOK_UNDER_TEST" \
                  | grep -E '\| *jq |jq -[rn]' | head -1 | cut -d: -f1)
# shellcheck disable=SC2016
first_case_line=$(awk 'NF && $0 !~ /^[[:space:]]*#/ { print NR":"$0 }' "$HOOK_UNDER_TEST" \
                  | grep 'case "\$INPUT"' | head -1 | cut -d: -f1)

if [ -z "$first_case_line" ]; then
  assert_fail "no \`case \"\$INPUT\"\` fastpath glob found — iter-55 regressed"
elif [ -z "$first_jq_line" ]; then
  assert_pass "no jq invocations at all in the hook (degenerate but valid — fastpath trivially holds)"
elif [ "$first_case_line" -lt "$first_jq_line" ]; then
  assert_pass "case-glob at line $first_case_line is BEFORE first jq at line $first_jq_line"
else
  assert_fail "case-glob at line $first_case_line is AFTER first jq at line $first_jq_line — iter-55 fast-path regressed"
fi

# A2: the dropped pre-iter-55 TOOL_NAME jq parse must NOT be present.
# Match the SPECIFIC pre-iter-55 source line, not a comment that mentions it.
# Pre-iter-55: `TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' ...)`
# Use grep -E with a pattern that requires the assignment form, so docs/
# comments referencing "TOOL_NAME" in narrative prose don't trip it.
# shellcheck disable=SC2016
# SC2016 intentional: the grep pattern uses `$` as a REGEX literal (to
# match `TOOL_NAME=$(echo ...`), not a shell expansion. Single quotes
# are correct here — the pattern must pass to grep verbatim. Double
# quotes would require escaping every `$` and break readability.
if grep -qE '^[[:space:]]*TOOL_NAME=\$\(echo .* \| jq' "$HOOK_UNDER_TEST"; then
  assert_fail "TOOL_NAME jq parse is still present — iter-55 dead-weight removal regressed"
else
  assert_pass "TOOL_NAME jq parse + equality guard are gone (matcher already guarantees WebFetch)"
fi

# A3: github.com case-glob pattern is present.
if grep -q '\*github\.com\*' "$HOOK_UNDER_TEST"; then
  assert_pass "github.com case-glob pattern is present in the source"
else
  assert_fail "github.com case-glob pattern missing — iter-55 fastpath regressed"
fi

# ---------------------------------------------------------------------------
# INVARIANT B: behavioral fast path — non-github URL → silent exit 0
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT B: behavioral — non-github URL bails silently ==="

# Construct a WebFetch payload targeting a clearly-non-github URL.
non_github_payload=$(jq -n '{
  tool_name: "WebFetch",
  tool_input: {
    url: "https://huggingface.co/docs/transformers/index",
    prompt: "Extract the latest transformer architecture changes"
  }
}')

fastpath_output=$(printf '%s' "$non_github_payload" | "$HOOK_UNDER_TEST" 2>&1 || true)

if [ -z "$fastpath_output" ]; then
  assert_pass "non-github URL produced empty output (correct fast-path bail)"
else
  assert_fail "non-github URL produced unexpected output: $fastpath_output"
fi

# ---------------------------------------------------------------------------
# INVARIANT C: behavioral slow path — github URL → permissionDecision JSON
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT C: behavioral — github URL emits soft-block JSON ==="

github_payload=$(jq -n '{
  tool_name: "WebFetch",
  tool_input: {
    url: "https://github.com/terrylica/cc-skills/issues/42",
    prompt: "Read issue body"
  }
}')

slow_path_output=$(printf '%s' "$github_payload" | "$HOOK_UNDER_TEST" 2>&1 || true)

# Should be JSON with permissionDecision: deny
if echo "$slow_path_output" | jq -e '.permissionDecision == "deny"' >/dev/null 2>&1; then
  assert_pass "github URL slow path emits permissionDecision: deny JSON"
else
  assert_fail "github URL slow path did NOT emit expected JSON. Got: $slow_path_output"
fi

# Should contain a gh CLI suggestion in the reason
if echo "$slow_path_output" | jq -e '.reason | test("gh ")' >/dev/null 2>&1; then
  assert_pass "soft-block reason contains a gh CLI suggestion"
else
  assert_fail "soft-block reason missing gh CLI suggestion. Got: $slow_path_output"
fi

# ---------------------------------------------------------------------------
# INVARIANT D: false-positive graceful deferral — prompt mentions
# "github.com" but URL doesn't → slow path's URL regex must reject and
# the hook must exit 0 silently (no soft-block).
# ---------------------------------------------------------------------------
echo ""
echo "=== INVARIANT D: false-positive deferral — prompt mentions github but URL is elsewhere ==="

false_positive_payload=$(jq -n '{
  tool_name: "WebFetch",
  tool_input: {
    url: "https://huggingface.co/papers/2024.12345",
    prompt: "Compare this to the github.com/related-repo project structure"
  }
}')

false_positive_output=$(printf '%s' "$false_positive_payload" | "$HOOK_UNDER_TEST" 2>&1 || true)

if [ -z "$false_positive_output" ]; then
  assert_pass "false-positive case-glob match deferred to slow path which correctly rejected"
else
  assert_fail "false-positive payload triggered unexpected soft-block: $false_positive_output"
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
