#!/usr/bin/env bash
# notify-coalesce-lib.sh — Notification coalescing for autonomous-loop
# Provides: get_cursor, set_cursor, coalesce_notifications, display_macos_notification, notify_coalesce_run
# Consumes notifications from ~/.claude/loops/.notifications.jsonl and emits coalesced summaries.

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/notifications-lib.sh" 2>/dev/null || {
  echo "ERROR: notify-coalesce-lib.sh: cannot source notifications-lib.sh" >&2
  return 1
}
# shellcheck source=/dev/null
source "$SCRIPT_DIR/status-lib.sh" 2>/dev/null || {
  echo "ERROR: notify-coalesce-lib.sh: cannot source status-lib.sh" >&2
  return 1
}

# get_cursor [cursor_file_override]
# Reads the cursor timestamp (microseconds) from ~/.claude/loops/.notifications.cursor
# Returns 0 if successfully read; output is the timestamp on stdout
# Returns 0 with empty output if cursor file doesn't exist (treat as start from beginning)
#
# Arguments:
#   $1 (optional): Override path to cursor file (for testing)
#
# Output:
#   Cursor timestamp (microseconds) on stdout, or empty if not found
#
# Exit code:
#   0 always
get_cursor() {
  local cursor_file="${1:-$HOME/.claude/loops/.notifications.cursor}"

  if [ -f "$cursor_file" ]; then
    cat "$cursor_file" 2>/dev/null || true
  fi

  return 0
}

# set_cursor <timestamp> [cursor_file_override]
# Writes the cursor timestamp to ~/.claude/loops/.notifications.cursor
# Format: single line, "ts_us:<microseconds>"
#
# Arguments:
#   $1: Cursor timestamp (microseconds)
#   $2 (optional): Override path to cursor file (for testing)
#
# Exit code:
#   0 on success
#   1 if write fails
set_cursor() {
  local ts_us="$1"
  local cursor_file="${2:-$HOME/.claude/loops/.notifications.cursor}"

  # Ensure directory exists
  local cursor_dir
  cursor_dir="$(dirname "$cursor_file")"
  if [ ! -d "$cursor_dir" ]; then
    mkdir -p "$cursor_dir" || {
      echo "ERROR: set_cursor: failed to create $cursor_dir" >&2
      return 1
    }
  fi

  # Write cursor atomically
  if ! echo "ts_us:$ts_us" > "$cursor_file" 2>/dev/null; then
    echo "ERROR: set_cursor: failed to write $cursor_file" >&2
    return 1
  fi

  return 0
}

# display_macos_notification <title> <message>
# Displays a macOS notification via osascript if available
# No-op on Linux and other platforms
#
# Arguments:
#   $1: Notification title
#   $2: Notification message (body)
#
# Exit code:
#   0 always (fail-graceful)
display_macos_notification() {
  local title="$1"
  local message="$2"

  # Only attempt on macOS
  if [ "$(uname)" != "Darwin" ]; then
    return 0
  fi

  # Skip if osascript not available
  if ! command -v osascript >/dev/null 2>&1; then
    return 0
  fi

  # Fire notification (best-effort, ignore errors)
  osascript -e "display notification \"$message\" with title \"$title\" sound name \"Submarine\"" 2>/dev/null || true

  return 0
}

# coalesce_notifications [since_us] [window_seconds] [notif_file_override]
# Reads raw notifications, groups by 60s windows, emits coalesced JSONL on stdout
# Algorithm:
#   1. Read notifications since cursor (or all if since_us=0)
#   2. Group by 60s windows: bucket_key = floor(ts_us / (window_seconds * 1000000))
#   3. For each window:
#      - If >=3 distinct loop_ids with kind in (stuck, anomaly, pending_takeover) → emit one coalesced message
#      - Else: pass through individual notifications as-is
#   4. Output: JSONL on stdout (one coalesced or pass-through per line)
#
# Arguments:
#   $1 (optional): since_us timestamp (microseconds); default 0 (read all)
#   $2 (optional): window_seconds; default 60
#   $3 (optional): Override path to notifications file (for testing)
#
# Output:
#   One JSONL message per line to stdout
#   Messages are either:
#     - kind="coalesced" with count, loop_ids array, window_start_us, window_end_us
#     - Original notification if pass-through (threshold <3 distinct loops)
#
# Exit code:
#   0 always (fail-graceful)
coalesce_notifications() {
  local since_us="${1:-0}"
  local window_seconds="${2:-60}"
  local notif_file="${3:-$HOME/.claude/loops/.notifications.jsonl}"

  # Use jq to group and coalesce entirely (compact JSONL output for streaming)
  read_notifications "$since_us" "$notif_file" | jq -sc \
    --argjson ws "$window_seconds" \
    'if length == 0 then
       empty
     else
       group_by((.ts_us | tonumber) / ($ws * 1000000) | floor) |
       map(
         . as $window |
         (($window[0].ts_us | tonumber) / ($ws * 1000000) | floor) as $bucket_key |
         (($window | map(.ts_us | tonumber) | max)) as $max_ts |
         (($window | map(select(.kind == "stuck" or .kind == "anomaly" or .kind == "pending_takeover")) | map(.loop_id) | unique)) as $loop_ids |
         (($loop_ids | length)) as $distinct_count |
         if $distinct_count >= 3 then
           {
             ts_us: ($max_ts | tostring),
             kind: "coalesced",
             count: $distinct_count,
             loop_ids: $loop_ids,
             window_start_us: ($bucket_key * $ws * 1000000 | tostring),
             window_end_us: (($bucket_key + 1) * $ws * 1000000 - 1 | tostring),
             summary: "\($distinct_count) loops stale; check /autonomous-loop:status"
           }
         else
           $window[]
         end
       )[]
     end' 2>/dev/null || true
}

# notify_coalesce_run [notif_file_override] [coalesced_file_override] [cursor_file_override]
# Full pipeline: read since cursor → coalesce → append to coalesced file → display → update cursor
# This is the main entry point for running the notification coalescing job.
#
# Arguments:
#   $1 (optional): Override path to notifications file (for testing)
#   $2 (optional): Override path to coalesced file (for testing)
#   $3 (optional): Override path to cursor file (for testing)
#
# Exit code:
#   0 on success
#   Non-zero if critical operation fails (but best-effort on display/osascript)
notify_coalesce_run() {
  local notif_file="${1:-$HOME/.claude/loops/.notifications.jsonl}"
  local coalesced_file="${2:-$HOME/.claude/loops/.notifications-coalesced.jsonl}"
  local cursor_file="${3:-$HOME/.claude/loops/.notifications.cursor}"

  # Ensure directory exists
  local loops_dir
  loops_dir="$(dirname "$notif_file")"
  if [ ! -d "$loops_dir" ]; then
    mkdir -p "$loops_dir" || {
      echo "ERROR: notify_coalesce_run: failed to create $loops_dir" >&2
      return 1
    }
  fi

  # Read current cursor
  local current_cursor
  current_cursor=$(get_cursor "$cursor_file")
  local since_us="${current_cursor#ts_us:}"
  if [ "$since_us" = "$current_cursor" ]; then
    # Cursor file doesn't have "ts_us:" prefix; assume it's a raw timestamp
    since_us="${current_cursor:-0}"
  fi

  # If cursor is empty or invalid, start from 0
  if [ -z "$since_us" ] || [ "$since_us" = "ts_us:" ]; then
    since_us="0"
  fi

  # Read raw notifications and coalesce
  local coalesced_output_str
  local max_ts_val="$since_us"

  coalesced_output_str=$(coalesce_notifications "$since_us" 60 "$notif_file")

  # If no new notifications, exit cleanly
  if [ -z "$coalesced_output_str" ]; then
    return 0
  fi

  # Extract max timestamp from coalesced output
  max_ts_val=$(echo "$coalesced_output_str" | jq -r '.ts_us // 0' 2>/dev/null | sort -n | tail -1 || echo "$since_us")

  # Append each coalesced message to file
  echo "$coalesced_output_str" | while IFS= read -r line; do
    if [ -n "$line" ] && echo "$line" | jq . >/dev/null 2>&1; then
      echo "$line" >> "$coalesced_file"

      # Display macOS notification if this is a coalesced message
      local kind
      kind=$(echo "$line" | jq -r '.kind // ""' 2>/dev/null)
      if [ "$kind" = "coalesced" ]; then
        local summary
        summary=$(echo "$line" | jq -r '.summary // ""' 2>/dev/null)
        display_macos_notification "Claude Loops" "$summary"
      fi
    fi
  done

  # Update cursor to max timestamp
  if [ "$max_ts_val" != "$since_us" ] && [ "$max_ts_val" != "0" ]; then
    set_cursor "$max_ts_val" "$cursor_file" || {
      echo "ERROR: notify_coalesce_run: failed to update cursor" >&2
      return 1
    }
  fi

  return 0
}

# Export functions for sourcing
export -f get_cursor
export -f set_cursor
export -f display_macos_notification
export -f coalesce_notifications
export -f notify_coalesce_run
