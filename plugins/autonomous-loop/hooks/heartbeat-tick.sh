#!/usr/bin/env bash
# heartbeat-tick.sh — PostToolUse hook for autonomous-loop
# Ticks the heartbeat for the current loop on each tool invocation.
#
# Logic:
# 1. Read CLAUDE_SESSION_ID environment variable (no-op if absent)
# 2. Determine current working directory
# 3. Read registry; find matching loop via contract_path prefix match
# 4. Verify owner_session_id matches CLAUDE_SESSION_ID (no-op if mismatch)
# 5. Check generation match (no-op + superseded event if generation drifted)
# 6. Increment heartbeat iteration and write via write_heartbeat
# 7. All paths exit 0 (never block user tool call)
#
# Error handling:
# - ERR trap logs to ~/.claude/loops/.hook-errors.log
# - Every code path exits 0 (fail-graceful, non-blocking)
# - jq parse errors, missing files, etc. logged but non-fatal

set -euo pipefail

# ===== Configuration =====
LOOPS_DIR="${HOME}/.claude/loops"
REGISTRY_PATH="${CLAUDE_LOOPS_REGISTRY:-$LOOPS_DIR/registry.json}"
HOOK_ERRORS_LOG="$LOOPS_DIR/.hook-errors.log"

# ===== Error handling: log and exit gracefully =====
_log_error() {
  local cwd
  cwd=$(pwd 2>/dev/null || echo 'unknown')
  local session="${CLAUDE_SESSION_ID:-absent}"
  local error_msg="$1"
  local exit_code="${2:-1}"

  # Ensure loops dir exists for logging
  mkdir -p "$LOOPS_DIR" 2>/dev/null || true

  # Append JSON error record to log (best-effort)
  {
    jq -n \
      --arg ts_us "$(python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo '0')" \
      --arg cwd "$cwd" \
      --arg session "$session" \
      --arg error "$error_msg" \
      --arg exit_code "$exit_code" \
      '{ts_us: $ts_us, cwd: $cwd, session: $session, error: $error, exit_code: $exit_code}' \
      >> "$HOOK_ERRORS_LOG" 2>/dev/null || true
  }
}

trap '_log_error "Unexpected error in heartbeat-tick hook" "$?"' ERR

# ===== Source library functions =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_LIB="$SCRIPT_DIR/../scripts/registry-lib.sh"
STATE_LIB="$SCRIPT_DIR/../scripts/state-lib.sh"

if [ ! -f "$REGISTRY_LIB" ]; then
  _log_error "registry-lib.sh not found at $REGISTRY_LIB" 1
  exit 0
fi

if [ ! -f "$STATE_LIB" ]; then
  _log_error "state-lib.sh not found at $STATE_LIB" 1
  exit 0
fi

# shellcheck source=/dev/null
source "$REGISTRY_LIB" 2>/dev/null || {
  _log_error "Failed to source registry-lib.sh" 1
  exit 0
}

# shellcheck source=/dev/null
source "$STATE_LIB" 2>/dev/null || {
  _log_error "Failed to source state-lib.sh" 1
  exit 0
}

# ===== Main logic =====

# Step 1: Read CLAUDE_SESSION_ID from environment
SESSION_ID="${CLAUDE_SESSION_ID:-}"
if [ -z "$SESSION_ID" ]; then
  # No session ID — no-op (likely running outside a Claude session)
  exit 0
fi

# Step 2: Get current working directory
CWD="$(pwd)" || {
  _log_error "Failed to get current working directory" 1
  exit 0
}

# Step 3: Read registry (fail-graceful — returns empty registry if missing)
REGISTRY=$(read_registry "$REGISTRY_PATH") || {
  _log_error "Failed to read registry at $REGISTRY_PATH" 1
  exit 0
}

# Step 4: Find matching loop via contract_path prefix match
# For each loop entry: if cwd starts with dirname(contract_path), it's the candidate
MATCHING_LOOP=""
MATCHING_LOOP_ID=""

# Use jq to iterate through loops and find prefix match
MATCHING_LOOP=$(echo "$REGISTRY" | jq -r '
.loops[] |
select(
  ((.contract_path | split("/") | .[:-1] | join("/")) as $contract_dir |
    ($contract_dir + "/") as $contract_prefix |
    ("'"$CWD"'" | startswith($contract_prefix)) or ("'"$CWD"'" == $contract_dir)
  )
) |
@json
' 2>/dev/null | head -1) || {
  # jq failed or no match
  exit 0
}

# If no matching loop found, no-op
if [ -z "$MATCHING_LOOP" ] || [ "$MATCHING_LOOP" = "" ]; then
  exit 0
fi

# Decode the matching loop from JSON
MATCHING_LOOP_ID=$(echo "$MATCHING_LOOP" | jq -r '.loop_id' 2>/dev/null) || {
  _log_error "Failed to extract loop_id from matching loop" 1
  exit 0
}

# Step 5: Verify owner_session_id matches CLAUDE_SESSION_ID
OWNER_SESSION_ID=$(echo "$MATCHING_LOOP" | jq -r '.owner_session_id // ""' 2>/dev/null) || {
  _log_error "Failed to extract owner_session_id from matching loop" 1
  exit 0
}

if [ "$OWNER_SESSION_ID" != "$SESSION_ID" ]; then
  # Different session owns this loop; no-op (don't tick another session's heartbeat)
  exit 0
fi

# Step 6: Check generation match
REGISTRY_GENERATION=$(echo "$MATCHING_LOOP" | jq -r '.generation // 0' 2>/dev/null) || {
  _log_error "Failed to extract generation from matching loop" 1
  exit 0
}

# Read current heartbeat
HB=$(read_heartbeat "$MATCHING_LOOP_ID" 2>/dev/null || echo "{}") || {
  # Gracefully handle read_heartbeat failure
  HB="{}"
}

HB_GENERATION=$(echo "$HB" | jq -r '.generation // 0' 2>/dev/null) || {
  _log_error "Failed to extract generation from heartbeat" 1
  exit 0
}

# If generation mismatch: this session has been reclaimed
if [ "$HB_GENERATION" != "$REGISTRY_GENERATION" ]; then
  # Write a superseded event to revision-log
  STATE_DIR=$(echo "$MATCHING_LOOP" | jq -r '.state_dir // ""' 2>/dev/null) || {
    _log_error "Failed to extract state_dir from matching loop" 1
    exit 0
  }

  if [ -d "$STATE_DIR/revision-log" ]; then
    SUPERSEDED_FILE="$STATE_DIR/revision-log/superseded-$(date +%s%N).json"
    {
      jq -n \
        --arg loop_id "$MATCHING_LOOP_ID" \
        --arg session_id "$SESSION_ID" \
        --arg reason "Generation mismatch: heartbeat=$HB_GENERATION, registry=$REGISTRY_GENERATION" \
        '{loop_id: $loop_id, session_id: $session_id, event: "superseded", reason: $reason, ts_us: '"$(python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo '0')"'}' \
        > "$SUPERSEDED_FILE" 2>/dev/null || true
    }
  fi

  # Exit 0 without ticking heartbeat
  exit 0
fi

# Step 7: Increment iteration and write heartbeat
CURRENT_ITERATION=$(echo "$HB" | jq -r '.iteration // 0' 2>/dev/null) || {
  _log_error "Failed to extract iteration from heartbeat" 1
  exit 0
}

NEW_ITERATION=$((CURRENT_ITERATION + 1))

# Call write_heartbeat to atomically write new heartbeat
if ! write_heartbeat "$MATCHING_LOOP_ID" "$SESSION_ID" "$NEW_ITERATION" 2>/dev/null; then
  _log_error "Failed to write heartbeat for loop $MATCHING_LOOP_ID" 1
  exit 0
fi

# Success: exit gracefully
exit 0
