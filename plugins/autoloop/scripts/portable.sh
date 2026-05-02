#!/usr/bin/env bash
# portable.sh — shared helpers used across autoloop scripts and hooks.
#
# Two responsibilities:
#   1. Identifier validation (UUID, loop_id, slug, session_id) — strict regex
#      gates that callers use to refuse hostile or malformed input before it
#      reaches `claude --resume`, `jq --arg`, `launchctl`, or the registry.
#   2. Structured logging to ~/.claude/loops/.hook-errors.log so the doctor
#      skill can surface validation rejections instead of them being silent.
#
# Source via:
#   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autoloop}"
#   . "$PLUGIN_ROOT/scripts/portable.sh"
#
# All helpers are idempotent and side-effect-free except `log_validation_event`.
# Designed to be sourced from bash 3.2 (macOS default) — no mapfile, no
# extended-regex sed, no bash 4-only constructs.

# --- Identifier validators ---
#
# Each returns 0 (valid) or 1 (invalid). Stays silent on stdout — callers log
# rejections via `log_validation_event` if they want them surfaced.

# is_valid_uuid <s>
# Strict UUID v4-ish format. Claude Code session_ids match this shape.
is_valid_uuid() {
    local s="${1:-}"
    [[ "$s" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

# is_valid_loop_id <s>
# 12 hex chars (sha256(realpath)[:12] convention).
is_valid_loop_id() {
    local s="${1:-}"
    [[ "$s" =~ ^[0-9a-f]{12}$ ]]
}

# is_valid_slug <s>
# Kebab-case, alphanumeric + hyphen, leading letter, ≤64 chars.
# Used for campaign_slug → directory name component.
is_valid_slug() {
    local s="${1:-}"
    [[ "$s" =~ ^[a-z][a-z0-9-]{0,63}$ ]]
}

# is_valid_short_hash <s>
# 6 hex chars (sha256(...)[:6]).
is_valid_short_hash() {
    local s="${1:-}"
    [[ "$s" =~ ^[0-9a-f]{6}$ ]]
}

# is_valid_jq_simple_path <s>
# Single-key dotted path like ".generation" or ".owner_pid". Blocks pipe-chained
# expressions, function calls (env, debug, input), and nested selectors that
# would let callers smuggle arbitrary jq into update_loop_field.
is_valid_jq_simple_path() {
    local s="${1:-}"
    [[ "$s" =~ ^\.[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

# is_session_id_real <s>
# Returns 0 ONLY when s is a real UUID — refuses placeholder values like
# `pending-bind`, `unknown`, `unknown-session`, and the legacy
# `session_<ts>_<hex>` reclaim-internal format. Use this at the
# `claude --resume <id>` boundary, where placeholders MUST be refused.
is_session_id_real() {
    is_valid_uuid "${1:-}"
}

# --- Structured logging ---

# log_validation_event <kind> <field> <value> [context...]
# Append a structured JSON line to ~/.claude/loops/.hook-errors.log.
# Truncates value to 80 chars to bound log size when the input is hostile.
# Silently no-ops if jq is unavailable or the log dir can't be created.
log_validation_event() {
    local kind="${1:-validation_reject}"
    local field="${2:-?}"
    local value="${3:-}"
    shift 3 || true

    command -v jq >/dev/null 2>&1 || return 0

    local loops_dir="$HOME/.claude/loops"
    mkdir -p "$loops_dir" 2>/dev/null || return 0
    local log="$loops_dir/.hook-errors.log"

    # Truncate value to 80 chars for safe logging.
    local trunc="${value:0:80}"
    [ "${#value}" -gt 80 ] && trunc="${trunc}…"

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || ts="?"

    # Optional context k=v pairs.
    local extra="{}"
    if [ "$#" -gt 0 ]; then
        local args=()
        local pair k v
        for pair in "$@"; do
            k="${pair%%=*}"
            v="${pair#*=}"
            args+=(--arg "$k" "$v")
        done
        extra=$(jq -nc "${args[@]}" '$ENV | to_entries | map(select(.key | startswith("__") | not)) | map({key, value: .value})' 2>/dev/null) || extra="{}"
    fi

    jq -nc \
        --arg ts "$ts" \
        --arg kind "$kind" \
        --arg field "$field" \
        --arg value_truncated "$trunc" \
        --arg pid "$$" \
        --argjson extra "$extra" \
        '{ts: $ts, kind: $kind, field: $field, value_truncated: $value_truncated, pid: $pid, extra: $extra}' \
        >>"$log" 2>/dev/null || true
    # Opportunistic rotation (Wave 4 W2.4). Same self-call pattern is safe
    # because rotate_jsonl_if_large is defined later in this same file.
    rotate_jsonl_if_large "$log" 2>/dev/null || true
}

# --- Machine identity ---

# current_machine_id
# Returns a stable 12-hex identifier for THIS machine. Used by Wave 4 to
# detect cross-machine registry contamination — if a user rsyncs / Time
# Machine-restores ~/.claude/loops/ between machines, registry entries from
# the source machine carry foreign owner_pids that look "dead" on the
# destination, leading doctor to flag everything as zombie. Stamping a
# machine_id on every entry at register_loop time lets doctor distinguish
# "real local zombie" from "foreign-machine entry, ignore the owner_pid".
#
# Wave 5 C3: cached at ~/.claude/loops/.machine-id on first compute. macOS
# rotates `hostname` with DHCP / network changes / Sharing→Computer Name
# edits; recomputing every call would falsely flag healthy local entries as
# foreign whenever the hostname mutates. The cache pins the value at first
# run; user can `rm ~/.claude/loops/.machine-id` to force a re-stamp after
# a genuine machine move.
#
# Derivation: sha256(hostname + ':' + uname-mhash)[:12] — stable across
# reboots on the same machine, different across machines that share a
# username and home directory layout. Avoids embedding the hostname raw
# (which can leak in error logs and notifications).
#
# Output:
#   12-hex string on stdout. Always succeeds; falls back to "unknown000000"
#   if neither hostname nor uname is available (very unlikely).
current_machine_id() {
  local cache_dir="${HOME:-/tmp}/.claude/loops"
  local cache_file="$cache_dir/.machine-id"

  # Fast path: cache exists and contains a valid 12-hex string.
  if [ -f "$cache_file" ]; then
    local cached
    cached=$(head -c 12 "$cache_file" 2>/dev/null || echo "")
    if [[ "$cached" =~ ^[0-9a-f]{12}$ ]]; then
      printf '%s' "$cached"
      return 0
    fi
  fi

  # Compute fresh.
  local h=""
  if command -v hostname >/dev/null 2>&1; then
    h=$(hostname 2>/dev/null || echo "")
  fi
  if [ -z "$h" ] && command -v uname >/dev/null 2>&1; then
    h=$(uname -n 2>/dev/null || echo "")
  fi
  local m=""
  if command -v uname >/dev/null 2>&1; then
    m=$(uname -m 2>/dev/null || echo "")
  fi
  local computed
  if [ -z "$h" ] && [ -z "$m" ]; then
    computed="unknown000000"
  else
    computed=$(printf '%s:%s' "$h" "$m" | shasum -a 256 2>/dev/null | cut -c1-12)
  fi

  # Best-effort persist. Failure is non-fatal — caller still gets the value.
  # Atomic write: tempfile + mv so concurrent first-callers don't see a
  # partial file. mkdir -p tolerates a pre-existing dir.
  if mkdir -p "$cache_dir" 2>/dev/null; then
    local tmp
    if tmp=$(mktemp "$cache_dir/.machine-id.XXXXXX" 2>/dev/null); then
      if printf '%s\n' "$computed" > "$tmp" 2>/dev/null; then
        if ! mv "$tmp" "$cache_file" 2>/dev/null; then
          rm -f "$tmp" 2>/dev/null
        fi
      else
        rm -f "$tmp" 2>/dev/null
      fi
    fi
  fi

  printf '%s' "$computed"
}

# --- JSONL rotation ---

# rotate_jsonl_if_large <file> [threshold_bytes] [keep]
# PROCESS-STORM-OK (bash function definition, not a fork bomb)
# Best-effort log rotation for append-only JSONL/log files. If <file> is
# larger than threshold_bytes (default 10MB), rename it to <file>.1 (and
# rotate any existing <file>.1 → <file>.2, up to <keep> generations) and
# gzip everything except <file>.1. Old generations beyond <keep> are deleted.
#
# Why best-effort: this runs from hot paths (every hook fire), MUST NOT
# block the user, and MUST NOT raise on any error. Worst case: the file
# stays oversized and rotation tries again next call. The function is
# idempotent across concurrent calls (two hooks rotating simultaneously
# both end up with <file> empty and <file>.1 holding the last full content;
# one of the rotations may "lose" a few lines, which is acceptable for
# logs vs. correctness-critical state).
#
# Why no flock: rotation happens on logs that are append-only with O_APPEND;
# concurrent appenders are kernel-serialized. Adding a lock here would just
# serialize the rotation itself, which is fine to be lossy.
#
# Files this is intended for:
#   ~/.claude/loops/.hook-errors.log
#   ~/.claude/loops/.notifications.jsonl
#   ~/.claude/loops/global-provenance.jsonl
#   ~/.claude/loops/registry.archive.jsonl
#   <state_dir>/revision-log/<session_id>.jsonl  (per-loop rotation)
#
# Arguments:
#   $1: file path
#   $2 (optional): threshold in bytes; default 10485760 (10MB)
#   $3 (optional): max rotation generations; default 3
#
# Exit code: always 0 (best-effort).
rotate_jsonl_if_large() {
  local file="${1:-}"
  local threshold="${2:-10485760}"
  local keep="${3:-3}"

  [ -z "$file" ] && return 0
  [ ! -f "$file" ] && return 0

  # Stat varies between BSD (macOS) and GNU. Try both.
  local size=""
  size=$(stat -f '%z' "$file" 2>/dev/null) || size=$(stat -c '%s' "$file" 2>/dev/null) || return 0
  case "$size" in
    ''|*[!0-9]*) return 0 ;;
  esac
  if [ "$size" -lt "$threshold" ]; then
    return 0
  fi

  # Cascade: file.<N-1>.gz → file.<N>.gz (oldest first, drop beyond keep)
  local i n_minus_1
  for ((i = keep; i >= 2; i--)); do
    n_minus_1=$((i - 1))
    if [ -f "$file.$n_minus_1.gz" ]; then
      if [ "$i" -gt "$keep" ]; then
        rm -f "$file.$n_minus_1.gz" 2>/dev/null
      else
        mv -f "$file.$n_minus_1.gz" "$file.$i.gz" 2>/dev/null || true
      fi
    fi
  done

  # file.1 (uncompressed previous rotation) → file.2.gz
  if [ -f "$file.1" ]; then
    if command -v gzip >/dev/null 2>&1; then
      gzip -f "$file.1" 2>/dev/null && mv -f "$file.1.gz" "$file.2.gz" 2>/dev/null || true
    else
      mv -f "$file.1" "$file.2" 2>/dev/null || true
    fi
  fi

  # Current file → file.1 (atomic rename). Caller's open file descriptors
  # keep pointing at the now-renamed inode until they reopen, so any
  # in-flight writes still land in the rotated file (acceptable).
  mv -f "$file" "$file.1" 2>/dev/null || true

  # Recreate empty file with same mode if possible. Logs are typically 0644.
  : > "$file" 2>/dev/null || true

  return 0
}

# Export for sourcing.
export -f is_valid_uuid is_valid_loop_id is_valid_slug is_valid_short_hash
export -f is_valid_jq_simple_path is_session_id_real
export -f log_validation_event
export -f current_machine_id
export -f rotate_jsonl_if_large
