#!/usr/bin/env bash
# test-launchd-plist-bash52-amp-backreference-safety.sh
#
# Regression guard for the iter-33 bash-5.2 ampersand-backreference fix.
#
# Bash 5.2+ added sed-style `&` backreference in `${VAR//PATTERN/REPLACEMENT}`:
# any `&` in the REPLACEMENT is reinterpreted as the matched PATTERN text.
# This silently broke two sites in launchd-lib.sh:
#
#   1. xmlescape() — `${str//</&lt;}` produced `<lt;` because the `&` in
#      `&lt;` got expanded to the matched `<`.
#
#   2. generate_plist() placeholder substitution — `${plist//STATE_DIR_PLACEHOLDER/$escaped}`
#      where $escaped contained `&` (from XML-escaped chars) produced
#      `pathSTATE_DIR_PLACEHOLDERamp;...` because the `&` was a backreference
#      to the matched `STATE_DIR_PLACEHOLDER` token.
#
# The bug was silent because:
#   (a) test-launchd-plist.sh Test 9 was masked by the `((VAR++))` gotcha
#       (iter-32 sweep uncovered it).
#   (b) the common path (no XML-special chars in state_dir) flows through
#       OK — only `&`, `<`, `>`, `"`, `'` in paths trigger the bug.
#
# This test pins three invariants:
#   A. xmlescape produces the expected RFC-compliant entities for each
#      reserved character — &lt;, &gt;, &amp;, &quot;, &apos;
#   B. generate_plist with special-character state_dir produces a plist
#      that passes `plutil -lint` (macOS only — Linux skip)
#   C. The fix in launchd-lib.sh is structurally present (text scan)
#
# Bash-version-conditional: the entire test class is meaningful on bash
# 5.2+ where the backreference is active. Older bash should also pass
# (the `\&` escape is a no-op there).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
LAUNCHD_LIB="$PLUGIN_DIR/scripts/launchd-lib.sh"

# shellcheck source=/dev/null
source "$LAUNCHD_LIB"

PASS=0
FAIL=0

assert_eq() {
  local actual="$1" expected="$2" desc="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ✓ PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ FAIL: $desc"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL+1))
  fi
}

# =============================================================================
# INVARIANT A: xmlescape produces RFC-compliant XML entities
# =============================================================================
echo "=== INVARIANT A: xmlescape produces RFC-compliant XML entities ==="
# Bash version banner. Extract major + minor as integers so we can compare
# numerically (-ge) rather than as strings. Bash 5.2.0 (sept 2022) is when
# the `&` backreference in pattern-substitution was introduced; earlier
# bash treats `&` as literal, so the test class is no-op-correct there.
_bash_major="${BASH_VERSION%%.*}"
_bash_rest="${BASH_VERSION#*.}"
_bash_minor="${_bash_rest%%.*}"
if [ "$_bash_major" -ge 5 ] && [ "$_bash_minor" -ge 2 ]; then
  _bash_backref_state="active"
else
  _bash_backref_state="inactive (predates bash 5.2 — test still valid as a no-op)"
fi
echo "  (bash $BASH_VERSION — &-backreference: $_bash_backref_state)"

assert_eq "$(xmlescape '<')"      "&lt;"   "lone < becomes &lt;"
assert_eq "$(xmlescape '>')"      "&gt;"   "lone > becomes &gt;"
assert_eq "$(xmlescape '&')"      "&amp;"  "lone & becomes &amp;"
# For the literal " character: use single-quotes around the dquote so the
# shell delivers a 1-char string (single dquote). Pre-iter-33 the test
# used '\"' which is the 2-char literal `\"` (backslash + dquote), so
# xmlescape only replaced the dquote and left the backslash → false fail.
assert_eq "$(xmlescape '"')"      "&quot;" "lone \" becomes &quot;"
assert_eq "$(xmlescape "'")"      "&apos;" "lone ' becomes &apos;"
# Combined: all five at once. Build the 5-char input via printf to avoid
# shell-quoting hazards around the mixed `\"`/`'`/`<`/`>`/`&` set.
ALL_FIVE=$(printf '<&>"%s' "'")
assert_eq "$(xmlescape "$ALL_FIVE")" "&lt;&amp;&gt;&quot;&apos;" "all-five-at-once preserves order + correct entities"

# Adversarial: text containing the literal substring "lt;" before a < character
# (pre-iter-33 bug would mangle this to "lt;lt;")
assert_eq "$(xmlescape 'a<b')"    "a&lt;b"  "no spurious 'lt;' from <-backreference"
assert_eq "$(xmlescape 'a&b')"    "a&amp;b" "no spurious 'amp;' from &-backreference"

# =============================================================================
# INVARIANT B: generate_plist with special chars in state_dir → valid plist
# =============================================================================
echo ""
echo "=== INVARIANT B: generate_plist with XML-special chars → valid plist ==="

if [ "$(uname -s)" != "Darwin" ]; then
  echo "  ⊘ SKIP: plutil -lint requires macOS (uname=$(uname))"
else
  TEST_TMP=$(mktemp -d -t bash52-amp-backref-XXXXXX)
  TEST_TMP=$(cd "$TEST_TMP" && pwd -P)
  trap 'rm -rf "$TEST_TMP"' EXIT

  # Worst-case input: all five XML-reserved chars in the path
  TEST_STATE='path&with<all>special"chars'"'"'.dir'
  TEST_STATE_DIR="$TEST_TMP/$TEST_STATE"
  mkdir -p "$TEST_STATE_DIR"
  STUB_WAKER="$TEST_STATE_DIR/waker.sh"
  echo '#!/bin/bash' > "$STUB_WAKER"
  chmod +x "$STUB_WAKER"

  if generate_plist 'beefcafedead' "$TEST_STATE_DIR" "$STUB_WAKER" '300' 2>/dev/null; then
    PLIST_FILE="$TEST_STATE_DIR/waker.plist"
    if [ -f "$PLIST_FILE" ]; then
      if plutil -lint "$PLIST_FILE" >/dev/null 2>&1; then
        echo "  ✓ PASS: plist with <&>\\\"' in state_dir passes plutil -lint"
        PASS=$((PASS+1))
      else
        echo "  ✗ FAIL: plutil -lint rejected the plist:"
        plutil -lint "$PLIST_FILE" 2>&1 | sed 's/^/      /'
        echo "    plist content (lines 5-15):"
        sed -n '5,15p' "$PLIST_FILE" | sed 's/^/      /'
        FAIL=$((FAIL+1))
      fi

      # Also verify the path is NOT mangled (e.g. literal STATE_DIR_PLACEHOLDER
      # surviving in the output is the iter-33 bug signature)
      if grep -q 'STATE_DIR_PLACEHOLDER\|RUNNER_PLACEHOLDER\|LABEL_PLACEHOLDER' "$PLIST_FILE"; then
        echo "  ✗ FAIL: placeholder token survived in plist output (iter-33 bug regressed)"
        FAIL=$((FAIL+1))
      else
        echo "  ✓ PASS: no placeholder tokens leaked into the rendered plist"
        PASS=$((PASS+1))
      fi
    else
      echo "  ✗ FAIL: generate_plist returned 0 but no plist file was created"
      FAIL=$((FAIL+1))
    fi
  else
    echo "  ✗ FAIL: generate_plist exited non-zero on special-char state_dir"
    FAIL=$((FAIL+1))
  fi
fi

# =============================================================================
# INVARIANT C: structural fix present in source
# =============================================================================
echo ""
echo "=== INVARIANT C: bash-5.2-amp-backref guard present in launchd-lib.sh ==="

# xmlescape function MUST use \& form (not bare &) for the < / > / " / ' cases.
# Counted by lines containing both `${str//` and `\&` together.
ESCAPED_AMP_COUNT=$(grep -cE '\$\{str//[^/]+/\\&' "$LAUNCHD_LIB" || true)
if [ "$ESCAPED_AMP_COUNT" -ge 4 ]; then
  echo "  ✓ PASS: xmlescape contains ≥4 \\& escape forms (< > \" ' all covered)"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: only $ESCAPED_AMP_COUNT of 4 expected \\& escape forms found"
  FAIL=$((FAIL+1))
fi

# generate_plist MUST escape & in the substitution values
ESCAPED_VAL_COUNT=$(grep -cE 'escaped_[a-z_]+="\$\{escaped_[a-z_]+//&/\\\\&\}"' "$LAUNCHD_LIB" || true)
if [ "$ESCAPED_VAL_COUNT" -ge 3 ]; then
  echo "  ✓ PASS: generate_plist post-processes ≥3 escaped paths with &→\\& (state_dir + runner_file + label)"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: only $ESCAPED_VAL_COUNT of 3 expected post-process &-escapes found"
  FAIL=$((FAIL+1))
fi

# =============================================================================
# INVARIANT D: iter-34 shopt -u patsub_replacement defense at hook entry points
# =============================================================================
echo ""
echo "=== INVARIANT D: shopt -u patsub_replacement at every hook entry point ==="
#
# Iter-34 added a global defense: every hook entry point (heartbeat-tick.sh,
# session-bind.sh, pacing-veto.sh, empty-firing-detector.sh, waker.sh) sets
# `shopt -u patsub_replacement 2>/dev/null || true` near the top of the
# file. This restores bash 5.1 substitution semantics for the entire hook
# process, preventing the same class of bug from recurring in FUTURE code
# added to any sourced library.
#
# This invariant guards against regression: if a maintainer ever deletes
# the shopt line "to clean up", the test fails before merge.

HOOK_ENTRY_POINTS=(
  "$PLUGIN_DIR/hooks/heartbeat-tick.sh"
  "$PLUGIN_DIR/hooks/session-bind.sh"
  "$PLUGIN_DIR/hooks/pacing-veto.sh"
  "$PLUGIN_DIR/hooks/empty-firing-detector.sh"
  "$PLUGIN_DIR/scripts/waker.sh"
)

for entry_point in "${HOOK_ENTRY_POINTS[@]}"; do
  if [ ! -f "$entry_point" ]; then
    echo "  ⚠ SKIP: $(basename "$entry_point") not found"
    continue
  fi
  if grep -qE '^shopt -u patsub_replacement' "$entry_point"; then
    echo "  ✓ PASS: $(basename "$entry_point") declares shopt -u patsub_replacement"
    PASS=$((PASS+1))
  else
    echo "  ✗ FAIL: $(basename "$entry_point") MISSING shopt -u patsub_replacement"
    echo "    Add this near the top of the file:"
    echo "      shopt -u patsub_replacement 2>/dev/null || true"
    FAIL=$((FAIL+1))
  fi
done

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
