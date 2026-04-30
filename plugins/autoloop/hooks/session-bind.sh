#!/usr/bin/env bash
# session-bind.sh — SessionStart hook for autoloop (v4.10.0 Phase 36)
#
# Authoritatively binds owner_session_id from stdin payload because the
# $CLAUDE_SESSION_ID env var is NOT populated in skill Bash subprocesses
# (anthropics/claude-code#47018). The skills/start/SKILL.md sets
# owner_session_id="pending-bind" at registration and this hook completes the
# binding on the next SessionStart event for ANY session whose cwd lies under
# a registered loop's contract directory.
#
# Stdin payload schema (Claude Code SessionStart hook):
#   {
#     "session_id": "<uuid>",
#     "cwd": "/path/to/cwd",
#     "source": "startup|resume|clear|compact",
#     "transcript_path": "...",
#     "hook_event_name": "SessionStart"
#   }
#
# Binding state machine (per matched loop):
#   "" / unknown / unknown-session / pending-bind  → bind_first
#   matches current session_id                     → bind_resume (idempotent)
#   other UUID, owner_pid alive                    → observer (no mutation)
#   other UUID, owner_pid dead, last_updated > 1h  → stale_owner_detected
#                                                     (no auto-reclaim;
#                                                      surfaced for doctor)
#
# All paths exit 0 — SessionStart hooks must never block session startup.

set -euo pipefail

# ===== Configuration =====
LOOPS_DIR="${HOME}/.claude/loops"
REGISTRY_PATH="${CLAUDE_LOOPS_REGISTRY:-$LOOPS_DIR/registry.json}"
HOOK_ERRORS_LOG="$LOOPS_DIR/.hook-errors.log"
STALE_OWNER_THRESHOLD_S="${SESSION_BIND_STALE_THRESHOLD_S:-3600}"  # 1h default

# ===== Error handling =====
_log_error() {
  local cwd
  cwd=$(pwd 2>/dev/null || echo 'unknown')
  local error_msg="$1"
  local exit_code="${2:-1}"
  mkdir -p "$LOOPS_DIR" 2>/dev/null || true
  jq -n \
    --arg ts_us "$(python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo '0')" \
    --arg cwd "$cwd" \
    --arg error "$error_msg" \
    --arg exit_code "$exit_code" \
    --arg hook "session-bind.sh" \
    '{ts_us: $ts_us, cwd: $cwd, error: $error, exit_code: $exit_code, hook: $hook}' \
    >>"$HOOK_ERRORS_LOG" 2>/dev/null || true
}

trap '_log_error "Unexpected error in session-bind hook" "$?"' ERR

# ===== Source libraries =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$SCRIPT_DIR/../scripts"

for lib in registry-lib.sh provenance-lib.sh state-lib.sh; do
  if [ ! -f "$PLUGIN_SCRIPTS/$lib" ]; then
    _log_error "missing $lib" 1
    exit 0
  fi
  # shellcheck source=/dev/null
  source "$PLUGIN_SCRIPTS/$lib" 2>/dev/null || {
    _log_error "failed to source $lib" 1
    exit 0
  }
done

# Set agent name for provenance events
export _PROV_AGENT="session-bind.sh"

# ===== Read stdin payload =====
PAYLOAD=$(cat 2>/dev/null || echo '{}')
[ -z "$PAYLOAD" ] && PAYLOAD='{}'

SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // ""' 2>/dev/null || echo "")
PAYLOAD_CWD=$(echo "$PAYLOAD" | jq -r '.cwd // ""' 2>/dev/null || echo "")
SOURCE=$(echo "$PAYLOAD" | jq -r '.source // "unknown"' 2>/dev/null || echo "unknown")

# Empty session_id is fatal for binding (but not an error — could be running
# outside Claude Code via direct invocation in tests).
if [ -z "$SESSION_ID" ]; then
  emit_provenance "" "bind_skipped_no_session_id" \
    reason="empty session_id from stdin payload" \
    decision="deferred" 2>/dev/null || true
  exit 0
fi

# Fall back to pwd if cwd not in payload
CWD="${PAYLOAD_CWD:-$(pwd)}"

# ===== Read registry =====
REGISTRY=$(read_registry "$REGISTRY_PATH" 2>/dev/null) || {
  _log_error "failed to read registry" 1
  exit 0
}

# ===== Iterate loops, find ones whose contract dir contains CWD =====
# Use jq to emit matching loop entries as JSON lines
MATCHES=$(echo "$REGISTRY" | jq -c --arg cwd "$CWD" '
  .loops[] |
  select(
    ((.contract_path | split("/") | .[:-1] | join("/")) as $contract_dir |
      ($contract_dir + "/") as $contract_prefix |
      ($cwd | startswith($contract_prefix)) or ($cwd == $contract_dir)
    )
  )
' 2>/dev/null || echo "")

if [ -z "$MATCHES" ]; then
  # No loops registered for this cwd — totally fine
  exit 0
fi

# ===== Per-match binding decision =====
NOW_US=$(python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo "0")

while IFS= read -r match; do
  [ -z "$match" ] && continue

  LOOP_ID=$(echo "$match" | jq -r '.loop_id // ""')
  OWNER_SID=$(echo "$match" | jq -r '.owner_session_id // ""')
  OWNER_PID=$(echo "$match" | jq -r '.owner_pid // ""')
  GEN=$(echo "$match" | jq -r '.generation // 0')
  LAST_UPDATED_US=$(echo "$match" | jq -r '.owner_start_time_us // 0')
  CONTRACT_PATH=$(echo "$match" | jq -r '.contract_path // ""')

  [ -z "$LOOP_ID" ] && continue

  case "$OWNER_SID" in
    "" | "unknown" | "unknown-session" | "pending-bind")
      # bind_first: atomic CAS to set owner_session_id
      if update_loop_field "$LOOP_ID" ".owner_session_id" "\"$SESSION_ID\"" 2>/dev/null; then
        update_loop_field "$LOOP_ID" ".owner_start_time_us" "\"$NOW_US\"" 2>/dev/null || true
        # v2: mirror owner_session_id + created_in_session into contract frontmatter
        # (best-effort; registry is SSoT)
        if [ -n "$CONTRACT_PATH" ] && [ -f "$CONTRACT_PATH" ] && command -v set_contract_field >/dev/null 2>&1; then
          set_contract_field "$CONTRACT_PATH" "owner_session_id" "\"$SESSION_ID\"" 2>/dev/null || true
          set_contract_field "$CONTRACT_PATH" "owner_started_us" "$NOW_US" 2>/dev/null || true
          # created_in_session: only if pending-bind placeholder present
          local_created_session=$(awk '
            NR == 1 && /^---/ { in_fm = 1; next }
            in_fm && /^---/ { exit }
            in_fm && /^created_in_session:/ { sub(/^created_in_session:[[:space:]]*/, ""); print; exit }
          ' "$CONTRACT_PATH" 2>/dev/null)
          case "$local_created_session" in
            ""|"<bound by session-bind hook on first SessionStart>"|"\"\""|"pending-bind")
              set_contract_field "$CONTRACT_PATH" "created_in_session" "\"$SESSION_ID\"" 2>/dev/null || true
              ;;
          esac
        fi
        emit_provenance "$LOOP_ID" "bind_first" \
          session_id="$SESSION_ID" \
          cwd_observed="$CWD" \
          cwd_bound="$(dirname "$CONTRACT_PATH")" \
          registry_generation="$GEN" \
          reason="prior owner_session_id=$OWNER_SID; bound on SessionStart source=$SOURCE" \
          decision="proceeded"
      else
        emit_provenance "$LOOP_ID" "bind_failed_cas" \
          session_id="$SESSION_ID" \
          cwd_observed="$CWD" \
          reason="update_loop_field returned non-zero" \
          decision="refused"
      fi
      ;;

    "$SESSION_ID")
      # bind_resume: same session, idempotent
      emit_provenance "$LOOP_ID" "bind_resume" \
        session_id="$SESSION_ID" \
        cwd_observed="$CWD" \
        registry_generation="$GEN" \
        reason="SessionStart source=$SOURCE; same session re-binds" \
        decision="proceeded"
      ;;

    *)
      # Different session owns this loop — check liveness
      if [ -n "$OWNER_PID" ] && kill -0 "$OWNER_PID" 2>/dev/null; then
        # Other owner alive → this session is an observer
        emit_provenance "$LOOP_ID" "observer" \
          session_id="$SESSION_ID" \
          cwd_observed="$CWD" \
          registry_generation="$GEN" \
          reason="loop owned by live session $OWNER_SID (pid $OWNER_PID); this session is an observer" \
          decision="refused"
      else
        # Other owner dead — only mark stale if last_updated is old enough
        AGE_S=$(((NOW_US - LAST_UPDATED_US) / 1000000))
        if [ "$AGE_S" -gt "$STALE_OWNER_THRESHOLD_S" ]; then
          emit_provenance "$LOOP_ID" "stale_owner_detected" \
            session_id="$SESSION_ID" \
            cwd_observed="$CWD" \
            registry_generation="$GEN" \
            owner_pid_before="$OWNER_PID" \
            reason="prior owner $OWNER_SID (pid $OWNER_PID) dead; last_updated ${AGE_S}s ago; auto-reclaim NOT performed (use /autoloop:reclaim or doctor --fix)" \
            decision="deferred"
        else
          # Recent dead-owner — log but don't act (race window)
          emit_provenance "$LOOP_ID" "observer" \
            session_id="$SESSION_ID" \
            cwd_observed="$CWD" \
            registry_generation="$GEN" \
            reason="prior owner $OWNER_SID (pid $OWNER_PID) dead but last_updated only ${AGE_S}s ago (<threshold ${STALE_OWNER_THRESHOLD_S}s); waiting" \
            decision="deferred"
        fi
      fi
      ;;
  esac
done <<< "$MATCHES"

# DOC-03: idempotent self-healing on SessionStart. heal-self.sh is gated by
# registry content-hash so it does nothing when the registry is unchanged.
HEAL_SCRIPT="$PLUGIN_SCRIPTS/heal-self.sh"
if [ -x "$HEAL_SCRIPT" ]; then
  "$HEAL_SCRIPT" 2>/dev/null || true
fi

exit 0
