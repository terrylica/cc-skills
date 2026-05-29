#!/usr/bin/env bash
# Pushover notification with supplementary URL
set -euo pipefail

TITLE="Incident Report"
MESSAGE="High memory usage detected on production servers (95%). Details and graphs available in the link below."
URL="https://monitoring.example.com/incidents/prod-mem-2026-05-29"
URL_TITLE="View Full Report"
PRIORITY=1

# Send with URL metadata (useful for detailed provenance)
curl -s -X POST "https://api.pushover.net/1/messages.json" \
  --data-urlencode "token=$PUSHOVER_TOKEN" \
  --data-urlencode "user=$PUSHOVER_USER" \
  --data-urlencode "title=$TITLE" \
  --data-urlencode "message=$MESSAGE" \
  --data-urlencode "url=$URL" \
  --data-urlencode "url_title=$URL_TITLE" \
  --data-urlencode "priority=$PRIORITY"
