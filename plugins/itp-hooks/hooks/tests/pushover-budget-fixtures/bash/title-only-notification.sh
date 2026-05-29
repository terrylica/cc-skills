#!/usr/bin/env bash
# Send a title-only Pushover notification (minimal message)
set -euo pipefail

TITLE="Server Health Check"
PRIORITY=-1

# Minimal Pushover send: title only, no message body
/usr/bin/curl -s -X POST "https://api.pushover.net/1/messages.json" \
  --data-urlencode "token=${PUSHOVER_TOKEN}" \
  --data-urlencode "user=${PUSHOVER_USER}" \
  --data-urlencode "title=${TITLE}" \
  --data-urlencode "priority=${PRIORITY}"
