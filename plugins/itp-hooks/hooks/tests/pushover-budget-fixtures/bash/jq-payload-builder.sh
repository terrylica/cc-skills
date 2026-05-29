#!/usr/bin/env bash
# Build Pushover JSON payload using jq
set -euo pipefail

TITLE="Alert"
MESSAGE="System down"
PRIORITY=2
RETRY=30
EXPIRE=600

# Construct JSON payload with jq
PAYLOAD=$(jq -n \
  --arg token "$PUSHOVER_TOKEN" \
  --arg user "$PUSHOVER_USER" \
  --arg title "$TITLE" \
  --arg message "$MESSAGE" \
  --argjson priority "$PRIORITY" \
  --argjson retry "$RETRY" \
  --argjson expire "$EXPIRE" \
  '{
    token: $token,
    user: $user,
    title: $title,
    message: $message,
    priority: $priority,
    retry: $retry,
    expire: $expire
  }')

# Send the JSON payload
curl -s -X POST "https://api.pushover.net/1/messages.json" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
