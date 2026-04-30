#!/usr/bin/env bash
# heartbeat-tick.sh — PostToolUse hook for autoloop
# Ticks the heartbeat for the current loop on each tool invocation.
#
# v4.10.0 Phase 36 (BIND-03): now reads session_id and cwd from stdin JSON
# payload (Claude Code's documented hook contract); env-var path retained as
# back-compat fallback only (anthropics/claude-code#47018 — env vars are NOT
# populated for skill Bash subprocesses, so the env path is unreliable).
#
# Logic:
# 1. Read stdin JSON payload {session_id, cwd}; fall back to $CLAUDE_SESSION_ID
#    + $(pwd) only if stdin is empty.
# 2. Read registry; find matching loop via contract_path prefix match.
# 3. Verify owner_session_id matches session_id (no-op if mismatch).
# 4. Check generation match (no-op + superseded event if generation drifted).
# 5. cwd-drift detection: compare CWD vs heartbeat.bound_cwd; on first tick
#    record bound_cwd; on subsequent ticks if mismatch flag cwd_drift_detected
#    in heartbeat.json AND emit cwd_drift_detected provenance event.
# 6. Increment iteration and write heartbeat via write_heartbeat.
# 7. All paths exit 0 (never block user tool call).

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
PROVENANCE_LIB="$SCRIPT_DIR/../scripts/provenance-lib.sh"

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

# Provenance is best-effort; missing lib is non-fatal
if [ -f "$PROVENANCE_LIB" ]; then
  # shellcheck source=/dev/null
  source "$PROVENANCE_LIB" 2>/dev/null || true
fi

export _PROV_AGENT="heartbeat-tick.sh"

# ===== Main logic =====

# Step 1: Read stdin JSON payload (modern Claude Code hook contract)
# Use a bounded read to avoid blocking when stdin is closed (no Claude Code present).
PAYLOAD=""
if [ ! -t 0 ]; then
  # stdin is connected to something (pipe/file). Read it.
  PAYLOAD=$(cat 2>/dev/null || echo "")
fi
[ -z "$PAYLOAD" ] && PAYLOAD='{}'

SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // ""' 2>/dev/null || echo "")
PAYLOAD_CWD=$(echo "$PAYLOAD" | jq -r '.cwd // ""' 2>/dev/null || echo "")

# Back-compat fallback: env var (DEPRECATED — see top-of-file comment)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="${CLAUDE_SESSION_ID:-}"
fi

if [ -z "$SESSION_ID" ]; then
  # No session ID anywhere — no-op (likely running outside a Claude session)
  exit 0
fi

# Step 2: Determine cwd (prefer stdin payload, fall back to pwd)
CWD="${PAYLOAD_CWD:-}"
if [ -z "$CWD" ]; then
  CWD="$(pwd 2>/dev/null || echo '')"
fi
if [ -z "$CWD" ]; then
  _log_error "Failed to determine cwd" 1
  exit 0
fi

# Step 3: Read registry (fail-graceful — returns empty registry if missing)
REGISTRY=$(read_registry "$REGISTRY_PATH") || {
  _log_error "Failed to read registry at $REGISTRY_PATH" 1
  exit 0
}

# Step 4: Find matching loop. Two-pass match (BIND-03 cwd-drift defense):
#   (a) primary: owner_session_id == this session — survives cwd drift
#   (b) fallback: cwd starts_with dirname(contract_path)
# Without (a), a session that drifts out of its contract dir would silently lose
# its loop binding and stop ticking heartbeat — masking the drift.
MATCHING_LOOP=""
MATCHING_LOOP_ID=""

MATCHING_LOOP=$(echo "$REGISTRY" | jq -r --arg sid "$SESSION_ID" '
.loops[] |
select(.owner_session_id == $sid) |
@json
' 2>/dev/null | head -1) || MATCHING_LOOP=""

if [ -z "$MATCHING_LOOP" ] || [ "$MATCHING_LOOP" = "" ]; then
  MATCHING_LOOP=$(echo "$REGISTRY" | jq -r --arg cwd "$CWD" '
.loops[] |
select(
  ((.contract_path | split("/") | .[:-1] | join("/")) as $contract_dir |
    ($contract_dir + "/") as $contract_prefix |
    ($cwd | startswith($contract_prefix)) or ($cwd == $contract_dir)
  )
) |
@json
' 2>/dev/null | head -1) || {
    exit 0
  }
fi

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

# Step 7.5 (BIND-03 prep): capture bound_cwd from existing heartbeat BEFORE
# write_heartbeat overwrites the file. write_heartbeat replaces the entire
# JSON object (no field-level merge), so any drift state we want to preserve
# across ticks must be re-applied below via jq merge after the rewrite.
STATE_DIR=$(echo "$MATCHING_LOOP" | jq -r '.state_dir // ""' 2>/dev/null || echo "")
CONTRACT_PATH=$(echo "$MATCHING_LOOP" | jq -r '.contract_path // ""' 2>/dev/null || echo "")
HB_FILE="$STATE_DIR/heartbeat.json"
PRE_BOUND_CWD=""
if [ -n "$STATE_DIR" ] && [ -f "$HB_FILE" ]; then
  PRE_BOUND_CWD=$(jq -r '.bound_cwd // ""' "$HB_FILE" 2>/dev/null || echo "")
fi

# Call write_heartbeat to atomically write new heartbeat
if ! write_heartbeat "$MATCHING_LOOP_ID" "$SESSION_ID" "$NEW_ITERATION" 2>/dev/null; then
  _log_error "Failed to write heartbeat for loop $MATCHING_LOOP_ID" 1
  exit 0
fi

# v2: mirror heartbeat into contract frontmatter (best-effort; registry+heartbeat
# are SSoT). Failure here MUST NOT abort the loop tick — a stale frontmatter is
# fine; an aborted heartbeat is not.
if [ -n "$CONTRACT_PATH" ] && [ -f "$CONTRACT_PATH" ] && command -v set_contract_field >/dev/null 2>&1; then
  _NOW_US=$(now_us 2>/dev/null || echo "")
  if [ -n "$_NOW_US" ]; then
    set_contract_field "$CONTRACT_PATH" "last_heartbeat_us" "$_NOW_US" 2>/dev/null || true
  fi
  set_contract_field "$CONTRACT_PATH" "last_heartbeat_session_id" "\"$SESSION_ID\"" 2>/dev/null || true
  set_contract_field "$CONTRACT_PATH" "iteration" "$NEW_ITERATION" 2>/dev/null || true
  set_contract_field "$CONTRACT_PATH" "generation" "$REGISTRY_GENERATION" 2>/dev/null || true
fi

# Step 8 (BIND-03): cwd-drift detection.
# Re-merge bound_cwd into the freshly-written heartbeat.json (write_heartbeat
# doesn't preserve our extension fields). Detect drift if PRE_BOUND_CWD was
# set and current CWD doesn't sit under it.
if [ -n "$STATE_DIR" ] && [ -f "$HB_FILE" ] && [ -n "$CONTRACT_PATH" ]; then
  CONTRACT_DIR=$(dirname "$CONTRACT_PATH")
  BOUND_CWD="$PRE_BOUND_CWD"

  if [ -z "$BOUND_CWD" ]; then
    # First heartbeat after binding — record bound_cwd
    TMP=$(mktemp "$HB_FILE.XXXXXX") || TMP=""
    if [ -n "$TMP" ]; then
      if jq --arg bc "$CONTRACT_DIR" '. + {bound_cwd: $bc, cwd_drift_detected: false}' "$HB_FILE" >"$TMP" 2>/dev/null; then
        mv "$TMP" "$HB_FILE" 2>/dev/null || rm -f "$TMP"
      else
        rm -f "$TMP"
      fi
    fi
    if command -v emit_provenance >/dev/null 2>&1; then
      emit_provenance "$MATCHING_LOOP_ID" "bound_cwd_recorded" \
        session_id="$SESSION_ID" \
        cwd_observed="$CWD" \
        cwd_bound="$CONTRACT_DIR" \
        registry_generation="$REGISTRY_GENERATION" \
        decision="proceeded" 2>/dev/null || true
    fi
  else
    # Subsequent heartbeat — check for drift
    case "$CWD" in
      "$BOUND_CWD"*)
        : # cwd matches; no action
        ;;
      *)
        # Drift detected — flag in heartbeat + emit provenance
        TMP=$(mktemp "$HB_FILE.XXXXXX") || TMP=""
        if [ -n "$TMP" ]; then
          if jq '. + {cwd_drift_detected: true}' "$HB_FILE" >"$TMP" 2>/dev/null; then
            mv "$TMP" "$HB_FILE" 2>/dev/null || rm -f "$TMP"
          else
            rm -f "$TMP"
          fi
        fi
        if command -v emit_provenance >/dev/null 2>&1; then
          emit_provenance "$MATCHING_LOOP_ID" "cwd_drift_detected" \
            session_id="$SESSION_ID" \
            cwd_observed="$CWD" \
            cwd_bound="$BOUND_CWD" \
            registry_generation="$REGISTRY_GENERATION" \
            reason="current cwd diverged from bound_cwd; resume disabled until reclaim" \
            decision="refused" 2>/dev/null || true
        fi
        ;;
    esac
  fi
fi

# Success: exit gracefully
exit 0
