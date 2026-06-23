#!/usr/bin/env bash
#
# pushover-notify.sh — verbatim+UUID-linked Pushover notification sender
#
# Pattern (iter 5, 2026-05-19):
#   - Generates UUID v4 per call; binds it to the run
#   - Writes COMPLETE verbatim payload to JSONL at
#     ~/.local/state/pushover/audit-YYYYMMDD.jsonl (one event per line)
#   - Sends a Pushover message containing the UUID, a short summary, and
#     a `pushover-lookup <UUID>` command the recipient can run/paste back
#     to retrieve the full verbatim entry. Pushover message body capped
#     at 1024 chars (per pushover.net/api); use the JSONL for the long tail.
#   - Credentials come from 1Password Claude Automation vault by default
#     (item <pushover-item>). Override via env for testing.
#
# Usage:
#   pushover-notify.sh \
#       --title "maccy-backup failure" \
#       --message "DB unreadable for 31 days" \
#       --service maccy-backup \
#       --actor launchd \
#       --target "Storage.sqlite" \
#       --level ERROR \
#       --priority 1 \
#       --extra '{"db_path":"/Users/.../Maccy/Storage.sqlite","last_success":"2026-04-17"}'
#
# Required flags: --title, --message, --service
# Optional flags: --actor, --target, --level, --priority, --extra, --ttl
#
# Exit codes:
#   0 = sent + logged successfully
#   1 = parse error / missing required flag
#   2 = JSONL write failed (no notification sent — fail loud)
#   3 = Pushover API call failed (JSONL written, alert delivery lost)
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

readonly LOG_DIR="${PUSHOVER_LOG_DIR:-$HOME/.local/state/pushover}"
# iter-53 SC2155: split `readonly LOG_FILE=$(... cmd ...)` declare-from-assign.
# The combined form masks the command-substitution exit code because
# `readonly` returns 0 regardless of whether the substitution succeeded.
# `date -u` essentially never fails, so this is defensive consistency
# (matching iter-37's high-impact SC2155 sweep) rather than an active
# hazard. The two-line split makes `date`'s exit code propagate via
# set -e on a clock-skew-broken VM or other unusual failure mode.
LOG_FILE="${LOG_DIR}/audit-$(/bin/date -u +%Y%m%d).jsonl"
readonly LOG_FILE
readonly MAX_BODY_CHARS=1024   # Pushover API limit (UTF-8)
readonly MAX_TITLE_CHARS=250   # Pushover API limit

# 1Password item holding cc-skills Pushover credentials.
# Override via env (PUSHOVER_TOKEN, PUSHOVER_USER) for testing or non-1P flows.
readonly OP_VAULT="Claude Automation"
readonly OP_ITEM_ID="${PUSHOVER_OP_ITEM_ID:-<pushover-item>}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { echo "pushover-notify: ERROR: $*" >&2; exit "${2:-1}"; }

usage() {
    /bin/cat <<'USAGE_EOF'
pushover-notify.sh — send Pushover notification with UUID+JSONL audit trail

REQUIRED:
  --title <text>      Pushover notification title (≤250 chars)
  --message <text>    Short summary (≤500 chars recommended; pushover body capped at 1024 total)
  --service <name>    Service/script emitting the event (e.g. "maccy-backup")

OPTIONAL:
  --actor <name>      Who triggered it (default: $USER)
  --target <name>     Object operated on
  --level <lvl>       INFO|WARN|ERROR (default: INFO; influences default priority)
  --priority <-2..2>  Pushover priority. Default -1=INFO, 0=WARN, 1=ERROR, 2=panic
  --ttl <seconds>     Auto-expire on device after N seconds (low-signal events)
  --device <name>     Send only to specified Pushover device (e.g. iphone_13_mini)
  --sound <name>      Pushover sound (e.g. siren, magic, intermission, none)
  --extra <json>      Extra structured fields, merged into JSONL entry
  --help              This help

ENVIRONMENT:
  PUSHOVER_TOKEN      Override token (skip 1P lookup)
  PUSHOVER_USER       Override user key (skip 1P lookup)
  PUSHOVER_LOG_DIR    Override JSONL log directory (default ~/.local/state/pushover)
  NO_PUSHOVER=1       Write JSONL only, skip remote send (dry run)
USAGE_EOF
}

# Generate a UUID v4. macOS has uuidgen; Linux has it in util-linux.
gen_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        die "no UUID generator (install uuidgen or run on Linux with /proc)" 1
    fi
}

# Look up Pushover credentials from 1Password using SA token first, biometric fallback
load_credentials() {
    if [ -n "${PUSHOVER_TOKEN:-}" ] && [ -n "${PUSHOVER_USER:-}" ]; then
        return 0  # already overridden
    fi

    # Proxy bypass — Claude Code OAuth proxy returns 502 on 1P endpoints
    local saved_https_proxy="${HTTPS_PROXY:-}"
    local saved_http_proxy="${HTTP_PROXY:-}"
    unset HTTPS_PROXY HTTP_PROXY 2>/dev/null || true

    local sa_token_path="$HOME/.claude/.secrets/op-service-account-token"
    if [ -r "$sa_token_path" ]; then
        # Try SA token first
        local sa_token
        sa_token=$(/bin/cat "$sa_token_path")
        export OP_SERVICE_ACCOUNT_TOKEN="$sa_token"
        if PUSHOVER_TOKEN=$(op read "op://${OP_VAULT}/${OP_ITEM_ID}/credential" 2>/dev/null); then
            PUSHOVER_USER=$(op read "op://${OP_VAULT}/${OP_ITEM_ID}/user_key" 2>/dev/null) || PUSHOVER_USER=""
            unset OP_SERVICE_ACCOUNT_TOKEN
        else
            # SA failed; try biometric (will prompt if interactive)
            unset OP_SERVICE_ACCOUNT_TOKEN
            PUSHOVER_TOKEN=$(op read "op://${OP_VAULT}/${OP_ITEM_ID}/credential" 2>/dev/null) || PUSHOVER_TOKEN=""
            PUSHOVER_USER=$(op read "op://${OP_VAULT}/${OP_ITEM_ID}/user_key" 2>/dev/null) || PUSHOVER_USER=""
        fi
    fi

    # Restore proxy state for caller
    [ -n "$saved_https_proxy" ] && export HTTPS_PROXY="$saved_https_proxy"
    [ -n "$saved_http_proxy" ] && export HTTP_PROXY="$saved_http_proxy"

    if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER:-}" ]; then
        die "could not load Pushover credentials from 1P (item ${OP_ITEM_ID} in ${OP_VAULT})" 1
    fi
}

# Default priority from level
default_priority_for_level() {
    case "$1" in
        ERROR) echo 1 ;;
        WARN)  echo 0 ;;
        INFO)  echo -1 ;;
        *)     echo 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

TITLE=""
MESSAGE=""
SERVICE=""
ACTOR="${USER:-unknown}"
TARGET=""
LEVEL="INFO"
PRIORITY=""
TTL=""
EXTRA_JSON="{}"
DEVICE=""   # iter 14: optional Pushover device name (e.g. iphone_13_mini); empty = all devices
SOUND=""    # iter 14: optional Pushover sound name (e.g. siren, magic, etc.); empty = default

while [ $# -gt 0 ]; do
    case "$1" in
        --title)    TITLE="$2"; shift 2 ;;
        --message)  MESSAGE="$2"; shift 2 ;;
        --service)  SERVICE="$2"; shift 2 ;;
        --actor)    ACTOR="$2"; shift 2 ;;
        --target)   TARGET="$2"; shift 2 ;;
        --level)    LEVEL="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        --ttl)      TTL="$2"; shift 2 ;;
        --extra)    EXTRA_JSON="$2"; shift 2 ;;
        --device)   DEVICE="$2"; shift 2 ;;
        --sound)    SOUND="$2"; shift 2 ;;
        --help|-h)  usage; exit 0 ;;
        *)          die "unknown flag: $1" 1 ;;
    esac
done

[ -z "$TITLE" ]   && { usage >&2; die "missing --title" 1; }
[ -z "$MESSAGE" ] && { usage >&2; die "missing --message" 1; }
[ -z "$SERVICE" ] && { usage >&2; die "missing --service" 1; }
[ -z "$PRIORITY" ] && PRIORITY="$(default_priority_for_level "$LEVEL")"

# Validate --extra is valid JSON object
if ! echo "$EXTRA_JSON" | /usr/bin/jq -e 'type == "object"' >/dev/null 2>&1; then
    die "--extra must be a JSON object" 1
fi

# ---------------------------------------------------------------------------
# Build the verbatim JSONL entry
# ---------------------------------------------------------------------------

UUID=$(gen_uuid)
# Prefer millisecond precision via GNU date (if installed via coreutils);
# fall back to second precision on stock macOS BSD date.
if TS=$(/opt/homebrew/opt/coreutils/libexec/gnubin/date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null); then
    :  # gnubin date worked
elif TS=$(gdate -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null); then
    :  # gdate worked (homebrew coreutils default install)
else
    TS=$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")
fi
HOST=$(/bin/hostname -s 2>/dev/null || echo unknown)

# Build the canonical JSONL entry — keeps full verbatim context.
# Schema: run_id (UUID), ts (ISO8601), host, service, actor, target, level,
# title, message, priority, ttl (if set), device (if set, iter 14),
# sound (if set, iter 14), extra (any extra fields).
JSONL_ENTRY=$(/usr/bin/jq -c -n \
    --arg run_id "$UUID" \
    --arg ts "$TS" \
    --arg host "$HOST" \
    --arg service "$SERVICE" \
    --arg actor "$ACTOR" \
    --arg target "$TARGET" \
    --arg level "$LEVEL" \
    --arg title "$TITLE" \
    --arg message "$MESSAGE" \
    --argjson priority "$PRIORITY" \
    --arg ttl "$TTL" \
    --arg device "$DEVICE" \
    --arg sound "$SOUND" \
    --argjson extra "$EXTRA_JSON" \
    '{
        run_id: $run_id,
        ts: $ts,
        host: $host,
        service: $service,
        actor: $actor,
        target: (if $target == "" then null else $target end),
        level: $level,
        title: $title,
        message: $message,
        priority: $priority,
        ttl: (if $ttl == "" then null else ($ttl | tonumber) end),
        device: (if $device == "" then null else $device end),
        sound: (if $sound == "" then null else $sound end),
        extra: $extra
    } | with_entries(select(.value != null))')

# ---------------------------------------------------------------------------
# Write JSONL FIRST (the durable side; alert can fail-soft)
# ---------------------------------------------------------------------------

/bin/mkdir -p "$LOG_DIR" || die "cannot create log dir $LOG_DIR" 2
if ! echo "$JSONL_ENTRY" >> "$LOG_FILE"; then
    die "JSONL append failed to $LOG_FILE" 2
fi

# ---------------------------------------------------------------------------
# Build the Pushover message body — verbatim within Pushover's 1024-char limit
# ---------------------------------------------------------------------------

# Compose the body: include UUID prominently + service + level + message + lookup
# command. Build, then check length; if over, truncate the user message to fit.
LOOKUP_CMD="pushover-lookup ${UUID}"

build_body() {
    local user_message="$1"
    /usr/bin/printf '%s\n%s%s %s\nlevel=%s priority=%s%s\n\nlookup: %s\n\nUUID: %s' \
        "$user_message" \
        "[$SERVICE]" \
        "${TARGET:+ → $TARGET}" \
        "${ACTOR:+(by $ACTOR)}" \
        "$LEVEL" \
        "$PRIORITY" \
        "${TTL:+ ttl=${TTL}s}" \
        "$LOOKUP_CMD" \
        "$UUID"
}

BODY=$(build_body "$MESSAGE")
BODY_BYTES=$(echo -n "$BODY" | /usr/bin/wc -c | tr -d ' ')

# If over the limit, truncate the user message portion until total fits
if [ "$BODY_BYTES" -gt "$MAX_BODY_CHARS" ]; then
    OVERAGE=$(( BODY_BYTES - MAX_BODY_CHARS + 4 ))  # +4 for "..." + safety
    MSG_LEN=${#MESSAGE}
    KEEP_LEN=$(( MSG_LEN - OVERAGE ))
    [ "$KEEP_LEN" -lt 20 ] && KEEP_LEN=20  # always keep at least 20 chars
    TRUNCATED=$(echo -n "$MESSAGE" | /usr/bin/head -c "$KEEP_LEN")
    BODY=$(build_body "${TRUNCATED}...")
fi

# Title is shorter — truncate aggressively if needed
TITLE_BYTES=$(echo -n "$TITLE" | /usr/bin/wc -c | tr -d ' ')
if [ "$TITLE_BYTES" -gt "$MAX_TITLE_CHARS" ]; then
    TITLE=$(echo -n "$TITLE" | /usr/bin/head -c $(( MAX_TITLE_CHARS - 3 )))...
fi

# ---------------------------------------------------------------------------
# Dispatch — Pushover API call (unless --no-pushover env or NO_PUSHOVER=1)
# ---------------------------------------------------------------------------

if [ "${NO_PUSHOVER:-0}" = "1" ]; then
    echo "$UUID"  # stdout: just the UUID so callers can capture it
    exit 0
fi

load_credentials

# Bypass HTTPS_PROXY for Pushover (proxy returns 502 on api.pushover.net)
unset HTTPS_PROXY HTTP_PROXY 2>/dev/null || true

# Build curl args. Use --noproxy '*' for extra safety in case env is locked.
CURL_ARGS=(
    --noproxy '*'
    --max-time 10
    -s
    -X POST "https://api.pushover.net/1/messages.json"
    --data-urlencode "token=$PUSHOVER_TOKEN"
    --data-urlencode "user=$PUSHOVER_USER"
    --data-urlencode "title=$TITLE"
    --data-urlencode "message=$BODY"
    --data-urlencode "priority=$PRIORITY"
)

[ -n "$TTL" ] && CURL_ARGS+=( --data-urlencode "ttl=$TTL" )

# Iter 14: optional device targeting + sound override
[ -n "$DEVICE" ] && CURL_ARGS+=( --data-urlencode "device=$DEVICE" )
[ -n "$SOUND" ] && CURL_ARGS+=( --data-urlencode "sound=$SOUND" )

# Emergency priority requires retry/expire params; default conservative values
if [ "$PRIORITY" = "2" ]; then
    CURL_ARGS+=(
        --data-urlencode "retry=30"
        --data-urlencode "expire=600"
    )
fi

RESPONSE=$(/usr/bin/curl "${CURL_ARGS[@]}" 2>&1) || {
    # Network failed — JSONL already written, log the dispatch failure
    /usr/bin/jq -c -n \
        --arg run_id "$UUID" \
        --arg ts "$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg detail "$RESPONSE" \
        '{run_id: $run_id, ts: $ts, service: "pushover-notify", level: "WARN", message: "dispatch_failed", detail: $detail}' \
        >> "$LOG_FILE"
    echo "$UUID"
    exit 3
}

# Parse response for success flag
if echo "$RESPONSE" | /usr/bin/jq -e '.status == 1' >/dev/null 2>&1; then
    # Save the receipt (if emergency priority returned one)
    RECEIPT=$(echo "$RESPONSE" | /usr/bin/jq -r '.receipt // empty')
    REQUEST_ID=$(echo "$RESPONSE" | /usr/bin/jq -r '.request // empty')
    if [ -n "$RECEIPT" ] || [ -n "$REQUEST_ID" ]; then
        /usr/bin/jq -c -n \
            --arg run_id "$UUID" \
            --arg ts "$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            --arg receipt "$RECEIPT" \
            --arg request_id "$REQUEST_ID" \
            '{run_id: $run_id, ts: $ts, service: "pushover-notify", level: "INFO", message: "dispatched", receipt: $receipt, pushover_request: $request_id}' \
            >> "$LOG_FILE"
    fi
    echo "$UUID"
    exit 0
else
    /usr/bin/jq -c -n \
        --arg run_id "$UUID" \
        --arg ts "$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg response "$RESPONSE" \
        '{run_id: $run_id, ts: $ts, service: "pushover-notify", level: "ERROR", message: "api_rejected", detail: $response}' \
        >> "$LOG_FILE"
    echo "$UUID"
    exit 3
fi
