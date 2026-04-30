#!/usr/bin/env bash
# status-lib.sh — Machine-wide loop enumeration and status reporting
# Provides: enumerate_loops, compute_dead_time_ratio, format_status_table, human_relative_time, is_reclaim_candidate_v2

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/registry-lib.sh" 2>/dev/null || {
  echo "ERROR: status-lib.sh: cannot source registry-lib.sh" >&2
  return 1
}
# shellcheck source=/dev/null
source "$SCRIPT_DIR/state-lib.sh" 2>/dev/null || {
  echo "ERROR: status-lib.sh: cannot source state-lib.sh" >&2
  return 1
}
# shellcheck source=/dev/null
source "$SCRIPT_DIR/ownership-lib.sh" 2>/dev/null || {
  echo "ERROR: status-lib.sh: cannot source ownership-lib.sh" >&2
  return 1
}

# human_relative_time <us_timestamp>
# Converts a microsecond timestamp to a human-readable relative time string.
# Returns "—" if timestamp is 0, null, or empty (no heartbeat).
#
# Arguments:
#   $1: Microseconds since epoch (integer), or empty/0
#
# Output:
#   "Ns ago" for N seconds, "Nm ago" for N minutes, "Nh ago" for N hours, "Nd ago" for N days, "—" for null
#
# Exit code:
#   0 always
#
# Example:
#   human_relative_time "1725000000000000"  # Output: "2m ago"
human_relative_time() {
  local last_wake_us="$1"

  # Handle null/empty/zero
  if [ -z "$last_wake_us" ] || [ "$last_wake_us" = "0" ]; then
    echo "—"
    return 0
  fi

  # Get current time in microseconds
  local now_us
  now_us=$(now_us) || now_us=$(($(date +%s) * 1000000))

  # Compute elapsed microseconds
  local elapsed_us=$((now_us - last_wake_us))
  if [ "$elapsed_us" -lt 0 ]; then
    echo "—"
    return 0
  fi

  # Convert to seconds
  local elapsed_s=$((elapsed_us / 1000000))

  # Format relative time
  if [ "$elapsed_s" -lt 60 ]; then
    echo "${elapsed_s}s ago"
  elif [ "$elapsed_s" -lt 3600 ]; then
    local mins=$((elapsed_s / 60))
    echo "${mins}m ago"
  elif [ "$elapsed_s" -lt 86400 ]; then
    local hours=$((elapsed_s / 3600))
    echo "${hours}h ago"
  else
    local days=$((elapsed_s / 86400))
    echo "${days}d ago"
  fi
}

# compute_dead_time_ratio <loop_id> [registry_path]
# Computes the fraction of a loop's lifespan that it was dead/inactive.
# Formula: dead_time_ratio = 1 - (heartbeat_count * cadence / lifespan)
# Clamped to [0.0, 1.0].
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2 (optional): Override path to registry file (for testing)
#
# Output:
#   Float string with 2 decimals: "0.00", "0.50", "1.00", etc.
#
# Exit code:
#   0 on success
#   1 if loop_id not found or read fails
#
# Example:
#   ratio=$(compute_dead_time_ratio "a1b2c3d4e5f6")
#   echo "$ratio"  # Output: "0.15"
compute_dead_time_ratio() {
  local loop_id="$1"
  local registry_path="${2:-$HOME/.claude/loops/registry.json}"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: compute_dead_time_ratio: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # Read registry entry
  local entry
  entry=$(read_registry_entry "$loop_id" "$registry_path") || return 1

  if [ "$entry" = "{}" ] || [ -z "$entry" ]; then
    echo "ERROR: compute_dead_time_ratio: loop_id not found" >&2
    return 1
  fi

  # Extract started_at_us (creation timestamp)
  local started_at_us
  started_at_us=$(echo "$entry" | jq -r '.started_at_us // empty' 2>/dev/null)
  if [ -z "$started_at_us" ]; then
    # Fallback: use current time minus state_dir mtime
    local state_dir
    state_dir=$(echo "$entry" | jq -r '.state_dir // empty' 2>/dev/null)
    if [ -z "$state_dir" ] || [ ! -d "$state_dir" ]; then
      echo "ERROR: compute_dead_time_ratio: cannot determine loop start time" >&2
      return 1
    fi
    # Get state_dir mtime as seconds since epoch, convert to us
    local dir_mtime
    dir_mtime=$(stat -f%m "$state_dir" 2>/dev/null || stat -c %Y "$state_dir" 2>/dev/null) || {
      echo "ERROR: compute_dead_time_ratio: cannot stat state_dir" >&2
      return 1
    }
    started_at_us=$((dir_mtime * 1000000))
  fi

  # Get current time in microseconds
  local now_us
  now_us=$(now_us) || now_us=$(($(date +%s) * 1000000))

  # Compute lifespan in seconds
  local lifespan_us=$((now_us - started_at_us))
  if [ "$lifespan_us" -le 0 ]; then
    # Loop hasn't started yet (clock skew); return 0
    echo "0.00"
    return 0
  fi

  # Read heartbeat to count ticks
  local hb_file
  hb_file=$(echo "$entry" | jq -r '.state_dir // empty' 2>/dev/null)
  if [ -z "$hb_file" ]; then
    echo "1.00"  # No state_dir, assume dead
    return 0
  fi
  hb_file="$hb_file/heartbeat.json"

  if [ ! -f "$hb_file" ]; then
    # No heartbeat written yet; entire lifespan was dead
    echo "1.00"
    return 0
  fi

  # Read iteration from heartbeat (approximates tick count)
  local iteration
  iteration=$(jq -r '.iteration // 0' "$hb_file" 2>/dev/null) || iteration=0

  # Extract expected_cadence_seconds
  local cadence_seconds
  cadence_seconds=$(echo "$entry" | jq -r '.expected_cadence_seconds // 1500' 2>/dev/null) || cadence_seconds=1500

  # Compute active_seconds = iteration_count * cadence (approximation)
  # Each iteration represents one cadence interval of activity
  local active_us=$((iteration * cadence_seconds * 1000000))

  # Clamp active_us to lifespan_us
  if [ "$active_us" -gt "$lifespan_us" ]; then
    active_us="$lifespan_us"
  fi

  # Compute dead_time_ratio = 1 - (active_us / lifespan_us)
  local ratio
  ratio=$(awk -v a="$active_us" -v l="$lifespan_us" 'BEGIN {printf "%.2f", 1.0 - (a / l)}')

  echo "$ratio"
  return 0
}

# is_reclaim_candidate_v2 <loop_id> [registry_path]
# Extended reclaim candidate check: returns "yes" if owner is dead AND state-dir mtime > 7 days,
# OR if the original is_reclaim_candidate predicate returns "yes".
# Pure read — no side effects.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2 (optional): Override path to registry file (for testing)
#
# Output:
#   "yes": loop can be reclaimed (dead owner + old state dir, or original stale predicate)
#   "no": loop cannot be reclaimed
#
# Exit code:
#   0 always
#
# Example:
#   candidate=$(is_reclaim_candidate_v2 "a1b2c3d4e5f6")
is_reclaim_candidate_v2() {
  local loop_id="$1"
  local registry_path="${2:-$HOME/.claude/loops/registry.json}"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "no"
    return 0
  fi

  # Check Phase 4's original predicate
  local original_result
  original_result=$(is_reclaim_candidate "$loop_id" "$registry_path")
  if [ "$original_result" = "yes" ]; then
    echo "yes"
    return 0
  fi

  # Additional check: if owner is dead AND state_dir older than 7 days
  local entry
  entry=$(read_registry_entry "$loop_id" "$registry_path") || {
    echo "no"
    return 0
  }

  if [ "$entry" = "{}" ] || [ -z "$entry" ]; then
    echo "no"
    return 0
  fi

  # Check if owner is dead
  local owner_status
  owner_status=$(verify_owner_alive "$loop_id" "$registry_path")
  if [ "$owner_status" != "dead" ]; then
    echo "no"
    return 0
  fi

  # Extract state_dir and check its mtime
  local state_dir
  state_dir=$(echo "$entry" | jq -r '.state_dir // empty' 2>/dev/null) || {
    echo "no"
    return 0
  }

  if [ -z "$state_dir" ] || [ ! -d "$state_dir" ]; then
    echo "yes"  # Owner dead and state_dir missing = reclaim
    return 0
  fi

  # Get current time in seconds
  local now_s=$(($(date +%s)))

  # Get state_dir modification time (seconds since epoch)
  local dir_mtime
  dir_mtime=$(stat -f%m "$state_dir" 2>/dev/null || stat -c %Y "$state_dir" 2>/dev/null) || {
    echo "yes"  # Owner dead and mtime unreadable = reclaim
    return 0
  }

  # Check if older than 7 days (604800 seconds)
  local seven_days_ago=$((now_s - 604800))
  if [ "$dir_mtime" -lt "$seven_days_ago" ]; then
    echo "yes"
    return 0
  fi

  # Owner dead but state_dir is fresh
  echo "no"
  return 0
}

# enumerate_loops [registry_path]
# Emits JSONL (JSON Lines) output, one loop per line, with computed status fields.
# Each line is a valid JSON object with: loop_id, session_id, status, last_wake_us, last_wake_human,
# dead_time_ratio, staleness_flag, reclaim_candidate.
#
# Arguments:
#   $1 (optional): Override path to registry file (for testing)
#
# Output:
#   JSONL to stdout (one JSON object per line)
#
# Exit code:
#   0 on success (even if no loops found)
#   1 if registry cannot be read
#
# Example:
#   enumerate_loops | jq -r '.status'
enumerate_loops() {
  local registry_path="${1:-$HOME/.claude/loops/registry.json}"

  # Read full registry
  local registry
  registry=$(read_registry "$registry_path") || return 1

  # Check if loops array is empty
  local loop_count
  loop_count=$(echo "$registry" | jq '.loops | length' 2>/dev/null) || loop_count=0

  if [ "$loop_count" -eq 0 ]; then
    # Return empty (no lines)
    return 0
  fi

  # Iterate over each loop and emit a status line
  echo "$registry" | jq -r '.loops[] | @json' 2>/dev/null | while read -r loop_json; do
    local loop_id session_id started_at_us expected_cadence state_dir

    # Extract fields from loop entry
    loop_id=$(echo "$loop_json" | jq -r '.loop_id // empty' 2>/dev/null)
    session_id=$(echo "$loop_json" | jq -r '.owner_session_id // empty' 2>/dev/null)
    started_at_us=$(echo "$loop_json" | jq -r '.started_at_us // empty' 2>/dev/null)
    expected_cadence=$(echo "$loop_json" | jq -r '.expected_cadence_seconds // 1500' 2>/dev/null)
    state_dir=$(echo "$loop_json" | jq -r '.state_dir // empty' 2>/dev/null)

    # Derive session_id prefix (first 8 chars) if full session_id available
    local session_prefix
    session_prefix="${session_id:0:8}"
    if [ -z "$session_prefix" ]; then
      session_prefix="—"
    fi

    # Determine status: ACTIVE, SATURATED, STALE, or DEAD
    local owner_alive
    owner_alive=$(verify_owner_alive "$loop_id" "$registry_path")

    local status="ACTIVE"
    if [ "$owner_alive" = "dead" ]; then
      status="DEAD"
    else
      # Owner is alive; check staleness
      local staleness_secs
      staleness_secs=$(staleness_seconds "$loop_id" "$registry_path")

      if [ "$staleness_secs" -gt $((4 * expected_cadence)) ]; then
        status="DEAD"
      elif [ "$staleness_secs" -gt $((3 * expected_cadence)) ]; then
        status="STALE"
      fi

      # Check if loop is saturated (contract has done: true or stop event)
      # For Phase 10 v1, assume not saturated (TODO: Phase 11 will add this check)
      # status="SATURATED"  # Placeholder
    fi

    # Get last_wake timestamp and human-readable form
    local last_wake_us
    local hb_file="$state_dir/heartbeat.json"
    if [ -f "$hb_file" ]; then
      last_wake_us=$(jq -r '.last_wake_us // empty' "$hb_file" 2>/dev/null)
    else
      last_wake_us=""
    fi

    local last_wake_human
    if [ -n "$last_wake_us" ]; then
      last_wake_human=$(human_relative_time "$last_wake_us")
    else
      last_wake_human="—"
    fi

    # Compute dead_time_ratio
    local dead_time_ratio
    dead_time_ratio=$(compute_dead_time_ratio "$loop_id" "$registry_path" 2>/dev/null) || dead_time_ratio="—"

    # Determine staleness flag
    local staleness_flag="—"
    if [ -n "$last_wake_us" ]; then
      local stale_secs
      stale_secs=$(staleness_seconds "$loop_id" "$registry_path")
      if [ "$stale_secs" -gt $((3 * expected_cadence)) ]; then
        staleness_flag="stale"
      else
        staleness_flag="fresh"
      fi
    fi

    # Determine if reclaim candidate
    local reclaim_candidate
    reclaim_candidate=$(is_reclaim_candidate_v2 "$loop_id" "$registry_path")
    if [ "$reclaim_candidate" = "yes" ]; then
      reclaim_candidate="yes"
    else
      reclaim_candidate="no"
    fi

    # Emit JSON line (compact format for JSONL)
    local output
    output=$(jq -cn \
      --arg loop_id "$loop_id" \
      --arg session_id "$session_prefix" \
      --arg status "$status" \
      --arg last_wake_us "$last_wake_us" \
      --arg last_wake_human "$last_wake_human" \
      --arg dead_time_ratio "$dead_time_ratio" \
      --arg staleness_flag "$staleness_flag" \
      --arg reclaim_candidate "$reclaim_candidate" \
      '{loop_id: $loop_id, session_id: $session_id, status: $status, last_wake_us: $last_wake_us, last_wake_human: $last_wake_human, dead_time_ratio: $dead_time_ratio, staleness_flag: $staleness_flag, reclaim_candidate: $reclaim_candidate}')

    echo "$output"
  done
}

# format_status_table <jsonl_input>
# Reads JSONL from stdin (one loop per line), formats as a pretty ASCII table.
# Output includes headers and aligned columns.
#
# Arguments:
#   None (reads from stdin)
#
# Output:
#   ASCII table to stdout
#
# Exit code:
#   0 on success (or if input is empty)
#   1 if jq fails
#
# Example:
#   enumerate_loops | format_status_table
format_status_table() {
  local line_count=0
  local header_printed=0

  # Read and format each line
  while IFS= read -r jsonl_line; do
    # Check if line is empty
    if [ -z "$jsonl_line" ]; then
      continue
    fi

    # Parse JSON fields
    local loop_id session_id status last_wake_human dead_time_ratio staleness_flag reclaim_candidate
    loop_id=$(echo "$jsonl_line" | jq -r '.loop_id // "—"' 2>/dev/null)
    session_id=$(echo "$jsonl_line" | jq -r '.session_id // "—"' 2>/dev/null)
    status=$(echo "$jsonl_line" | jq -r '.status // "—"' 2>/dev/null)
    last_wake_human=$(echo "$jsonl_line" | jq -r '.last_wake_human // "—"' 2>/dev/null)
    dead_time_ratio=$(echo "$jsonl_line" | jq -r '.dead_time_ratio // "—"' 2>/dev/null)
    staleness_flag=$(echo "$jsonl_line" | jq -r '.staleness_flag // "—"' 2>/dev/null)
    reclaim_candidate=$(echo "$jsonl_line" | jq -r '.reclaim_candidate // "no"' 2>/dev/null)

    # Print header on first iteration
    if [ "$header_printed" -eq 0 ]; then
      printf "%-12s %-8s %-9s %-10s %-4s %-6s %-4s\n" \
        "LOOP_ID" "SESSION" "STATUS" "LAST_WAKE" "DEAD" "STALE" "RECLAIM"
      printf "%-12s %-8s %-9s %-10s %-4s %-6s %-4s\n" \
        "————————————" "————————" "—————————" "——————————" "————" "——————" "————"
      header_printed=1
    fi

    # Print data row
    printf "%-12s %-8s %-9s %-10s %-4s %-6s %-4s\n" \
      "$loop_id" "$session_id" "$status" "$last_wake_human" "$dead_time_ratio" "$staleness_flag" "$reclaim_candidate"

    ((line_count++))
  done

  # If no loops, print "No active loops"
  if [ "$line_count" -eq 0 ]; then
    echo "No active loops."
  fi

  return 0
}

# Export functions for sourcing by other scripts
export -f human_relative_time
export -f compute_dead_time_ratio
export -f is_reclaim_candidate_v2
export -f enumerate_loops
export -f format_status_table
