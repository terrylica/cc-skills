#!/usr/bin/env bash
# test-provenance.sh — Unit tests for provenance-lib.sh
# Verifies PROV-01..04: schema-versioned ledger with atomic dual-write,
# concurrent-write integrity, rotation, graceful degrade on missing state_dir,
# and schema validation.
# shellcheck disable=SC2329

set -euo pipefail

# ===== Test environment =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

TEMP_DIR=$(mktemp -d)
export HOME="$TEMP_DIR/home"
mkdir -p "$HOME/.claude/loops"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Override globals so the lib uses our isolated paths
export PROVENANCE_GLOBAL_DIR="$HOME/.claude/loops"
export PROVENANCE_GLOBAL_FILE="$PROVENANCE_GLOBAL_DIR/global-provenance.jsonl"

# Source after exports so the lib picks up our overrides
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/provenance-lib.sh" 2>/dev/null || {
  echo "FAIL: failed to source provenance-lib.sh" >&2
  exit 1
}

PASS=0
FAIL=0

assert_eq() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ✓ PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL: $name"
    echo "      expected: $expected"
    echo "      actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_truthy() {
  local condition="$1" name="$2"
  if [ "$condition" = "true" ]; then
    echo "  ✓ PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

reset_state() {
  rm -rf "$HOME/.claude/loops"
  mkdir -p "$HOME/.claude/loops"
}

# ===== Test 1: happy path =====
echo "Test 1: happy path — single emit writes to global mirror with valid schema"
reset_state
STATE_DIR1="$TEMP_DIR/loop1"
mkdir -p "$STATE_DIR1"
# Stub read_registry_entry so the lib can find state_dir
read_registry_entry() {
  if [ "$1" = "aaaaaaaaaaaa" ]; then
    jq -nc --arg sd "$STATE_DIR1" '{state_dir: $sd}'
  else
    echo "{}"
  fi
}

emit_provenance "aaaaaaaaaaaa" "bind_first" \
  session_id="abc-123-def" \
  cwd_observed="/tmp/foo" \
  reason="test happy path" \
  decision="proceeded"

GLOBAL_LINES=$(wc -l <"$PROVENANCE_GLOBAL_FILE" 2>/dev/null | tr -d ' ')
PERLOOP_LINES=$(wc -l <"$STATE_DIR1/provenance.jsonl" 2>/dev/null | tr -d ' ')
assert_eq "$GLOBAL_LINES" "1" "global mirror has 1 line"
assert_eq "$PERLOOP_LINES" "1" "per-loop ledger has 1 line"

LINE=$(head -1 "$PROVENANCE_GLOBAL_FILE")
HAS_FIELDS=$(echo "$LINE" | jq -r '
  has("ts_iso") and
  has("ts_us") and
  has("event") and
  has("loop_id") and
  has("agent") and
  has("session_id") and
  has("cwd_observed") and
  has("cwd_bound") and
  has("registry_generation") and
  has("owner_pid_before") and
  has("owner_pid_after") and
  has("reason") and
  has("decision") and
  has("schema_version")
' 2>/dev/null)
assert_eq "$HAS_FIELDS" "true" "all required fields present"
SCHEMA_V=$(echo "$LINE" | jq -r '.schema_version')
assert_eq "$SCHEMA_V" "1" "schema_version=1"
EVENT=$(echo "$LINE" | jq -r '.event')
assert_eq "$EVENT" "bind_first" "event=bind_first"
SID=$(echo "$LINE" | jq -r '.session_id')
assert_eq "$SID" "abc-123-def" "session_id round-trip"

# ===== Test 2: concurrent writes =====
echo ""
echo "Test 2: concurrent writes — 10 parallel processes, no torn lines, all 10 reasons present"
reset_state
STATE_DIR2="$TEMP_DIR/loop2"
mkdir -p "$STATE_DIR2"
read_registry_entry() {
  if [ "$1" = "bbbbbbbbbbbb" ]; then
    jq -nc --arg sd "$STATE_DIR2" '{state_dir: $sd}'
  else
    echo "{}"
  fi
}

# Spawn 10 background emits with unique reasons
for i in $(seq 1 10); do
  (
    # Re-source in subshell to ensure stub is picked up
    # shellcheck source=/dev/null
    source "$PLUGIN_DIR/scripts/provenance-lib.sh"
    read_registry_entry() {
      if [ "$1" = "bbbbbbbbbbbb" ]; then
        jq -nc --arg sd "$STATE_DIR2" '{state_dir: $sd}'
      else
        echo "{}"
      fi
    }
    emit_provenance "bbbbbbbbbbbb" "spawn_attempted" reason="parallel-$i"
  ) &
done
wait

GLOBAL_LINES=$(wc -l <"$PROVENANCE_GLOBAL_FILE" 2>/dev/null | tr -d ' ')
PERLOOP_LINES=$(wc -l <"$STATE_DIR2/provenance.jsonl" 2>/dev/null | tr -d ' ')
assert_eq "$GLOBAL_LINES" "10" "global mirror has 10 lines (no torn writes)"
assert_eq "$PERLOOP_LINES" "10" "per-loop ledger has 10 lines"

# Every line must parse as JSON
PARSE_OK="true"
while IFS= read -r line; do
  if ! echo "$line" | jq empty 2>/dev/null; then
    PARSE_OK="false"
    break
  fi
done <"$STATE_DIR2/provenance.jsonl"
assert_eq "$PARSE_OK" "true" "all 10 per-loop lines parse as JSON"

# Every reason value present exactly once
UNIQUE_REASONS=$(jq -r '.reason' "$STATE_DIR2/provenance.jsonl" | sort -u | wc -l | tr -d ' ')
assert_eq "$UNIQUE_REASONS" "10" "all 10 unique reason values present"

# ===== Test 3: rotation at 10k =====
echo ""
echo "Test 3: rotation — pre-populate 10001 lines, rotate, archive has 5001 lines, current has 5000"
reset_state
# Use small thresholds for fast test
export PROVENANCE_ROTATION_THRESHOLD=100
export PROVENANCE_ROTATION_KEEP=50
# Pre-populate 101 lines of valid JSON
for i in $(seq 1 101); do
  echo "{\"n\": $i, \"schema_version\": 1}"
done >"$PROVENANCE_GLOBAL_FILE"

rotate_global_provenance

CURRENT_LINES=$(wc -l <"$PROVENANCE_GLOBAL_FILE" 2>/dev/null | tr -d ' ')
assert_eq "$CURRENT_LINES" "50" "current global mirror has 50 lines after rotation (kept newest)"

ARCHIVE_GZ=$(find "$PROVENANCE_GLOBAL_DIR" -maxdepth 1 -name 'global-provenance.*.jsonl.gz' 2>/dev/null | head -1)
if [ -n "$ARCHIVE_GZ" ]; then
  ARCHIVE_LINES=$(gunzip -c "$ARCHIVE_GZ" | wc -l | tr -d ' ')
  assert_eq "$ARCHIVE_LINES" "51" "archive has 51 lines (oldest, gzipped)"
else
  echo "  ✗ FAIL: archive .gz file not created"
  FAIL=$((FAIL + 1))
fi

# Verify content split: archive should have lines 1..51, current 52..101
FIRST_ARCHIVED=$(gunzip -c "$ARCHIVE_GZ" | head -1 | jq -r '.n')
LAST_ARCHIVED=$(gunzip -c "$ARCHIVE_GZ" | tail -1 | jq -r '.n')
FIRST_CURRENT=$(head -1 "$PROVENANCE_GLOBAL_FILE" | jq -r '.n')
LAST_CURRENT=$(tail -1 "$PROVENANCE_GLOBAL_FILE" | jq -r '.n')
assert_eq "$FIRST_ARCHIVED" "1" "archive starts at line 1"
assert_eq "$LAST_ARCHIVED" "51" "archive ends at line 51"
assert_eq "$FIRST_CURRENT" "52" "current starts at line 52"
assert_eq "$LAST_CURRENT" "101" "current ends at line 101"

# Restore production thresholds for remaining tests
export PROVENANCE_ROTATION_THRESHOLD=10000
export PROVENANCE_ROTATION_KEEP=5000

# ===== Test 4: missing state_dir → graceful, global mirror still written =====
echo ""
echo "Test 4: missing state_dir — graceful degrade, only global mirror written"
reset_state
# Clean up state dirs from prior tests so we can detect a stray cleanly
rm -rf "$TEMP_DIR/loop1" "$TEMP_DIR/loop2" "$TEMP_DIR/loop4" 2>/dev/null
read_registry_entry() {
  echo "{}"  # registry has no entry for any loop_id
}

emit_provenance "cccccccccccc" "spawn_refused" reason="test missing state"

GLOBAL_LINES=$(wc -l <"$PROVENANCE_GLOBAL_FILE" 2>/dev/null | tr -d ' ')
assert_eq "$GLOBAL_LINES" "1" "global mirror has 1 line"

# No per-loop ledger should exist outside the .claude/loops mirror location
STRAY=$(find "$TEMP_DIR" -name "provenance.jsonl" -not -path "*/.claude/loops/*" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$STRAY" "0" "no stray per-loop provenance.jsonl created"

# ===== Test 5: schema validation =====
echo ""
echo "Test 5: schema validation — every emitted line passes schema check"
reset_state
read_registry_entry() {
  echo "{}"  # global-only mode
}

# Emit several events with varying field combinations
emit_provenance "dddddddddddd" "bind_first" session_id="uuid-1"
emit_provenance "dddddddddddd" "spawn_succeeded" \
  session_id="uuid-2" \
  cwd_observed="/a/b" \
  cwd_bound="/a/b" \
  registry_generation="3" \
  owner_pid_before="100" \
  owner_pid_after="200" \
  decision="proceeded"
emit_provenance "" "doctor_check" reason="orphan event with empty loop_id"

# Every line must:
#  - parse as JSON
#  - have schema_version = 1
#  - have all 14 required keys
ALL_VALID="true"
while IFS= read -r line; do
  IS_VALID=$(echo "$line" | jq -r '
    .schema_version == 1 and
    has("ts_iso") and has("ts_us") and has("event") and has("loop_id") and
    has("agent") and has("session_id") and has("cwd_observed") and
    has("cwd_bound") and has("registry_generation") and
    has("owner_pid_before") and has("owner_pid_after") and
    has("reason") and has("decision") and has("schema_version")
  ' 2>/dev/null) || IS_VALID="false"
  if [ "$IS_VALID" != "true" ]; then
    ALL_VALID="false"
    echo "    invalid line: $line"
    break
  fi
done <"$PROVENANCE_GLOBAL_FILE"
assert_eq "$ALL_VALID" "true" "all 3 emitted lines pass schema validation"

# Verify numeric fields are emitted as numbers, not strings
NUMERIC_OK=$(jq -r 'select(.event == "spawn_succeeded") | (.registry_generation == 3 and .owner_pid_before == 100 and .owner_pid_after == 200)' "$PROVENANCE_GLOBAL_FILE")
assert_eq "$NUMERIC_OK" "true" "numeric fields parsed as JSON numbers"

# Verify empty-string args become null
NULL_LOOP=$(jq -r 'select(.event == "doctor_check") | .loop_id' "$PROVENANCE_GLOBAL_FILE")
assert_eq "$NULL_LOOP" "null" "empty loop_id arg becomes JSON null"

# ===== Summary =====
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "All tests passed."
exit 0
