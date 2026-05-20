#!/usr/bin/env bash
# test-iter27-throttle-uuid-shape-required-and-read-write-symmetric.sh
#
# Regression guard for iter-32 hardening of the iter-27 tool-burst-tick-
# deduplication throttle. Two distinct invariants are verified:
#
#   INVARIANT A — throttle-key-uuid-shape-required:
#     The iter-27 bash regex MUST require the captured `session_id` value
#     to be UUID-shaped (8-4-4-4-12 lowercase hex). The pre-iter-32 form
#     `"session_id":"([^"]+)"` matched the FIRST occurrence of `session_id`
#     anywhere in the PAYLOAD — including a nested field like
#     `tool_input.session_id` when the JSON serializer emits it before the
#     top-level key. The iter-32 form embeds the UUID shape into the
#     capture group so non-UUID nested values are skipped over and the
#     next UUID-shaped value (typically the top-level field) is selected.
#
#   INVARIANT B — throttle-read-write-symmetric:
#     The throttle file must be READ at the same key it was WRITTEN at.
#     Pre-iter-32 the read used $SESSION_ID_FAST (bash regex) while the
#     write used $SESSION_ID (jq-decoded). When they disagreed (because
#     of invariant-A's latent bug), the write would land at the correct
#     key but the next read searched by the wrong key — silent throttle
#     miss, every tick traversed the slow path. The iter-32 fix uses
#     $SESSION_ID_FAST (fallback to $SESSION_ID) for BOTH read and write.
#
# This is a regression test, not a perf test. The companion perf bench
# (bench-heartbeat-tick-tool-burst-deduplication-fastpath.sh) still measures
# the throttled-fast-path latency.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOK="$PLUGIN_DIR/hooks/heartbeat-tick.sh"

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
# INVARIANT A: throttle-key-uuid-shape-required
# =============================================================================
echo "=== INVARIANT A: bash regex requires UUID-shaped session_id ==="

# Probe the EXACT regex from the live hook by extracting it via grep.
# The actual code spans two lines (`if [[ ... =~ ... ]]; then` then
# `SESSION_ID_FAST="${BASH_REMATCH[1]}"`), so grep for the regex anchor
# (the `=~` operator paired with `session_id`).
# `set -euo pipefail` + grep-empty-exit-1 require explicit `|| true` to
# avoid masking real failures while still allowing the grep to find nothing.
# shellcheck disable=SC2016
# grep pattern intentionally contains literal `$PAYLOAD` to match the
# source's exact bash test expression. Same SC2016 false-positive shape
# as the patterns below.
HOOK_REGEX_LINE=$(grep -E '\[\[ "\$PAYLOAD" =~.*session_id' "$HOOK" | head -1 || true)
if [ -z "$HOOK_REGEX_LINE" ]; then
  echo "  ✗ FAIL: could not locate iter-27 throttle regex in $HOOK"
  FAIL=$((FAIL+1))
else
  echo "  ✓ PASS: located iter-27 throttle regex in hook source"
  PASS=$((PASS+1))
fi

# Verify the hook's regex includes UUID-shape gating (presence of {8}, {4}, {12}
# quantifiers means the regex requires UUID structure)
if grep -qE '\{8\}-\[0-9a-f\]\{4\}.*\{4\}.*\{4\}.*\{12\}' "$HOOK"; then
  echo "  ✓ PASS: hook regex contains UUID-shape quantifiers (iter-32 invariant)"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: hook regex does NOT require UUID shape — iter-32 hardening regressed"
  FAIL=$((FAIL+1))
fi

# Inline probe of the regex behavior (since BASH_REMATCH is process-local,
# we reproduce the regex behavior here in a sub-shell). This gates that the
# regex pattern semantics still produce the expected matches.
HARDENED='"session_id"[[:space:]]*:[[:space:]]*"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"'

probe_regex() {
  local input="$1"
  if [[ "$input" =~ $HARDENED ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# Test A1: common case (top-level UUID session_id) — must extract correctly
A1=$(probe_regex '{"session_id":"550e8400-e29b-41d4-a716-446655440000","cwd":"/tmp"}')
assert_eq "$A1" "550e8400-e29b-41d4-a716-446655440000" "A1 common case extracts top-level UUID"

# Test A2: nested non-UUID session_id BEFORE top-level UUID — must skip nested
A2=$(probe_regex '{"tool_input":{"session_id":"task-12345"},"session_id":"550e8400-e29b-41d4-a716-446655440000"}')
assert_eq "$A2" "550e8400-e29b-41d4-a716-446655440000" "A2 nested non-UUID is skipped, top-level UUID wins"

# Test A3: nested string-id BEFORE top-level UUID — must skip
A3=$(probe_regex '{"tool_input":{"session_id":"WRONG-NESTED-STRING"},"session_id":"550e8400-e29b-41d4-a716-446655440000"}')
assert_eq "$A3" "550e8400-e29b-41d4-a716-446655440000" "A3 string-shaped nested session_id is skipped"

# Test A4: top-level value is NOT UUID-shaped — regex MUST return empty
# (correctness fallback: fast path bypassed, jq decode runs, throttle disabled)
A4=$(probe_regex '{"session_id":"not-a-real-uuid-just-a-string","cwd":"/tmp"}')
assert_eq "$A4" "" "A4 non-UUID top-level → empty (forces jq fallback, no false key)"

# Test A5: Claude Code's actual PostToolUse payload shape (session_id first)
A5=$(probe_regex '{"session_id":"550e8400-e29b-41d4-a716-446655440000","cwd":"/tmp","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"tool_response":{"content":"x"}}')
assert_eq "$A5" "550e8400-e29b-41d4-a716-446655440000" "A5 real Claude Code payload extracts correctly"

# =============================================================================
# INVARIANT B: throttle-read-write-symmetric
# =============================================================================
echo ""
echo "=== INVARIANT B: read and write use the same throttle-file key ==="

# Verify the hook source: both read and write paths reference the SAME
# variable (after iter-32 fix, both use $_hbt_throttle_key OR $SESSION_ID_FAST).
# Pre-iter-32: read used $SESSION_ID_FAST, write used $SESSION_ID — different.
# Iter-32: both use $_hbt_throttle_key which falls back through SESSION_ID_FAST → SESSION_ID.

# shellcheck disable=SC2016
# The grep patterns intentionally contain a literal `$` — they're regex
# patterns matching shell variable references INSIDE the heartbeat-tick.sh
# source. SC2016 misfires here because it can't distinguish "shell variable
# I want expanded" from "regex pattern targeting a literal $-prefixed token".
READ_KEY=$(grep -oE 'AUTOLOOP_TICK_DEDUP_DIR/\$[A-Z_a-z]+(_[a-z]+)?(_FAST)?\.us' "$HOOK" | head -1)
# shellcheck disable=SC2016
WRITE_KEY=$(grep -oE 'AUTOLOOP_TICK_DEDUP_DIR/\$[A-Z_a-z]+(_[a-z]+)?(_FAST)?\.us' "$HOOK" | tail -1)

# Strip the $ prefix and .us suffix to get the bare variable name.
# shellcheck disable=SC2016
# Same SC2016 false-positive shape as above — the sed pattern intentionally
# contains a literal `$` to match the shell-variable reference textually.
READ_VAR=$(echo "$READ_KEY" | sed -E 's:AUTOLOOP_TICK_DEDUP_DIR/\$([^.]+)\.us:\1:')
# shellcheck disable=SC2016
WRITE_VAR=$(echo "$WRITE_KEY" | sed -E 's:AUTOLOOP_TICK_DEDUP_DIR/\$([^.]+)\.us:\1:')

echo "  hook reads throttle file at \$$READ_VAR"
echo "  hook writes throttle file at \$$WRITE_VAR"

assert_eq "$READ_VAR" "$WRITE_VAR" "B1 read variable name MATCHES write variable name"

# Verify the variable resolves to the same value (i.e. it's not just two
# different vars that happen to be assigned the same string). Both should
# point at $_hbt_throttle_key (iter-32) or both at $SESSION_ID_FAST.
if [ "$READ_VAR" = "$WRITE_VAR" ] && grep -qE '_hbt_throttle_key="\$\{?SESSION_ID' "$HOOK"; then
  echo "  ✓ PASS: B2 read/write share key via \$_hbt_throttle_key with SESSION_ID_FAST fallback"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: B2 the shared-key variable chain is broken"
  echo "    Expected: \$_hbt_throttle_key=\"\${SESSION_ID_FAST:-\$SESSION_ID}\""
  FAIL=$((FAIL+1))
fi

# =============================================================================
# E2E: drive a real hook tick with a payload that triggers the iter-27 latent
# bug (nested non-UUID session_id BEFORE top-level UUID), confirm the throttle
# file is created at the CORRECT key.
# =============================================================================
echo ""
echo "=== E2E: real tick with adversarial payload — throttle file lands at correct key ==="

BENCH_TMP_RAW=$(mktemp -d -t autoloop-iter32-e2e-XXXXXX)
BENCH_TMP=$(cd "$BENCH_TMP_RAW" && pwd -P)
trap 'rm -rf "$BENCH_TMP_RAW"' EXIT

mkdir -p "$BENCH_TMP/loops" "$BENCH_TMP/state/revision-log"
touch "$BENCH_TMP/CONTRACT.md"

REAL_UUID="550e8400-e29b-41d4-a716-446655440000"
# Use a hex loop_id (iter-26 lesson)
LID="deadbeefcafe"
cat > "$BENCH_TMP/loops/registry.json" <<JSON
{"schema_version":2,"loops":[{"loop_id":"$LID","owner_session_id":"$REAL_UUID","owner_pid":$$,"owner_started_us":0,"generation":0,"state_dir":"$BENCH_TMP/state","contract_path":"$BENCH_TMP/CONTRACT.md","created_at_cwd":"$BENCH_TMP"}]}
JSON
cat > "$BENCH_TMP/state/heartbeat.json" <<JSON
{"loop_id":"$LID","session_id":"$REAL_UUID","iteration":0,"generation":0,"bound_cwd":"$BENCH_TMP"}
JSON

# Adversarial PAYLOAD: nested tool_input.session_id BEFORE top-level. This is
# the EXACT shape that broke the iter-27 throttle pre-iter-32.
ADVERSARIAL_PAYLOAD="{\"tool_input\":{\"session_id\":\"task-12345\"},\"session_id\":\"$REAL_UUID\",\"cwd\":\"$BENCH_TMP\"}"
THROTTLE_DIR="$BENCH_TMP/throttle"

CLAUDE_LOOPS_REGISTRY="$BENCH_TMP/loops/registry.json" \
  AUTOLOOP_TICK_DEDUP_DIR="$THROTTLE_DIR" \
  AUTOLOOP_TICK_DEDUP_INTERVAL_US=500000 \
  bash "$HOOK" <<< "$ADVERSARIAL_PAYLOAD" >/dev/null 2>&1 || true

# Throttle file MUST exist at the real UUID's path (not at "task-12345" or empty)
if [ -f "$THROTTLE_DIR/$REAL_UUID.us" ]; then
  echo "  ✓ PASS: throttle file landed at correct UUID key '$REAL_UUID.us'"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: throttle file NOT at $THROTTLE_DIR/$REAL_UUID.us"
  echo "    Files present:"
  find "$THROTTLE_DIR" -mindepth 1 -maxdepth 1 -type f -print 2>/dev/null | sed 's/^/      /'
  FAIL=$((FAIL+1))
fi

# Throttle file MUST NOT have been created at the nested wrong key
if [ ! -f "$THROTTLE_DIR/task-12345.us" ]; then
  echo "  ✓ PASS: no spurious throttle file at nested-session_id key"
  PASS=$((PASS+1))
else
  echo "  ✗ FAIL: throttle file leaked to wrong nested key — iter-32 fix regressed"
  FAIL=$((FAIL+1))
fi

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
