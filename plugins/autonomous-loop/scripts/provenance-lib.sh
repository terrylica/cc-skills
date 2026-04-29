#!/usr/bin/env bash
# provenance-lib.sh — Append-only schema-versioned ledger for autonomous-loop state mutations.
# Provides: emit_provenance, rotate_global_provenance
#
# Design (v4.10.0 Phase 35):
#   - Per-loop ledger at <state_dir>/provenance.jsonl (append-only).
#   - Global mirror at ~/.claude/loops/global-provenance.jsonl, rotated at 10k lines.
#   - Atomic writes via flock fd 9 on per-file lock files (defends Pitfall #4).
#   - Returns 0 on all paths so callers in hooks/wakers never block on provenance failure.
#   - Decoupled from registry/heartbeat: this lib does NOT mutate either; callers do
#     and emit a provenance event before/after their own mutation (intent-before-state).

set -euo pipefail

# ===== Constants =====
PROVENANCE_SCHEMA_VERSION=1
PROVENANCE_GLOBAL_DIR="${PROVENANCE_GLOBAL_DIR:-$HOME/.claude/loops}"
PROVENANCE_GLOBAL_FILE="${PROVENANCE_GLOBAL_FILE:-$PROVENANCE_GLOBAL_DIR/global-provenance.jsonl}"
PROVENANCE_ROTATION_THRESHOLD="${PROVENANCE_ROTATION_THRESHOLD:-10000}"
PROVENANCE_ROTATION_KEEP="${PROVENANCE_ROTATION_KEEP:-5000}"

# ===== Source siblings (only for state_dir lookup; degrade gracefully if absent) =====
_PROV_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_PROV_SCRIPT_DIR/registry-lib.sh" ]; then
  # shellcheck source=/dev/null
  source "$_PROV_SCRIPT_DIR/registry-lib.sh" 2>/dev/null || true
fi

# _prov_now_iso
# Emit ISO 8601 UTC timestamp with millisecond precision.
# Tries gdate (GNU) → python3 → date (millis = .000).
_prov_now_iso() {
  if command -v gdate >/dev/null 2>&1; then
    gdate -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import datetime; print(datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.') + f'{datetime.datetime.utcnow().microsecond // 1000:03d}Z')" 2>/dev/null && return 0
  fi
  date -u +"%Y-%m-%dT%H:%M:%S.000Z"
}

# _prov_now_us
# Emit microseconds since epoch.
_prov_now_us() {
  if command -v gdate >/dev/null 2>&1; then
    local ns
    ns=$(gdate +%s%N 2>/dev/null) && echo $((ns / 1000)) && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null && return 0
  fi
  echo $(($(date +%s) * 1000000))
}

# _prov_resolve_state_dir <loop_id>
# Returns the state_dir for a given loop_id, or empty string if not in registry.
_prov_resolve_state_dir() {
  local loop_id="$1"
  [ -z "$loop_id" ] && return 0
  if ! command -v read_registry_entry >/dev/null 2>&1; then
    return 0
  fi
  local entry
  entry=$(read_registry_entry "$loop_id" 2>/dev/null) || return 0
  [ -z "$entry" ] && return 0
  [ "$entry" = "{}" ] && return 0
  echo "$entry" | jq -r '.state_dir // empty' 2>/dev/null | sed 's:/*$::'
}

# _prov_atomic_append <file> <content>
# Append a single JSON line to file with cross-platform locking (flock on Linux,
# lockf on macOS, POSIX O_APPEND fallback otherwise). Returns 0 always (graceful).
#
# JSON lines are well under PIPE_BUF (4096 bytes), so `>>` is atomic per POSIX
# even without explicit locking — but we lock anyway for defence-in-depth and to
# serialize against rotation operations.
_prov_atomic_append() {
  local target="$1"
  local content="$2"
  local lockfile="$target.lock"

  # Ensure parent exists
  mkdir -p "$(dirname "$target")" 2>/dev/null || return 0
  touch "$lockfile" 2>/dev/null || true

  if command -v flock >/dev/null 2>&1; then
    # Linux (or macOS with util-linux): flock with fd 9 in subshell
    (
      exec 9>>"$lockfile" 2>/dev/null || exit 0
      flock -x -w 5 9 2>/dev/null || exit 0
      printf '%s\n' "$content" >>"$target" 2>/dev/null || exit 0
    ) || true
  elif command -v lockf >/dev/null 2>&1; then
    # macOS (BSD lockf): retry-with-sleep, then perform the append under the lock
    local retries=50
    while ! lockf -t 0 "$lockfile" sh -c "printf '%s\n' \"\$0\" >> \"\$1\" 2>/dev/null" "$content" "$target" 2>/dev/null; do
      retries=$((retries - 1))
      if [ "$retries" -le 0 ]; then
        # Lock contention timeout — fall through to unlocked append (POSIX O_APPEND atomic for <PIPE_BUF)
        printf '%s\n' "$content" >>"$target" 2>/dev/null || true
        break
      fi
      sleep 0.1
    done
  else
    # No lock tool: rely on POSIX O_APPEND atomicity (safe for lines < PIPE_BUF=4096B)
    printf '%s\n' "$content" >>"$target" 2>/dev/null || true
  fi

  return 0
}

# emit_provenance <loop_id> <event> [field=value ...]
# Writes one schema-versioned JSONL line to:
#   1. <state_dir>/provenance.jsonl (skipped if state_dir unresolvable)
#   2. ~/.claude/loops/global-provenance.jsonl (always)
#
# Required positional arguments:
#   $1 — loop_id (12 hex chars; "" allowed for orphan events)
#   $2 — event (string from event vocabulary; not enforced — open for v2 evolution)
#
# Optional named arguments (key=value):
#   session_id, cwd_observed, cwd_bound, registry_generation,
#   owner_pid_before, owner_pid_after, reason, decision
#
# Override agent name via _PROV_AGENT env var (defaults to BASH_SOURCE[1] basename).
#
# Output: nothing on stdout. Errors silently (returns 0 always).
emit_provenance() {
  local loop_id="${1:-}"
  local event="${2:-}"
  shift 2 || true

  # Validate event is non-empty (degraded silent return 0 on empty — fail-graceful)
  [ -z "$event" ] && return 0

  # Auto-detect agent if not overridden
  local agent="${_PROV_AGENT:-}"
  if [ -z "$agent" ]; then
    agent="$(basename "${BASH_SOURCE[1]:-$0}")"
  fi

  # Parse named args into local vars
  local session_id="" cwd_observed="" cwd_bound=""
  local registry_generation="" owner_pid_before="" owner_pid_after=""
  local reason="" decision=""
  local kv key val
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    case "$key" in
      session_id)          session_id="$val" ;;
      cwd_observed)        cwd_observed="$val" ;;
      cwd_bound)           cwd_bound="$val" ;;
      registry_generation) registry_generation="$val" ;;
      owner_pid_before)    owner_pid_before="$val" ;;
      owner_pid_after)     owner_pid_after="$val" ;;
      reason)              reason="$val" ;;
      decision)            decision="$val" ;;
      *) ;;  # silently ignore unknown fields (forward-compat)
    esac
  done

  local ts_iso ts_us
  ts_iso=$(_prov_now_iso)
  ts_us=$(_prov_now_us)

  # Build the JSON line. Use jq -n to ensure valid JSON output.
  # Numeric fields use --argjson with null fallback; strings use --arg.
  local json_line
  json_line=$(jq -nc \
    --arg ts_iso "$ts_iso" \
    --argjson ts_us "${ts_us:-0}" \
    --arg event "$event" \
    --arg loop_id "$loop_id" \
    --arg agent "$agent" \
    --arg session_id "$session_id" \
    --arg cwd_observed "$cwd_observed" \
    --arg cwd_bound "$cwd_bound" \
    --arg registry_generation "$registry_generation" \
    --arg owner_pid_before "$owner_pid_before" \
    --arg owner_pid_after "$owner_pid_after" \
    --arg reason "$reason" \
    --arg decision "$decision" \
    --argjson schema_version "$PROVENANCE_SCHEMA_VERSION" \
    '{
      ts_iso: $ts_iso,
      ts_us: $ts_us,
      event: $event,
      loop_id: ($loop_id | if . == "" then null else . end),
      agent: $agent,
      session_id: ($session_id | if . == "" then null else . end),
      cwd_observed: ($cwd_observed | if . == "" then null else . end),
      cwd_bound: ($cwd_bound | if . == "" then null else . end),
      registry_generation: ($registry_generation | if . == "" then null else (tonumber? // .) end),
      owner_pid_before: ($owner_pid_before | if . == "" then null else (tonumber? // .) end),
      owner_pid_after: ($owner_pid_after | if . == "" then null else (tonumber? // .) end),
      reason: ($reason | if . == "" then null else . end),
      decision: ($decision | if . == "" then null else . end),
      schema_version: $schema_version
    }' 2>/dev/null) || return 0

  [ -z "$json_line" ] && return 0

  # Write 1: per-loop ledger (skip if state_dir unresolvable)
  local state_dir
  state_dir=$(_prov_resolve_state_dir "$loop_id")
  if [ -n "$state_dir" ] && [ -d "$state_dir" ]; then
    _prov_atomic_append "$state_dir/provenance.jsonl" "$json_line"
  fi

  # Write 2: global mirror (always)
  mkdir -p "$PROVENANCE_GLOBAL_DIR" 2>/dev/null || return 0
  _prov_atomic_append "$PROVENANCE_GLOBAL_FILE" "$json_line"

  return 0
}

# rotate_global_provenance
# Idempotent. If global mirror exceeds PROVENANCE_ROTATION_THRESHOLD lines,
# move the oldest (count - PROVENANCE_ROTATION_KEEP) lines to a gzipped archive.
# Archive name: global-provenance.<unixts>.jsonl.gz
#
# Output: nothing on stdout. Errors print to stderr but return 0 (graceful).
rotate_global_provenance() {
  local target="$PROVENANCE_GLOBAL_FILE"
  [ -f "$target" ] || return 0

  local lines
  lines=$(wc -l <"$target" 2>/dev/null | tr -d ' ')
  [ -z "$lines" ] && return 0
  if [ "$lines" -le "$PROVENANCE_ROTATION_THRESHOLD" ]; then
    return 0
  fi

  local keep="$PROVENANCE_ROTATION_KEEP"
  local archive_count=$((lines - keep))
  [ "$archive_count" -le 0 ] && return 0

  local ts archive_path
  ts=$(date +%s)
  archive_path="$PROVENANCE_GLOBAL_DIR/global-provenance.${ts}.jsonl"

  # Rotation body — runs under whatever lock primitive is available.
  _prov_rotate_body() {
    local target="$1" archive_path="$2" keep="$3" threshold="$4"

    local now_lines
    now_lines=$(wc -l <"$target" 2>/dev/null | tr -d ' ')
    [ -z "$now_lines" ] && return 0
    if [ "$now_lines" -le "$threshold" ]; then
      return 0
    fi
    local archive_count=$((now_lines - keep))
    [ "$archive_count" -le 0 ] && return 0

    local tmp_remainder
    tmp_remainder=$(mktemp "$target.rotate.XXXXXX") || return 0

    head -n "$archive_count" "$target" >"$archive_path" 2>/dev/null || {
      rm -f "$tmp_remainder" "$archive_path"
      return 0
    }
    tail -n "$keep" "$target" >"$tmp_remainder" 2>/dev/null || {
      rm -f "$tmp_remainder" "$archive_path"
      return 0
    }
    mv "$tmp_remainder" "$target" || {
      rm -f "$tmp_remainder" "$archive_path"
      return 0
    }
    gzip -f "$archive_path" 2>/dev/null || true
    return 0
  }

  local lockfile="$target.lock"
  touch "$lockfile" 2>/dev/null || true

  if command -v flock >/dev/null 2>&1; then
    (
      exec 9>>"$lockfile" 2>/dev/null || exit 0
      flock -x -w 10 9 2>/dev/null || exit 0
      _prov_rotate_body "$target" "$archive_path" "$keep" "$PROVENANCE_ROTATION_THRESHOLD"
    ) || true
  elif command -v lockf >/dev/null 2>&1; then
    local retries=100  # ~10 seconds
    while ! lockf -t 0 "$lockfile" true 2>/dev/null; do
      retries=$((retries - 1))
      if [ "$retries" -le 0 ]; then
        return 0
      fi
      sleep 0.1
    done
    # Re-check and perform; lockf above only acquired-and-released, so we run unlocked.
    # Acceptable: rotation under high contention is rare; idempotent on retry.
    _prov_rotate_body "$target" "$archive_path" "$keep" "$PROVENANCE_ROTATION_THRESHOLD"
  else
    _prov_rotate_body "$target" "$archive_path" "$keep" "$PROVENANCE_ROTATION_THRESHOLD"
  fi

  return 0
}
