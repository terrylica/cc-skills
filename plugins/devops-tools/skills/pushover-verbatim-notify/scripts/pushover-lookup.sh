#!/usr/bin/env bash
#
# pushover-lookup.sh — retrieve a verbatim JSONL entry by UUID
#
# Companion to pushover-notify.sh. When you receive a Pushover notification
# containing a UUID, run:
#       pushover-lookup <uuid>
# to print the full verbatim JSONL entry (including all extra fields beyond
# what fit in the 1024-char Pushover body).
#
# You can also pipe a Pushover message body into this script — it will
# extract the first UUID it sees and look that up.
#
# Usage:
#   pushover-lookup <uuid>                   # exact match
#   pushover-lookup <partial-prefix>         # 8-char prefix match (first 8)
#   pushover-lookup --recent [N]             # last N entries (default 10)
#   pushover-lookup --service <name> [N]     # last N entries for one service
#   echo "...UUID xyz..." | pushover-lookup  # extract UUID from stdin
#
# Output: pretty-printed JSON of the matching JSONL line(s) via jq.
#

set -euo pipefail

readonly LOG_DIR="${PUSHOVER_LOG_DIR:-$HOME/.local/state/pushover}"

die() { echo "pushover-lookup: ERROR: $*" >&2; exit "${2:-1}"; }

usage() {
    /bin/cat <<'USAGE_EOF'
pushover-lookup — retrieve verbatim JSONL entry by UUID

USAGE:
  pushover-lookup <uuid>                   Exact UUID match (full v4 format)
  pushover-lookup <prefix>                 Prefix match (≥8 chars unique)
  pushover-lookup --recent [N]             Last N entries (default 10)
  pushover-lookup --service <name> [N]     Last N entries for one service
  pushover-lookup --tail                   Follow today's log (like tail -f)
  pushover-lookup --help                   This help

  Or pipe Pushover message body in:
       echo "... UUID abc-... ..." | pushover-lookup

LOG LOCATION: ${PUSHOVER_LOG_DIR:-~/.local/state/pushover}/audit-YYYYMMDD.jsonl
USAGE_EOF
}

# Search across all daily JSONL files in LOG_DIR
all_logs() {
    /bin/ls -t "$LOG_DIR"/audit-*.jsonl 2>/dev/null || true
}

today_log() {
    echo "$LOG_DIR/audit-$(/bin/date -u +%Y%m%d).jsonl"
}

case "${1:-}" in
    --help|-h)
        usage; exit 0 ;;
    --recent)
        N="${2:-10}"
        for log in $(all_logs); do
            /usr/bin/tail -n "$N" "$log"
        done | /usr/bin/tail -n "$N" | /usr/bin/jq -s '.'
        exit 0 ;;
    --service)
        SVC="${2:-}"
        [ -z "$SVC" ] && die "--service requires a name" 1
        N="${3:-10}"
        for log in $(all_logs); do
            /usr/bin/jq -c --arg svc "$SVC" 'select(.service == $svc)' "$log"
        done | /usr/bin/tail -n "$N" | /usr/bin/jq -s '.'
        exit 0 ;;
    --tail)
        L=$(today_log)
        [ -r "$L" ] || die "no log file for today: $L" 1
        /usr/bin/tail -f "$L" | while IFS= read -r line; do
            echo "$line" | /usr/bin/jq -c .
        done
        ;;
    "")
        # No arg — read from stdin if not a tty
        if [ -t 0 ]; then
            usage; exit 0
        fi
        STDIN_INPUT=$(/bin/cat)
        # Extract first UUID-shaped token (8-4-4-4-12 hex)
        UUID=$(echo "$STDIN_INPUT" | /usr/bin/grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | /usr/bin/head -1)
        [ -z "$UUID" ] && die "no UUID found in stdin" 1
        set -- "$UUID"
        ;;
esac

QUERY="$1"
QUERY_LOWER=$(echo "$QUERY" | /usr/bin/tr '[:upper:]' '[:lower:]')

# Search every log file. Prefer exact match; fall back to prefix.
MATCHES=()
for log in $(all_logs); do
    while IFS= read -r line; do
        MATCHES+=("$line")
    done < <(/usr/bin/jq -c --arg q "$QUERY_LOWER" 'select((.run_id // "") | ascii_downcase | startswith($q))' "$log" 2>/dev/null)
done

[ "${#MATCHES[@]}" -eq 0 ] && die "no entry matching UUID/prefix: $QUERY" 1

# Print pretty JSON for each match
for line in "${MATCHES[@]}"; do
    echo "$line" | /usr/bin/jq .
done
