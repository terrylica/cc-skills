#!/usr/bin/env bash
# notifications-lib.sh — Notification emission and filtering for autonomous-loop
# Provides: emit_notification, read_notifications
# Notifications are appended to ~/.claude/loops/.notifications.jsonl as JSONL

set -euo pipefail

# emit_notification <loop_id> <kind> <message> [metadata...]
# Emits a notification by appending a JSONL line to ~/.claude/loops/.notifications.jsonl.
# Uses atomic append (no flock needed — append is atomic up to PIPE_BUF on POSIX).
# Includes timestamp, loop_id, kind, and optional metadata fields.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2: kind (stuck|anomaly|pending_takeover|spawn)
#   $3: message (human-readable description)
#   $4+ (optional): Additional fields as KEY=VALUE pairs
#
# Output:
#   None on success
#
# Exit code:
#   0 on success
#   1 if append fails
#
# Example:
#   emit_notification "a1b2c3d4e5f6" "stuck" "Owner alive but heartbeat stale" owner_pid=1234 staleness_s=1500
emit_notification() {
  local loop_id="$1"
  local kind="$2"
  local message="$3"
  shift 3

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: emit_notification: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # Validate kind is one of the expected values
  if ! [[ "$kind" =~ ^(stuck|anomaly|pending_takeover|spawn)$ ]]; then
    echo "ERROR: emit_notification: invalid kind '$kind'" >&2
    return 1
  fi

  # Ensure ~/.claude/loops/ directory exists
  local loops_dir="$HOME/.claude/loops"
  if [ ! -d "$loops_dir" ]; then
    mkdir -p "$loops_dir" || {
      echo "ERROR: emit_notification: failed to create $loops_dir" >&2
      return 1
    }
  fi

  # Get current timestamp in microseconds
  local ts_us
  local ns
  if command -v gdate >/dev/null 2>&1; then
    ns=$(gdate +%s%N 2>/dev/null) || {
      ts_us=$(($(date +%s) * 1000000))
    }
    if [ -z "$ns" ]; then
      ts_us=$(($(date +%s) * 1000000))
    else
      ts_us=$((ns / 1000))
    fi
  else
    ts_us=$(($(date +%s) * 1000000))
  fi

  # Build base JSON object
  local notification_json
  notification_json=$(jq -n \
    --arg ts_us "$ts_us" \
    --arg loop_id "$loop_id" \
    --arg kind "$kind" \
    --arg message "$message" \
    '{ts_us: $ts_us, loop_id: $loop_id, kind: $kind, message: $message}')

  # Add optional metadata fields
  while [ $# -gt 0 ]; do
    local kv="$1"
    shift

    # Parse KEY=VALUE
    if [[ "$kv" =~ ^([^=]+)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"

      # Try to parse value as JSON (number, boolean, null); otherwise treat as string
      if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" =~ ^(true|false|null)$ ]]; then
        notification_json=$(echo "$notification_json" | jq --arg k "$key" --arg v "$value" '. + {($k): ($v | fromjson)}')
      else
        notification_json=$(echo "$notification_json" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
      fi
    fi
  done

  # Append to notifications file (atomic append on POSIX)
  local notif_file="$loops_dir/.notifications.jsonl"
  if ! echo "$notification_json" >> "$notif_file" 2>/dev/null; then
    echo "ERROR: emit_notification: failed to append to $notif_file" >&2
    return 1
  fi

  return 0
}

# read_notifications [since_us] [notif_file_override]
# Reads and filters notifications from the JSONL file.
# Returns one notification per line (valid JSON).
#
# Arguments:
#   $1 (optional): Timestamp filter (only return notifications with ts_us >= since_us)
#   $2 (optional): Override path to notifications file (for testing)
#
# Output:
#   One notification JSON per line to stdout
#   Invalid lines are skipped silently
#
# Exit code:
#   0 always (fail-graceful)
#
# Example:
#   read_notifications "1725000000000000" | jq '.kind'
read_notifications() {
  local since_us="${1:-0}"
  local notif_file="${2:-$HOME/.claude/loops/.notifications.jsonl}"

  # Return empty if file doesn't exist
  if [ ! -f "$notif_file" ]; then
    return 0
  fi

  # Read and filter by timestamp
  if [ "$since_us" = "0" ]; then
    # No filter — just output valid JSONL lines
    while IFS= read -r line; do
      if [ -n "$line" ] && echo "$line" | jq . >/dev/null 2>&1; then
        echo "$line"
      fi
    done < "$notif_file"
  else
    # Filter by timestamp
    while IFS= read -r line; do
      if [ -n "$line" ] && echo "$line" | jq . >/dev/null 2>&1; then
        local ts
        ts=$(echo "$line" | jq -r '.ts_us // 0' 2>/dev/null)
        if [ -n "$ts" ] && [ "$ts" -gt "$since_us" ]; then
          echo "$line"
        fi
      fi
    done < "$notif_file"
  fi

  return 0
}

# Export functions for sourcing by other scripts
export -f emit_notification
export -f read_notifications
