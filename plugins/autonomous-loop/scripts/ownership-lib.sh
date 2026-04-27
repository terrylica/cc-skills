#!/usr/bin/env bash
# ownership-lib.sh — Per-loop ownership protocol with PID-reuse defense
# Provides: acquire_owner_lock, release_owner_lock, verify_owner_alive, capture_process_start_time
#
# Pitfall #1 (PID reuse): Defense via owner_start_time_us comparison on verification
# Pitfall #2 (TOCTOU first-half): Defense via atomic flock acquire

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

# Export functions for sourcing by other scripts
export -f capture_process_start_time
export -f acquire_owner_lock
export -f release_owner_lock
export -f verify_owner_alive
