#!/usr/bin/env bash
# PROCESS-STORM-OK: Intentional single spawn under heavy safeguards (pitfall #6 defense: re-verify in lock, rate-limit via last_spawn_us)
# waker.sh — Launchd-invoked waker that decides whether to spawn/notify/do-nothing
# Directly invoked with <loop_id> argument. Implements decision tree per phase 9 context.
# Sources: registry-lib.sh, ownership-lib.sh, state-lib.sh, notifications-lib.sh

set -euo pipefail

# Error trap: log and exit 0 (never block launchd)
trap 'echo "ERROR at line $LINENO: waker.sh failed" >&2; exit 0' ERR

# Get the script directory for sourcing libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
# shellcheck source=/dev/null
source "$SCRIPT_DIR/registry-lib.sh" || { echo "ERROR: failed to source registry-lib.sh" >&2; exit 0; }
# shellcheck source=/dev/null
source "$SCRIPT_DIR/ownership-lib.sh" || { echo "ERROR: failed to source ownership-lib.sh" >&2; exit 0; }
# shellcheck source=/dev/null
source "$SCRIPT_DIR/state-lib.sh" || { echo "ERROR: failed to source state-lib.sh" >&2; exit 0; }
# shellcheck source=/dev/null
source "$SCRIPT_DIR/notifications-lib.sh" || { echo "ERROR: failed to source notifications-lib.sh" >&2; exit 0; }

# Provenance is best-effort; missing lib is non-fatal (Phase 35 introduced it)
if [ -f "$SCRIPT_DIR/provenance-lib.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/provenance-lib.sh" 2>/dev/null || true
fi
export _PROV_AGENT="waker.sh"

# WAKE-04 (v4.10.0 Phase 37): Five-check pre-spawn invariant.
# Every spawn refusal emits a typed provenance event AND a notification.
# Returns 0 if all invariants pass (caller may proceed with spawn);
# returns 1 if any invariant fails (caller MUST NOT spawn).
_invariant_check_spawn() {
  local loop_id="$1" entry="$2" session_id="$3" expected_cadence="$4"

  # (a) UUID validity — refuses pending-bind, unknown, empty, etc.
  if ! [[ "$session_id" =~ ^[0-9a-f-]{36}$ ]]; then
    if command -v emit_provenance >/dev/null 2>&1; then
      emit_provenance "$loop_id" "spawn_refused_invalid_session_id" \
        session_id="$session_id" \
        reason="session_id '$session_id' is not a UUID; binding incomplete" \
        decision="refused" 2>/dev/null || true
    fi
    emit_notification "$loop_id" "spawn_refused" "spawn refused: invalid session_id '$session_id'" \
      session_id="$session_id" 2>/dev/null || true
    return 1
  fi

  local state_dir contract_path
  state_dir=$(echo "$entry" | jq -r '.state_dir // ""' 2>/dev/null)
  contract_path=$(echo "$entry" | jq -r '.contract_path // ""' 2>/dev/null)
  state_dir="${state_dir%/}"

  # (b) Heartbeat-from-cwd — proof of life from inside the contract dir.
  local hb_file="$state_dir/heartbeat.json"
  if [ ! -f "$hb_file" ]; then
    if command -v emit_provenance >/dev/null 2>&1; then
      emit_provenance "$loop_id" "spawn_refused_no_heartbeat" \
        session_id="$session_id" \
        reason="no heartbeat.json at $hb_file; loop has not yet ticked from inside contract dir" \
        decision="refused" 2>/dev/null || true
    fi
    emit_notification "$loop_id" "spawn_refused" "spawn refused: no heartbeat" 2>/dev/null || true
    return 1
  fi

  # (c) bound_cwd matches contract_dir
  local bound_cwd contract_dir
  bound_cwd=$(jq -r '.bound_cwd // ""' "$hb_file" 2>/dev/null)
  contract_dir=$(dirname "$contract_path")
  if [ -z "$bound_cwd" ]; then
    if command -v emit_provenance >/dev/null 2>&1; then
      emit_provenance "$loop_id" "spawn_refused_no_bound_cwd" \
        session_id="$session_id" \
        reason="heartbeat has no bound_cwd; binding incomplete" \
        decision="refused" 2>/dev/null || true
    fi
    return 1
  fi
  if [ "$bound_cwd" != "$contract_dir" ]; then
    if command -v emit_provenance >/dev/null 2>&1; then
      emit_provenance "$loop_id" "spawn_refused_cwd_drift" \
        session_id="$session_id" \
        cwd_bound="$bound_cwd" \
        reason="bound_cwd '$bound_cwd' != contract_dir '$contract_dir'; cwd drift detected" \
        decision="refused" 2>/dev/null || true
    fi
    emit_notification "$loop_id" "spawn_refused" "spawn refused: cwd drift" \
      bound_cwd="$bound_cwd" contract_dir="$contract_dir" 2>/dev/null || true
    return 1
  fi
  local drift_flag
  drift_flag=$(jq -r '.cwd_drift_detected // false' "$hb_file" 2>/dev/null)
  if [ "$drift_flag" = "true" ]; then
    if command -v emit_provenance >/dev/null 2>&1; then
      emit_provenance "$loop_id" "spawn_refused_cwd_drift" \
        session_id="$session_id" \
        reason="heartbeat.cwd_drift_detected=true; resume disabled until reclaim" \
        decision="refused" 2>/dev/null || true
    fi
    return 1
  fi

  # (d) Launchd Label uniqueness — refuse if duplicate (collision).
  if command -v launchctl >/dev/null 2>&1; then
    local label
    label="com.user.claude.loop.$loop_id"
    local count
    count=$(launchctl list 2>/dev/null | awk -v lbl="$label" '$3 == lbl' | wc -l | tr -d ' ')
    if [ "${count:-0}" -ge 2 ]; then
      if command -v emit_provenance >/dev/null 2>&1; then
        emit_provenance "$loop_id" "spawn_refused_label_collision" \
          session_id="$session_id" \
          reason="launchctl shows $count entries for label $label; collision" \
          decision="refused" 2>/dev/null || true
      fi
      emit_notification "$loop_id" "spawn_refused" "spawn refused: launchd label collision ($count entries)" 2>/dev/null || true
      return 1
    fi
  fi

  # (e) Generation-drift detection — re-read registry; require generation
  # equals what we observed at invariant-check entry. (Concurrent reclaim
  # would have incremented it.)
  local current_gen entry_gen
  entry_gen=$(echo "$entry" | jq -r '.generation // 0' 2>/dev/null)
  local fresh_entry
  fresh_entry=$(read_registry_entry "$loop_id" 2>/dev/null) || fresh_entry="{}"
  current_gen=$(echo "$fresh_entry" | jq -r '.generation // 0' 2>/dev/null)
  if [ "$current_gen" != "$entry_gen" ]; then
    if command -v emit_provenance >/dev/null 2>&1; then
      emit_provenance "$loop_id" "spawn_refused_generation_drift" \
        session_id="$session_id" \
        reason="registry generation drifted from $entry_gen to $current_gen; concurrent reclaim" \
        decision="refused" 2>/dev/null || true
    fi
    return 1
  fi

  # All invariants pass.
  if command -v emit_provenance >/dev/null 2>&1; then
    emit_provenance "$loop_id" "spawn_invariants_passed" \
      session_id="$session_id" \
      cwd_bound="$bound_cwd" \
      registry_generation="$current_gen" \
      decision="proceeded" 2>/dev/null || true
  fi
  return 0
}

# expected_cadence parameter retained for future cadence-aware refusal logic
true

# Main waker function
main() {
  local loop_id="$1"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: waker.sh: invalid loop_id format '$loop_id'" >&2
    exit 0
  fi

  # Step 1: Read registry entry by loop_id
  local entry
  entry=$(read_registry_entry "$loop_id") || {
    echo "ERROR: waker.sh: failed to read registry entry for loop_id '$loop_id'" >&2
    exit 0
  }

  # If entry is missing, log and exit 0
  if [ "$entry" = "{}" ] || [ -z "$entry" ]; then
    echo "INFO: waker.sh: loop '$loop_id' unregistered, exiting"
    exit 0
  fi

  # Extract needed fields from entry
  local state_dir
  state_dir=$(echo "$entry" | jq -r '.state_dir // empty' 2>/dev/null) || state_dir=""
  if [ -z "$state_dir" ]; then
    echo "ERROR: waker.sh: no state_dir in entry for loop_id '$loop_id'" >&2
    exit 0
  fi

  local expected_cadence
  expected_cadence=$(echo "$entry" | jq -r '.expected_cadence_seconds // 1500' 2>/dev/null) || expected_cadence="1500"

  local owner_pid
  owner_pid=$(echo "$entry" | jq -r '.owner_pid // empty' 2>/dev/null) || owner_pid=""

  local owner_session_id
  owner_session_id=$(echo "$entry" | jq -r '.owner_session_id // empty' 2>/dev/null) || owner_session_id=""

  # Step 2: Verify owner alive
  local owner_status
  owner_status=$(verify_owner_alive "$loop_id") || owner_status="unknown"

  # Step 3: Compute heartbeat staleness
  local staleness
  staleness=$(staleness_seconds "$loop_id") || staleness="-1"

  # Step 4: Decision matrix
  if [ "$owner_status" = "alive" ]; then
    if [ "$staleness" -le $((3 * expected_cadence)) ]; then
      # Alive + fresh: do-nothing (logged)
      echo "INFO: waker.sh: loop '$loop_id' alive+fresh, no action needed"
      exit 0
    else
      # Alive + stale: owner alive but stuck. Emit "stuck" notification.
      echo "INFO: waker.sh: loop '$loop_id' alive+stale, emitting stuck notification"
      local msg="Owner alive but heartbeat stale (staleness: ${staleness}s, threshold: $((3 * expected_cadence))s)"
      emit_notification "$loop_id" "stuck" "$msg" \
        owner_pid="$owner_pid" \
        owner_session="$owner_session_id" \
        staleness_s="$staleness" \
        expected_cadence_s="$expected_cadence" || {
        echo "ERROR: waker.sh: failed to emit stuck notification" >&2
      }
      exit 0
    fi
  fi

  # owner_status is "dead"
  if [ "$staleness" -le $((3 * expected_cadence)) ]; then
    # Dead + fresh: anomaly. Emit "anomaly" notification, do NOT spawn.
    echo "INFO: waker.sh: loop '$loop_id' dead+fresh (anomaly), emitting notification"
    local msg="Owner dead but heartbeat fresh (anomaly: process gone, heartbeat recent)"
    emit_notification "$loop_id" "anomaly" "$msg" \
      owner_pid="$owner_pid" \
      owner_session="$owner_session_id" \
      staleness_s="$staleness" \
      expected_cadence_s="$expected_cadence" || {
      echo "ERROR: waker.sh: failed to emit anomaly notification" >&2
    }
    exit 0
  elif [ "$staleness" -le $((4 * expected_cadence)) ]; then
    # Dead + stale (between 3× and 4×): emit "pending_takeover". Wait for next tick.
    echo "INFO: waker.sh: loop '$loop_id' dead+stale (pending_takeover), emitting notification"
    local msg="Owner dead and heartbeat stale (between 3× and 4× cadence); pending takeover"
    emit_notification "$loop_id" "pending_takeover" "$msg" \
      owner_pid="$owner_pid" \
      owner_session="$owner_session_id" \
      staleness_s="$staleness" \
      expected_cadence_s="$expected_cadence" || {
      echo "ERROR: waker.sh: failed to emit pending_takeover notification" >&2
    }
    exit 0
  else
    # Dead + stale (>4×): safe to spawn
    echo "INFO: waker.sh: loop '$loop_id' dead+stale (>4×), attempting spawn"
    spawn_loop_safe "$loop_id" "$state_dir" "$owner_session_id" "$expected_cadence" "$owner_pid" || {
      echo "ERROR: waker.sh: spawn attempt failed" >&2
    }
    exit 0
  fi
}

# spawn_loop_safe <loop_id> <state_dir> <session_id> <expected_cadence> <old_owner_pid>
# Atomically spawn with re-verify inside lock to defend pitfall #6 (double-spawn race).
spawn_loop_safe() {
  local loop_id="$1"
  local state_dir="$2"
  local session_id="$3"
  local expected_cadence="$4"
  local old_owner_pid="$5"

  # Create temp file for spawn markers (used by spawn_impl_locked to request spawn)
  local temp_spawn_file
  temp_spawn_file=$(mktemp) || return 1
  export TEMP_SPAWN_FILE="$temp_spawn_file"
  trap 'rm -f "$temp_spawn_file"' RETURN

  # Get current timestamp
  local now_us
  now_us=$(now_us) || {
    echo "ERROR: spawn_loop_safe: failed to get current time" >&2
    return 1
  }

  # Check last_spawn_us BEFORE acquiring lock (quick check)
  local entry
  entry=$(read_registry_entry "$loop_id") || return 1
  local last_spawn_us
  last_spawn_us=$(echo "$entry" | jq -r '.last_spawn_us // 0' 2>/dev/null) || last_spawn_us="0"

  if [ "$last_spawn_us" != "0" ]; then
    local time_since_spawn=$((now_us - last_spawn_us))
    if [ "$time_since_spawn" -lt 60000000 ]; then  # 60 seconds in microseconds
      echo "INFO: spawn_loop_safe: spawn refused (last spawn ${time_since_spawn}us ago, need >60s)"
      emit_notification "$loop_id" "spawn" "Spawn rate-limited (last spawn <60s ago)" \
        staleness_s="$(((now_us - $(jq -r '.metadata.last_heartbeat_us // 0' <<< "$entry")) / 1000000))" \
        expected_cadence_s="$expected_cadence" || true
      return 0
    fi
  fi

  # Acquire registry lock and re-verify conditions inside lock (pitfall #6 defense)
  _with_registry_lock spawn_impl_locked "$loop_id" "$state_dir" "$session_id" "$expected_cadence" "$old_owner_pid" "$now_us" || {
    echo "ERROR: spawn_loop_safe: lock or spawn implementation failed" >&2
    return 1
  }

  # After lock released, process any spawn requests recorded in temp file
  if [ -f "$temp_spawn_file" ] && [ -s "$temp_spawn_file" ]; then
    while IFS='|' read -r req_session_id req_state_dir req_loop_id req_now_us; do
      spawn_claude_resume "$req_session_id" "$req_state_dir" "$req_loop_id" "$req_now_us" || {
        echo "ERROR: spawn_loop_safe: post-lock spawn failed" >&2
      }
    done < "$temp_spawn_file"
  fi
}

# spawn_impl_locked <loop_id> <state_dir> <session_id> <expected_cadence> <old_owner_pid> <now_us>
# Implementation function passed to _with_registry_lock.
# Reads stdin (current registry), re-verifies conditions, performs spawn if safe, outputs new registry.
# shellcheck disable=SC2329 # Function invoked indirectly via _with_registry_lock
spawn_impl_locked() {
  local loop_id="$1"
  local state_dir="$2"
  local session_id="$3"
  local expected_cadence="$4"
  local old_owner_pid="$5"
  local now_us="$6"

  # Parse stdin as registry
  local registry
  registry=$(cat)

  # Re-read entry inside lock
  local entry
  entry=$(echo "$registry" | jq ".loops[] | select(.loop_id == \"$loop_id\")" 2>/dev/null) || return 1

  # Re-verify alive/stale conditions (pitfall #6: owner might have come back alive)
  local owner_status
  owner_status=$(echo "$entry" | jq -r '.owner_pid // "unknown"' 2>/dev/null) || owner_status="unknown"

  # Quick check: is owner alive?
  if kill -0 "$owner_status" 2>/dev/null && [ "$owner_status" != "unknown" ]; then
    # Owner came back alive! Abort spawn.
    echo "INFO: spawn_impl_locked: owner came back alive during lock hold, aborting spawn" >&2
    echo "$registry"
    return 0
  fi

  # Re-check staleness inside lock
  local hb_file="$state_dir/heartbeat.json"
  if [ -f "$hb_file" ]; then
    local last_wake_us
    last_wake_us=$(jq -r '.last_wake_us // 0' "$hb_file" 2>/dev/null) || last_wake_us="0"

    local staleness_check=$((now_us - last_wake_us))
    if [ "$staleness_check" -lt $((4 * expected_cadence * 1000000)) ]; then
      # Staleness changed (became fresher) during lock hold, abort spawn
      echo "INFO: spawn_impl_locked: heartbeat became fresher during lock hold, aborting spawn" >&2
      echo "$registry"
      return 0
    fi
  fi

  # Safe to spawn: update last_spawn_us in registry
  local updated_registry
  updated_registry=$(echo "$registry" | jq "(.loops[] | select(.loop_id == \"$loop_id\") | .last_spawn_us) |= \"$now_us\"" 2>/dev/null) || {
    return 1
  }

  # Write the updated registry to stdout (captured by _with_registry_lock for atomic commit)
  echo "$updated_registry"

  # Write spawn markers to file for post-lock handling (to avoid stdout pollution)
  echo "$session_id|$state_dir|$loop_id|$now_us" >> "$TEMP_SPAWN_FILE" 2>/dev/null || true
}

# spawn_claude_resume <session_id> <state_dir> <loop_id> <now_us>
# Spawns: nohup claude --resume <session_id> >> state_dir/spawn.log 2>&1 &
# shellcheck disable=SC2329 # Function invoked indirectly via spawn_impl_locked
spawn_claude_resume() {
  local session_id="$1"
  local state_dir="$2"
  local loop_id="$3"
  local now_us="$4"

  # WAKE-04 (v4.10.0 Phase 37): Five-check invariant gate. If any invariant
  # fails, refuse the spawn. Refusals already emitted typed provenance +
  # notification inside the helper; we just bail.
  local entry
  entry=$(read_registry_entry "$loop_id" 2>/dev/null) || entry="{}"
  if ! _invariant_check_spawn "$loop_id" "$entry" "$session_id" "0"; then
    return 0
  fi

  # WAKE-02: cd to dirname(contract_path), NOT dirname(state_dir).
  # state_dir often lives at project root (e.g. .loop-state/<id>/) while the
  # contract may be nested deeper (e.g. findings/.../FOO_LOOP_CONTRACT.md).
  # Resuming from the wrong cwd contaminates the JSONL with the wrong project.
  local contract_path cwd
  contract_path=$(echo "$entry" | jq -r '.contract_path // ""' 2>/dev/null)
  if [ -z "$contract_path" ]; then
    echo "ERROR: spawn_claude_resume: cannot read contract_path from registry" >&2
    return 1
  fi
  cwd=$(dirname "$contract_path") || {
    echo "ERROR: spawn_claude_resume: cannot determine cwd from contract_path" >&2
    return 1
  }

  cd "$cwd" || {
    echo "ERROR: spawn_claude_resume: cannot cd to $cwd" >&2
    return 1
  }

  # nohup detaches the process from launchd's control
  nohup claude --resume "$session_id" >> "$state_dir/spawn.log" 2>&1 &
  local spawn_pid=$!

  echo "INFO: spawn_claude_resume: spawned claude --resume $session_id (PID: $spawn_pid)"

  # Append spawn event to revision-log
  local spawn_event
  spawn_event=$(jq -n \
    --arg ts_us "$now_us" \
    --arg event "spawn" \
    --arg session_id "$session_id" \
    --arg pid "$spawn_pid" \
    --arg cwd "$cwd" \
    --arg reason "dead+stale" \
    '{ts_us: $ts_us, event: $event, session_id: $session_id, spawned_pid: $pid, cwd: $cwd, reason: $reason}')

  mkdir -p "$state_dir/revision-log" || {
    echo "ERROR: spawn_claude_resume: failed to create revision-log directory" >&2
    return 1
  }

  echo "$spawn_event" >> "$state_dir/revision-log/spawn.jsonl" || {
    echo "ERROR: spawn_claude_resume: failed to append spawn event" >&2
    return 1
  }

  # Emit spawn notification
  local staleness_s
  staleness_s=$(staleness_seconds "$loop_id") || staleness_s="-1"
  emit_notification "$loop_id" "spawn" "Spawned claude --resume $session_id (PID: $spawn_pid)" \
    spawned_pid="$spawn_pid" \
    session_id="$session_id" \
    staleness_s="$staleness_s" || {
    echo "ERROR: spawn_claude_resume: failed to emit spawn notification" >&2
  }

  return 0
}

# Execute main with the loop_id argument — only when invoked directly, not
# when sourced (e.g. by tests that want access to _invariant_check_spawn).
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]:-}" ]; then
  if [ $# -lt 1 ]; then
    echo "ERROR: waker.sh: usage: waker.sh <loop_id>" >&2
    exit 0
  fi
  main "$1"
fi
