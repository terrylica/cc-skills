#!/usr/bin/env bash
# FILE-SIZE-OK
# ownership-lib.sh — Per-loop ownership protocol with PID-reuse defense
# Provides: acquire_owner_lock, release_owner_lock, verify_owner_alive, capture_process_start_time
#           staleness_seconds, is_reclaim_candidate, reclaim_loop, append_takeover_event
#
# Pitfall #1 (PID reuse): Defense via owner_start_time_us comparison on verification
# Pitfall #2 (TOCTOU first-half): Defense via atomic flock acquire
# Pitfall #2 (TOCTOU second-half): Defense via generation counter + atomic reclaim

set -euo pipefail

# capture_process_start_time <pid>
# Captures the start time of a process via ps lstart, converts to microseconds since epoch.
# Returns empty string if process does not exist or parse fails (graceful).
#
# Arguments:
#   $1: Process ID
#
# Output:
#   Microseconds since epoch as integer, or empty string on error
#
# Exit code:
#   0 on success (even if empty output — process may have died)
#   1 only on fatal error (e.g., jq not installed)
#
# Example:
#   start_time=$(capture_process_start_time $$)
#   echo "$start_time"  # Output: 1725000000000000
capture_process_start_time() {
  local pid="$1"

  # Use ps to get lstart (absolute start time, stable)
  local lstart
  lstart=$(ps -p "$pid" -o lstart= 2>/dev/null) || return 0

  # Parse lstart (e.g., "Sun 26 Apr 17:55:09 2026") to Unix timestamp
  # Format from ps lstart: "DayOfWeek DD Mon HH:MM:SS YYYY"
  # Use date -j -f on macOS, gdate or native date on Linux
  local unix_ts
  if command -v date >/dev/null 2>&1 && date -j >/dev/null 2>&1; then
    # macOS native date with -j
    unix_ts=$(date -j -f "%a %d %b %T %Y" "$lstart" +%s 2>/dev/null) || return 0
  elif command -v gdate >/dev/null 2>&1; then
    # GNU date (from coreutils on macOS or Linux)
    # gdate uses slightly different format parsing; try directly with gdate
    unix_ts=$(gdate -d "$lstart" +%s 2>/dev/null) || return 0
  else
    # Fallback: try native date (non-macOS)
    unix_ts=$(date -d "$lstart" +%s 2>/dev/null) || return 0
  fi

  # Convert seconds to microseconds
  local start_time_us=$((unix_ts * 1000000))
  echo "$start_time_us"
}

# acquire_owner_lock <loop_id>
# Acquires an exclusive lock for a loop's owner.lock file.
# Lock is held by the current process and must be released via release_owner_lock.
# Uses flock on Linux, lockf on macOS; fd 8 (to avoid Phase 2's fd 9).
#
# Arguments:
#   $1: loop_id (12 hex characters)
#
# Output:
#   None
#
# Exit code:
#   0 on success (lock acquired, fd 8 is now held)
#   1 if lock cannot be acquired (another owner holds it) or I/O fails
#
# Side effect:
#   Opens fd 8 and holds the lock. Caller must release via release_owner_lock or exit.
#
# Example:
#   acquire_owner_lock "a1b2c3d4e5f6" || {
#     echo "Cannot start loop: lock held by another process"
#     exit 1
#   }
acquire_owner_lock() {
  local loop_id="$1"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: acquire_owner_lock: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # Ensure ~/.claude/loops/ directory exists
  local loops_dir="$HOME/.claude/loops"
  if [ ! -d "$loops_dir" ]; then
    mkdir -p "$loops_dir" || {
      echo "ERROR: acquire_owner_lock: failed to create $loops_dir" >&2
      return 1
    }
  fi

  local lock_file="$loops_dir/$loop_id.owner.lock"

  # Create lock file if it doesn't exist
  touch "$lock_file" || {
    echo "ERROR: acquire_owner_lock: failed to create lock file '$lock_file'" >&2
    return 1
  }

  # Acquire exclusive lock using platform-appropriate tool
  # fd 8 for owner.lock (fd 9 is used by Phase 2 for registry.lock)
  if command -v flock >/dev/null 2>&1; then
    # Linux: flock with fd 8, non-blocking (fail fast)
    exec 8>"$lock_file" || {
      echo "ERROR: acquire_owner_lock: failed to open fd 8 for '$lock_file'" >&2
      return 1
    }
    if ! flock --wait 5 -x 8; then
      echo "ERROR: acquire_owner_lock: lock contention; another owner is active" >&2
      exec 8>&-
      return 1
    fi
  elif command -v lockf >/dev/null 2>&1; then
    # macOS: lockf with non-blocking + retry
    exec 8>"$lock_file" || {
      echo "ERROR: acquire_owner_lock: failed to open fd 8 for '$lock_file'" >&2
      return 1
    }
    local retries=50  # ~5 seconds with 100ms sleeps
    while ! lockf -t 0 "$lock_file" true 2>/dev/null; do
      retries=$((retries - 1))
      if [ $retries -le 0 ]; then
        echo "ERROR: acquire_owner_lock: lock contention; another owner is active" >&2
        exec 8>&-
        return 1
      fi
      sleep 0.1
    done
  else
    echo "ERROR: acquire_owner_lock: neither flock nor lockf found; cannot acquire lock" >&2
    return 1
  fi

  return 0
}

# release_owner_lock <loop_id>
# Releases the exclusive owner.lock acquired by acquire_owner_lock.
# Idempotent: no error if lock is not held.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#
# Exit code:
#   0 always (idempotent)
#   1 only if loop_id format is invalid
#
# Example:
#   release_owner_lock "a1b2c3d4e5f6"
release_owner_lock() {
  local loop_id="$1"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: release_owner_lock: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # Close fd 8 (releases the lock)
  exec 8>&- 2>/dev/null || true

  return 0
}

# verify_owner_alive <loop_id>
# Verifies that the current owner of a loop is alive and is the same process.
# Defends against PID reuse via start time comparison.
# Must be cheap (<10ms) — used in hooks on every PostToolUse.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2 (optional): Override path to registry file (for testing)
#
# Output:
#   "alive" if owner is current process
#   "dead" if owner does not exist or has been recycled
#   "unknown" if parse error (graceful fallback)
#
# Exit code:
#   0 always (output indicates status, not exit)
#
# Example:
#   status=$(verify_owner_alive "a1b2c3d4e5f6")
#   if [ "$status" = "alive" ]; then
#     echo "Owner is running"
#   fi
verify_owner_alive() {
  local loop_id="$1"
  local registry_path="${2:-$HOME/.claude/loops/registry.json}"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "unknown"
    return 0
  fi

  # Read registry entry
  local entry
  entry=$(jq ".loops[] | select(.loop_id == \"$loop_id\")" "$registry_path" 2>/dev/null) || {
    echo "unknown"
    return 0
  }

  if [ -z "$entry" ]; then
    echo "unknown"
    return 0
  fi

  # Extract owner_pid and owner_start_time_us
  local owner_pid owner_start_time_us
  owner_pid=$(echo "$entry" | jq -r '.owner_pid // empty' 2>/dev/null) || {
    echo "unknown"
    return 0
  }
  owner_start_time_us=$(echo "$entry" | jq -r '.owner_start_time_us // empty' 2>/dev/null) || {
    echo "unknown"
    return 0
  }

  # Validate fields exist
  if [ -z "$owner_pid" ] || [ -z "$owner_start_time_us" ]; then
    echo "unknown"
    return 0
  fi

  # Check 1: Is process alive? (kill -0 sends no signal, just checks if process exists)
  if ! kill -0 "$owner_pid" 2>/dev/null; then
    echo "dead"
    return 0
  fi

  # Check 2: Is this process running something Claude-like? (ps command check)
  # Note: This is a heuristic. We check for "bash" or "sh" to avoid false negatives
  # from PIDs reused by unrelated processes. More precise check would read /proc/$pid/environ
  # and verify CLAUDE_SESSION_ID, but that's harder on macOS.
  local ps_cmd
  ps_cmd=$(ps -p "$owner_pid" -o command= 2>/dev/null | head -c 100) || {
    echo "dead"
    return 0
  }

  # If process command is empty or doesn't look like Claude, assume dead
  if [ -z "$ps_cmd" ]; then
    echo "dead"
    return 0
  fi

  # Check 3: Has process start time changed? (PID reuse defense)
  local current_start_time_us
  current_start_time_us=$(capture_process_start_time "$owner_pid") || {
    echo "dead"
    return 0
  }

  # If capture failed (empty string), assume dead
  if [ -z "$current_start_time_us" ]; then
    echo "dead"
    return 0
  fi

  # Compare start times: allow 1 second tolerance for clock skew / process startup jitter
  local time_diff=$((current_start_time_us - owner_start_time_us))
  if [ "$time_diff" -lt 0 ]; then
    time_diff=$((-time_diff))
  fi

  local tolerance_us=$((1 * 1000000))  # 1 second in microseconds
  if [ "$time_diff" -gt "$tolerance_us" ]; then
    # Start time differs by >1 second — PID was recycled
    echo "dead"
    return 0
  fi

  # All checks passed
  echo "alive"
  return 0
}

# staleness_seconds <loop_id>
# Returns elapsed seconds since last heartbeat, or -1 if no heartbeat exists.
# Reads from <state_dir>/heartbeat.json (written by Phase 5, mocked in tests).
#
# Arguments:
#   $1: loop_id (12 hex characters)
#
# Output:
#   Positive integer: seconds elapsed
#   -1: no heartbeat file found or parse error
#
# Exit code:
#   0 always (output indicates status)
#
# Example:
#   staleness=$(staleness_seconds "a1b2c3d4e5f6")
#   if [ "$staleness" -gt 100 ]; then echo "Stale"; fi
staleness_seconds() {
  local loop_id="$1"
  local registry_path="${2:-$HOME/.claude/loops/registry.json}"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "-1"
    return 0
  fi

  # Read registry entry to get state_dir
  local entry
  entry=$(jq ".loops[] | select(.loop_id == \"$loop_id\")" "$registry_path" 2>/dev/null) || {
    echo "-1"
    return 0
  }

  if [ -z "$entry" ]; then
    echo "-1"
    return 0
  fi

  # Extract state_dir
  local state_dir
  state_dir=$(echo "$entry" | jq -r '.state_dir // empty' 2>/dev/null) || {
    echo "-1"
    return 0
  }

  if [ -z "$state_dir" ]; then
    echo "-1"
    return 0
  fi

  # Check if heartbeat.json exists
  local hb_file="$state_dir/heartbeat.json"
  if [ ! -f "$hb_file" ]; then
    echo "-1"
    return 0
  fi

  # Read last_wake_us from heartbeat
  local last_wake_us
  last_wake_us=$(jq -r '.last_wake_us // empty' "$hb_file" 2>/dev/null) || {
    echo "-1"
    return 0
  }

  if [ -z "$last_wake_us" ]; then
    echo "-1"
    return 0
  fi

  # Compute now in microseconds
  local now_us
  if command -v gdate >/dev/null 2>&1; then
    local gdate_ns
    gdate_ns=$(gdate +%s%N 2>/dev/null) || {
      echo "-1"
      return 0
    }
    now_us=$((gdate_ns / 1000))
  else
    now_us=$(($(date +%s) * 1000000))
  fi

  # Compute elapsed seconds
  local elapsed_us=$((now_us - last_wake_us))
  if [ "$elapsed_us" -lt 0 ]; then
    elapsed_us=0
  fi

  local elapsed_secs=$((elapsed_us / 1000000))
  echo "$elapsed_secs"
}

# is_reclaim_candidate <loop_id>
# Determines if a loop can be reclaimed by checking: (1) entry exists, (2) owner dead OR heartbeat stale.
# Pure read — no side effects. Returns one of: "yes", "no", "owner_alive".
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2 (optional): Override path to registry file (for testing)
#
# Output:
#   "yes": entry exists and can be reclaimed (owner dead or heartbeat stale)
#   "no": entry does not exist (nothing to reclaim)
#   "owner_alive": entry exists but owner is alive and heartbeat fresh
#
# Exit code:
#   0 always (output indicates status)
#
# Example:
#   candidate=$(is_reclaim_candidate "a1b2c3d4e5f6")
#   if [ "$candidate" = "yes" ]; then reclaim_loop "a1b2c3d4e5f6"; fi
is_reclaim_candidate() {
  local loop_id="$1"
  local registry_path="${2:-$HOME/.claude/loops/registry.json}"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "no"
    return 0
  fi

  # Read registry entry
  local entry
  entry=$(jq ".loops[] | select(.loop_id == \"$loop_id\")" "$registry_path" 2>/dev/null) || {
    echo "no"
    return 0
  }

  if [ -z "$entry" ] || [ "$entry" = "{}" ]; then
    echo "no"
    return 0
  fi

  # Extract expected_cadence_seconds
  local expected_cadence
  expected_cadence=$(echo "$entry" | jq -r '.expected_cadence_seconds // 1500' 2>/dev/null) || {
    expected_cadence=1500
  }

  # Check 1: Is owner dead?
  local owner_status
  owner_status=$(verify_owner_alive "$loop_id" "$registry_path")
  if [ "$owner_status" = "dead" ]; then
    echo "yes"
    return 0
  fi

  # Check 2: Is heartbeat stale? (>3× expected_cadence)
  local staleness
  staleness=$(staleness_seconds "$loop_id" "$registry_path")
  if [ "$staleness" -gt $((3 * expected_cadence)) ]; then
    echo "yes"
    return 0
  fi

  # Owner is alive and heartbeat fresh
  echo "owner_alive"
  return 0
}

# reclaim_loop <loop_id> [--reason owner_dead|heartbeat_stale]
# Atomically reclaims a loop from a dead or stuck owner.
# Increments generation counter inside _with_registry_lock (atomic).
# Appends takeover event to revision-log.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2 (optional): --reason flag
#   $3 (optional): reason value (owner_dead | heartbeat_stale | user_request)
#
# Output:
#   Success: prints "Reclaimed loop_id [reason]"
#   Error: prints error message to stderr
#
# Exit code:
#   0 on success
#   1 if conditions not met or atomic update fails
#
# Example:
#   reclaim_loop "a1b2c3d4e5f6" --reason "owner_dead"
reclaim_loop() {
  local loop_id="$1"
  local reason="${3:-owner_dead}"
  local registry_path="${LOOP_REGISTRY_PATH:-$HOME/.claude/loops/registry.json}"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: reclaim_loop: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # Check if reclaim is actually needed
  local candidate
  candidate=$(is_reclaim_candidate "$loop_id" "$registry_path")
  if [ "$candidate" != "yes" ]; then
    echo "ERROR: reclaim_loop: loop is not a reclaim candidate (status: $candidate)" >&2
    return 1
  fi

  # Read current entry to get state_dir and generation
  local entry
  entry=$(jq ".loops[] | select(.loop_id == \"$loop_id\")" "$registry_path" 2>/dev/null) || {
    echo "ERROR: reclaim_loop: failed to read entry" >&2
    return 1
  }

  local old_generation
  old_generation=$(echo "$entry" | jq -r '.generation // 0' 2>/dev/null) || old_generation=0

  local state_dir
  state_dir=$(echo "$entry" | jq -r '.state_dir // empty' 2>/dev/null) || {
    echo "ERROR: reclaim_loop: no state_dir in entry" >&2
    return 1
  }

  # Atomically: increment generation, update owner fields
  local new_generation=$((old_generation + 1))
  local now_us
  if command -v gdate >/dev/null 2>&1; then
    now_us=$(gdate +%s%N | xargs -I '{}' sh -c "echo \$(( {} ))" 2>/dev/null) || {
      now_us=$(($(date +%s) * 1000000))
    }
  else
    now_us=$(($(date +%s) * 1000000))
  fi

  local current_pid=$$
  local current_start_time_us
  current_start_time_us=$(capture_process_start_time "$current_pid")
  if [ -z "$current_start_time_us" ]; then
    echo "ERROR: reclaim_loop: failed to capture process start time" >&2
    return 1
  fi

  # Generate new session_id for reclaimer
  local random_suffix
  random_suffix=$(tr -dc 'a-f0-9' </dev/urandom | head -c 8)
  local session_timestamp
  session_timestamp=$(date +%s)
  local new_session_id="session_${session_timestamp}_${random_suffix}"

  # Call atomic update via _with_registry_lock
  if ! update_loop_field "$loop_id" ".generation" "$new_generation"; then
    echo "ERROR: reclaim_loop: failed to increment generation" >&2
    return 1
  fi

  if ! update_loop_field "$loop_id" ".owner_pid" "$current_pid"; then
    echo "ERROR: reclaim_loop: failed to update owner_pid" >&2
    return 1
  fi

  if ! update_loop_field "$loop_id" ".owner_start_time_us" "$current_start_time_us"; then
    echo "ERROR: reclaim_loop: failed to update owner_start_time_us" >&2
    return 1
  fi

  if ! update_loop_field "$loop_id" ".owner_session_id" "\"$new_session_id\""; then
    echo "ERROR: reclaim_loop: failed to update owner_session_id" >&2
    return 1
  fi

  # Append takeover event to revision-log
  mkdir -p "$state_dir/revision-log" || {
    echo "ERROR: reclaim_loop: failed to create revision-log directory" >&2
    return 1
  }

  # Build takeover event JSON
  local takeover_event
  takeover_event=$(jq -n \
    --arg ts_us "$now_us" \
    --arg event "takeover" \
    --arg reason "$reason" \
    --arg from_owner_pid "$(echo "$entry" | jq -r '.owner_pid // "unknown"')" \
    --arg from_owner_session_id "$(echo "$entry" | jq -r '.owner_session_id // "unknown"')" \
    --arg generation "$new_generation" \
    '{ts_us: $ts_us, event: $event, reason: $reason, from_owner_pid: $from_owner_pid, from_owner_session_id: $from_owner_session_id, generation: $generation}')

  # Append to revision-log (atomic append to JSONL file)
  echo "$takeover_event" >> "$state_dir/revision-log/${new_session_id}.jsonl" || {
    echo "ERROR: reclaim_loop: failed to append takeover event" >&2
    return 1
  }

  echo "Reclaimed loop $loop_id (generation: $old_generation -> $new_generation, reason: $reason)"
  return 0
}

# append_takeover_event <state_dir> <event_json>
# Appends a takeover event to the revision-log JSONL file.
# Creates revision-log/ directory if missing.
#
# Arguments:
#   $1: state_dir (full path to loop state directory)
#   $2: event JSON object
#
# Exit code:
#   0 on success
#   1 on failure
#
# Example:
#   event=$(jq -n '{event: "takeover", reason: "owner_dead", generation: 1}')
#   append_takeover_event "/path/to/.loop-state/loop_id/" "$event"
append_takeover_event() {
  local state_dir="$1"
  local event_json="$2"

  # Ensure revision-log directory exists
  mkdir -p "$state_dir/revision-log" || {
    echo "ERROR: append_takeover_event: failed to create revision-log directory" >&2
    return 1
  }

  # Extract session_id from event (or generate one)
  local session_id
  session_id=$(echo "$event_json" | jq -r '.session_id // "default"' 2>/dev/null) || session_id="default"

  # Append event as JSONL line
  echo "$event_json" >> "$state_dir/revision-log/${session_id}.jsonl" || {
    echo "ERROR: append_takeover_event: failed to append to revision-log" >&2
    return 1
  }

  return 0
}

# Export functions for sourcing by other scripts
export -f capture_process_start_time
export -f acquire_owner_lock
export -f release_owner_lock
export -f verify_owner_alive
export -f staleness_seconds
export -f is_reclaim_candidate
export -f reclaim_loop
export -f append_takeover_event
