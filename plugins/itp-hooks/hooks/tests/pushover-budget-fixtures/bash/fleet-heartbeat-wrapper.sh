#!/usr/bin/env bash
# fleet heartbeat dispatcher using pushover-notify wrapper function

# Define wrapper to call the installed pushover-notify command
po_notify() {
    local title="$1"
    local message="$2"
    local service="$3"
    
    if command -v pushover-notify >/dev/null 2>&1; then
        pushover-notify \
            --title "$title" \
            --message "$message" \
            --service "$service" \
            --level INFO
    else
        echo "pushover-notify not found" >&2
        return 1
    fi
}

# Collect metrics and dispatch
QUOTA_USED=$(jq -r '.used' ~/.local/state/pushover/quota.json)
QUOTA_LIMIT=$(jq -r '.limit' ~/.local/state/pushover/quota.json)

po_notify \
    "Fleet Status Update" \
    "Quota: ${QUOTA_USED}/${QUOTA_LIMIT}" \
    "heartbeat-monitor"
