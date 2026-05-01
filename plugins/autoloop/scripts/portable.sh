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
}

# Export for sourcing.
export -f is_valid_uuid is_valid_loop_id is_valid_slug is_valid_short_hash
export -f is_valid_jq_simple_path is_session_id_real
export -f log_validation_event
