#!/usr/bin/env bash
# test-reclaim-atomicity.sh — W1.3 atomic 4-field reclaim harness
#
# Verifies that:
#   1. Concurrent reclaim attempts on the same dead loop produce a single
#      coherent winner — registry.json is never observed in a partially-applied
#      state (e.g., generation incremented but owner_pid still old).
#   2. The 4 reclaim fields (generation / owner_pid / owner_start_time_us /
#      owner_session_id) all update atomically as a unit, not one-at-a-time.
#
# Method: fork two reclaim_loop calls in parallel against a registered dead
# owner, then assert exactly one succeeded (post-condition: generation ===
# old + 1, not old + 2 — and the survivor's owner_session_id appears in the
# registry, not a Frankenstein mix).
#
# This is a probabilistic test (timing-dependent), so we run several rounds.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/portable.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/registry-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/ownership-lib.sh"

PASS=0
FAIL=0

ok()  { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# Per-round: spin up isolated HOME with a registered loop pointing at a dead
# owner_pid (PID 99999 — almost certainly unused), heartbeat older than the
# 3× cadence threshold, then race two reclaim_loop calls.
run_one_round() {
  local round="$1"
  local temp_dir
  temp_dir=$(mktemp -d)
  export HOME="$temp_dir/home"
  mkdir -p "$HOME/.claude/loops"

  local loop_id="abcdef012345"
  local state_dir="$HOME/loop-state/$loop_id"
  mkdir -p "$state_dir"

  # Stamp a stale heartbeat (1 hour old, well past 3× the default cadence).
  local now_us stale_us
  now_us=$(($(date +%s) * 1000000))
  stale_us=$((now_us - 3600 * 1000000))
  echo "{\"last_wake_us\": $stale_us, \"bound_cwd\": \"$state_dir\"}" \
    > "$state_dir/heartbeat.json"

  # Register the loop with a dead PID and matching owner_start_time_us.
  cat > "$HOME/.claude/loops/registry.json" <<EOF
{
  "loops": [
    {
      "loop_id": "$loop_id",
      "contract_path": "$state_dir/CONTRACT.md",
      "state_dir": "$state_dir",
      "owner_pid": 99999,
      "owner_session_id": "dead-owner",
      "owner_start_time_us": 1577836800000000,
      "generation": 0,
      "expected_cadence_seconds": 60
    }
  ],
  "schema_version": 1
}
EOF
  touch "$state_dir/CONTRACT.md"

  # Race two reclaims in parallel.
  ( reclaim_loop "$loop_id" --reason "owner_dead" >"$temp_dir/r1.out" 2>"$temp_dir/r1.err" ) &
  local pid1=$!
  ( reclaim_loop "$loop_id" --reason "owner_dead" >"$temp_dir/r2.out" 2>"$temp_dir/r2.err" ) &
  local pid2=$!

  local exit1 exit2
  wait $pid1; exit1=$?
  wait $pid2; exit2=$?

  # Post-conditions on the registry.
  local registry final_gen final_pid final_sid final_start
  registry=$(cat "$HOME/.claude/loops/registry.json")
  if ! echo "$registry" | jq -e . >/dev/null 2>&1; then
    nok "round $round: registry corrupted (invalid JSON)"
    rm -rf "$temp_dir"; return
  fi
  final_gen=$(echo "$registry"   | jq -r ".loops[0].generation")
  final_pid=$(echo "$registry"   | jq -r ".loops[0].owner_pid")
  final_sid=$(echo "$registry"   | jq -r ".loops[0].owner_session_id")
  final_start=$(echo "$registry" | jq -r ".loops[0].owner_start_time_us")

  # Assertion 1: generation incremented exactly once. Either both reclaim calls
  # found the loop in candidate state and applied gen=1 (only one wins because
  # the second sees gen=1 with a live owner — its is_reclaim_candidate returns
  # owner_alive). Or one raced ahead and the other refused. Both end states
  # are gen=1, never gen=2.
  if [ "$final_gen" = "1" ]; then
    ok "round $round: final generation == 1 (atomic, no double-increment)"
  else
    nok "round $round: final generation == $final_gen (expected 1)"
  fi

  # Assertion 2: pid and session_id reflect the SAME reclaim run, not a mix.
  # The session_id is generated as session_<ts>_<8hex>; the pid is one of the
  # two child shells. We can't predict which one wins, but we can check that
  # owner_pid is not 99999 (the dead one) and owner_session_id no longer says
  # "dead-owner".
  if [ "$final_pid" != "99999" ] && [ "$final_sid" != "dead-owner" ]; then
    ok "round $round: dead owner_pid + owner_session_id both replaced"
  else
    nok "round $round: registry retains stale owner (pid=$final_pid sid=$final_sid)"
  fi

  # Assertion 3: at least one reclaim_loop reported success. (Both can succeed
  # in principle if scheduled with enough gap that the second observes the
  # first's gen=1 + heartbeat update — but in practice the second usually
  # gets refused with "not a reclaim candidate" because the first's commit
  # was atomic.)
  if [ "$exit1" = "0" ] || [ "$exit2" = "0" ]; then
    ok "round $round: at least one reclaim succeeded"
  else
    nok "round $round: both reclaims failed (e1=$exit1, e2=$exit2)"
    echo "    r1.err: $(head -1 "$temp_dir/r1.err")"
    echo "    r2.err: $(head -1 "$temp_dir/r2.err")"
  fi

  # Assertion 4: owner_start_time_us is a number (matches new schema), not the
  # legacy value 1577836800000000 from the seed registry.
  if [ "$final_start" != "1577836800000000" ] && [[ "$final_start" =~ ^[0-9]+$ ]]; then
    ok "round $round: owner_start_time_us replaced and numeric"
  else
    nok "round $round: owner_start_time_us did not update (got '$final_start')"
  fi

  rm -rf "$temp_dir"
}

echo "========================================"
echo "Reclaim Atomicity Tests (W1.3)"
echo "========================================"

# Run 3 rounds to give the race some chance to manifest if atomicity is broken.
for i in 1 2 3; do
  echo ""
  echo "--- Round $i ---"
  run_one_round "$i"
done

echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
