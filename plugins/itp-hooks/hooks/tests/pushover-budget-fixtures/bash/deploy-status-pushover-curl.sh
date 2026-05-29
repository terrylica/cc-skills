#!/usr/bin/env bash
# deployment status notifier — curl to api.pushover.net
set -euo pipefail

DEPLOY_ENV="$1"
STATUS="$2"

# Load Pushover credentials from env
PUSHOVER_TOKEN="${PUSHOVER_TOKEN:-}"
PUSHOVER_USER="${PUSHOVER_USER:-}"

if [ -z "$PUSHOVER_TOKEN" ] || [ -z "$PUSHOVER_USER" ]; then
    echo "Error: PUSHOVER_TOKEN and PUSHOVER_USER not set" >&2
    exit 1
fi

# Build the notification message
TITLE="Deployment Alert: $DEPLOY_ENV"
MESSAGE="Status: $STATUS\nTimestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)\nCommit: $(git rev-parse --short HEAD)"
PRIORITY=0

# Send via curl to Pushover API
curl -s -X POST "https://api.pushover.net/1/messages.json" \
  --data-urlencode "token=$PUSHOVER_TOKEN" \
  --data-urlencode "user=$PUSHOVER_USER" \
  --data-urlencode "title=$TITLE" \
  --data-urlencode "message=$MESSAGE" \
  --data-urlencode "priority=$PRIORITY"
