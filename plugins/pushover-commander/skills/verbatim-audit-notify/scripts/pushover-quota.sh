#!/usr/bin/env bash
#
# pushover-quota.sh — monthly quota monitor for the pushover-verbatim-notify skill
#
# Companion to pushover-notify.sh / pushover-lookup.sh / pushover-prune.sh.
#
# Why this exists (iter 12b, 2026-05-19):
#   Pushover's free/personal tier caps each app token at 10,000 messages per
#   calendar month. Hitting the cap silently drops new notifications until
#   the month resets. We built the verbatim-notify observability infra but
#   had no visibility into our own quota — eat-own-dogfood gap.
#
# Behavior:
#   - Calls Pushover's /1/apps/limits.json endpoint with our app token
#   - Persists the response to ~/.local/state/pushover/quota.json (atomic write)
#   - If --alert-threshold is set and `remaining < limit * threshold`, fires
#     a pushover-notify with WARN level so we get a heads-up before exhaustion
#
# Usage:
#   pushover-quota                           # check + persist (no alert)
#   pushover-quota --alert-threshold 0.20    # alert at <20% remaining (Recommended)
#   pushover-quota --json-only               # print JSON to stdout, skip persist+alert
#   pushover-quota --help
#
# Exit codes:
#   0 = success (quota retrieved + persisted)
#   1 = parse error / missing creds
#   2 = network error / unparseable response
#

set -euo pipefail

readonly LOG_DIR="${PUSHOVER_LOG_DIR:-$HOME/.local/state/pushover}"
readonly QUOTA_FILE="${LOG_DIR}/quota.json"
readonly OP_VAULT="Claude Automation"
readonly OP_ITEM_ID="${PUSHOVER_OP_ITEM_ID:-<pushover-item>}"

ALERT_THRESHOLD=""   # e.g. "0.20" = alert when remaining < 20% of limit
JSON_ONLY=0

die() { echo "pushover-quota: ERROR: $*" >&2; exit "${2:-1}"; }

usage() {
    /bin/cat <<'USAGE_EOF'
pushover-quota — monthly quota monitor for pushover-verbatim-notify

USAGE:
  pushover-quota                           Persist quota state, no alert
  pushover-quota --alert-threshold <frac>  Fire WARN alert when remaining < frac*limit
                                           (e.g. 0.20 = alert at 20% remaining)
  pushover-quota --json-only               Print fresh JSON to stdout, skip persist+alert
  pushover-quota --help

ENV:
  PUSHOVER_TOKEN      Override token (skip 1P lookup)
  PUSHOVER_LOG_DIR    Override persist dir (default ~/.local/state/pushover)

OUTPUT (persisted JSON):
  {
    "checked_at": "2026-05-19T07:23:01Z",
    "limit": 10000,
    "remaining": 9990,
    "reset_at_unix": 1782000000,
    "reset_at_iso": "2026-06-01T00:00:00Z",
    "used_pct": 0.1
  }
USAGE_EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --alert-threshold) ALERT_THRESHOLD="${2:?--alert-threshold requires a fraction (e.g. 0.20)}"; shift 2 ;;
        --json-only)       JSON_ONLY=1; shift ;;
        --help|-h)         usage; exit 0 ;;
        *)                 die "unknown arg: $1" 1 ;;
    esac
done

# Validate threshold if set
if [ -n "$ALERT_THRESHOLD" ]; then
    case "$ALERT_THRESHOLD" in
        0.[0-9]*|1.0|1) ;;
        *) die "--alert-threshold must be a fraction in [0,1] (got: $ALERT_THRESHOLD)" 1 ;;
    esac
fi

# Load Pushover app token from 1P (SA-first, biometric fallback)
load_token() {
    if [ -n "${PUSHOVER_TOKEN:-}" ]; then
        return 0
    fi

    # Proxy bypass — Claude Code OAuth proxy returns 502 on 1P endpoints
    local saved_https="${HTTPS_PROXY:-}" saved_http="${HTTP_PROXY:-}"
    unset HTTPS_PROXY HTTP_PROXY 2>/dev/null || true

    local sa_token_path="$HOME/.claude/.secrets/op-service-account-token"
    if [ -r "$sa_token_path" ]; then
        local sa_token
        sa_token=$(/bin/cat "$sa_token_path")
        export OP_SERVICE_ACCOUNT_TOKEN="$sa_token"
        if ! PUSHOVER_TOKEN=$(op read "op://${OP_VAULT}/${OP_ITEM_ID}/credential" 2>/dev/null); then
            unset OP_SERVICE_ACCOUNT_TOKEN
            PUSHOVER_TOKEN=$(op read "op://${OP_VAULT}/${OP_ITEM_ID}/credential" 2>/dev/null) || PUSHOVER_TOKEN=""
        else
            unset OP_SERVICE_ACCOUNT_TOKEN
        fi
    fi

    [ -n "$saved_https" ] && export HTTPS_PROXY="$saved_https"
    [ -n "$saved_http" ] && export HTTP_PROXY="$saved_http"

    if [ -z "${PUSHOVER_TOKEN:-}" ]; then
        die "could not load Pushover token from 1P (item ${OP_ITEM_ID} in ${OP_VAULT})" 1
    fi
}

load_token

# Fetch limits — --noproxy bypasses any inherited HTTPS_PROXY
RESPONSE=$(/usr/bin/curl -sS --noproxy '*' --max-time 10 \
    "https://api.pushover.net/1/apps/limits.json?token=${PUSHOVER_TOKEN}" 2>&1) || \
    die "curl failed: $RESPONSE" 2

# Validate response shape
if ! echo "$RESPONSE" | /usr/bin/jq -e '.status == 1 and .limit and .remaining' >/dev/null 2>&1; then
    die "unexpected response from Pushover: $RESPONSE" 2
fi

LIMIT=$(echo "$RESPONSE" | /usr/bin/jq -r '.limit')
REMAINING=$(echo "$RESPONSE" | /usr/bin/jq -r '.remaining')
RESET_UNIX=$(echo "$RESPONSE" | /usr/bin/jq -r '.reset // 0')

# Compose persistable JSON
NOW_ISO=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)
if [ "$RESET_UNIX" != "0" ] && [ "$RESET_UNIX" != "null" ]; then
    RESET_ISO=$(/bin/date -u -r "$RESET_UNIX" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
else
    RESET_ISO=""
fi

USED=$(( LIMIT - REMAINING ))
USED_PCT=$(/usr/bin/jq -n --argjson used "$USED" --argjson limit "$LIMIT" '($used / $limit * 100 * 100 | round) / 100')

OUT_JSON=$(/usr/bin/jq -n \
    --arg checked_at "$NOW_ISO" \
    --argjson limit "$LIMIT" \
    --argjson remaining "$REMAINING" \
    --argjson reset_unix "$RESET_UNIX" \
    --arg reset_iso "$RESET_ISO" \
    --argjson used_pct "$USED_PCT" \
    '{checked_at: $checked_at, limit: $limit, remaining: $remaining,
      reset_at_unix: $reset_unix, reset_at_iso: $reset_iso, used_pct: $used_pct}')

if [ "$JSON_ONLY" -eq 1 ]; then
    echo "$OUT_JSON"
    exit 0
fi

# Atomic persist
/bin/mkdir -p "$LOG_DIR"
TMP="${QUOTA_FILE}.tmp.$$"
echo "$OUT_JSON" > "$TMP" && /bin/mv "$TMP" "$QUOTA_FILE"

echo "pushover-quota: used=${USED}/${LIMIT} (${USED_PCT}%) remaining=${REMAINING} reset=${RESET_ISO:-unknown}"

# Alert if threshold crossed
if [ -n "$ALERT_THRESHOLD" ]; then
    THRESHOLD_REMAINING=$(/usr/bin/jq -n --argjson limit "$LIMIT" --argjson t "$ALERT_THRESHOLD" '($limit * $t | floor)')
    if [ "$REMAINING" -lt "$THRESHOLD_REMAINING" ]; then
        if command -v pushover-notify >/dev/null 2>&1; then
            pushover-notify \
                --title "Pushover quota low: ${REMAINING}/${LIMIT} remaining" \
                --message "Pushover monthly quota is below ${ALERT_THRESHOLD} threshold. Reset at ${RESET_ISO:-unknown}." \
                --service pushover-quota \
                --level WARN \
                --extra "$OUT_JSON" \
                >/dev/null
            echo "pushover-quota: ALERT fired (remaining=${REMAINING} < threshold=${THRESHOLD_REMAINING})"
        else
            echo "pushover-quota: threshold crossed but pushover-notify not in PATH; skipping alert" >&2
        fi
    fi
fi
