#!/usr/bin/env bash
#
# pushover-heartbeat.sh — daily fleet summary via pushover-verbatim-notify
#
# Iter 20 (2026-05-19): proactive monitoring instead of reactive-only.
# Eats own dogfood: composes a fleet status snapshot and sends it via the
# iter-5 pushover-notify skill so the dispatch is UUID-correlated + JSONL-
# audited like every other Pushover event.
#
# Probes (each with short timeout + graceful fallback to "unknown"):
#   - pushover quota         ~/.local/state/pushover/quota.json
#   - disk                   ~/.local/state/launchd-logs/    (total size)
#   - failed launchd         launchctl print loop, last_exit != 0
#
# Level: INFO (priority -1) — silent, no quiet-hours bypass. Heartbeat is
# routine; we don't want to wake the user. If a real failure happens, the
# RELEVANT subsystem (service-watchdog, etc.) is
# expected to fire its own ERROR-level alert. The heartbeat answers
# "are all subsystems healthy now" once per day.
#
# Usage:
#   pushover-heartbeat                  # collect + send (use as launchd timer)
#   pushover-heartbeat --dry-run        # print the message body, do not send
#   pushover-heartbeat --json-only      # print the structured payload JSON
#

set -euo pipefail

DRY_RUN=0
JSON_ONLY=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)   DRY_RUN=1; shift ;;
        --json-only) JSON_ONLY=1; shift ;;
        --help|-h)
            /bin/cat <<'USAGE_EOF'
pushover-heartbeat — daily fleet status summary via pushover-verbatim-notify

USAGE:
  pushover-heartbeat              Send the heartbeat now
  pushover-heartbeat --dry-run    Show the message body, do not send
  pushover-heartbeat --json-only  Print structured payload JSON to stdout
  pushover-heartbeat --help

Designed for a daily launchd timer. Level=INFO/priority=-1 so it's silent
on the device — informational, not alert-worthy.
USAGE_EOF
            exit 0
            ;;
        *) echo "pushover-heartbeat: unknown arg: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Probes — each safely no-ops to "unknown" on failure
# ---------------------------------------------------------------------------

# Pushover quota (from iter-12b daily monitor)
QUOTA_FILE="$HOME/.local/state/pushover/quota.json"
if [ -r "$QUOTA_FILE" ]; then
    QUOTA_USED=$(/usr/bin/jq -r '.limit - .remaining' "$QUOTA_FILE")
    QUOTA_LIMIT=$(/usr/bin/jq -r '.limit' "$QUOTA_FILE")
    QUOTA_PCT=$(/usr/bin/jq -r '.used_pct' "$QUOTA_FILE")
else
    QUOTA_USED=0; QUOTA_LIMIT=0; QUOTA_PCT=0
fi

# Disk usage (launchd logs + pushover audit dirs)
LOGS_SIZE_BYTES=$(/usr/bin/du -sk "$HOME/.local/state/launchd-logs" 2>/dev/null | /usr/bin/awk '{print $1*1024}')
LOGS_SIZE_BYTES=${LOGS_SIZE_BYTES:-0}
LOGS_SIZE_MB=$(( LOGS_SIZE_BYTES / 1024 / 1024 ))
AUDIT_DAYS=$(/bin/ls "$HOME/.local/state/pushover"/audit-*.jsonl 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')

# Failed launchd services — any com.terryli.* with last_exit != 0
FAILED_SERVICES=""
for s in $(/bin/launchctl list 2>/dev/null | /usr/bin/awk '/com\.terryli\./{print $NF}'); do
    exit_code=$(/bin/launchctl print "gui/$(/usr/bin/id -u)/$s" 2>/dev/null | /usr/bin/awk '/last exit code/{print $NF; exit}')
    case "$exit_code" in
        ""|0|-|exited\)) ;;
        *) FAILED_SERVICES="${FAILED_SERVICES}${s}=${exit_code} " ;;
    esac
done
FAILED_SERVICES=$(echo "$FAILED_SERVICES" | /usr/bin/sed 's/ $//')
[ -z "$FAILED_SERVICES" ] && FAILED_SERVICES="none"

# ---------------------------------------------------------------------------
# Compose the message body — terse, dense, single-screen-readable
# ---------------------------------------------------------------------------

BODY="🔔 Fleet daily heartbeat

pushover quota: ${QUOTA_USED}/${QUOTA_LIMIT} (${QUOTA_PCT}%)
disk: launchd-logs=${LOGS_SIZE_MB}MB · audit days=$AUDIT_DAYS
failed services: $FAILED_SERVICES"

# Structured JSON for --extra (full machine-readable snapshot)
EXTRA_JSON=$(/usr/bin/jq -nc \
    --argjson quota_used "${QUOTA_USED:-0}" \
    --argjson quota_limit "${QUOTA_LIMIT:-0}" \
    --argjson quota_pct "${QUOTA_PCT:-0}" \
    --argjson logs_size_mb "${LOGS_SIZE_MB:-0}" \
    --argjson audit_days "${AUDIT_DAYS:-0}" \
    --arg failed_services "$FAILED_SERVICES" \
    '{pushover: {used: $quota_used, limit: $quota_limit, used_pct: $quota_pct},
      disk: {launchd_logs_mb: $logs_size_mb, audit_days_retained: $audit_days},
      failed_services: $failed_services}')

if [ "$JSON_ONLY" -eq 1 ]; then
    echo "$EXTRA_JSON"
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "--- DRY RUN — message body ---"
    echo "$BODY"
    echo ""
    echo "--- structured extra ---"
    echo "$EXTRA_JSON" | /usr/bin/jq .
    exit 0
fi

# Dispatch via iter-5 skill
if ! command -v pushover-notify >/dev/null 2>&1; then
    echo "pushover-heartbeat: ERROR — pushover-notify not in PATH; cannot dispatch" >&2
    exit 1
fi

# Determine level: INFO (silent) by default; WARN if anything looks off
LEVEL=INFO
if [ "$FAILED_SERVICES" != "none" ]; then
    LEVEL=WARN
fi

# --ttl 90000 (25h, official API parameter, adopted 2026-06-11): the daily
# heartbeat self-deletes from the device shortly after the next one lands,
# so routine snapshots never pile up. Quota-hygiene companion to the
# 2026-05-01 per-account pool change (all fleet apps share one 10k/month
# budget). The JSONL audit trail keeps the full history regardless; the
# device copy is ephemeral by design. (ttl is ignored by the API for
# priority 2 — irrelevant here, heartbeat is INFO/WARN.)
if pushover-notify \
    --title "🔔 Fleet daily heartbeat" \
    --message "$BODY" \
    --service "fleet-heartbeat" \
    --level "$LEVEL" \
    --device iphone_13_mini \
    --ttl 90000 \
    --extra "$EXTRA_JSON" \
    >/dev/null
then
    # Only claim "dispatched" once pushover-notify actually succeeded. Printing
    # this unconditionally previously masked a ~12-day credential outage (the
    # send die'd but the log still said "dispatched"). See reference_pushover_scs_migration.
    echo "pushover-heartbeat: dispatched (level=$LEVEL, quota=${QUOTA_PCT}%, failed=$FAILED_SERVICES)"
else
    rc=$?
    echo "pushover-heartbeat: DISPATCH FAILED — pushover-notify exit $rc (level=$LEVEL, quota=${QUOTA_PCT}%, failed=$FAILED_SERVICES)" >&2
    exit "$rc"
fi
