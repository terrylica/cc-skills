#!/usr/bin/env bash
# test-display-name.sh — AL-naming convention harness (Wave 3)
#
# Verifies:
#   1. format_loop_display_name returns AL-<slug>--<hash> for v2 entries,
#      AL-<slug> when only slug present, AL-loop-<id6> for legacy.
#   2. resolve_loop_identifier accepts loop_id, AL-name forms, bare slug.
#   3. Ambiguity (multiple campaigns sharing slug) errors with candidate list.
#   4. Garbage input is rejected at the regex gate.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/portable.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/state-lib.sh"

PASS=0
FAIL=0

ok()  { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

assert_eq() {
  local desc="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then ok "$desc"
  else nok "$desc — expected '$expected', got '$actual'"
  fi
}

T=$(mktemp -d); export HOME="$T/home"
mkdir -p "$HOME/.claude/loops"
cat > "$HOME/.claude/loops/registry.json" <<'EOF'
{
  "loops": [
    {"loop_id":"3555bbe1f0fb","campaign_slug":"odb-research","short_hash":"a1b2c3","contract_path":"/x"},
    {"loop_id":"abcdef012345","campaign_slug":"flaky-ci-watcher","contract_path":"/y"},
    {"loop_id":"cafebabe1234","contract_path":"/z"},
    {"loop_id":"deadbeef9999","campaign_slug":"odb-research","short_hash":"d4e5f6","contract_path":"/w"}
  ],
  "schema_version": 1
}
EOF
trap '(cd /tmp && rm -rf "$T")' EXIT

echo "========================================"
echo "AL-Naming Convention Tests (Wave 3)"
echo "========================================"

echo ""
echo "[Group 1] format_loop_display_name"
assert_eq "v2 with slug+hash"     "$(format_loop_display_name 3555bbe1f0fb)" "AL-odb-research--a1b2c3"
assert_eq "v2 slug only"          "$(format_loop_display_name abcdef012345)" "AL-flaky-ci-watcher"
assert_eq "legacy fallback"       "$(format_loop_display_name cafebabe1234)" "AL-loop-cafeba"
# Invalid id returns nonzero with no output.
out=$(format_loop_display_name "BADBADBAD123" 2>/dev/null; echo "rc=$?")
if echo "$out" | grep -q "rc=1"; then ok "invalid loop_id rejected (rc=1)"; else nok "invalid loop_id not rejected"; fi
# Loop_id absent from registry returns AL-loop-<id6> fallback.
assert_eq "loop_id not in registry → fallback" \
  "$(format_loop_display_name 999999999999)" "AL-loop-999999"

echo ""
echo "[Group 2] resolve_loop_identifier — happy paths"
assert_eq "form 1 (loop_id)"             "$(resolve_loop_identifier 3555bbe1f0fb)"          "3555bbe1f0fb"
assert_eq "form 2 (AL-slug--hash)"       "$(resolve_loop_identifier AL-odb-research--a1b2c3)" "3555bbe1f0fb"
assert_eq "form 2 disambiguator works"   "$(resolve_loop_identifier AL-odb-research--d4e5f6)" "deadbeef9999"
assert_eq "form 3 (AL-slug, unique)"     "$(resolve_loop_identifier AL-flaky-ci-watcher)"   "abcdef012345"
assert_eq "form 4 (bare slug, unique)"   "$(resolve_loop_identifier flaky-ci-watcher)"      "abcdef012345"

# Sourcing registry-lib.sh inherits its `set -euo pipefail`, so a nonzero
# return from resolve_loop_identifier in `$(...)` would otherwise abort
# the script via -e. Disable -e for the error-path block so we can capture
# expected non-zero exits.
set +e

echo ""
echo "[Group 3] resolve_loop_identifier — error paths"
# Ambiguous slug → exit 2, error mentions candidate count
out=$(resolve_loop_identifier AL-odb-research 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$out" | grep -q "ambiguous slug"; then
  ok "ambiguous slug → exit 2 with candidate list"
else
  nok "ambiguous slug behavior wrong (rc=$rc, out=$out)"
fi

# No match → exit 1, no candidate list
out=$(resolve_loop_identifier AL-nonexistent 2>&1)
rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "no loop with campaign_slug"; then
  ok "no match → exit 1"
else
  nok "no match behavior wrong (rc=$rc)"
fi

# Garbage with shell metachars → exit 3
out=$(resolve_loop_identifier "BAD; echo pwned" 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$out" | grep -q "is not a valid"; then
  ok "shell-metachar garbage rejected at regex gate (rc=3)"
else
  nok "garbage input behavior wrong (rc=$rc)"
fi

# Stale loop_id (well-formed but not in registry) → exit 1
out=$(resolve_loop_identifier "999999999999" 2>&1)
rc=$?
if [ "$rc" = "1" ] && echo "$out" | grep -q "not in registry"; then
  ok "stale loop_id rejected (rc=1)"
else
  nok "stale loop_id behavior wrong (rc=$rc)"
fi

# Empty input → exit 3
out=$(resolve_loop_identifier "" 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$out" | grep -q "empty input"; then
  ok "empty input rejected (rc=3)"
else
  nok "empty input behavior wrong (rc=$rc)"
fi

set -e

echo ""
echo "[Group 4] Round-trip: every loop_id resolves through its display name"
while IFS= read -r lid; do
  [ -z "$lid" ] && continue
  display=$(format_loop_display_name "$lid")
  resolved=$(resolve_loop_identifier "$display" 2>/dev/null || true)
  if [ "$resolved" = "$lid" ]; then
    # Skip ambiguous duplicate-slug cases — they're tested separately above.
    [ "$display" = "AL-odb-research" ] || ok "round-trip: $display → $lid"
  else
    [ "$display" = "AL-odb-research" ] || nok "round-trip broke for $lid (display=$display, resolved=$resolved)"
  fi
done < <(jq -r '.loops[].loop_id' "$HOME/.claude/loops/registry.json")

echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
